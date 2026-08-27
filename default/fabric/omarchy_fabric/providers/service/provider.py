"""System service inventory and lifecycle planning."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .._engine import FakeBackend, LeafProvider
from .._probe import ProbeRunner, invoke_probe, run_probe
from .._real import ReadOnlyProbeBackend
from ..process._leaf import LeafDefinition, provider_bundle

DOMAIN = "service"
PROVIDER_ID = "service.provider"
OPERATION_ACTION = "lifecycle.plan"
SERVICE_COMMAND = FixedArgvCommand("/usr/bin/systemctl", ("list-units", "--type=service", "--all", "--no-legend", "--plain", "--no-pager"))
ACTIONS = ("start", "stop", "restart", "enable", "disable")

STATE_SCHEMA = {
    "type": "object",
    "required": ["load", "active", "substate", "enabled", "pendingAction"],
    "properties": {
        "load": {"type": "string", "enum": ["loaded", "not-found", "masked", "error", "unknown"]},
        "active": {"type": "string", "enum": ["active", "inactive", "failed", "activating", "deactivating", "reloading", "unknown"]},
        "substate": {"type": "string", "minLength": 1, "maxLength": 64},
        "enabled": {"type": "string", "enum": ["enabled", "disabled", "static", "masked", "unknown"]},
        "pendingAction": {"oneOf": [{"type": "null"}, {"type": "string", "enum": list(ACTIONS)}]},
    },
    "additionalProperties": False,
}
RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "unit", "description", "observedCount", "inventoryTruncated", "state"],
    "properties": {
        "id": {"type": "string", "pattern": "^service\\.[0-9a-f]{24}$"},
        "label": {"type": "string", "minLength": 1, "maxLength": 128},
        "kind": {"const": "service"},
        "unit": {"type": "string", "pattern": r"^(?:[A-Za-z0-9_.@:-]|\\x[0-9A-Fa-f]{2})+\.service$", "maxLength": 128},
        "description": {"type": "string", "maxLength": 256},
        "observedCount": {"type": "integer", "minimum": 1, "maximum": 1000000},
        "inventoryTruncated": {"type": "boolean"},
        "state": STATE_SCHEMA,
    },
    "additionalProperties": False,
}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "action"],
    "properties": {
        "resourceId": {"type": "string", "pattern": "^service\\.[0-9a-f]{24}$"},
        "action": {"type": "string", "enum": list(ACTIONS)},
    },
    "additionalProperties": False,
}


def parse_services(text: str) -> list[dict[str, Any]]:
    resources: list[dict[str, Any]] = []
    seen: set[str] = set()
    for line in text.splitlines():
        fields = line.strip().split(maxsplit=4)
        if len(fields) < 4:
            raise ValueError("systemd service row is invalid")
        unit, load, active, substate = fields[:4]
        description = fields[4] if len(fields) == 5 else ""
        if re.fullmatch(r"(?:[A-Za-z0-9_.@:-]|\\x[0-9A-Fa-f]{2})+\.service", unit) is None or len(unit) > 128:
            raise ValueError("systemd service identity is invalid")
        if not substate or len(substate) > 64 or any(not character.isprintable() for character in substate):
            raise ValueError("systemd service substate is invalid")
        if len(description) > 256 or any(not character.isprintable() for character in description):
            raise ValueError("systemd service description is invalid")
        resource_id = f"service.{hashlib.sha256(unit.encode('utf-8')).hexdigest()[:24]}"
        if resource_id in seen:
            raise ValueError("systemd service identity is duplicated")
        seen.add(resource_id)
        load_state = load if load in {"loaded", "not-found", "masked", "error"} else "unknown"
        active_state = active if active in {"active", "inactive", "failed", "activating", "deactivating", "reloading"} else "unknown"
        resources.append(
            {
                "id": resource_id,
                "label": unit.removesuffix(".service")[:128],
                "kind": "service",
                "unit": unit,
                "description": description[:256],
                "observedCount": 1,
                "inventoryTruncated": False,
                "state": {"load": load_state, "active": active_state, "substate": substate[:64] or "unknown", "enabled": "unknown", "pendingAction": None},
            }
        )
    observed_count = len(resources)
    resources.sort(key=lambda resource: (resource["state"]["active"] not in {"failed", "active"}, resource["unit"]))
    resources = resources[:64]
    for resource in resources:
        resource["observedCount"] = observed_count
        resource["inventoryTruncated"] = observed_count > len(resources)
    return resources


async def _probe_resources(runner: ProbeRunner) -> list[Mapping[str, Any]]:
    return parse_services((await invoke_probe(SERVICE_COMMAND, runner)).stdout)


def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"resourceId": arguments["resourceId"], "action": arguments["action"]}


def _propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    if current["load"] in {"not-found", "error"}:
        raise ValueError("service unit is not actionable")
    action = arguments["action"]
    if action == "start" and current["active"] == "active":
        raise ValueError("service is already active")
    if action == "stop" and current["active"] == "inactive":
        raise ValueError("service is already inactive")
    return {**dict(current), "pendingAction": action}


SPEC, MANIFEST, SCHEMAS = provider_bundle(
    LeafDefinition(DOMAIN, PROVIDER_ID, "service", OPERATION_ACTION, "service.lifecycle.plan", "consequential", ("mutating", "privileged")),
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=STATE_SCHEMA,
    normalize_arguments=_normalize,
    target_id=lambda arguments: arguments["resourceId"],
    propose_state=_propose,
    describe_change=lambda _current, _proposed, arguments: f"Plan service action {arguments['action']}; no systemd unit is changed.",
)


def build_provider(*, runner: ProbeRunner = run_probe) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, ReadOnlyProbeBackend(DOMAIN, lambda: _probe_resources(runner)))


def build_fake_provider(resources: list[Mapping[str, Any]], *, state_path: Path | None = None, fail_on: frozenset[str] = frozenset()) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, FakeBackend(DOMAIN, resources, state_path=state_path, fail_on=fail_on))
