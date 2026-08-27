"""System timer inventory and schedule planning."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .._engine import FakeBackend, LeafProvider
from .._probe import ProbeRunner, invoke_probe, parse_probe_json, run_probe
from .._real import ReadOnlyProbeBackend
from ..process._leaf import LeafDefinition, provider_bundle

DOMAIN = "schedule"
PROVIDER_ID = "schedule.provider"
OPERATION_ACTION = "timer.plan"
SCHEDULE_COMMAND = FixedArgvCommand("/usr/bin/systemctl", ("list-timers", "--all", "--no-legend", "--no-pager", "--output=json"))
ACTIONS = ("enable", "disable", "run")

STATE_SCHEMA = {
    "type": "object",
    "required": ["enabled", "nextRun", "lastRun", "definitionRevision", "pendingAction"],
    "properties": {
        "enabled": {"type": "string", "enum": ["enabled", "disabled", "unknown"]},
        "nextRun": {"oneOf": [{"type": "null"}, {"type": "integer", "minimum": 0, "maximum": 9223372036854775807}]},
        "lastRun": {"oneOf": [{"type": "null"}, {"type": "integer", "minimum": 0, "maximum": 9223372036854775807}]},
        "definitionRevision": {"type": "string", "pattern": "^sha256\\.[0-9a-f]{64}$"},
        "pendingAction": {"oneOf": [{"type": "null"}, {"type": "string", "enum": list(ACTIONS)}]},
    },
    "additionalProperties": False,
}
RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "unit", "activates", "state"],
    "properties": {
        "id": {"type": "string", "pattern": "^schedule\\.[0-9a-f]{24}$"},
        "label": {"type": "string", "minLength": 1, "maxLength": 128},
        "kind": {"const": "timer"},
        "unit": {"type": "string", "pattern": r"^(?:[A-Za-z0-9_.@:-]|\\x[0-9A-Fa-f]{2})+\.timer$", "maxLength": 128},
        "activates": {"type": "string", "pattern": r"^(?:[A-Za-z0-9_.@:-]|\\x[0-9A-Fa-f]{2})+\.service$", "maxLength": 128},
        "state": STATE_SCHEMA,
    },
    "additionalProperties": False,
}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "action"],
    "properties": {
        "resourceId": {"type": "string", "pattern": "^schedule\\.[0-9a-f]{24}$"},
        "action": {"type": "string", "enum": list(ACTIONS)},
    },
    "additionalProperties": False,
}


def _timestamp_or_none(value: object) -> int | None:
    if value is None or value == 0:
        return None
    if isinstance(value, bool) or not isinstance(value, int) or not 0 < value <= 9223372036854775807:
        raise ValueError("timer timestamp is invalid")
    return value


def parse_schedules(text: str) -> list[dict[str, Any]]:
    document = parse_probe_json(text)
    if not isinstance(document, list) or len(document) > 64:
        raise ValueError("systemd timer inventory is invalid")
    resources: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in document:
        if not isinstance(item, dict):
            raise ValueError("systemd timer row is invalid")
        unit = item.get("unit")
        activates = item.get("activates")
        if (
            not isinstance(unit, str)
            or len(unit) > 128
            or re.fullmatch(r"(?:[A-Za-z0-9_.@:-]|\\x[0-9A-Fa-f]{2})+\.timer", unit) is None
            or not isinstance(activates, str)
            or len(activates) > 128
            or re.fullmatch(r"(?:[A-Za-z0-9_.@:-]|\\x[0-9A-Fa-f]{2})+\.service", activates) is None
        ):
            raise ValueError("systemd timer identity is invalid")
        resource_id = f"schedule.{hashlib.sha256(unit.encode('utf-8')).hexdigest()[:24]}"
        if resource_id in seen:
            raise ValueError("systemd timer identity is duplicated")
        seen.add(resource_id)
        resources.append(
            {
                "id": resource_id,
                "label": unit.removesuffix(".timer")[:128],
                "kind": "timer",
                "unit": unit,
                "activates": activates,
                "state": {
                    "enabled": "unknown",
                    "nextRun": _timestamp_or_none(item.get("next")),
                    "lastRun": _timestamp_or_none(item.get("last")),
                    "definitionRevision": "sha256." + hashlib.sha256(f"{unit}\x00{activates}".encode("utf-8")).hexdigest(),
                    "pendingAction": None,
                },
            }
        )
    return resources


async def _probe_resources(runner: ProbeRunner) -> list[Mapping[str, Any]]:
    return parse_schedules((await invoke_probe(SCHEDULE_COMMAND, runner)).stdout)


def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"resourceId": arguments["resourceId"], "action": arguments["action"]}


def _propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    action = arguments["action"]
    if action == "enable" and current["enabled"] == "enabled":
        raise ValueError("timer is already enabled")
    if action == "disable" and current["enabled"] == "disabled":
        raise ValueError("timer is already disabled")
    return {**dict(current), "pendingAction": action}


SPEC, MANIFEST, SCHEMAS = provider_bundle(
    LeafDefinition(DOMAIN, PROVIDER_ID, "timer", OPERATION_ACTION, "schedule.timer.plan", "consequential", ("mutating", "privileged")),
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=STATE_SCHEMA,
    normalize_arguments=_normalize,
    target_id=lambda arguments: arguments["resourceId"],
    propose_state=_propose,
    describe_change=lambda _current, _proposed, arguments: f"Plan timer action {arguments['action']}; no timer is changed or triggered.",
)


def build_provider(*, runner: ProbeRunner = run_probe) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, ReadOnlyProbeBackend(DOMAIN, lambda: _probe_resources(runner)))


def build_fake_provider(resources: list[Mapping[str, Any]], *, state_path: Path | None = None, fail_on: frozenset[str] = frozenset()) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, FakeBackend(DOMAIN, resources, state_path=state_path, fail_on=fail_on))
