"""Hermetic durable compatibility deployment lifecycle."""

from __future__ import annotations

import asyncio
import hashlib
import json
import os
import uuid
from copy import deepcopy
from pathlib import Path
from typing import Any, Mapping

from jsonschema import Draft202012Validator

from omarchy_fabric.models import FabricError
from omarchy_fabric.security.principal import EndpointPrincipal
from omarchy_fabric.providers.packages.identity import REVISION_RE, STABLE_ID_RE, canonical_json, revision, stable_id

from .adapters import route_adapter
from .contracts import CONTRACTS
from .recipes import RecipeCatalog
from .router import CompatibilityRouter

CHECKPOINTS = ("verify-route", "prepare", "apply", "validate", "commit")
TERMINAL = {"succeeded", "failed", "cancelled", "rolled-back"}
MAX_STATE_BYTES = 2 * 1024 * 1024
MAX_OPERATIONS = 4096
_PLAN_VALIDATOR = Draft202012Validator(CONTRACTS["urn:omarchy:fabric:provider:compatibility:operation-preflight:v0"])


def _reject_json_constant(value: str) -> None:
    raise ValueError(f"invalid JSON constant: {value}")


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
        raise FabricError("compatibility.state-busy", "Compatibility state is busy", "Another process currently owns the durable journal write lock.", retryable=True, change_state="unknown") from error
    return descriptor


def _release_state_lock(descriptor: int | None) -> None:
    if descriptor is None:
        return
    import fcntl

    fcntl.flock(descriptor, fcntl.LOCK_UN)
    os.close(descriptor)


def deployment_revision(deployments: list[Mapping[str, Any]]) -> str:
    return revision(sorted((deepcopy(dict(item)) for item in deployments), key=lambda item: item["id"]))


class FakeCompatibilityAdapter:
    def __init__(self, *, fail_at: str | None = None, pause_at: str | None = None) -> None:
        if fail_at is not None and fail_at not in CHECKPOINTS:
            raise ValueError("compatibility failure checkpoint is invalid")
        if pause_at is not None and pause_at not in CHECKPOINTS:
            raise ValueError("compatibility pause checkpoint is invalid")
        self.fail_at = fail_at
        self.pause_at = pause_at
        self.calls: list[dict[str, Any]] = []
        self.entered = asyncio.Event()
        self.release = asyncio.Event()

    async def checkpoint(self, name: str, plan: Mapping[str, Any]) -> None:
        if name not in CHECKPOINTS:
            raise ValueError("compatibility checkpoint is invalid")
        self.calls.append({"checkpoint": name, "operationId": plan["operationId"], "decisionRevision": plan["decision"]["revision"]})
        if self.pause_at == name:
            self.entered.set()
            await self.release.wait()
        if self.fail_at == name:
            raise FabricError("compatibility.adapter-failed", "Compatibility adapter failed", "The hermetic adapter produced its requested deterministic failure.", detail=name, retryable=True, change_state="unknown" if name in {"apply", "validate", "commit"} else "none", recovery_actions=("compatibility.reconcile",))


