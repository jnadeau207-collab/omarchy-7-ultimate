"""Shared leaf execution mechanics; central Fabric owns durable operation records."""

from __future__ import annotations

import asyncio
import hashlib
import json
import os
import uuid
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Mapping, Protocol

from jsonschema import Draft202012Validator, FormatChecker, ValidationError

from omarchy_fabric.models import FabricError
from omarchy_fabric.security.principal import EndpointPrincipal

from ._immutable import freeze, thaw

JsonObject = Mapping[str, Any]

def canonical_json(value: Any) -> str:
    return json.dumps(value, allow_nan=False, ensure_ascii=False, separators=(",", ":"), sort_keys=True)

def state_revision(value: Any) -> str:
    return f"sha256.{hashlib.sha256(canonical_json(value).encode('utf-8')).hexdigest()}"

@dataclass(frozen=True)
class BackendSnapshot:
    available: bool
    operation_available: bool
    resources: tuple[Mapping[str, Any], ...]
    reason: FabricError | None = None

class LeafBackend(Protocol):
    async def snapshot(self) -> BackendSnapshot: ...

    async def replace(
        self,
        resource_id: str,
        resource: Mapping[str, Any],
        expected_revision: str,
    ) -> BackendSnapshot: ...

NormalizeArguments = Callable[[Mapping[str, Any]], dict[str, Any]]
TargetId = Callable[[Mapping[str, Any]], str]
ProposeState = Callable[[Mapping[str, Any], Mapping[str, Any]], dict[str, Any]]
DescribeChange = Callable[[Mapping[str, Any], Mapping[str, Any], Mapping[str, Any]], str]

@dataclass(frozen=True)
class DomainSpec:
    domain: str
    provider_id: str
    version: str
    resource_kind: str
    inventory_action: str
    operation_action: str
    normalize_arguments: NormalizeArguments
    target_id: TargetId
    propose_state: ProposeState
    describe_change: DescribeChange

class FakeBackend:
    """Hermetic resource backend with optional atomic persistence for restart tests."""

    def __init__(
        self,
        domain: str,
        resources: list[Mapping[str, Any]],
        *,
        state_path: Path | None = None,
        fail_on: frozenset[str] = frozenset(),
    ) -> None:
        if fail_on - {"snapshot", "apply"}:
            raise ValueError("fake backend failure points are snapshot or apply")
        self.domain = domain
        self.state_path = Path(state_path) if state_path is not None else None
        self.fail_on = fail_on
        self.write_count = 0
        self._lock = asyncio.Lock()
        self._resources = deepcopy(resources)
        if self.state_path is not None and self.state_path.exists():
            self._resources = self._load()

    def _load(self) -> list[dict[str, Any]]:
        assert self.state_path is not None
        raw = self.state_path.read_bytes()
        if len(raw) > 256 * 1024:
            raise ValueError("fake provider state exceeds 256 KiB")
        document = json.loads(raw)
        if (
            not isinstance(document, dict)
            or set(document) != {"schemaVersion", "domain", "resources"}
            or document["schemaVersion"] != "v0"
            or document["domain"] != self.domain
            or not isinstance(document["resources"], list)
            or len(document["resources"]) > 64
            or any(not isinstance(resource, dict) for resource in document["resources"])
        ):
            raise ValueError("fake provider state is invalid")
        return deepcopy(document["resources"])

    def _persist(self) -> None:
        if self.state_path is None:
            return
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        document = {"schemaVersion": "v0", "domain": self.domain, "resources": self._resources}
        payload = canonical_json(document).encode("utf-8")
        if len(payload) > 256 * 1024:
            raise ValueError("fake provider state exceeds 256 KiB")
        temporary = self.state_path.with_name(f".{self.state_path.name}.{uuid.uuid4().hex}.tmp")
        try:
            with temporary.open("xb") as stream:
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, self.state_path)
        finally:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass

    async def snapshot(self) -> BackendSnapshot:
        if "snapshot" in self.fail_on:
            raise FabricError(
                f"{self.domain}.fake-snapshot-failed",
                f"{self.domain.title()} fake inventory failed",
                "The hermetic backend produced its requested deterministic read failure.",
                retryable=True,
            )
        async with self._lock:
            return BackendSnapshot(True, True, tuple(freeze(deepcopy(self._resources))))

    async def replace(
        self,
        resource_id: str,
        resource: Mapping[str, Any],
        expected_revision: str,
    ) -> BackendSnapshot:
        if "apply" in self.fail_on:
            raise FabricError(
                f"{self.domain}.fake-apply-failed",
                f"{self.domain.title()} fake operation failed",
                "The hermetic backend produced its requested deterministic apply failure.",
                retryable=True,
            )
        async with self._lock:
            index = next(
                (index for index, candidate in enumerate(self._resources) if candidate.get("id") == resource_id),
                None,
            )
            if index is None:
                raise _resource_missing(self.domain, resource_id)
            current = self._resources[index]
            if state_revision(current.get("state")) != expected_revision:
                raise _stale_state(self.domain, resource_id)
            self._resources[index] = deepcopy(thaw(resource))
            self.write_count += 1
            self._persist()
            return BackendSnapshot(True, True, tuple(freeze(deepcopy(self._resources))))

    async def force_state(self, resource_id: str, value: Mapping[str, Any]) -> None:
        async with self._lock:
            resource = next(
                (candidate for candidate in self._resources if candidate.get("id") == resource_id),
                None,
            )
            if resource is None:
                raise KeyError(resource_id)
            resource["state"] = deepcopy(dict(value))
            self._persist()

