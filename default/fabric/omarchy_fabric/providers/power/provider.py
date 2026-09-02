"""Power inventory and hermetic profile operation."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .._contracts import build_contracts
from .._engine import DomainSpec, FakeBackend, LeafProvider
from .._immutable import load_frozen_json
from .._probe import ProbeRunner, invoke_probe, run_probe
from .._real import ReadOnlyProbeBackend

DOMAIN = "power"
PROVIDER_ID = "power.provider"
INVENTORY_ACTION = "inspect"
OPERATION_ACTION = "profile.set"
RESOURCE_KIND = "power-profile"
RESOURCE_ID = "power.profile.current"
PROFILES = ("power-saver", "balanced", "performance")
BATTERY_STATES = ("charging", "discharging", "empty", "fully-charged", "pending-charge", "pending-discharge", "holding", "unknown")

PROFILES_COMMAND = FixedArgvCommand("/usr/bin/omarchy-powerprofiles-list", ("--active-state",))
SOURCE_COMMAND = FixedArgvCommand(
    "/usr/bin/busctl",
    ("--system", "get-property", "org.freedesktop.UPower", "/org/freedesktop/UPower", "org.freedesktop.UPower", "OnBattery"),
)
BATTERY_COMMAND = FixedArgvCommand("/usr/bin/omarchy-battery-status", ("--shell",))

PROFILE_STATE_SCHEMA = {
    "type": "object",
    "required": ["source", "activeProfile", "availableProfiles"],
    "properties": {
        "source": {"type": "string", "enum": ["ac", "battery"]},
        "activeProfile": {"type": "string", "enum": list(PROFILES)},
        "availableProfiles": {
            "type": "array",
            "minItems": 1,
            "maxItems": 3,
            "uniqueItems": True,
            "items": {"type": "string", "enum": list(PROFILES)},
        },
    },
    "additionalProperties": False,
}
BATTERY_SCHEMA = {
    "oneOf": [
        {"type": "null"},
        {
            "type": "object",
            "required": ["percentage", "state"],
            "properties": {
                "percentage": {"type": "integer", "minimum": 0, "maximum": 100},
                "state": {"type": "string", "enum": list(BATTERY_STATES)},
            },
            "additionalProperties": False,
        },
    ]
}
RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "battery", "state"],
    "properties": {
        "id": {"const": RESOURCE_ID},
        "label": {"const": "Power profile"},
        "kind": {"const": "profile"},
        "battery": BATTERY_SCHEMA,
        "state": PROFILE_STATE_SCHEMA,
    },
    "additionalProperties": False,
}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "profile"],
    "properties": {
        "resourceId": {"const": RESOURCE_ID},
        "profile": {"type": "string", "enum": list(PROFILES)},
    },
    "additionalProperties": False,
}

SCHEMAS = build_contracts(
    domain=DOMAIN,
    provider_id=PROVIDER_ID,
    resource_kind=RESOURCE_KIND,
    inventory_action=INVENTORY_ACTION,
    operation_action=OPERATION_ACTION,
    operation_capability="power.profile.set",
    risk="low",
    effects=("mutating",),
    max_resources=1,
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=PROFILE_STATE_SCHEMA,
)

def _parse_profiles(text: str) -> tuple[list[str], str]:
    profiles: list[str] = []
    active: list[str] = []
    for line in text.splitlines():
        if not line:
            continue
        fields = line.split("\t")
        if len(fields) != 2 or fields[0] not in PROFILES or fields[1] not in {"0", "1"}:
            raise ValueError("power profile row is invalid")
        if fields[0] in profiles:
            raise ValueError("power profile row is duplicated")
        profiles.append(fields[0])
        if fields[1] == "1":
            active.append(fields[0])
    if not profiles or len(active) != 1:
        raise ValueError("power profile inventory requires one active profile")
    return sorted(profiles), active[0]

def _parse_source(text: str) -> str:
    value = text.strip()
    if value == "b true":
        return "battery"
    if value == "b false":
        return "ac"
    raise ValueError("UPower OnBattery property is invalid")

def _parse_battery(text: str) -> Mapping[str, Any] | None:
    if not text.strip():
        return None
    fields: dict[str, str] = {}
    for line in text.splitlines():
        parts = line.split("\t", maxsplit=1)
        if (
            len(parts) != 2
            or not parts[0]
            or parts[0] in fields
            or len(parts[0]) > 32
            or len(parts[1]) > 160
            or len(fields) >= 16
        ):
            raise ValueError("battery status row is invalid or duplicated")
        fields[parts[0]] = parts[1]
    percentage = re.fullmatch(r"(\d{1,3})%", fields.get("percentage", ""))
    state = fields.get("state", "unknown")
    if percentage is None or not 0 <= int(percentage.group(1)) <= 100 or state not in BATTERY_STATES:
        raise ValueError("battery status is invalid")
    return {"percentage": int(percentage.group(1)), "state": state}

async def _probe_resources(runner: ProbeRunner) -> list[Mapping[str, Any]]:
    profiles, active = _parse_profiles((await invoke_probe(PROFILES_COMMAND, runner)).stdout)
    source = _parse_source((await invoke_probe(SOURCE_COMMAND, runner)).stdout)
    battery = _parse_battery((await invoke_probe(BATTERY_COMMAND, runner)).stdout)
    return [
        {
            "id": RESOURCE_ID,
            "label": "Power profile",
            "kind": "profile",
            "battery": battery,
            "state": {"source": source, "activeProfile": active, "availableProfiles": profiles},
        }
    ]

def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"resourceId": RESOURCE_ID, "profile": arguments["profile"]}

def _propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    if arguments["profile"] not in current["availableProfiles"]:
        raise ValueError("requested power profile is unavailable")
    return {
        "source": current["source"],
        "activeProfile": arguments["profile"],
        "availableProfiles": list(current["availableProfiles"]),
    }

def _describe(current: Mapping[str, Any], proposed: Mapping[str, Any], _arguments: Mapping[str, Any]) -> str:
    if current == proposed:
        return "The current power source already uses the requested profile; no change will be made."
    return f"Set the {current['source']} power profile to {proposed['activeProfile']}."

SPEC = DomainSpec(
    domain=DOMAIN,
    provider_id=PROVIDER_ID,
    version="v0",
    resource_kind=RESOURCE_KIND,
    inventory_action=INVENTORY_ACTION,
    operation_action=OPERATION_ACTION,
    normalize_arguments=_normalize,
    target_id=lambda arguments: arguments["resourceId"],
    propose_state=_propose,
    describe_change=_describe,
)

def _manifest() -> Mapping[str, Any]:
    return load_frozen_json(Path(__file__).with_name("manifest-v0.json"))

def build_provider(*, runner: ProbeRunner = run_probe) -> LeafProvider:
    return LeafProvider(SPEC, _manifest(), SCHEMAS, ReadOnlyProbeBackend(DOMAIN, lambda: _probe_resources(runner), session_operable=False))

def build_fake_provider(
    resources: list[Mapping[str, Any]],
    *,
    state_path: Path | None = None,
    fail_on: frozenset[str] = frozenset(),
) -> LeafProvider:
    return LeafProvider(SPEC, _manifest(), SCHEMAS, FakeBackend(DOMAIN, resources, state_path=state_path, fail_on=fail_on))
