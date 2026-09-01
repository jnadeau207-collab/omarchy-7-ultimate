"""Project Software Center preflight onto the durable coordinator contract.

Package v0 preflight is a catalog/inventory plan. The coordinator requires
resource-scoped current/proposed state, a typed RiskLevel, and a system-executor
intent. This module maps those fields without editing the v0 provider schema
and without putting pacman on the session executor.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from copy import deepcopy
from typing import Any, Mapping

from ..models import FabricError, FixedArgvCommand
from ..security.normalize import normalize_json
from ..security.system_executor import validate_system_executor_request
from .contracts import ExecutorIntent, OperationDefinition, OperationPlan, operation_error
from .executor import (
    CancellationProbe,
    ExecutorApplyResult,
    ExecutorReconcileResult,
    IntentCatalog,
    IntentDefinition,
)
from .registry_gateway import RegistryOperationGateway

PRIVILEGED_PACKAGE_INTENTS = frozenset({"packages.install", "packages.remove"})
SYSTEM_EXECUTOR = "/usr/libexec/omarchy-fabric-system-executor"


def _package_ids(value: Any) -> tuple[str, ...]:
    # Durable intents freeze arrays as tuples; accept both JSON list and frozen form.
    if isinstance(value, (str, bytes, bytearray)) or not isinstance(value, Sequence) or len(value) != 1:
        raise ValueError("package_ids must name exactly one catalog entry")
    item = value[0]
    if not isinstance(item, str) or not item or len(item) > 160:
        raise ValueError("package id is invalid")
    return (item,)


def _resource_id(value: Any) -> str:
    if not isinstance(value, str) or not value or len(value) > 160:
        raise ValueError("resource id is invalid")
    return value


def _preserve_data(value: Any) -> bool:
    if not isinstance(value, bool):
        raise ValueError("preserve_data must be boolean")
    return value


def package_intents() -> tuple[IntentDefinition, ...]:
    return (
        IntentDefinition(
            "packages.install",
            FixedArgvCommand(SYSTEM_EXECUTOR, ("packages.install",)),
            required={"resourceId": _resource_id, "package_ids": _package_ids},
        ),
        IntentDefinition(
            "packages.remove",
            FixedArgvCommand(SYSTEM_EXECUTOR, ("packages.remove",)),
            required={
                "resourceId": _resource_id,
                "package_ids": _package_ids,
                "preserve_data": _preserve_data,
            },
        ),
    )


def package_definitions() -> tuple[OperationDefinition, ...]:
    return (
        OperationDefinition(
            "packages.provider",
            "install",
            "packages.install",
            lambda preflight: {
                "resourceId": preflight["resource"]["id"],
                "package_ids": [preflight["resource"]["id"]],
            },
        ),
        OperationDefinition(
            "packages.provider",
            "remove",
            "packages.remove",
            lambda preflight: {
                "resourceId": preflight["resource"]["id"],
                "package_ids": [preflight["resource"]["id"]],
                "preserve_data": preflight["normalizedArguments"]["preserveUserData"],
            },
        ),
    )


def _coordinator_risk(value: str) -> str:
    if value == "destructive":
        return "high"
    if value == "consequential":
        return "consequential"
    raise operation_error("operation.preflight-invalid", "Package operation risk is not coordinator-admissible.")


def _state_value(item: Mapping[str, Any] | None, app_id: str, digest: str | None) -> dict[str, Any]:
    if item is None:
        return {"catalogId": app_id, "present": False, "artifactDigest": None, "adopted": False}
    return {
        "catalogId": app_id,
        "present": True,
        "artifactDigest": item.get("artifactDigest", digest),
        "adopted": bool(item.get("adopted")),
    }


def project_package_preflight(envelope: Mapping[str, Any]) -> dict[str, Any]:
    inner = envelope["preflight"]
    app_id = inner["resource"]["id"]
    revision = inner["inventoryRevision"]
    prior = inner["recovery"]["priorItem"]
    digest = inner["provenance"]["artifactDigest"]
    if inner["action"] == "remove":
        proposed_item = None
    else:
        proposed_item = prior if prior is not None and not inner["changed"] else {
            "catalogId": app_id,
            "artifactDigest": digest,
            "adopted": True,
        }
    current = {"resourceId": app_id, "revision": revision, "value": _state_value(prior, app_id, digest)}
    proposed = {
        "resourceId": app_id,
        "revision": "proposal.unapplied" if inner["changed"] else revision,
        "value": _state_value(proposed_item, app_id, digest),
    }
    risk = _coordinator_risk(inner["risk"])
    projected = {
        "schemaVersion": "v0",
        "provider": inner["provider"],
        "providerVersion": inner["providerVersion"],
        "action": inner["action"],
        "capability": envelope["capability"],
        "resource": inner["resource"],
        "normalizedArguments": inner["normalizedArguments"],
        "stateRevision": revision,
        "currentState": current,
        "proposedState": proposed,
        "changed": inner["changed"],
        "summary": inner["summary"],
        "risk": risk,
        "effects": list(inner["effects"]),
        "recovery": {"mode": inner["recovery"]["mode"], "priorState": current},
    }
    return {
        "provider": envelope["provider"],
        "providerVersion": envelope["providerVersion"],
        "providerFingerprint": envelope["providerFingerprint"],
        "generation": envelope["generation"],
        "action": envelope["action"],
        "capability": envelope["capability"],
        "risk": risk,
        "effects": list(envelope["effects"]),
        "preflight": projected,
        "observedAt": envelope["observedAt"],
    }


class CoordinatedRegistryGateway:
    """Registry preflight plus package-to-coordinator projection."""

    def __init__(self, registry: Any) -> None:
        self._inner = RegistryOperationGateway(registry=registry)

    async def preflight(self, provider_id, action, arguments, principal):
        envelope = await self._inner.preflight(provider_id, action, arguments, principal)
        if provider_id == "packages.provider" and action in {"install", "remove"}:
            return project_package_preflight(envelope)
        if provider_id == "compatibility.provider" and action in {"deploy", "remove", "export"}:
            from .compatibility_plane import project_compatibility_preflight

            return project_compatibility_preflight(envelope)
        if provider_id == "device.provider" and action == "authorization.plan":
            from .device_plane import project_device_preflight

            return project_device_preflight(envelope)
        return envelope

    def assert_current(self, binding):
        return self._inner.assert_current(binding)


def build_system_executor_document(plan: OperationPlan, intent: ExecutorIntent) -> dict[str, Any]:
    action = "packages.install" if intent.intent_id == "packages.install" else "packages.remove"
    arguments = {"package_ids": list(intent.payload["package_ids"])}
    if action == "packages.remove":
        arguments["preserve_data"] = intent.payload["preserve_data"]
    return {
        "schemaVersion": "v0",
        "requestId": str(uuid.uuid4()),
        "operationId": plan.operation_id,
        "action": action,
        "arguments": arguments,
        "providerVersion": plan.provider.version,
        "stateRevision": plan.resource.revision,
        "approvalBinding": plan.binding_digest,
        "consentNonce": str(uuid.uuid4()),
    }


class HermeticPackageExecutor:
    """Coordinator executor that drives the hermetic package engine.

    It validates a system-executor request and applies through the existing
    package journal. It never invokes a package manager.
    """

    available = True

    def __init__(self, engine: Any, catalog: IntentCatalog) -> None:
        self.engine = engine
        self.catalog = catalog
        self.calls: list[tuple[str, str]] = []
        self.system_requests: list[dict[str, Any]] = []

    def _resolve(self, plan: OperationPlan, intent: ExecutorIntent) -> None:
        self.catalog.resolve(intent)
        if intent.digest != plan.intent.digest:
            raise operation_error("executor.intent-drift", "Executor intent does not match the durable plan.")
        if intent.payload.get("resourceId") != plan.resource.resource_id:
            raise operation_error("executor.resource-drift", "Executor payload targets another resource.")

    def _observe(self, app_id: str) -> dict[str, Any]:
        inventory = self.engine.inventory(include_unmanaged=True)
        item = next((entry for entry in inventory["items"] if entry["catalogId"] == app_id), None)
        return {
            "resourceId": app_id,
            "revision": inventory["revision"],
            "value": _state_value(item, app_id, item["artifactDigest"] if item is not None else None),
        }

    def _system_request(self, plan: OperationPlan, intent: ExecutorIntent) -> None:
        document = build_system_executor_document(plan, intent)
        validate_system_executor_request(document)
        self.system_requests.append(document)

    async def apply(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        cancelled: CancellationProbe,
    ) -> ExecutorApplyResult:
        self._resolve(plan, intent)
        if cancelled():
            raise operation_error("operation.cancelled", "Execution observed durable cancellation.")
        self._system_request(plan, intent)
        action = "install" if intent.intent_id == "packages.install" else "remove"
        result = await self.engine.apply(action, dict(plan.normalized_arguments), plan.resource.revision)
        if result["status"] != "succeeded":
            raise FabricError(
                "packages.adapter-failed",
                "Software adapter failed",
                result.get("error") or "The hermetic package engine did not succeed.",
                change_state="unknown",
            )
        self.calls.append(("apply", plan.operation_id))
        observed = self._observe(plan.resource.resource_id)
        return ExecutorApplyResult(observed["revision"], observed, {"stage": "apply", "engineStatus": result["status"]})

    async def validate(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        expected_state: Mapping[str, Any],
        cancelled: CancellationProbe,
    ) -> Mapping[str, Any]:
        self._resolve(plan, intent)
        if cancelled():
            raise operation_error("operation.cancelled", "Execution observed durable cancellation.", change_state="unknown")
        observed = self._observe(plan.resource.resource_id)
        expected = normalize_json(dict(expected_state).get("value"))
        self.calls.append(("validate", plan.operation_id))
        return {"observedState": observed, "matchesExpected": observed["value"] == expected}

    async def rollback(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        prior_state: Mapping[str, Any],
        expected_revision: str,
        cancelled: CancellationProbe,
    ) -> ExecutorApplyResult:
        self._resolve(plan, intent)
        if cancelled():
            raise operation_error("operation.cancelled", "Execution observed durable cancellation.", change_state="unknown")
        operation_id = None
        for operation in self.engine.operations()["operations"]:
            if operation["requestId"] == plan.normalized_arguments["requestId"]:
                operation_id = operation["operationId"]
                break
        if operation_id is None:
            raise operation_error("packages.operation-missing", "Software operation is missing from the hermetic journal.")
        await self.engine.rollback(operation_id, expected_revision)
        self.calls.append(("rollback", plan.operation_id))
        observed = self._observe(plan.resource.resource_id)
        return ExecutorApplyResult(observed["revision"], observed, {"stage": "rollback"})

    async def reconcile(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        cancelled: CancellationProbe,
    ) -> ExecutorReconcileResult:
        self._resolve(plan, intent)
        if cancelled():
            raise operation_error("operation.cancelled", "Execution observed durable cancellation.", change_state="unknown")
        observed = self._observe(plan.resource.resource_id)
        desired = normalize_json(plan.preflight["proposedState"]["value"])
        before = normalize_json(plan.preflight["currentState"]["value"])
        if observed["value"] == desired:
            disposition = "desired"
        elif observed["value"] == before:
            disposition = "before"
        else:
            disposition = "diverged"
        self.calls.append(("reconcile", plan.operation_id))
        return ExecutorReconcileResult(disposition, observed["revision"], observed, {"stage": "reconcile"})
