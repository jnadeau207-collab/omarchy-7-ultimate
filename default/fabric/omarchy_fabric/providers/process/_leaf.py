"""Small builder for administration leaves on the existing Fabric engine."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Mapping

from .._contracts import build_contracts, contract_ref
from .._engine import DomainSpec

@dataclass(frozen=True)
class LeafDefinition:
    domain: str
    provider_id: str
    resource_kind: str
    operation_action: str
    operation_capability: str
    risk: str
    effects: tuple[str, ...]
    max_resources: int = 64
    inventory_action: str = "inspect"

def provider_bundle(
    definition: LeafDefinition,
    *,
    resource_schema: Mapping[str, Any],
    arguments_schema: Mapping[str, Any],
    state_schema: Mapping[str, Any],
    normalize_arguments: Callable[[Mapping[str, Any]], dict[str, Any]],
    target_id: Callable[[Mapping[str, Any]], str],
    propose_state: Callable[[Mapping[str, Any], Mapping[str, Any]], dict[str, Any]],
    describe_change: Callable[[Mapping[str, Any], Mapping[str, Any], Mapping[str, Any]], str],
    operation_state_schema: Mapping[str, Any] | None = None,
    operation_resource_kind: str | None = None,
    scope: Any = None,
) -> tuple[DomainSpec, dict[str, Any], dict[str, dict[str, Any]]]:
    """Build closed schemas and a manifest consumed by the central registry."""

    contracts = build_contracts(
        domain=definition.domain,
        provider_id=definition.provider_id,
        resource_kind=definition.resource_kind,
        inventory_action=definition.inventory_action,
        operation_action=definition.operation_action,
        operation_capability=definition.operation_capability,
        risk=definition.risk,
        effects=definition.effects,
        max_resources=definition.max_resources,
        resource_schema=resource_schema,
        arguments_schema=arguments_schema,
        state_schema=state_schema,
        operation_state_schema=operation_state_schema,
        operation_resource_kind=operation_resource_kind,
    )
    manifest = {
        "schemaVersion": "v0",
        "provider": definition.provider_id,
        "providerVersion": "v0",
        "minFabricProtocol": 0,
        "maxFabricProtocol": 0,
        "capabilities": [f"{definition.domain}.inspect", definition.operation_capability],
        "actions": {
            definition.inventory_action: {
                "capability": f"{definition.domain}.inspect",
                "mode": "read",
                "risk": "read-only",
                "effects": [],
                "arguments": contract_ref(definition.domain, "inventory-arguments"),
                "result": contract_ref(definition.domain, "inventory-result"),
                "preflight": None,
                "state": None,
                "supportsRollback": False,
                "supportsCancellation": False,
            },
            definition.operation_action: {
                "capability": definition.operation_capability,
                "mode": "operation",
                "risk": definition.risk,
                "effects": list(definition.effects),
                "arguments": contract_ref(definition.domain, "operation-arguments"),
                "result": contract_ref(definition.domain, "operation-result"),
                "preflight": contract_ref(definition.domain, "operation-preflight"),
                "state": contract_ref(definition.domain, "operation-state"),
                "supportsRollback": True,
                "supportsCancellation": False,
            },
        },
    }
    spec = DomainSpec(
        domain=definition.domain,
        provider_id=definition.provider_id,
        version="v0",
        resource_kind=definition.resource_kind,
        inventory_action=definition.inventory_action,
        operation_action=definition.operation_action,
        normalize_arguments=normalize_arguments,
        target_id=target_id,
        propose_state=propose_state,
        describe_change=describe_change,
        scope=scope,
    )
    return spec, manifest, contracts