class LeafProvider:
    def __init__(
        self,
        spec: DomainSpec,
        manifest: Mapping[str, Any],
        schemas: Mapping[str, Mapping[str, Any]],
        backend: LeafBackend,
    ) -> None:
        self.spec = spec
        self.manifest = freeze(thaw(manifest))
        self.schemas = freeze(thaw(schemas))
        self.backend = backend
        self._validators: dict[str, Draft202012Validator] = {}
        for schema_id, schema in schemas.items():
            document = thaw(schema)
            Draft202012Validator.check_schema(document)
            self._validators[schema_id] = Draft202012Validator(document, format_checker=FormatChecker())

    def _action(self, action: str, mode: str) -> Mapping[str, Any]:
        if not isinstance(action, str) or action not in self.manifest["actions"]:
            raise FabricError(
                f"{self.spec.domain}.action-unavailable",
                f"{self.spec.domain.title()} action is unavailable",
                "The provider does not expose the requested typed action.",
                detail=str(action)[:160],
            )
        definition = self.manifest["actions"][action]
        if definition["mode"] != mode:
            raise FabricError(
                f"{self.spec.domain}.action-mode-invalid",
                f"{self.spec.domain.title()} action mode is invalid",
                f"The action cannot be used through the {mode} provider seam.",
                detail=action,
            )
        return definition

    def _validate(self, reference: Mapping[str, Any], value: Any, label: str) -> None:
        validator = self._validators.get(reference["id"])
        if validator is None:
            raise FabricError(
                f"{self.spec.domain}.contract-missing",
                f"{self.spec.domain.title()} contract is missing",
                "The provider refuses to run without its exact versioned contract.",
            )
        try:
            validator.validate(thaw(value))
        except ValidationError as error:
            path = ".".join(str(part) for part in error.absolute_path)
            raise FabricError(
                f"{self.spec.domain}.contract-invalid",
                f"{self.spec.domain.title()} {label} is invalid",
                "The typed value does not satisfy the closed leaf contract.",
                detail=f"{label}{'.' + path if path else ''}",
            ) from error

    async def read(self, action: str, arguments: Mapping[str, Any]) -> Mapping[str, Any]:
        definition = self._action(action, "read")
        self._validate(definition["arguments"], arguments, "arguments")
        snapshot = await self._snapshot()
        result = self._inventory_result(snapshot)
        self._validate(definition["result"], result, "result")
        return result

    def _inventory_result(self, snapshot: BackendSnapshot) -> dict[str, Any]:
        return {
            "schemaVersion": self.spec.version,
            "provider": self.spec.provider_id,
            "providerVersion": self.spec.version,
            "action": self.spec.inventory_action,
            "availability": {
                "read": snapshot.available,
                "operation": snapshot.available and snapshot.operation_available,
                "reason": snapshot.reason.to_dict() if snapshot.reason is not None else None,
            },
            "revision": state_revision([thaw(resource) for resource in snapshot.resources]),
            "resources": [thaw(resource) for resource in snapshot.resources],
        }

    async def preflight(
        self,
        action: str,
        arguments: Mapping[str, Any],
        principal: EndpointPrincipal,
    ) -> Mapping[str, Any]:
        if not isinstance(principal, EndpointPrincipal):
            raise FabricError(
                "principal.required",
                "An authenticated Fabric principal is required",
                "Provider preflight accepts only a daemon-issued endpoint principal.",
            )
        definition = self._action(action, "operation")
        normalized = self._normalized(definition, arguments)
        snapshot = await self._available_snapshot(operation=True)
        resource = self._resource(snapshot, self.spec.target_id(normalized))
        current_state = self._state(resource)
        proposed_value = self._proposed(current_state["value"], normalized)
        proposed_state = self._state(resource, proposed_value)
        result = {
            "schemaVersion": self.spec.version,
            "provider": self.spec.provider_id,
            "providerVersion": self.spec.version,
            "action": action,
            "capability": definition["capability"],
            "resource": {"kind": self.spec.resource_kind, "id": resource["id"]},
            "normalizedArguments": normalized,
            "stateRevision": current_state["revision"],
            "currentState": current_state,
            "proposedState": proposed_state,
            "changed": current_state["value"] != proposed_state["value"],
            "summary": self.spec.describe_change(current_state["value"], proposed_state["value"], normalized),
            "risk": definition["risk"],
            "effects": list(definition["effects"]),
            "recovery": {"mode": "rollback", "priorState": current_state},
        }
        self._validate(definition["preflight"], result, "preflight")
        return result

    async def apply(
        self,
        action: str,
        normalized_arguments: Mapping[str, Any],
        expected_revision: str,
    ) -> Mapping[str, Any]:
        definition = self._action(action, "operation")
        normalized = self._normalized(definition, normalized_arguments)
        snapshot = await self._available_snapshot(operation=True)
        resource = self._resource(snapshot, self.spec.target_id(normalized))
        current_state = self._state(resource)
        if current_state["revision"] != expected_revision:
            raise _stale_state(self.spec.domain, resource["id"])
        proposed_value = self._proposed(current_state["value"], normalized)
        if current_state["value"] == proposed_value:
            return self._result(definition, action, resource, current_state, changed=False)
        replacement = thaw(resource)
        replacement["state"] = proposed_value
        updated = await self._replace(resource["id"], replacement, expected_revision)
        updated_resource = self._resource(updated, resource["id"])
        updated_state = self._state(updated_resource)
        if updated_state["value"] != proposed_value:
            raise FabricError(
                f"{self.spec.domain}.validation-failed",
                f"{self.spec.domain.title()} operation could not be validated",
                "The backend did not expose the exact requested state after apply.",
                retryable=True,
                change_state="unknown",
                recovery_actions=(f"{self.spec.domain}.rollback",),
            )
        return self._result(definition, action, updated_resource, updated_state, changed=True)

    async def validate(
        self,
        action: str,
        normalized_arguments: Mapping[str, Any],
        expected_state: Mapping[str, Any],
    ) -> Mapping[str, Any]:
        definition = self._action(action, "operation")
        normalized = self._normalized(definition, normalized_arguments)
        self._validate(definition["state"], expected_state, "expectedState")
        target_id = self.spec.target_id(normalized)
        if expected_state["resourceId"] != target_id:
            raise FabricError(
                f"{self.spec.domain}.resource-mismatch",
                f"{self.spec.domain.title()} resource identity changed",
                "Validation state belongs to a different stable resource.",
            )
        snapshot = await self._available_snapshot(operation=False)
        resource = self._resource(snapshot, target_id)
        actual = self._state(resource)
        if thaw(actual) != thaw(expected_state):
            raise FabricError(
                f"{self.spec.domain}.validation-failed",
                f"{self.spec.domain.title()} operation state drifted",
                "The current state does not match the exact expected revision and value.",
                retryable=True,
                change_state="unknown",
                recovery_actions=(f"{self.spec.domain}.rollback",),
            )
        return self._result(definition, action, resource, actual, changed=False)

    async def rollback(
        self,
        action: str,
        prior_state: Mapping[str, Any],
        expected_revision: str,
    ) -> Mapping[str, Any]:
        definition = self._action(action, "operation")
        if not definition["supportsRollback"]:
            raise FabricError(
                f"{self.spec.domain}.rollback-unavailable",
                f"{self.spec.domain.title()} rollback is unavailable",
                "The action contract does not permit rollback.",
            )
        self._validate(definition["state"], prior_state, "priorState")
        snapshot = await self._available_snapshot(operation=True)
        resource = self._resource(snapshot, prior_state["resourceId"])
        current = self._state(resource)
        if current["revision"] != expected_revision:
            raise _stale_state(self.spec.domain, resource["id"])
        if current["value"] == prior_state["value"]:
            return self._result(definition, action, resource, current, changed=False)
        replacement = thaw(resource)
        replacement["state"] = thaw(prior_state["value"])
        updated = await self._replace(resource["id"], replacement, expected_revision)
        updated_resource = self._resource(updated, resource["id"])
        updated_state = self._state(updated_resource)
        if thaw(updated_state) != thaw(prior_state):
            raise FabricError(
                f"{self.spec.domain}.rollback-failed",
                f"{self.spec.domain.title()} rollback could not be validated",
                "The backend did not restore the exact prior state fingerprint.",
                retryable=True,
                change_state="unknown",
                recovery_actions=("provider.reconcile",),
            )
        return self._result(definition, action, updated_resource, updated_state, changed=True)

    async def _snapshot(self) -> BackendSnapshot:
        try:
            snapshot = await self.backend.snapshot()
        except FabricError:
            raise
        except Exception as error:
            raise FabricError(
                f"{self.spec.domain}.backend-failed",
                f"{self.spec.domain.title()} backend failed",
                "The provider backend failed without a trusted typed result.",
                detail=type(error).__name__,
                retryable=True,
            ) from error
        return self._normalize_snapshot(snapshot)

    def _normalize_snapshot(self, snapshot: BackendSnapshot) -> BackendSnapshot:
        if not isinstance(snapshot, BackendSnapshot) or len(snapshot.resources) > 64:
            raise FabricError(
                f"{self.spec.domain}.backend-invalid",
                f"{self.spec.domain.title()} backend result is invalid",
                "The backend did not return the bounded typed snapshot contract.",
            )
        if (
            (not snapshot.available and (snapshot.operation_available or snapshot.resources or snapshot.reason is None))
            or (snapshot.available and snapshot.operation_available and snapshot.reason is not None)
            or (snapshot.available and not snapshot.operation_available and snapshot.reason is None)
        ):
            raise FabricError(
                f"{self.spec.domain}.backend-invalid",
                f"{self.spec.domain.title()} backend availability is invalid",
                "Read, operation, reason, and resource availability must describe one coherent state.",
            )
        resource_ids: list[str] = []
        for resource in snapshot.resources:
            resource_id = resource.get("id") if isinstance(resource, Mapping) else None
            if not isinstance(resource_id, str) or not 1 <= len(resource_id) <= 128:
                raise FabricError(
                    f"{self.spec.domain}.backend-invalid",
                    f"{self.spec.domain.title()} backend result is invalid",
                    "Every provider resource requires one bounded stable identity.",
                )
            resource_ids.append(resource_id)
        if len(resource_ids) != len(set(resource_ids)):
            raise FabricError(
                f"{self.spec.domain}.backend-invalid",
                f"{self.spec.domain.title()} backend result is invalid",
                "The backend returned duplicate stable resource identities.",
            )
        normalized = BackendSnapshot(
            snapshot.available,
            snapshot.operation_available,
            tuple(sorted(snapshot.resources, key=lambda resource: resource["id"])),
            snapshot.reason,
        )
        try:
            inventory_definition = self.manifest["actions"][self.spec.inventory_action]
            self._validate(inventory_definition["result"], self._inventory_result(normalized), "backendInventory")
        except FabricError as error:
            raise FabricError(
                f"{self.spec.domain}.backend-invalid",
                f"{self.spec.domain.title()} backend result is invalid",
                "The backend snapshot does not satisfy the closed inventory contract.",
                detail=error.detail,
            ) from error
        except (TypeError, ValueError) as error:
            raise FabricError(
                f"{self.spec.domain}.backend-invalid",
                f"{self.spec.domain.title()} backend result is invalid",
                "The backend snapshot cannot be represented as finite canonical JSON.",
                detail=type(error).__name__,
            ) from error
        return normalized

    async def _available_snapshot(self, *, operation: bool) -> BackendSnapshot:
        snapshot = await self._snapshot()
        if not snapshot.available or (operation and not snapshot.operation_available):
            reason = snapshot.reason
            raise FabricError(
                f"{self.spec.domain}.operation-unavailable" if operation else f"{self.spec.domain}.inventory-unavailable",
                f"{self.spec.domain.title()} operation is unavailable" if operation else f"{self.spec.domain.title()} inventory is unavailable",
                "The real provider is read-only until central durable operation authorization is integrated."
                if operation and snapshot.available
                else "The provider cannot establish trusted current state.",
                detail=reason.code if reason is not None else "",
                retryable=True,
                recovery_actions=("provider.reconnect",),
            )
        return snapshot

    def _normalized(self, definition: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
        self._validate(definition["arguments"], arguments, "arguments")
        try:
            normalized = self.spec.normalize_arguments(thaw(arguments))
        except (KeyError, TypeError, ValueError) as error:
            raise FabricError(
                f"{self.spec.domain}.arguments-invalid",
                f"{self.spec.domain.title()} arguments are invalid",
                "The provider could not normalize the closed typed arguments.",
            ) from error
        self._validate(definition["arguments"], normalized, "normalizedArguments")
        return normalized

    def _proposed(self, current: Mapping[str, Any], normalized: Mapping[str, Any]) -> dict[str, Any]:
        try:
            proposed = self.spec.propose_state(thaw(current), thaw(normalized))
        except (KeyError, TypeError, ValueError) as error:
            raise FabricError(
                f"{self.spec.domain}.precondition-failed",
                f"{self.spec.domain.title()} operation cannot run",
                "The current resource does not satisfy the action's closed preconditions.",
                detail=type(error).__name__,
                retryable=True,
                recovery_actions=(f"{self.spec.domain}.inventory.refresh",),
            ) from error
        if not isinstance(proposed, dict):
            raise FabricError(
                f"{self.spec.domain}.backend-invalid",
                f"{self.spec.domain.title()} proposed state is invalid",
                "The leaf did not produce a typed JSON object for the requested state.",
            )
        return proposed

    async def _replace(
        self,
        resource_id: str,
        replacement: Mapping[str, Any],
        expected_revision: str,
    ) -> BackendSnapshot:
        try:
            updated = await self.backend.replace(resource_id, replacement, expected_revision)
        except FabricError:
            raise
        except Exception as error:
            raise FabricError(
                f"{self.spec.domain}.backend-failed",
                f"{self.spec.domain.title()} backend failed during apply",
                "The backend did not return a trusted typed result after the requested transition.",
                detail=type(error).__name__,
                retryable=True,
                change_state="unknown",
                recovery_actions=(f"{self.spec.domain}.reconcile",),
            ) from error
        if not isinstance(updated, BackendSnapshot):
            raise FabricError(
                f"{self.spec.domain}.backend-invalid",
                f"{self.spec.domain.title()} backend result is invalid",
                "The apply backend did not return a typed snapshot.",
                change_state="unknown",
                recovery_actions=(f"{self.spec.domain}.reconcile",),
            )
        try:
            return self._normalize_snapshot(updated)
        except FabricError as error:
            raise FabricError(
                f"{self.spec.domain}.backend-invalid",
                f"{self.spec.domain.title()} backend result is invalid after apply",
                "The backend changed state but did not return a valid closed inventory snapshot.",
                detail=error.detail,
                retryable=True,
                change_state="unknown",
                recovery_actions=(f"{self.spec.domain}.reconcile",),
            ) from error

    def _resource(self, snapshot: BackendSnapshot, resource_id: str) -> Mapping[str, Any]:
        matches = [resource for resource in snapshot.resources if resource.get("id") == resource_id]
        if len(matches) != 1:
            raise _resource_missing(self.spec.domain, resource_id)
        return matches[0]

    @staticmethod
    def _state(resource: Mapping[str, Any], value: Mapping[str, Any] | None = None) -> dict[str, Any]:
        state_value = thaw(resource["state"] if value is None else value)
        return {
            "resourceId": resource["id"],
            "revision": state_revision(state_value),
            "value": state_value,
        }

    def _result(
        self,
        definition: Mapping[str, Any],
        action: str,
        resource: Mapping[str, Any],
        state: Mapping[str, Any],
        *,
        changed: bool,
    ) -> Mapping[str, Any]:
        result = {
            "schemaVersion": self.spec.version,
            "provider": self.spec.provider_id,
            "providerVersion": self.spec.version,
            "action": action,
            "capability": definition["capability"],
            "resource": {"kind": self.spec.resource_kind, "id": resource["id"]},
            "changed": changed,
            "changeState": "complete" if changed else "none",
            "stateRevision": state["revision"],
            "state": thaw(state),
            "error": None,
        }
        self._validate(definition["result"], result, "result")
        return result

def _resource_missing(domain: str, resource_id: str) -> FabricError:
    return FabricError(
        f"{domain}.resource-unavailable",
        f"{domain.title()} resource is unavailable",
        "The stable resource identity is not present in the current inventory.",
        detail=str(resource_id)[:128],
        retryable=True,
        recovery_actions=(f"{domain}.inventory.refresh",),
    )

def _stale_state(domain: str, resource_id: str) -> FabricError:
    return FabricError(
        f"{domain}.state-stale",
        f"{domain.title()} state changed",
        "The resource state fingerprint changed after preflight; request a new preflight.",
        detail=str(resource_id)[:128],
        retryable=True,
        recovery_actions=(f"{domain}.preflight",),
    )
