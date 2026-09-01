"""Device Manager authorization through the durable coordinator.

``device.authorization.plan`` is inventory-shaped until it is projected onto a
privileged system-executor intent. Pacman and udev writes stay off the session
helper.
"""

from __future__ import annotations

from typing import Any, Mapping

from ..models import FixedArgvCommand
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

PRIVILEGED_DEVICE_INTENTS = frozenset({"device.authorize"})


def _resource_id(value: Any) -> str:
    if not isinstance(value, str) or not value.startswith("device.") or len(value) > 160:
        raise ValueError("device resource id is invalid")
    return value


def _authorized(value: Any) -> bool:
    if not isinstance(value, bool):
        raise ValueError("authorized must be boolean")
    return value


def device_intents() -> tuple[IntentDefinition, ...]:
    return (
        IntentDefinition(
            "device.authorize",
            FixedArgvCommand(SYSTEM_EXECUTOR, ("device.authorize",)),
            required={
                "resourceId": _resource_id,
                "device_id": stable_token,
                "authorized": _authorized,
            },
        ),
    )


def _coordinator_device_state(value: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "online": value["online"],
        "authorized": value["authorized"],
        "driver": value["driver"],
        "pendingDecision": value["pendingAuthorization"] if "pendingAuthorization" in value else value["pendingDecision"],
    }


def project_device_preflight(envelope: Mapping[str, Any]) -> dict[str, Any]:
    inner = envelope["preflight"]
    current = dict(inner["currentState"])
    proposed = dict(inner["proposedState"])
    current["value"] = _coordinator_device_state(current["value"])
    proposed["value"] = _coordinator_device_state(proposed["value"])
    prior = dict(inner["recovery"]["priorState"])
    prior["value"] = _coordinator_device_state(prior["value"])
    projected = {
        **dict(inner),
        "currentState": current,
        "proposedState": proposed,
        "recovery": {"mode": inner["recovery"]["mode"], "priorState": prior},
    }
    return {**dict(envelope), "preflight": projected}


def device_definitions() -> tuple[OperationDefinition, ...]:
    return (
        OperationDefinition(
            "device.provider",
            "authorization.plan",
            "device.authorize",
            lambda preflight: {
                "resourceId": preflight["resource"]["id"],
                "device_id": preflight["resource"]["id"],
                "authorized": preflight["normalizedArguments"]["authorized"],
            },
        ),
    )


class HermeticDeviceExecutor:
    """Coordinator executor that drives the hermetic device leaf.

    It never talks to udevadm. Production mutation stays on the system executor.
    """

    available = True

    def __init__(self, provider: Any, catalog: IntentCatalog) -> None:
        self.provider = provider
        self.catalog = catalog
        self.calls: list[tuple[str, str]] = []
        self.system_requests: list[dict[str, Any]] = []

    def _resolve(self, plan: OperationPlan, intent: ExecutorIntent) -> None:
        self.catalog.resolve(intent)
        if intent.digest != plan.intent.digest:
            raise operation_error("executor.intent-drift", "Executor intent does not match the durable plan.")
        if intent.payload.get("resourceId") != plan.resource.resource_id:
            raise operation_error("executor.resource-drift", "Executor payload targets another resource.")

    async def _observe(self, resource_id: str) -> dict[str, Any]:
        snapshot = await self.provider.backend.snapshot()
        resource = next((entry for entry in snapshot.resources if entry["id"] == resource_id), None)
        if resource is None:
            raise operation_error("executor.resource-unavailable", "The hermetic device is unavailable.")
        from ..providers._engine import state_revision
        from ..providers._immutable import thaw

        leaf_state = thaw(resource["state"])
        value = normalize_json(_coordinator_device_state(leaf_state))
        return {"resourceId": resource_id, "revision": state_revision(leaf_state), "value": value}

    async def apply(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        cancelled: CancellationProbe,
    ) -> ExecutorApplyResult:
        from .system_command_executor import build_system_executor_document
        from ..security.system_executor import validate_system_executor_request

        self._resolve(plan, intent)
        if cancelled():
            raise operation_error("operation.cancelled", "Execution observed durable cancellation.")
        document = build_system_executor_document(plan, intent)
        validate_system_executor_request(document)
        self.system_requests.append(document)
        result = await self.provider.apply(
            "authorization.plan",
            dict(plan.normalized_arguments),
            plan.resource.revision,
        )
        self.calls.append(("apply", plan.operation_id))
        observed = await self._observe(plan.resource.resource_id)
        return ExecutorApplyResult(
            observed["revision"],
            observed,
            {"stage": "apply", "changed": result.get("changed")},
        )

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
        observed = await self._observe(plan.resource.resource_id)
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
        await self.provider.rollback("authorization.plan", dict(prior_state), expected_revision)
        self.calls.append(("rollback", plan.operation_id))
        observed = await self._observe(plan.resource.resource_id)
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
        observed = await self._observe(plan.resource.resource_id)
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
