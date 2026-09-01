"""Project Compatibility Center preflight onto the durable coordinator contract.

Compatibility v0 preflight is a route/deployment plan. The coordinator requires
resource-scoped current/proposed state and a typed RiskLevel. This module maps
those fields without editing the v0 provider schema and without treating a seed
catalog as release-verified.
"""

from __future__ import annotations

from typing import Any, Mapping

from ..models import FabricError, FixedArgvCommand
from ..security.normalize import normalize_json
from .contracts import ExecutorIntent, OperationDefinition, OperationPlan, operation_error
from .executor import (
    CancellationProbe,
    ExecutorApplyResult,
    ExecutorReconcileResult,
    IntentCatalog,
    IntentDefinition,
    stable_token,
)
from .package_plane import SYSTEM_EXECUTOR

COMPATIBILITY_INTENTS = frozenset({"compatibility.deploy", "compatibility.remove", "compatibility.export"})


def _resource_id(value: Any) -> str:
    if not isinstance(value, str) or not value or len(value) > 160:
        raise ValueError("resource id is invalid")
    return value


def _request_id(value: Any) -> str:
    return stable_token(value)


def _boolean(value: Any) -> bool:
    if not isinstance(value, bool):
        raise ValueError("expected a boolean")
    return value


def compatibility_intents() -> tuple[IntentDefinition, ...]:
    return (
        IntentDefinition(
            "compatibility.deploy",
            FixedArgvCommand(SYSTEM_EXECUTOR, ("compatibility.deploy",)),
            required={"resourceId": _resource_id, "requestId": _request_id, "preserveData": _boolean},
        ),
        IntentDefinition(
            "compatibility.remove",
            FixedArgvCommand(SYSTEM_EXECUTOR, ("compatibility.remove",)),
            required={"resourceId": _resource_id, "requestId": _request_id, "preserveData": _boolean},
        ),
        IntentDefinition(
            "compatibility.export",
            FixedArgvCommand(SYSTEM_EXECUTOR, ("compatibility.export",)),
            required={"resourceId": _resource_id, "requestId": _request_id, "preserveData": _boolean},
        ),
    )


def compatibility_definitions() -> tuple[OperationDefinition, ...]:
    return (
        OperationDefinition(
            "compatibility.provider",
            "deploy",
            "compatibility.deploy",
            lambda preflight: {
                "resourceId": preflight["resource"]["id"],
                "requestId": preflight["normalizedArguments"]["requestId"],
                "preserveData": preflight["normalizedArguments"]["preserveData"],
            },
        ),
        OperationDefinition(
            "compatibility.provider",
            "remove",
            "compatibility.remove",
            lambda preflight: {
                "resourceId": preflight["resource"]["id"],
                "requestId": preflight["normalizedArguments"]["requestId"],
                "preserveData": preflight["normalizedArguments"]["preserveData"],
            },
        ),
        OperationDefinition(
            "compatibility.provider",
            "export",
            "compatibility.export",
            lambda preflight: {
                "resourceId": preflight["resource"]["id"],
                "requestId": preflight["normalizedArguments"]["requestId"],
                "preserveData": preflight["normalizedArguments"]["preserveData"],
            },
        ),
    )


def _coordinator_risk(value: str) -> str:
    if value == "destructive":
        return "high"
    if value in {"consequential", "low"}:
        return value
    raise operation_error("operation.preflight-invalid", "Compatibility operation risk is not coordinator-admissible.")


def _deployment_value(item: Mapping[str, Any] | None, workload_id: str) -> dict[str, Any]:
    if item is None:
        return {"workloadId": workload_id, "present": False, "route": None, "state": None}
    return {
        "workloadId": workload_id,
        "present": True,
        "route": item.get("route"),
        "state": item.get("state"),
        "decisionRevision": item.get("decisionRevision"),
    }


def project_compatibility_preflight(envelope: Mapping[str, Any]) -> dict[str, Any]:
    inner = envelope["preflight"]
    workload_id = inner["normalizedArguments"]["request"]["id"]
    revision = inner["deploymentRevision"]
    prior = inner["recovery"]["priorDeployment"]
    if inner["action"] == "remove":
        proposed_item = None
    elif inner["action"] == "export":
        proposed_item = prior
    else:
        proposed_item = {
            "workloadId": workload_id,
            "route": inner["decision"]["selectedRoute"],
            "state": "installed",
            "decisionRevision": inner["decision"]["revision"],
        }
    current = {"resourceId": workload_id, "revision": revision, "value": _deployment_value(prior, workload_id)}
    proposed = {
        "resourceId": workload_id,
        "revision": "proposal.unapplied" if inner["changed"] else revision,
        "value": _deployment_value(proposed_item, workload_id),
    }
    risk = _coordinator_risk(inner["risk"])
    projected = {
        "schemaVersion": "v0",
        "provider": inner["provider"],
        "providerVersion": inner["providerVersion"],
        "action": inner["action"],
        "capability": envelope["capability"],
        "resource": {"kind": "compatibility-workload", "id": workload_id},
        "normalizedArguments": inner["normalizedArguments"],
        "stateRevision": revision,
        "currentState": current,
        "proposedState": proposed,
        "changed": inner["changed"],
        "summary": inner["summary"],
        "risk": risk,
        "effects": list(inner["effects"]),
        "recovery": {"mode": "rollback", "priorState": current},
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


class HermeticCompatibilityExecutor:
    """Coordinator executor that drives the hermetic compatibility engine.

    It consumes measured-host preflight and release attestation already applied
    by the recipe catalog. It never invokes a live compatibility adapter.
    """

    available = True

    def __init__(self, engine: Any, catalog: IntentCatalog) -> None:
        self.engine = engine
        self.catalog = catalog
        self.calls: list[tuple[str, str]] = []

    def _resolve(self, plan: OperationPlan, intent: ExecutorIntent) -> None:
        self.catalog.resolve(intent)
        if intent.digest != plan.intent.digest:
            raise operation_error("executor.intent-drift", "Executor intent does not match the durable plan.")
        if intent.payload.get("resourceId") != plan.resource.resource_id:
            raise operation_error("executor.resource-drift", "Executor payload targets another resource.")

    def _observe(self, workload_id: str) -> dict[str, Any]:
        deployments = self.engine.deployments()
        item = next((entry for entry in deployments["deployments"] if entry["workloadId"] == workload_id), None)
        return {
            "resourceId": workload_id,
            "revision": deployments["revision"],
            "value": _deployment_value(item, workload_id),
        }

    async def apply(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        cancelled: CancellationProbe,
    ) -> ExecutorApplyResult:
        self._resolve(plan, intent)
        if cancelled():
            raise operation_error("operation.cancelled", "Execution observed durable cancellation.")
        action = plan.action
        result = await self.engine.apply(
            action,
            normalize_json(plan.normalized_arguments),
            plan.resource.revision,
        )
        if result["status"] != "succeeded":
            raise FabricError(
                "compatibility.adapter-failed",
                "Compatibility adapter failed",
                result.get("error") or "The hermetic compatibility engine did not succeed.",
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
        for operation in self.engine._operations.values():
            if operation["requestId"] == plan.normalized_arguments["requestId"]:
                operation_id = operation["operationId"]
                break
        if operation_id is None:
            raise operation_error("compatibility.operation-missing", "Compatibility operation is missing from the hermetic journal.")
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
