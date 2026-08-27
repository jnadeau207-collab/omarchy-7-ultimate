"""Generate closed standalone Draft 2020-12 leaf schemas."""

from __future__ import annotations

from copy import deepcopy
from typing import Any, Mapping

DRAFT = "https://json-schema.org/draft/2020-12/schema"
VERSION = "v0"
REVISION_PATTERN = r"^sha256\.[0-9a-f]{64}$"
RESOURCE_ID_PATTERN = "^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,127}$"
STABLE_ID_PATTERN = "^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$"


def contract_id(domain: str, name: str) -> str:
    return f"urn:omarchy:fabric:provider:{domain}:{name}:v0"


def contract_ref(domain: str, name: str) -> dict[str, str]:
    return {"id": contract_id(domain, name), "version": VERSION}


def _document(schema_id: str, title: str, body: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "$schema": DRAFT,
        "$id": schema_id,
        "x-omarchy-version": VERSION,
        "title": title,
        **deepcopy(dict(body)),
    }


def _error_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": ["code", "title", "explanation", "detail", "retryable", "changeState"],
        "properties": {
            "code": {"type": "string", "pattern": STABLE_ID_PATTERN, "maxLength": 160},
            "title": {"type": "string", "minLength": 1, "maxLength": 160},
            "explanation": {"type": "string", "minLength": 1, "maxLength": 2000},
            "detail": {"type": "string", "maxLength": 2000},
            "retryable": {"type": "boolean"},
            "changeState": {"type": "string", "enum": ["none", "partial", "complete", "unknown"]},
            "recoveryActions": {
                "type": "array",
                "maxItems": 8,
                "items": {"type": "string", "pattern": STABLE_ID_PATTERN, "maxLength": 160},
                "uniqueItems": True,
            },
        },
        "additionalProperties": False,
    }


def _state_body(state_schema: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "type": "object",
        "required": ["resourceId", "revision", "value"],
        "properties": {
            "resourceId": {"type": "string", "pattern": RESOURCE_ID_PATTERN, "maxLength": 128},
            "revision": {"type": "string", "pattern": REVISION_PATTERN},
            "value": deepcopy(dict(state_schema)),
        },
        "additionalProperties": False,
    }


def build_contracts(
    *,
    domain: str,
    provider_id: str,
    resource_kind: str,
    inventory_action: str,
    operation_action: str,
    operation_capability: str,
    risk: str,
    effects: tuple[str, ...],
    max_resources: int,
    resource_schema: Mapping[str, Any],
    arguments_schema: Mapping[str, Any],
    state_schema: Mapping[str, Any],
) -> dict[str, dict[str, Any]]:
    if isinstance(max_resources, bool) or not isinstance(max_resources, int) or not 1 <= max_resources <= 64:
        raise ValueError("leaf inventory bound must be an integer from 1 through 64")
    state_body = _state_body(state_schema)
    resource_ref = {
        "type": "object",
        "required": ["kind", "id"],
        "properties": {
            "kind": {"const": resource_kind},
            "id": {"type": "string", "pattern": RESOURCE_ID_PATTERN, "maxLength": 128},
        },
        "additionalProperties": False,
    }
    metadata = {
        "schemaVersion": {"const": VERSION},
        "provider": {"const": provider_id},
        "providerVersion": {"const": VERSION},
    }
    inventory_arguments = _document(
        contract_id(domain, "inventory-arguments"),
        f"{domain.title()} inventory arguments",
        {"type": "object", "maxProperties": 0, "additionalProperties": False},
    )
    inventory_result = _document(
        contract_id(domain, "inventory-result"),
        f"{domain.title()} inventory result",
        {
            "type": "object",
            "required": [
                "schemaVersion",
                "provider",
                "providerVersion",
                "action",
                "availability",
                "revision",
                "resources",
            ],
            "properties": {
                **metadata,
                "action": {"const": inventory_action},
                "availability": {
                    "type": "object",
                    "required": ["read", "operation", "reason"],
                    "properties": {
                        "read": {"type": "boolean"},
                        "operation": {"type": "boolean"},
                        "reason": {"oneOf": [{"type": "null"}, _error_schema()]},
                    },
                    "additionalProperties": False,
                },
                "revision": {"type": "string", "pattern": REVISION_PATTERN},
                "resources": {
                    "type": "array",
                    "maxItems": max_resources,
                    "items": deepcopy(dict(resource_schema)),
                },
            },
            "additionalProperties": False,
        },
    )
    operation_arguments = _document(
        contract_id(domain, "operation-arguments"),
        f"{domain.title()} operation arguments",
        arguments_schema,
    )
    operation_state = _document(
        contract_id(domain, "operation-state"),
        f"{domain.title()} operation state",
        state_body,
    )
    operation_preflight = _document(
        contract_id(domain, "operation-preflight"),
        f"{domain.title()} operation preflight",
        {
            "type": "object",
            "required": [
                "schemaVersion",
                "provider",
                "providerVersion",
                "action",
                "capability",
                "resource",
                "normalizedArguments",
                "stateRevision",
                "currentState",
                "proposedState",
                "changed",
                "summary",
                "risk",
                "effects",
                "recovery",
            ],
            "properties": {
                **metadata,
                "action": {"const": operation_action},
                "capability": {"const": operation_capability},
                "resource": resource_ref,
                "normalizedArguments": deepcopy(dict(arguments_schema)),
                "stateRevision": {"type": "string", "pattern": REVISION_PATTERN},
                "currentState": deepcopy(state_body),
                "proposedState": deepcopy(state_body),
                "changed": {"type": "boolean"},
                "summary": {"type": "string", "minLength": 1, "maxLength": 1000},
                "risk": {"const": risk},
                "effects": {"type": "array", "const": list(effects)},
                "recovery": {
                    "type": "object",
                    "required": ["mode", "priorState"],
                    "properties": {
                        "mode": {"const": "rollback"},
                        "priorState": deepcopy(state_body),
                    },
                    "additionalProperties": False,
                },
            },
            "additionalProperties": False,
        },
    )
    operation_result = _document(
        contract_id(domain, "operation-result"),
        f"{domain.title()} operation result",
        {
            "type": "object",
            "required": [
                "schemaVersion",
                "provider",
                "providerVersion",
                "action",
                "capability",
                "resource",
                "changed",
                "changeState",
                "stateRevision",
                "state",
                "error",
            ],
            "properties": {
                **metadata,
                "action": {"const": operation_action},
                "capability": {"const": operation_capability},
                "resource": resource_ref,
                "changed": {"type": "boolean"},
                "changeState": {"type": "string", "enum": ["none", "complete"]},
                "stateRevision": {"type": "string", "pattern": REVISION_PATTERN},
                "state": deepcopy(state_body),
                "error": {"type": "null"},
            },
            "additionalProperties": False,
        },
    )
    return {
        document["$id"]: document
        for document in (
            inventory_arguments,
            inventory_result,
            operation_arguments,
            operation_state,
            operation_preflight,
            operation_result,
        )
    }
