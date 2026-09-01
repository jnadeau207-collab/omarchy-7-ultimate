"""Input inventory and hermetic keyboard-layout operation."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .._contracts import build_contracts
from .._engine import DomainSpec, FakeBackend, LeafProvider
from .._identity import stable_resource_id
from .._immutable import load_frozen_json
from .._probe import ProbeRunner, invoke_probe, parse_probe_json, run_probe
from .._real import ReadOnlyProbeBackend

DOMAIN = "input"
PROVIDER_ID = "input.provider"
INVENTORY_ACTION = "inspect"
OPERATION_ACTION = "keyboard-layout.set"
RESOURCE_KIND = "input-keyboard"
RESOURCE_ID_PATTERN = "^input\\.keyboard\\.[0-9a-f]{64}$"
UNTYPED_KEYBOARDS = re.compile(r"^(hl-virtual-keyboard|power-button|sleep-button|lid-switch|video-bus)")

DEVICES_COMMAND = FixedArgvCommand("/usr/bin/hyprctl", ("-j", "devices"))

KEYBOARD_STATE_SCHEMA = {
    "type": "object",
    "required": ["activeIndex", "activeKeymap", "layouts", "switchable"],
    "properties": {
        "activeIndex": {"type": ["integer", "null"], "minimum": 0, "maximum": 7},
        "activeKeymap": {"type": ["string", "null"], "minLength": 1, "maxLength": 160},
        "layouts": {
            "type": "array",
            "maxItems": 8,
            "uniqueItems": True,
            "items": {"type": "string", "minLength": 1, "maxLength": 64},
        },
        "switchable": {"type": "boolean"},
    },
    "additionalProperties": False,
}
RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "main", "state"],
    "properties": {
        "id": {"type": "string", "pattern": RESOURCE_ID_PATTERN},
        "label": {"type": "string", "minLength": 1, "maxLength": 160},
        "kind": {"const": "keyboard"},
        "main": {"type": "boolean"},
        "state": KEYBOARD_STATE_SCHEMA,
    },
    "additionalProperties": False,
}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "layoutIndex"],
    "properties": {
        "resourceId": {"type": "string", "pattern": RESOURCE_ID_PATTERN},
        "layoutIndex": {"type": "integer", "minimum": 0, "maximum": 7},
    },
    "additionalProperties": False,
}

SCHEMAS = build_contracts(
    domain=DOMAIN,
    provider_id=PROVIDER_ID,
    resource_kind=RESOURCE_KIND,
    inventory_action=INVENTORY_ACTION,
    operation_action=OPERATION_ACTION,
    operation_capability="input.keyboard-layout.set",
    risk="low",
    effects=("mutating",),
    max_resources=16,
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=KEYBOARD_STATE_SCHEMA,
)

def _bounded_label(value: Any) -> str:
    if not isinstance(value, str) or not 1 <= len(value) <= 160:
        raise ValueError("keyboard name is not a bounded string")
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise ValueError("keyboard name contains a control character")
    return value

def _layouts(value: Any) -> list[str]:
    if value is None or value == "":
        return []
    if not isinstance(value, str):
        raise ValueError("keyboard layouts are not a string")
    layouts = [layout.strip() for layout in value.split(",")]
    if not 1 <= len(layouts) <= 8 or len(layouts) != len(set(layouts)):
        raise ValueError("keyboard layout list is empty, excessive, or duplicated")
    if any(
        not layout
        or len(layout) > 64
        or any(ord(character) < 32 or ord(character) == 127 for character in layout)
        for layout in layouts
    ):
        raise ValueError("keyboard layout entry is invalid")
    return layouts

async def _probe_resources(runner: ProbeRunner) -> list[Mapping[str, Any]]:
    document = parse_probe_json((await invoke_probe(DEVICES_COMMAND, runner)).stdout)
    if not isinstance(document, dict) or not isinstance(document.get("keyboards"), list):
        raise ValueError("hyprctl devices has no keyboard list")
    listed = document["keyboards"]
    if len(listed) > 64 or any(not isinstance(keyboard, dict) for keyboard in listed):
        raise ValueError("hyprctl keyboard inventory is invalid or excessive")
    resources: list[Mapping[str, Any]] = []
    seen_names: set[str] = set()
    for keyboard in listed:
        name = _bounded_label(keyboard.get("name"))
        if UNTYPED_KEYBOARDS.match(name):
            continue
        if name in seen_names:
            raise ValueError("hyprctl returned a duplicate keyboard name")
        seen_names.add(name)
        layouts = _layouts(keyboard.get("layout"))
        active_index = keyboard.get("active_layout_index")
        active_keymap = keyboard.get("active_keymap")
        if isinstance(active_index, bool) or not isinstance(active_index, int) or not 0 <= active_index <= 7:
            active_index = None
        if (
            not isinstance(active_keymap, str)
            or not 1 <= len(active_keymap) <= 160
            or any(ord(character) < 32 or ord(character) == 127 for character in active_keymap)
        ):
            active_keymap = None
        switchable = len(layouts) > 1 and active_index is not None and active_index < len(layouts)
        main = keyboard.get("main")
        if not isinstance(main, bool):
            raise ValueError("hyprctl keyboard main state is not a boolean")
        resources.append(
            {
                "id": stable_resource_id(DOMAIN, "keyboard", name),
                "label": name,
                "kind": "keyboard",
                "main": main,
                "state": {
                    "activeIndex": active_index,
                    "activeKeymap": active_keymap,
                    "layouts": layouts,
                    "switchable": switchable,
                },
            }
        )
        if len(resources) > 16:
            raise ValueError("typed keyboard inventory exceeds 16 entries")
    return resources

def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"resourceId": arguments["resourceId"], "layoutIndex": arguments["layoutIndex"]}

def _propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    index = arguments["layoutIndex"]
    layouts = list(current["layouts"])
    if not current["switchable"] or index >= len(layouts):
        raise ValueError("keyboard does not expose the requested switchable layout")
    return {
        "activeIndex": index,
        "activeKeymap": layouts[index],
        "layouts": layouts,
        "switchable": True,
    }

def _describe(current: Mapping[str, Any], proposed: Mapping[str, Any], _arguments: Mapping[str, Any]) -> str:
    if current == proposed:
        return "The keyboard already uses the requested layout; no change will be made."
    return f"Switch the selected keyboard to layout {proposed['activeKeymap']}."

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
    return LeafProvider(SPEC, _manifest(), SCHEMAS, ReadOnlyProbeBackend(DOMAIN, lambda: _probe_resources(runner), session_operable=True))

def build_fake_provider(
    resources: list[Mapping[str, Any]],
    *,
    state_path: Path | None = None,
    fail_on: frozenset[str] = frozenset(),
) -> LeafProvider:
    return LeafProvider(SPEC, _manifest(), SCHEMAS, FakeBackend(DOMAIN, resources, state_path=state_path, fail_on=fail_on))