class CompatibilityEngine:
    def __init__(self, recipes: RecipeCatalog, *, deployments: list[Mapping[str, Any]] | None = None, state_path: Path | None = None, adapter: FakeCompatibilityAdapter | None = None) -> None:
        self.recipes = recipes
        self.router = CompatibilityRouter(recipes)
        self.state_path = Path(state_path) if state_path is not None else None
        self.adapter = adapter or FakeCompatibilityAdapter()
        self._lock = asyncio.Lock()
        self._cancelled: set[str] = set()
        self._state_token: str | None = None
        self._deployments = self._validate_deployments(deployments or [])
        self._operations: dict[str, dict[str, Any]] = {}
        if self.state_path is not None and self.state_path.exists():
            self._load()
        changed = False
        for operation in self._operations.values():
            if operation["status"] == "running":
                operation["status"] = "needs-reconcile"
                operation["mutationState"] = "unknown"
                operation["error"] = "Fabric restarted during a compatibility transition."
                operation["revision"] = self._operation_revision(operation)
                changed = True
        if changed:
            self._persist()

    def _validate_deployments(self, values: list[Mapping[str, Any]]) -> list[dict[str, Any]]:
        required = {"id", "workloadId", "displayName", "decisionId", "decisionRevision", "route", "recipeId", "state", "permissions", "dataArtifacts"}
        if not isinstance(values, list) or len(values) > 2048:
            raise FabricError("compatibility.deployments-invalid", "Compatibility deployments are invalid", "Deployments must be a bounded array.")
        output: list[dict[str, Any]] = []
        identities: set[str] = set()
        workload_identities: set[str] = set()
        for value in values:
            if not isinstance(value, Mapping) or set(value) != required:
                raise FabricError("compatibility.deployments-invalid", "Compatibility deployments are invalid", "Every deployment must use the closed deployment shape.")
            item = deepcopy(dict(value))
            if (
                item["id"] in identities
                or item["workloadId"] in workload_identities
                or any(not isinstance(item[field], str) or not item[field] for field in ("id", "workloadId", "displayName", "decisionId", "decisionRevision", "route", "state"))
                or any(len(item[field]) > 160 for field in ("id", "workloadId", "displayName", "decisionId"))
                or any(STABLE_ID_RE.fullmatch(item[field]) is None for field in ("id", "workloadId", "decisionId"))
                or REVISION_RE.fullmatch(item["decisionRevision"]) is None
                or item["route"] not in {"native", "pwa", "known-good-recipe", "game-proton", "isolated-app", "vm"}
                or item["state"] not in {"installed", "partial", "broken"}
                or (item["recipeId"] is not None and (not isinstance(item["recipeId"], str) or STABLE_ID_RE.fullmatch(item["recipeId"]) is None))
                or not isinstance(item["permissions"], list)
                or not isinstance(item["dataArtifacts"], list)
                or len(item["permissions"]) > 16
                or len(item["dataArtifacts"]) > 64
                or any(not isinstance(value, str) for value in (*item["permissions"], *item["dataArtifacts"]))
                or any(value not in {"network", "audio", "camera", "microphone", "notifications", "filesystem-home", "filesystem-removable", "devices", "session"} for value in item["permissions"])
                or any(STABLE_ID_RE.fullmatch(value) is None for value in item["dataArtifacts"])
                or len(set(item["permissions"])) != len(item["permissions"])
                or len(set(item["dataArtifacts"])) != len(item["dataArtifacts"])
                or any(len(value) > 160 for value in item["dataArtifacts"])
                or item["id"] != stable_id("deployment.compatibility", item["workloadId"], item["route"])
            ):
                raise FabricError("compatibility.deployments-invalid", "Compatibility deployments are invalid", "Deployment identity or state is invalid.")
            if item["route"] == "known-good-recipe":
                recipe = self.recipes.recipes.get(item["recipeId"])
                if recipe is None or recipe["workloadId"] != item["workloadId"] or not set(item["permissions"]) <= set(recipe["permissions"]):
                    raise FabricError("compatibility.deployments-invalid", "Compatibility deployments are invalid", "Recipe deployments must name an exact admissible recipe for the workload.")
            elif item["recipeId"] is not None:
                raise FabricError("compatibility.deployments-invalid", "Compatibility deployments are invalid", "Non-recipe deployments cannot claim a recipe identity.")
            item["permissions"] = sorted(item["permissions"])
            item["dataArtifacts"] = sorted(item["dataArtifacts"])
            identities.add(item["id"])
            workload_identities.add(item["workloadId"])
            output.append(item)
        return sorted(output, key=lambda item: item["id"])

    def _load(self) -> None:
        assert self.state_path is not None
        with self.state_path.open("rb") as stream:
            raw = stream.read(MAX_STATE_BYTES + 1)
        if len(raw) > MAX_STATE_BYTES:
            raise FabricError("compatibility.state-corrupt", "Compatibility state is corrupt", "Durable compatibility state is too large.")
        try:
            document = json.loads(raw, parse_constant=_reject_json_constant)
        except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
            raise FabricError("compatibility.state-corrupt", "Compatibility state is corrupt", "Durable compatibility state is not UTF-8 JSON.", detail=type(error).__name__) from error
        if not isinstance(document, dict) or set(document) != {"schemaVersion", "recipeRevision", "deployments", "operations"} or document.get("schemaVersion") != "v0" or document.get("recipeRevision") != self.recipes.revision or not isinstance(document.get("operations"), list):
            raise FabricError("compatibility.state-corrupt", "Compatibility state is corrupt", "Durable state does not match its closed version or recipe revision.")
        self._deployments = self._validate_deployments(document["deployments"])
        operations: dict[str, dict[str, Any]] = {}
        request_ids: set[str] = set()
        required = {"operationId", "requestId", "sequence", "action", "plan", "status", "mutationState", "checkpoints", "priorDeployment", "targetDeployment", "deploymentRevision", "revision", "error", "exportArtifact"}
        if len(document["operations"]) > MAX_OPERATIONS:
            raise FabricError("compatibility.state-corrupt", "Compatibility state is corrupt", "The durable operation count exceeds its bounded contract.")
        for operation in document["operations"]:
            if (
                not isinstance(operation, dict)
                or set(operation) != required
                or operation["operationId"] in operations
                or operation.get("requestId") in request_ids
                or not isinstance(operation["sequence"], int)
                or isinstance(operation["sequence"], bool)
                or operation["sequence"] < 1
                or any(candidate["sequence"] == operation["sequence"] for candidate in operations.values())
                or operation["status"] not in TERMINAL | {"running", "needs-reconcile"}
                or operation["mutationState"] not in {"none", "complete", "unknown"}
                or operation["action"] not in {"deploy", "remove", "export"}
                or not isinstance(operation["operationId"], str)
                or STABLE_ID_RE.fullmatch(operation["operationId"]) is None
                or not isinstance(operation["requestId"], str)
                or STABLE_ID_RE.fullmatch(operation["requestId"]) is None
                or not isinstance(operation["checkpoints"], list)
                or operation["checkpoints"] != list(CHECKPOINTS[:len(operation["checkpoints"])])
                or not isinstance(operation["plan"], dict)
            ):
                raise FabricError("compatibility.state-corrupt", "Compatibility state is corrupt", "A durable compatibility operation is invalid.")
            if not self._valid_persisted_operation(operation) or operation["revision"] != self._operation_revision(operation):
                raise FabricError("compatibility.state-corrupt", "Compatibility state is corrupt", "A durable compatibility operation revision or nested plan is invalid.")
            operations[operation["operationId"]] = deepcopy(operation)
            request_ids.add(operation["requestId"])
        self._operations = operations
        self._state_token = hashlib.sha256(raw).hexdigest()

    def _valid_persisted_operation(self, operation: Mapping[str, Any]) -> bool:
        try:
            plan = operation["plan"]
            if next(iter(_PLAN_VALIDATOR.iter_errors(plan)), None) is not None:
                return False
            normalized = plan["normalizedArguments"]
            workload_id = normalized["request"]["id"]
            decision = self.router.decide(normalized["request"], normalized["host"])
            prior = self._validated_deployment_or_none(operation["priorDeployment"])
            target = self._validated_deployment_or_none(operation["targetDeployment"])
            if (
                plan["operationId"] != operation["operationId"]
                or plan["action"] != operation["action"]
                or normalized["requestId"] != operation["requestId"]
                or normalized["recipeRevision"] != self.recipes.revision
                or normalized["expectedDeploymentRevision"] != plan["deploymentRevision"]
                or plan["decision"] != decision
                or plan["operationId"] != stable_id("operation.compatibility", operation["requestId"], workload_id)
                or plan["planRevision"] != revision({**plan, "planRevision": "sha256." + "0" * 64})
                or plan["recovery"]["priorDeployment"] != operation["priorDeployment"]
                or plan["recovery"]["exportArtifact"] != operation["exportArtifact"]
                or operation["exportArtifact"] != (self._export_artifact(prior) if operation["action"] == "export" else None)
                or target != self._target_deployment(operation["action"], normalized["request"], decision, prior)
                or plan["changed"] != (operation["action"] == "export" or prior != target)
                or plan["lifecycle"]["permissions"] != (decision["requiredPermissions"] if operation["action"] == "deploy" else prior["permissions"])
                or not isinstance(operation["deploymentRevision"], str)
                or REVISION_RE.fullmatch(operation["deploymentRevision"]) is None
                or not isinstance(operation["error"], (str, type(None)))
                or (isinstance(operation["error"], str) and len(operation["error"]) > 1000)
                or (operation["status"] == "needs-reconcile" and operation["mutationState"] != "unknown")
                or (operation["status"] == "rolled-back" and operation["mutationState"] != "complete")
                or (operation["status"] == "succeeded" and operation["mutationState"] != ("complete" if plan["changed"] else "none"))
                or (operation["status"] == "succeeded" and operation["checkpoints"] != list(CHECKPOINTS))
            ):
                return False
            selected_route = decision["selectedRoute"] if operation["action"] == "deploy" else prior["route"]
            if plan["adapter"] != route_adapter(selected_route, {}).public():
                return False
            action = operation["action"]
            selected_recipe = decision["recipeId"] if action == "deploy" else prior["recipeId"]
            recipe = self.recipes.recipes.get(selected_recipe) if selected_recipe else None
            if action == "deploy" and decision["eligibility"] != "supported":
                return False
            if action in {"remove", "export"} and prior is None:
                return False
            if prior is not None and prior["workloadId"] != workload_id:
                return False
            if action == "export" and recipe is not None and recipe["exportPolicy"] == "unsupported":
                return False
            expected_removal = deepcopy(recipe["removalPlan"]) if recipe is not None else {
                "preserve": deepcopy(prior["dataArtifacts"] if prior and normalized["preserveData"] else []),
                "delete": ["runtime.compatibility", "launcher.desktop-entry"],
            }
            if not normalized["preserveData"]:
                expected_removal["delete"] = sorted(set(expected_removal["delete"] + expected_removal["preserve"]))
                expected_removal["preserve"] = []
            display_name = normalized["request"]["name"] if action == "deploy" else prior["displayName"]
            expected_summary = {
                "deploy": f"Deploy {display_name} through the {selected_route} route.",
                "remove": f"Remove {display_name} using its declared data disposition.",
                "export": f"Export the portable data projection for {display_name}.",
            }[action]
            if (
                plan["summary"] != expected_summary
                or plan["risk"] != {"deploy": "consequential", "remove": "destructive", "export": "low"}[action]
                or plan["effects"] != {"deploy": ["mutating", "download"], "remove": ["mutating", "destructive"], "export": ["mutating"]}[action]
                or plan["lifecycle"]["checkpoints"] != list(CHECKPOINTS)
                or plan["recovery"]["preserveData"] != normalized["preserveData"]
                or plan["recovery"]["removalPlan"] != expected_removal
            ):
                return False
            return True
        except (KeyError, TypeError, ValueError, FabricError):
            return False

    def _validated_deployment_or_none(self, value: Any) -> dict[str, Any] | None:
        if value is None:
            return None
        return self._validate_deployments([value])[0]

    def _persist(self) -> None:
        if self.state_path is None:
            return
        document = {"schemaVersion": "v0", "recipeRevision": self.recipes.revision, "deployments": self._deployments, "operations": sorted(self._operations.values(), key=lambda item: item["sequence"])}
        payload = canonical_json(document).encode("utf-8")
        if len(payload) > MAX_STATE_BYTES:
            raise FabricError("compatibility.state-too-large", "Compatibility state is too large", "Durable compatibility state exceeds its bounded contract.")
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        lock_descriptor = _acquire_state_lock(self.state_path)
        try:
            if self.state_path.exists():
                with self.state_path.open("rb") as stream:
                    current = stream.read(MAX_STATE_BYTES + 1)
                if len(current) > MAX_STATE_BYTES:
                    raise FabricError("compatibility.state-concurrent", "Compatibility state changed concurrently", "The current durable journal exceeds its bounded contract.", retryable=False, change_state="unknown")
                current_token = hashlib.sha256(current).hexdigest()
                if self._state_token != current_token:
                    raise FabricError("compatibility.state-concurrent", "Compatibility state changed concurrently", "This engine instance no longer owns the exact durable journal revision.", retryable=True, change_state="unknown")
            elif self._state_token is not None:
                raise FabricError("compatibility.state-concurrent", "Compatibility state changed concurrently", "The durable journal disappeared after this engine loaded it.", retryable=True, change_state="unknown")
            temporary = self.state_path.with_name(f".{self.state_path.name}.{uuid.uuid4().hex}.tmp")
            try:
                with temporary.open("xb") as stream:
                    stream.write(payload); stream.flush(); os.fsync(stream.fileno())
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
        payload = deepcopy(dict(operation)); payload["revision"] = "sha256." + "0" * 64
        return revision(payload)

    def deployments(self) -> dict[str, Any]:
        return {"schemaVersion": "v0", "provider": "compatibility.provider", "revision": deployment_revision(self._deployments), "deployments": deepcopy(self._deployments)}

    def preflight(self, action: str, arguments: Mapping[str, Any], principal: EndpointPrincipal) -> dict[str, Any]:
        if not isinstance(principal, EndpointPrincipal):
            raise FabricError("principal.required", "An authenticated Fabric principal is required", "Compatibility preflight accepts only a daemon-issued endpoint principal.")
        return self._plan(action, arguments)

    def _plan(self, action: str, arguments: Mapping[str, Any]) -> dict[str, Any]:
        if arguments["recipeRevision"] != self.recipes.revision:
            raise FabricError("compatibility.recipe-drift", "Compatibility recipes changed", "The selected recipe revision is stale.", retryable=True, recovery_actions=("compatibility.recipes.refresh",))
        current_revision = deployment_revision(self._deployments)
        if arguments["expectedDeploymentRevision"] != current_revision:
            raise FabricError("compatibility.deployment-drift", "Compatibility deployments changed", "The operation was planned from stale deployment state.", retryable=True, recovery_actions=("compatibility.deployments.refresh",))
        decision = self.router.decide(arguments["request"], arguments["host"])
        workload_id = arguments["request"]["id"]
        prior = next((item for item in self._deployments if item["workloadId"] == workload_id), None)
        if action == "deploy" and decision["eligibility"] != "supported":
            raise FabricError("compatibility.unsupported", "Workload is unsupported", decision["explanation"], detail=decision["reasonCode"])
        if action in {"remove", "export"} and prior is None:
            raise FabricError("compatibility.deployment-missing", "Compatibility deployment is missing", "Removal and export require an installed compatibility deployment.", detail=workload_id)
        selected_route = decision["selectedRoute"] if action == "deploy" else prior["route"]
        selected_recipe = decision["recipeId"] if action == "deploy" else prior["recipeId"]
        recipe = self.recipes.recipes.get(selected_recipe) if selected_recipe else None
        if action == "export" and recipe is not None and recipe["exportPolicy"] == "unsupported":
            raise FabricError("compatibility.export-unsupported", "Compatibility export is unsupported", "The reviewed recipe explicitly prohibits a trustworthy export.")
        target = self._target_deployment(action, arguments["request"], decision, prior)
        changed = action == "export" or prior != target
        adapter = route_adapter(selected_route, {"requestId": arguments["requestId"], "workloadId": workload_id, "action": action})
        removal = deepcopy(recipe["removalPlan"]) if recipe is not None else {"preserve": deepcopy(prior["dataArtifacts"] if prior and arguments["preserveData"] else []), "delete": ["runtime.compatibility", "launcher.desktop-entry"]}
        if not arguments["preserveData"]:
            removal["delete"] = sorted(set(removal["delete"] + removal["preserve"])); removal["preserve"] = []
        export_artifact = self._export_artifact(prior) if action == "export" else None
        lifecycle_permissions = decision["requiredPermissions"] if action == "deploy" else deepcopy(prior["permissions"])
        display_name = arguments["request"]["name"] if action == "deploy" else prior["displayName"]
        core = {
            "schemaVersion": "v0", "provider": "compatibility.provider", "providerVersion": "v0", "action": action,
            "operationId": stable_id("operation.compatibility", arguments["requestId"], workload_id), "normalizedArguments": deepcopy(dict(arguments)),
            "decision": decision, "deploymentRevision": current_revision, "changed": changed,
            "summary": {"deploy": f"Deploy {display_name} through the {selected_route} route.", "remove": f"Remove {display_name} using its declared data disposition.", "export": f"Export the portable data projection for {display_name}."}[action],
            "risk": {"deploy": "consequential", "remove": "destructive", "export": "low"}[action],
            "effects": {"deploy": ["mutating", "download"], "remove": ["mutating", "destructive"], "export": ["mutating"]}[action],
            "adapter": adapter.public(), "lifecycle": {"checkpoints": list(CHECKPOINTS), "permissions": lifecycle_permissions},
            "recovery": {"priorDeployment": deepcopy(prior), "preserveData": arguments["preserveData"], "removalPlan": removal, "exportArtifact": export_artifact},
        }
        core["planRevision"] = revision({**core, "planRevision": "sha256." + "0" * 64})
        core["_targetDeployment"] = target
        return core

    @staticmethod
    def _export_artifact(prior: Mapping[str, Any]) -> dict[str, Any]:
        content = {"workloadId": prior["workloadId"], "decisionRevision": prior["decisionRevision"], "dataArtifacts": sorted(prior["dataArtifacts"])}
        content_revision = revision(content)
        return {"id": stable_id("artifact.compatibility", prior["workloadId"], prior["decisionRevision"], content_revision), "format": "compatibility-export-v0", "contentRevision": content_revision}

    @staticmethod
    def _target_deployment(action: str, request: Mapping[str, Any], decision: Mapping[str, Any], prior: Mapping[str, Any] | None) -> dict[str, Any] | None:
        if action == "remove":
            return None
        if action == "export":
            return deepcopy(dict(prior))
        return {"id": stable_id("deployment.compatibility", request["id"], decision["selectedRoute"]), "workloadId": request["id"], "displayName": request["name"], "decisionId": decision["decisionId"], "decisionRevision": decision["revision"], "route": decision["selectedRoute"], "recipeId": decision["recipeId"], "state": "installed", "permissions": decision["requiredPermissions"], "dataArtifacts": []}

    async def apply(self, action: str, arguments: Mapping[str, Any], expected_revision: str) -> dict[str, Any]:
        async with self._lock:
            prior_operation = next((item for item in self._operations.values() if item["requestId"] == arguments["requestId"]), None)
            if prior_operation is not None:
                if prior_operation["action"] != action or prior_operation["plan"]["normalizedArguments"] != dict(arguments):
                    raise FabricError("compatibility.idempotency-conflict", "Compatibility request conflicts", "The request ID is already bound to different normalized arguments.")
                return self._result(prior_operation)
            plan = self._plan(action, arguments)
            if expected_revision != plan["deploymentRevision"]:
                raise FabricError("compatibility.deployment-drift", "Compatibility deployments changed", "The durable operation expected a different deployment revision.", retryable=True)
            if any(item["status"] in {"running", "needs-reconcile"} for item in self._operations.values()):
                raise FabricError("compatibility.operation-conflict", "Compatibility operation conflicts", "The global deployment revision is owned by another running or reconciliation-required operation.", retryable=True)
            target = plan.pop("_targetDeployment")
            operation = {"operationId": plan["operationId"], "requestId": arguments["requestId"], "sequence": max((item["sequence"] for item in self._operations.values()), default=0) + 1, "action": action, "plan": plan, "status": "running", "mutationState": "none", "checkpoints": [], "priorDeployment": plan["recovery"]["priorDeployment"], "targetDeployment": target, "deploymentRevision": expected_revision, "revision": "sha256." + "0" * 64, "error": None, "exportArtifact": plan["recovery"]["exportArtifact"]}
            operation["revision"] = self._operation_revision(operation); self._operations[operation["operationId"]] = operation; self._persist()
        mutated = False
        try:
            for checkpoint in CHECKPOINTS:
                if operation["operationId"] in self._cancelled:
                    operation["status"] = "needs-reconcile" if mutated else "cancelled"
                    operation["mutationState"] = "unknown" if mutated else "none"
                    operation["error"] = "Cancellation arrived after the mutation boundary." if mutated else None
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
                        if action != "export":
                            self._set_target(arguments["request"]["id"], target)
                        mutated = True
                        operation["mutationState"] = "complete"
                    operation["checkpoints"].append(checkpoint); operation["deploymentRevision"] = deployment_revision(self._deployments); operation["revision"] = self._operation_revision(operation); self._persist()
            else:
                async with self._lock:
                    operation["status"] = "succeeded"
                    operation["mutationState"] = "complete" if plan["changed"] else "none"
        except FabricError as error:
            operation["status"] = "needs-reconcile" if mutated or error.change_state == "unknown" else "failed"; operation["mutationState"] = "unknown" if operation["status"] == "needs-reconcile" else "none"; operation["error"] = error.explanation
        except Exception as error:
            operation["status"] = "needs-reconcile" if mutated else "failed"
            operation["mutationState"] = "unknown" if operation["status"] == "needs-reconcile" else "none"
            operation["error"] = f"Compatibility adapter raised an unexpected {type(error).__name__}."
        finally:
            async with self._lock:
                operation["deploymentRevision"] = deployment_revision(self._deployments); operation["revision"] = self._operation_revision(operation); self._persist(); self._cancelled.discard(operation["operationId"])
        return self._result(operation)

    def _set_target(self, workload_id: str, target: Mapping[str, Any] | None) -> None:
        self._deployments = [item for item in self._deployments if item["workloadId"] != workload_id]
        if target is not None:
            self._deployments.append(deepcopy(dict(target)))
        self._deployments.sort(key=lambda item: item["id"])

    def cancel(self, operation_id: str) -> None:
        operation = self._operations.get(operation_id)
        if operation is None:
            raise FabricError("compatibility.operation-missing", "Compatibility operation is missing", "The requested operation is absent from durable state.")
        if operation["status"] != "running":
            raise FabricError("compatibility.operation-terminal", "Compatibility operation is complete", "A terminal operation cannot be cancelled.")
        self._cancelled.add(operation_id)

    async def rollback(self, operation_id: str, expected_revision: str) -> dict[str, Any]:
        async with self._lock:
            operation = self._operations.get(operation_id)
            if operation is None:
                raise FabricError("compatibility.operation-missing", "Compatibility operation is missing", "The requested operation is absent from durable state.")
            if operation["status"] not in {"succeeded", "needs-reconcile"}:
                raise FabricError("compatibility.rollback-invalid", "Compatibility rollback is unavailable", "Only a completed or reconciliation-required operation can be rolled back.")
            if deployment_revision(self._deployments) != expected_revision:
                raise FabricError("compatibility.deployment-drift", "Compatibility deployments changed", "Rollback refuses to overwrite newer deployment state.", retryable=True)
            workload_id = operation["plan"]["normalizedArguments"]["request"]["id"]
            if any(
                candidate is not operation
                and candidate["sequence"] > operation["sequence"]
                and candidate["plan"]["normalizedArguments"]["request"]["id"] == workload_id
                and candidate["plan"]["changed"]
                and "apply" in candidate["checkpoints"]
                for candidate in self._operations.values()
            ):
                raise FabricError("compatibility.rollback-superseded", "Compatibility rollback was superseded", "Another durable operation has crossed the mutation boundary for this workload.")
            current = next((item for item in self._deployments if item["workloadId"] == workload_id), None)
            if current not in (operation["targetDeployment"], operation["priorDeployment"]):
                raise FabricError("compatibility.rollback-drift", "Compatibility rollback state drifted", "The current deployment no longer matches this operation's prior or target state.")
            self._set_target(workload_id, operation["priorDeployment"])
            operation["status"] = "rolled-back"; operation["mutationState"] = "complete"; operation["error"] = None; operation["deploymentRevision"] = deployment_revision(self._deployments); operation["revision"] = self._operation_revision(operation); self._persist()
            return self._result(operation)

    async def reconcile(self) -> list[dict[str, Any]]:
        async with self._lock:
            results = []
            for operation in self._operations.values():
                if operation["status"] != "needs-reconcile":
                    continue
                workload_id = operation["plan"]["normalizedArguments"]["request"]["id"]
                current = next((item for item in self._deployments if item["workloadId"] == workload_id), None)
                target = operation["targetDeployment"]
                if operation["action"] == "export":
                    operation["status"] = "failed"
                    operation["mutationState"] = "unknown"
                    operation["error"] = "Export completion cannot be proven from deployment inventory alone."
                else:
                    operation["status"] = "succeeded" if current == target else "failed"
                    operation["mutationState"] = "complete" if current == target else "unknown"
                    operation["error"] = None if current == target else "Current deployments do not match the operation target."
                operation["deploymentRevision"] = deployment_revision(self._deployments); operation["revision"] = self._operation_revision(operation)
                results.append(self._result(operation))
            self._persist(); return results

    @staticmethod
    def _result(operation: Mapping[str, Any]) -> dict[str, Any]:
        target_state = "exported" if operation["action"] == "export" else ("absent" if operation["targetDeployment"] is None else "installed")
        if operation["status"] == "rolled-back":
            target_state = "absent" if operation["priorDeployment"] is None else "installed"
        return {"schemaVersion": "v0", "provider": "compatibility.provider", "providerVersion": "v0", "action": operation["action"], "operationId": operation["operationId"], "status": operation["status"], "changed": "apply" in operation["checkpoints"] and operation["plan"]["changed"], "changeState": operation["mutationState"], "checkpoints": deepcopy(operation["checkpoints"]), "deploymentRevision": operation["deploymentRevision"], "state": {"operationId": operation["operationId"], "revision": operation["revision"], "status": operation["status"], "deploymentRevision": operation["deploymentRevision"], "targetState": target_state}, "error": operation["error"], "exportArtifact": deepcopy(operation["exportArtifact"])}
