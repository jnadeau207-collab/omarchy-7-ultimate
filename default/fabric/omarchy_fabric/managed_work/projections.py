"""Read-only daemon authority adapters for Agent Center projections."""

from __future__ import annotations

from typing import Any, Mapping, Sequence

from ..reference_operation import REFERENCE_CAPABILITY
from .plane import ManagedWorkPlane
from .types import Actor


class DaemonProjectionBridge:
    """Project only truth already owned by the running Fabric daemon.

    Provider readiness comes from the central typed registry catalog. Reference
    activity comes from the verified tamper-evident operation store. No caller
    payload is accepted by this bridge.
    """

    def __init__(self, plane: ManagedWorkPlane, reference_operations: Any) -> None:
        self._plane = plane
        self._reference_operations = reference_operations

    def refresh_providers(self, actor: Actor, catalog: Sequence[Mapping[str, Any]]) -> None:
        self._plane.project_provider_inventory(actor, catalog)

    @staticmethod
    def _change_state(operation: Mapping[str, Any]) -> str:
        status = operation["status"]
        checkpoint = operation["checkpoint"]
        if status in {"succeeded", "recovered"}:
            return "complete"
        if status == "failed":
            if operation.get("errorChangeState") in {
                "none",
                "partial",
                "complete",
                "unknown",
            }:
                return str(operation["errorChangeState"])
            return "unknown"
        if status == "cancelled":
            if operation.get("resultValidated") is True:
                return "none"
            return "unknown"
        if checkpoint == "applied":
            return "partial" if status == "running" else "unknown"
        if status in {"interrupted", "reconciling"}:
            return "unknown"
        return "none"

    def refresh_reference_operations(self, actor: Actor) -> None:
        sources = self._reference_operations.projection_sources(
            actor.principal_id,
            limit=self._plane.capacities.operation_links,
        )
        inventory: list[tuple[Actor, Mapping[str, Any]]] = []
        for operation in sources:
            operation_id = str(operation["operationId"])
            source_actor = Actor(actor.principal_id, str(operation["sessionId"]))
            inventory.append(
                (
                    source_actor,
                    {
                    "sourceRevision": int(operation["sourceRevision"]),
                    "operationId": operation_id,
                    "taskId": None,
                    "runId": None,
                    "capability": operation["capability"],
                    "legacyOwner": bool(operation["legacyOwner"]),
                    "status": operation["status"],
                    "changeState": self._change_state(operation),
                    "summary": f"Reference operation is {operation['status']}.",
                    "recoveryEligible": operation["status"] == "interrupted",
                    "artifactIds": [],
                    "createdAt": operation["createdAt"],
                    "updatedAt": operation["updatedAt"],
                    },
                )
            )
        self._plane.project_operation_inventory(
            actor,
            inventory,
            source_capability=REFERENCE_CAPABILITY,
        )
