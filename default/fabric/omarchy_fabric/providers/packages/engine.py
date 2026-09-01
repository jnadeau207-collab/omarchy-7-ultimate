"""Hermetic durable package operation lifecycle.

The engine models the production coordinator seam without invoking package
managers.  State transitions, checkpoints, cancellation, rollback, and restart
reconciliation are real; the adapter is deliberately fake and deterministic.
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import os
import posixpath
import uuid
from copy import deepcopy
from pathlib import Path, PurePosixPath
from typing import Any, Mapping

from jsonschema import Draft202012Validator

from omarchy_fabric.models import FabricError
from omarchy_fabric.security.principal import EndpointPrincipal

from .adapters import plan_adapter
from .catalog import PackageCatalog
from .contracts import CONTRACTS
from .identity import REVISION_RE, SHA256_RE, STABLE_ID_RE, canonical_json, revision, stable_id

MAX_STATE_BYTES = 2 * 1024 * 1024
CHECKPOINTS = ("verify-provenance", "stage-payload", "apply", "validate", "commit")
TERMINAL = {"succeeded", "failed", "cancelled", "rolled-back"}
MAX_OPERATIONS = 4096
_PLAN_VALIDATOR = Draft202012Validator(CONTRACTS["urn:omarchy:fabric:provider:packages:operation-preflight:v0"])

def _reject_json_constant(value: str) -> None:
    raise ValueError(f"invalid JSON constant: {value}")

def _safe_inventory_path(value: object) -> bool:
    return (
        isinstance(value, str)
        and 1 < len(value) <= 500
        and value.startswith("/")
        and "\x00" not in value
        and not any(ord(character) < 32 or ord(character) == 127 for character in value)
        and ".." not in PurePosixPath(value).parts
        and posixpath.normpath(value) == value
    )

def _fsync_directory(path: Path) -> None:
    if os.name != "posix":
        return
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)

def _acquire_state_lock(path: Path) -> int | None:
    if os.name != "posix":
        return None
    import fcntl

    lock_path = path.with_name(f".{path.name}.lock")
    descriptor = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        os.close(descriptor)
        raise FabricError("packages.state-busy", "Software operation state is busy", "Another process currently owns the durable journal write lock.", retryable=True, change_state="unknown") from error
    return descriptor

def _release_state_lock(descriptor: int | None) -> None:
    if descriptor is None:
        return
    import fcntl

    fcntl.flock(descriptor, fcntl.LOCK_UN)
    os.close(descriptor)

def inventory_revision(inventory: list[Mapping[str, Any]]) -> str:
    return revision(sorted((deepcopy(dict(item)) for item in inventory), key=lambda item: item["id"]))

class FakeExecutionAdapter:
    """Controllable adapter that records typed input and never executes a process."""

    def __init__(self, *, fail_at: str | None = None, pause_at: str | None = None) -> None:
        if fail_at is not None and fail_at not in CHECKPOINTS:
            raise ValueError("fake adapter failure checkpoint is invalid")
        if pause_at is not None and pause_at not in CHECKPOINTS:
            raise ValueError("fake adapter pause checkpoint is invalid")
        self.fail_at = fail_at
        self.pause_at = pause_at
        self.calls: list[dict[str, Any]] = []
        self.entered = asyncio.Event()
        self.release = asyncio.Event()

    async def checkpoint(self, name: str, plan: Mapping[str, Any]) -> None:
        if name not in CHECKPOINTS:
            raise ValueError("checkpoint is invalid")
        self.calls.append({"checkpoint": name, "operationId": plan["operationId"], "arguments": deepcopy(plan["normalizedArguments"])})
        if self.pause_at == name:
            self.entered.set()
            await self.release.wait()
        if self.fail_at == name:
            raise FabricError("packages.adapter-failed", "Software adapter failed", "The hermetic adapter produced its requested deterministic failure.", detail=name, retryable=True, change_state="unknown" if name in {"apply", "validate", "commit"} else "none", recovery_actions=("packages.reconcile",))

class PackageOperationEngine:
    def __init__(
        self,
        catalog: PackageCatalog,
        inventory: list[Mapping[str, Any]],
        *,
        state_path: Path | None = None,
        adapter: FakeExecutionAdapter | None = None,
    ) -> None:
        self.catalog = catalog
        self.state_path = Path(state_path) if state_path is not None else None
        self.adapter = adapter or FakeExecutionAdapter()
        self._lock = asyncio.Lock()
        self._cancelled: set[str] = set()
        self._state_token: str | None = None
        self._inventory = self._validate_inventory(inventory)
        self._operations: dict[str, dict[str, Any]] = {}
        if self.state_path is not None and self.state_path.exists():
            self._load()
        interrupted = False
        for operation in self._operations.values():
            if operation["status"] == "running":
                operation["status"] = "needs-reconcile"
                operation["mutationState"] = "unknown"
                operation["error"] = "Fabric restarted while the package adapter was running."
                operation["revision"] = self._operation_revision(operation)
                interrupted = True
        if interrupted:
            self._persist()

    @staticmethod
    def _validate_inventory(inventory: list[Mapping[str, Any]]) -> list[dict[str, Any]]:
        if not isinstance(inventory, list) or len(inventory) > 4096:
            raise FabricError("packages.inventory-invalid", "Software inventory is invalid", "Inventory must be a bounded array.")
        output: list[dict[str, Any]] = []
        identifiers: set[str] = set()
        catalog_identifiers: set[str] = set()
        package_identities: set[tuple[str, str]] = set()
        required = {"id", "catalogId", "sourceType", "packageRef", "installedVersion", "artifactDigest", "adopted", "state", "configPaths", "dataPaths"}
        for value in inventory:
            if not isinstance(value, Mapping) or set(value) != required:
                raise FabricError("packages.inventory-invalid", "Software inventory is invalid", "Every installed item must use the closed inventory shape.")
            item = deepcopy(dict(value))
            string_fields = (item["id"], item["catalogId"], item["packageRef"], item["installedVersion"])
            package_identity = (item["sourceType"], item["packageRef"]) if isinstance(item["sourceType"], str) and isinstance(item["packageRef"], str) else ("", "")
            if (
                item["id"] in identifiers
                or item["catalogId"] in catalog_identifiers
                or package_identity in package_identities
                or any(not isinstance(field, str) or not field for field in string_fields)
                or len(item["id"]) > 160
                or len(item["catalogId"]) > 160
                or len(item["packageRef"]) > 300
                or len(item["installedVersion"]) > 100
                or STABLE_ID_RE.fullmatch(item["id"]) is None
                or STABLE_ID_RE.fullmatch(item["catalogId"]) is None
                or not isinstance(item["sourceType"], str)
                or item["sourceType"] not in {"curated", "signed-repo", "flatpak", "reviewed-aur", "appimage", "web-app"}
                or not isinstance(item["artifactDigest"], str)
                or SHA256_RE.fullmatch(item["artifactDigest"]) is None
                or not isinstance(item["configPaths"], list)
                or not isinstance(item["dataPaths"], list)
                or len(item["configPaths"]) > 64
                or len(item["dataPaths"]) > 64
                or any(not _safe_inventory_path(path) for path in (*item["configPaths"], *item["dataPaths"]))
                or len(set(item["configPaths"])) != len(item["configPaths"])
                or len(set(item["dataPaths"])) != len(item["dataPaths"])
                or set(item["configPaths"]) & set(item["dataPaths"])
                or (package_identity != ("", "") and item["id"] != stable_id("installed.software", *package_identity))
            ):
                raise FabricError("packages.inventory-invalid", "Software inventory is invalid", "Installed identities, fields, and paths must be bounded, canonical, and unique.")
            if item["state"] not in {"installed", "partial", "broken", "foreign"}:
                raise FabricError("packages.inventory-invalid", "Software inventory is invalid", "Installed state is not recognized.", detail=item["id"])
            if not isinstance(item["adopted"], bool):
                raise FabricError("packages.inventory-invalid", "Software inventory is invalid", "Installed paths or adoption state are unsafe.", detail=item["id"])
            identifiers.add(item["id"])
            catalog_identifiers.add(item["catalogId"])
            package_identities.add(package_identity)
            output.append(item)
        return sorted(output, key=lambda item: item["id"])

    def _load(self) -> None:
        assert self.state_path is not None
        with self.state_path.open("rb") as stream:
            raw = stream.read(MAX_STATE_BYTES + 1)
        if len(raw) > MAX_STATE_BYTES:
            raise FabricError("packages.state-corrupt", "Software operation state is corrupt", "The durable state exceeds its bounded contract.")
        try:
            document = json.loads(raw, parse_constant=_reject_json_constant)
        except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
            raise FabricError("packages.state-corrupt", "Software operation state is corrupt", "The durable state is not UTF-8 JSON.", detail=type(error).__name__) from error
        if not isinstance(document, dict) or set(document) != {"schemaVersion", "catalogRevision", "inventory", "operations"} or document.get("schemaVersion") != "v0" or document.get("catalogRevision") != self.catalog.revision or not isinstance(document.get("operations"), list):
            raise FabricError("packages.state-corrupt", "Software operation state is corrupt", "The durable state does not match its closed version or catalog.")
        self._inventory = self._validate_inventory(document["inventory"])
        operations: dict[str, dict[str, Any]] = {}
        request_ids: set[str] = set()
        if len(document["operations"]) > MAX_OPERATIONS:
            raise FabricError("packages.state-corrupt", "Software operation state is corrupt", "The durable operation count exceeds its bounded contract.")
        for operation in document["operations"]:
            if not isinstance(operation, dict) or set(operation) != {"operationId", "requestId", "sequence", "action", "plan", "status", "mutationState", "checkpoints", "priorItem", "targetItem", "inventoryRevision", "revision", "error"}:
                raise FabricError("packages.state-corrupt", "Software operation state is corrupt", "A durable operation has an invalid shape.")
            checkpoints = operation["checkpoints"]
            if (
                operation["operationId"] in operations
                or operation.get("requestId") in request_ids
                or not isinstance(operation["sequence"], int)
                or isinstance(operation["sequence"], bool)
                or operation["sequence"] < 1
                or any(candidate["sequence"] == operation["sequence"] for candidate in operations.values())
                or operation["status"] not in TERMINAL | {"running", "needs-reconcile"}
                or operation["mutationState"] not in {"none", "complete", "unknown"}
                or operation["action"] not in {"install", "remove", "adopt", "recover"}
                or not isinstance(operation["operationId"], str)
                or STABLE_ID_RE.fullmatch(operation["operationId"]) is None
                or not isinstance(operation["requestId"], str)
                or STABLE_ID_RE.fullmatch(operation["requestId"]) is None
                or not isinstance(checkpoints, list)
                or checkpoints != list(CHECKPOINTS[:len(checkpoints)])
                or not isinstance(operation["plan"], dict)
            ):
                raise FabricError("packages.state-corrupt", "Software operation state is corrupt", "A durable operation identity or status is invalid.")
            if not self._valid_persisted_operation(operation) or operation["revision"] != self._operation_revision(operation):
                raise FabricError("packages.state-corrupt", "Software operation state is corrupt", "A durable operation revision does not match its contents.")
            operations[operation["operationId"]] = deepcopy(operation)
            request_ids.add(operation["requestId"])
        self._operations = operations
        self._state_token = hashlib.sha256(raw).hexdigest()

    def _valid_persisted_operation(self, operation: Mapping[str, Any]) -> bool:
        try:
            plan = operation["plan"]
            if next(iter(_PLAN_VALIDATOR.iter_errors(plan)), None) is not None:
                return False
            app_id = plan["resource"]["id"]
            entry = self.catalog.by_id.get(app_id)
            if entry is None:
                return False
            normalized = plan["normalizedArguments"]
            if (
                plan["operationId"] != operation["operationId"]
                or plan["action"] != operation["action"]
                or normalized["requestId"] != operation["requestId"]
                or normalized["appId"] != app_id
                or normalized["catalogRevision"] != self.catalog.revision
                or normalized["expectedInventoryRevision"] != plan["inventoryRevision"]
                or plan["catalogRevision"] != self.catalog.revision
                or plan["provenance"] != entry["provenance"]
                or plan["operationId"] != stable_id("operation.packages", operation["requestId"], app_id)
                or plan["planRevision"] != revision({**plan, "planRevision": "sha256." + "0" * 64})
                or plan["recovery"]["priorItem"] != operation["priorItem"]
                or not isinstance(operation["inventoryRevision"], str)
                or REVISION_RE.fullmatch(operation["inventoryRevision"]) is None
                or not isinstance(operation["error"], (str, type(None)))
                or (isinstance(operation["error"], str) and len(operation["error"]) > 1000)
                or (operation["status"] == "needs-reconcile" and operation["mutationState"] != "unknown")
                or (operation["status"] == "rolled-back" and operation["mutationState"] != "complete")
                or (operation["status"] == "succeeded" and operation["mutationState"] != ("complete" if plan["changed"] else "none"))
            ):
                return False
            prior = self._validated_item_or_none(operation["priorItem"])
            target = self._validated_item_or_none(operation["targetItem"])
            action = operation["action"]
            if prior is not None and prior["catalogId"] != app_id:
                return False
            if target != self._target_item(action, entry, prior):
                return False
            if plan["changed"] != (prior != target):
                return False
            adapter_intent = "remove" if action == "remove" else ("adopt" if action == "adopt" else "install")
            expected_adapter = plan_adapter(entry["sourceType"], adapter_intent, {}).public()
            paths = sorted(set((*prior["configPaths"], *prior["dataPaths"]))) if prior is not None and action == "remove" else []
            preserve = normalized["preserveUserData"]
            expected_recovery = {
                "mode": "restore-prior-item",
                "priorItem": prior,
                "preserveUserData": preserve,
                "dataDisposition": {"preserve": paths if preserve else [], "delete": [] if preserve else paths},
            }
            expected_steps = [{"id": name, "ordinal": index + 1, "mutationBoundary": name == "apply"} for index, name in enumerate(CHECKPOINTS)]
            if (
                plan["summary"] != self._summary(action, entry, prior, plan["changed"])
                or plan["risk"] != ("destructive" if action == "remove" else "consequential")
                or plan["effects"] != (["mutating", "destructive"] if action == "remove" else (["mutating"] if action == "adopt" else ["mutating", "download"]))
                or plan["steps"] != expected_steps
                or plan["adapter"] != expected_adapter
                or plan["recovery"] != expected_recovery
            ):
                return False
            if operation["status"] == "succeeded" and operation["checkpoints"] != list(CHECKPOINTS):
                return False
            return True
        except (KeyError, TypeError, ValueError, FabricError):
            return False

    def _validated_item_or_none(self, value: Any) -> dict[str, Any] | None:
        if value is None:
            return None
        return self._validate_inventory([value])[0]

    def _persist(self) -> None:
        if self.state_path is None:
            return
        document = {
            "schemaVersion": "v0",
            "catalogRevision": self.catalog.revision,
            "inventory": self._inventory,
            "operations": sorted(self._operations.values(), key=lambda operation: operation["sequence"]),
        }
        payload = canonical_json(document).encode("utf-8")
        if len(payload) > MAX_STATE_BYTES:
            raise FabricError("packages.state-too-large", "Software operation state is too large", "The durable state exceeds its bounded contract.")
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        lock_descriptor = _acquire_state_lock(self.state_path)
        try:
            if self.state_path.exists():
                with self.state_path.open("rb") as stream:
                    current = stream.read(MAX_STATE_BYTES + 1)
                if len(current) > MAX_STATE_BYTES:
                    raise FabricError("packages.state-concurrent", "Software operation state changed concurrently", "The current durable journal exceeds its bounded contract.", retryable=False, change_state="unknown")
                current_token = hashlib.sha256(current).hexdigest()
                if self._state_token != current_token:
                    raise FabricError("packages.state-concurrent", "Software operation state changed concurrently", "This engine instance no longer owns the exact durable journal revision.", retryable=True, change_state="unknown")
            elif self._state_token is not None:
                raise FabricError("packages.state-concurrent", "Software operation state changed concurrently", "The durable journal disappeared after this engine loaded it.", retryable=True, change_state="unknown")
            temporary = self.state_path.with_name(f".{self.state_path.name}.{uuid.uuid4().hex}.tmp")
            try:
                with temporary.open("xb") as stream:
                    stream.write(payload)
                    stream.flush()
                    os.fsync(stream.fileno())
                os.replace(temporary, self.state_path)
                _fsync_directory(self.state_path.parent)
                self._state_token = hashlib.sha256(payload).hexdigest()
            finally:
                try:
                    temporary.unlink()
                except FileNotFoundError:
                    pass
        finally:
            _release_state_lock(lock_descriptor)

    @staticmethod
    def _operation_revision(operation: Mapping[str, Any]) -> str:
        payload = deepcopy(dict(operation))
        payload["revision"] = "sha256." + "0" * 64
        return revision(payload)

    def inventory(self, *, include_unmanaged: bool) -> dict[str, Any]:
        items = [deepcopy(item) for item in self._inventory if include_unmanaged or item["adopted"]]
        return {"schemaVersion": "v0", "provider": "packages.provider", "revision": inventory_revision(self._inventory), "items": items}

    def operations(self) -> dict[str, Any]:
        return {"schemaVersion": "v0", "provider": "packages.provider", "revision": revision(self._operations), "operations": [self._public_operation(operation) for operation in sorted(self._operations.values(), key=lambda item: item["operationId"])]}

    @staticmethod
    def _public_operation(operation: Mapping[str, Any]) -> dict[str, Any]:
        return {key: deepcopy(operation[key]) for key in ("operationId", "requestId", "action", "status", "checkpoints", "inventoryRevision", "revision", "error")}

    def preflight(self, action: str, arguments: Mapping[str, Any], principal: EndpointPrincipal) -> dict[str, Any]:
        if not isinstance(principal, EndpointPrincipal):
            raise FabricError("principal.required", "An authenticated Fabric principal is required", "Software preflight accepts only a daemon-issued endpoint principal.")
        return self._plan(action, arguments)

    def _plan(self, action: str, arguments: Mapping[str, Any]) -> dict[str, Any]:
        if arguments["catalogRevision"] != self.catalog.revision:
            raise FabricError("packages.catalog-drift", "Software catalog changed", "The selected catalog revision is stale.", retryable=True, recovery_actions=("packages.catalog.refresh",))
        current_revision = inventory_revision(self._inventory)
        if arguments["expectedInventoryRevision"] != current_revision:
            raise FabricError("packages.inventory-drift", "Software inventory changed", "The package plan was built from a stale installed inventory.", retryable=True, recovery_actions=("packages.inventory.refresh",))
        app_id = arguments["appId"]
        entry = self.catalog.by_id.get(app_id)
        installed = next((item for item in self._inventory if item["catalogId"] == app_id), None)
        if entry is None:
            raise FabricError("packages.catalog-entry-missing", "Software is not in the trusted catalog", "Package operations require an exact trusted catalog entry.", detail=app_id)
        if action in {"remove", "adopt"} and installed is None:
            raise FabricError("packages.installation-missing", "Software is not installed", "The requested operation requires an installed catalog item.", detail=app_id)
        if action == "adopt" and installed is not None and installed["artifactDigest"] != entry["provenance"]["artifactDigest"]:
            raise FabricError("packages.adoption-conflict", "Software cannot be adopted", "The installed artifact does not match the trusted catalog digest.", detail=app_id)
        target_item = self._target_item(action, entry, installed)
        changed = installed != target_item
        if action in {"install", "recover"} and changed:
            installed_catalog_ids = {item["catalogId"] for item in self._inventory}
            conflicts = set(entry["install"]["conflicts"]) & installed_catalog_ids
            reverse_conflicts = {
                candidate["id"]
                for candidate in self.catalog.entries
                if candidate["id"] in installed_catalog_ids and app_id in candidate["install"]["conflicts"]
            }
            if conflicts or reverse_conflicts:
                detail = ",".join(sorted(conflicts | reverse_conflicts))
                raise FabricError("packages.install-conflict", "Software installation conflicts", "The trusted catalog declares an installed package conflict.", detail=detail)
        source_type = entry["sourceType"]
        adapter = plan_adapter(source_type, "remove" if action == "remove" else ("adopt" if action == "adopt" else "install"), {"appId": app_id, "requestId": arguments["requestId"]})
        normalized = deepcopy(dict(arguments))
        operation_id = stable_id("operation.packages", arguments["requestId"], app_id)
        steps = [{"id": name, "ordinal": index + 1, "mutationBoundary": name == "apply"} for index, name in enumerate(CHECKPOINTS)]
        prior_item = deepcopy(installed)
        paths = sorted(set((*installed["configPaths"], *installed["dataPaths"]))) if installed is not None and action == "remove" else []
        data_disposition = {"preserve": paths if arguments["preserveUserData"] else [], "delete": [] if arguments["preserveUserData"] else paths}
        core = {
            "schemaVersion": "v0",
            "provider": "packages.provider",
            "providerVersion": "v0",
            "action": action,
            "operationId": operation_id,
            "resource": {"kind": "software", "id": app_id},
            "normalizedArguments": normalized,
            "catalogRevision": self.catalog.revision,
            "inventoryRevision": current_revision,
            "changed": changed,
            "summary": self._summary(action, entry, installed, changed),
            "risk": "destructive" if action == "remove" else "consequential",
            "effects": ["mutating", "destructive"] if action == "remove" else (["mutating"] if action == "adopt" else ["mutating", "download"]),
            "provenance": deepcopy((entry or self.catalog.by_id[installed["catalogId"]])["provenance"]),
            "steps": steps,
            "adapter": adapter.public(),
            "recovery": {"mode": "restore-prior-item", "priorItem": prior_item, "preserveUserData": arguments["preserveUserData"], "dataDisposition": data_disposition},
        }
        core["planRevision"] = revision({**core, "planRevision": "sha256." + "0" * 64})
        core["_targetItem"] = target_item
        return core

    @staticmethod
    def _summary(action: str, entry: Mapping[str, Any] | None, installed: Mapping[str, Any] | None, changed: bool) -> str:
        name = entry["displayName"] if entry is not None else installed["packageRef"]
        if not changed:
            return f"{name} already satisfies the requested {action} state; no change will be made."
        assurance = entry["provenance"]["assurance"] if entry is not None else "declared"
        return {"install": f"Install {name} from its {assurance} catalog source.", "remove": f"Remove {name} with the declared recovery plan.", "adopt": f"Adopt the exact catalog-matched {name} installation.", "recover": f"Recover {name} to its {assurance} catalog state."}[action]

    @staticmethod
    def _target_item(action: str, entry: Mapping[str, Any] | None, installed: Mapping[str, Any] | None) -> dict[str, Any] | None:
        if action == "remove":
            return None
        if action == "adopt":
            output = deepcopy(dict(installed))
            output["adopted"] = True
            return output
        assert entry is not None
        retained_config_paths = deepcopy(installed["configPaths"]) if installed is not None else []
        retained_data_paths = deepcopy(installed["dataPaths"]) if installed is not None else []
        return {
            "id": stable_id("installed.software", entry["sourceType"], entry["packageRef"]),
            "catalogId": entry["id"],
            "sourceType": entry["sourceType"],
            "packageRef": entry["packageRef"],
            "installedVersion": entry["version"],
            "artifactDigest": entry["provenance"]["artifactDigest"],
            "adopted": True,
            "state": "installed",
            "configPaths": retained_config_paths,
            "dataPaths": retained_data_paths,
        }

    async def apply(self, action: str, arguments: Mapping[str, Any], expected_revision: str) -> dict[str, Any]:
        async with self._lock:
            prior = next((operation for operation in self._operations.values() if operation["requestId"] == arguments["requestId"]), None)
            if prior is not None:
                if prior["action"] != action or prior["plan"]["normalizedArguments"] != dict(arguments):
                    raise FabricError("packages.idempotency-conflict", "Software request conflicts", "The request ID is already bound to different normalized arguments.")
                return self._result(prior)
            plan = self._plan(action, arguments)
            if expected_revision != plan["inventoryRevision"]:
                raise FabricError("packages.inventory-drift", "Software inventory changed", "The durable operation expected a different inventory revision.", retryable=True, recovery_actions=("packages.inventory.refresh",))
            if any(operation["status"] in {"running", "needs-reconcile"} for operation in self._operations.values()):
                raise FabricError("packages.operation-conflict", "Software operation conflicts", "The global inventory revision is owned by another running or reconciliation-required operation.", retryable=True)
            target_item = plan.pop("_targetItem")
            operation = {
                "operationId": plan["operationId"], "requestId": arguments["requestId"], "sequence": max((item["sequence"] for item in self._operations.values()), default=0) + 1, "action": action,
                "plan": plan, "status": "running", "mutationState": "none", "checkpoints": [], "priorItem": plan["recovery"]["priorItem"],
                "targetItem": target_item, "inventoryRevision": expected_revision, "revision": "sha256." + "0" * 64, "error": None,
            }
            operation["revision"] = self._operation_revision(operation)
            self._operations[operation["operationId"]] = operation
            self._persist()
        mutated = False
        try:
            for checkpoint in CHECKPOINTS:
                if operation["operationId"] in self._cancelled:
                    if mutated:
                        operation["status"] = "needs-reconcile"
                        operation["mutationState"] = "unknown"
                        operation["error"] = "Cancellation arrived after the mutation boundary."
                    else:
                        operation["status"] = "cancelled"
                        operation["mutationState"] = "none"
                        operation["error"] = None
                    break
                await self.adapter.checkpoint(checkpoint, plan)
                async with self._lock:
                    if operation["operationId"] in self._cancelled:
                        if mutated or checkpoint in {"apply", "validate", "commit"}:
                            operation["status"] = "needs-reconcile"
                            operation["mutationState"] = "unknown"
                            operation["error"] = "Cancellation arrived while the adapter was at or beyond the mutation boundary."
                        else:
                            operation["status"] = "cancelled"
                            operation["mutationState"] = "none"
                            operation["error"] = None
                        operation["revision"] = self._operation_revision(operation)
                        self._persist()
                        break
                    if checkpoint == "apply" and plan["changed"]:
                        self._apply_target(plan["resource"]["id"], target_item)
                        mutated = True
                        operation["mutationState"] = "complete"
                    operation["checkpoints"].append(checkpoint)
                    operation["inventoryRevision"] = inventory_revision(self._inventory)
                    operation["revision"] = self._operation_revision(operation)
                    self._persist()
            else:
                async with self._lock:
                    operation["status"] = "succeeded"
                    operation["mutationState"] = "complete" if plan["changed"] else "none"
        except FabricError as error:
            operation["status"] = "needs-reconcile" if mutated or error.change_state == "unknown" else "failed"
            operation["mutationState"] = "unknown" if operation["status"] == "needs-reconcile" else "none"
            operation["error"] = error.explanation
        except Exception as error:
            operation["status"] = "needs-reconcile" if mutated else "failed"
            operation["mutationState"] = "unknown" if operation["status"] == "needs-reconcile" else "none"
            operation["error"] = f"Software adapter raised an unexpected {type(error).__name__}."
        finally:
            async with self._lock:
                operation["inventoryRevision"] = inventory_revision(self._inventory)
                operation["revision"] = self._operation_revision(operation)
                self._persist()
                self._cancelled.discard(operation["operationId"])
        return self._result(operation)

    def _apply_target(self, app_id: str, target: Mapping[str, Any] | None) -> None:
        self._inventory = [item for item in self._inventory if item["catalogId"] != app_id]
        if target is not None:
            self._inventory.append(deepcopy(dict(target)))
        self._inventory.sort(key=lambda item: item["id"])

    def cancel(self, operation_id: str) -> None:
        operation = self._operations.get(operation_id)
        if operation is None:
            raise FabricError("packages.operation-missing", "Software operation is missing", "The requested operation is not in durable state.")
        if operation["status"] != "running":
            raise FabricError("packages.operation-terminal", "Software operation is already complete", "A terminal operation cannot be cancelled.")
        self._cancelled.add(operation_id)

    async def rollback(self, operation_id: str, expected_revision: str) -> dict[str, Any]:
        async with self._lock:
            operation = self._operations.get(operation_id)
            if operation is None:
                raise FabricError("packages.operation-missing", "Software operation is missing", "The requested operation is not in durable state.")
            if operation["status"] not in {"succeeded", "needs-reconcile"}:
                raise FabricError("packages.rollback-invalid", "Software rollback is unavailable", "Only a completed or reconciliation-required operation can be rolled back.")
            if inventory_revision(self._inventory) != expected_revision:
                raise FabricError("packages.inventory-drift", "Software inventory changed", "Rollback refuses to overwrite newer package state.", retryable=True)
            app_id = operation["plan"]["resource"]["id"]
            if any(
                candidate is not operation
                and candidate["sequence"] > operation["sequence"]
                and candidate["plan"]["resource"]["id"] == app_id
                and candidate["plan"]["changed"]
                and "apply" in candidate["checkpoints"]
                for candidate in self._operations.values()
            ):
                raise FabricError("packages.rollback-superseded", "Software rollback was superseded", "Another durable operation has crossed the mutation boundary for this software resource.", retryable=False)
            current = next((item for item in self._inventory if item["catalogId"] == app_id), None)
            if current not in (operation["targetItem"], operation["priorItem"]):
                raise FabricError("packages.rollback-drift", "Software rollback state drifted", "The current software resource no longer matches this operation's prior or target state.", retryable=False)
            self._apply_target(app_id, operation["priorItem"])
            operation["status"] = "rolled-back"
            operation["mutationState"] = "complete"
            operation["error"] = None
            operation["inventoryRevision"] = inventory_revision(self._inventory)
            operation["revision"] = self._operation_revision(operation)
            self._persist()
            return self._result(operation)

    async def reconcile(self) -> list[dict[str, Any]]:
        async with self._lock:
            output = []
            for operation in self._operations.values():
                if operation["status"] != "needs-reconcile":
                    continue
                target = operation["targetItem"]
                current = next((item for item in self._inventory if item["catalogId"] == operation["plan"]["resource"]["id"]), None)
                operation["status"] = "succeeded" if current == target else "failed"
                operation["mutationState"] = "complete" if current == target else "unknown"
                operation["error"] = None if current == target else "Current inventory does not match the operation target."
                operation["inventoryRevision"] = inventory_revision(self._inventory)
                operation["revision"] = self._operation_revision(operation)
                output.append(self._public_operation(operation))
            self._persist()
            return output

    @staticmethod
    def _result(operation: Mapping[str, Any]) -> dict[str, Any]:
        return {
            "schemaVersion": "v0", "provider": "packages.provider", "providerVersion": "v0",
            "action": operation["action"], "operationId": operation["operationId"], "status": operation["status"],
            "changed": "apply" in operation["checkpoints"] and operation["plan"]["changed"],
            "changeState": operation["mutationState"],
            "checkpoints": deepcopy(operation["checkpoints"]), "inventoryRevision": operation["inventoryRevision"],
            "state": {"operationId": operation["operationId"], "revision": operation["revision"], "status": operation["status"], "inventoryRevision": operation["inventoryRevision"], "targetState": "absent" if (operation["priorItem"] if operation["status"] == "rolled-back" else operation["targetItem"]) is None else "installed"},
            "error": operation["error"],
        }
