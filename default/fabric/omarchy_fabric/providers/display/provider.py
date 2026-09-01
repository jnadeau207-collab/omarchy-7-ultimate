"""Display inventory and hermetic brightness operation."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .._contracts import build_contracts
from .._engine import DomainSpec, FakeBackend, LeafProvider
from .._identity import stable_resource_id
from .._immutable import load_frozen_json
from .._probe import ProbeRunner, invoke_probe, parse_probe_json, run_probe
from .._real import ReadOnlyProbeBackend

DOMAIN = "display"
PROVIDER_ID = "display.provider"
INVENTORY_ACTION = "inspect"
OPERATION_ACTION = "brightness.set"
RESOURCE_KIND = "display-output"
RESOURCE_ID_PATTERN = "^display\\.output\\.[0-9a-f]{64}$"

MONITORS_COMMAND = FixedArgvCommand("/usr/bin/hyprctl", ("-j", "monitors", "all"))

BRIGHTNESS_STATE_SCHEMA = {
    "type": "object",
    "required": ["available", "percent"],
    "properties": {
        "available": {"type": "boolean"},
        "percent": {"type": ["integer", "null"], "minimum": 1, "maximum": 100},
    },
    "additionalProperties": False,
}
MODE_SCHEMA = {
    "oneOf": [
        {"type": "null"},
        {
            "type": "object",
            "required": ["width", "height", "refreshHz"],
            "properties": {
                "width": {"type": "integer", "minimum": 1, "maximum": 32768},
                "height": {"type": "integer", "minimum": 1, "maximum": 32768},
                "refreshHz": {"type": "number", "exclusiveMinimum": 0, "maximum": 1000},
            },
            "additionalProperties": False,
        },
    ]
}
RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "enabled", "focused", "mode", "position", "scale", "transform", "mirrorOf", "dpms", "state"],
    "properties": {
        "id": {"type": "string", "pattern": RESOURCE_ID_PATTERN},
        "label": {"type": "string", "minLength": 1, "maxLength": 160},
        "kind": {"const": "output"},
        "enabled": {"type": "boolean"},
        "focused": {"type": "boolean"},
        "mode": MODE_SCHEMA,
        "position": {
            "type": "object",
            "required": ["x", "y"],
            "properties": {
                "x": {"type": "integer", "minimum": -32768, "maximum": 32768},
                "y": {"type": "integer", "minimum": -32768, "maximum": 32768},
            },
            "additionalProperties": False,
        },
        "scale": {"type": "number", "exclusiveMinimum": 0, "maximum": 10},
        "transform": {"type": "integer", "minimum": 0, "maximum": 7},
        "mirrorOf": {"type": ["string", "null"], "pattern": RESOURCE_ID_PATTERN},
        "dpms": {"type": "boolean"},
        "state": BRIGHTNESS_STATE_SCHEMA,
    },
    "additionalProperties": False,
}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "percent"],
    "properties": {
        "resourceId": {"type": "string", "pattern": RESOURCE_ID_PATTERN},
        "percent": {"type": "integer", "minimum": 1, "maximum": 100},
    },
    "additionalProperties": False,
}

SCHEMAS = build_contracts(
    domain=DOMAIN,
    provider_id=PROVIDER_ID,
    resource_kind=RESOURCE_KIND,
    inventory_action=INVENTORY_ACTION,
    operation_action=OPERATION_ACTION,
    operation_capability="display.configure",
    risk="low",
    effects=("mutating",),
    max_resources=16,
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=BRIGHTNESS_STATE_SCHEMA,
)

def _label(value: Any) -> str:
    if not isinstance(value, str) or not 1 <= len(value) <= 160:
        raise ValueError("display connector is not a bounded string")
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise ValueError("display connector contains a control character")
    return value

def _integer(value: Any, name: str, minimum: int, maximum: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
        raise ValueError(f"display {name} is invalid")
    return value

def _number(value: Any, name: str, minimum: float, maximum: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not minimum < float(value) <= maximum:
        raise ValueError(f"display {name} is invalid")
    return float(value)

def _boolean(value: Any, name: str, *, default: bool | None = None) -> bool:
    if value is None and default is not None:
        return default
    if not isinstance(value, bool):
        raise ValueError(f"display {name} is not a boolean")
    return value

async def _probe_resources(runner: ProbeRunner) -> list[Mapping[str, Any]]:
    document = parse_probe_json((await invoke_probe(MONITORS_COMMAND, runner)).stdout)
    if not isinstance(document, list) or len(document) > 16 or any(not isinstance(monitor, dict) for monitor in document):
        raise ValueError("hyprctl monitor inventory is invalid or excessive")
    native_names: list[str] = []
    for monitor in document:
        name = _label(monitor.get("name"))
        if name in native_names:
            raise ValueError("hyprctl returned a duplicate monitor connector")
        native_names.append(name)
    identities = {name: stable_resource_id(DOMAIN, "output", name) for name in native_names}
    resources: list[Mapping[str, Any]] = []
    for monitor, name in zip(document, native_names, strict=True):
        disabled = _boolean(monitor.get("disabled"), "disabled state", default=False)
        width = monitor.get("width")
        height = monitor.get("height")
        enabled = not disabled and isinstance(width, int) and not isinstance(width, bool) and width > 0 and isinstance(height, int) and not isinstance(height, bool) and height > 0
        mode = None
        if enabled:
            mode = {
                "width": _integer(width, "width", 1, 32768),
                "height": _integer(height, "height", 1, 32768),
                "refreshHz": _number(monitor.get("refreshRate"), "refresh rate", 0, 1000),
            }
        mirror_value = monitor.get("mirrorOf")
        if mirror_value is None:
            mirror_native = None
        elif not isinstance(mirror_value, str):
            raise ValueError("hyprctl monitor mirror target is invalid")
        elif mirror_value in ("", "none"):
            mirror_native = None
        else:
            mirror_native = _label(mirror_value)
            if mirror_native not in identities:
                raise ValueError("hyprctl monitor mirrors an unknown connector")
        resources.append(
            {
                "id": identities[name],
                "label": name,
                "kind": "output",
                "enabled": enabled,
                "focused": _boolean(monitor.get("focused"), "focused state"),
                "mode": mode,
                "position": {
                    "x": _integer(monitor.get("x", 0), "x position", -32768, 32768),
                    "y": _integer(monitor.get("y", 0), "y position", -32768, 32768),
                },
                "scale": _number(monitor.get("scale", 1), "scale", 0, 10),
                "transform": _integer(monitor.get("transform", 0), "transform", 0, 7),
                "mirrorOf": identities.get(mirror_native),
                "dpms": _boolean(monitor.get("dpmsStatus"), "DPMS state"),
                "state": {"available": False, "percent": None},
            }
        )
    return resources

def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"resourceId": arguments["resourceId"], "percent": arguments["percent"]}

def _propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    if not current["available"]:
        raise ValueError("display does not expose controllable brightness")
    return {"available": True, "percent": arguments["percent"]}

def _describe(current: Mapping[str, Any], proposed: Mapping[str, Any], _arguments: Mapping[str, Any]) -> str:
    if current == proposed:
        return "The display already uses the requested brightness; no change will be made."
    return f"Set the selected display brightness to {proposed['percent']} percent."

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
    return LeafProvider(SPEC, _manifest(), SCHEMAS, ReadOnlyProbeBackend(DOMAIN, lambda: _probe_resources(runner)))

def build_fake_provider(
    resources: list[Mapping[str, Any]],
    *,
    state_path: Path | None = None,
    fail_on: frozenset[str] = frozenset(),
) -> LeafProvider:
    return LeafProvider(SPEC, _manifest(), SCHEMAS, FakeBackend(DOMAIN, resources, state_path=state_path, fail_on=fail_on))
