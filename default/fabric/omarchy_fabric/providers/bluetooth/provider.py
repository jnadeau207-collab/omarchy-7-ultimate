"""Bluetooth inventory and hermetic audio-device pairing operation."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .._contracts import build_contracts
from .._engine import DomainSpec, FakeBackend, LeafProvider
from .._identity import stable_resource_id
from .._immutable import load_frozen_json
from .._probe import ProbeRunner, invoke_probe, run_probe
from .._real import ReadOnlyProbeBackend

DOMAIN = "bluetooth"
PROVIDER_ID = "bluetooth.provider"
INVENTORY_ACTION = "inspect"
OPERATION_ACTION = "audio.pair"
RESOURCE_KIND = "bluetooth-device"
MAC_PATTERN = "^[0-9a-f]{2}(?::[0-9a-f]{2}){5}$"
MAC_RE = re.compile(MAC_PATTERN, re.IGNORECASE)

SHOW_COMMAND = FixedArgvCommand("/usr/bin/bluetoothctl", ("show",))
DEVICES_COMMAND = FixedArgvCommand("/usr/bin/bluetoothctl", ("devices",))
PAIRED_COMMAND = FixedArgvCommand("/usr/bin/bluetoothctl", ("devices", "Paired"))
CONNECTED_COMMAND = FixedArgvCommand("/usr/bin/bluetoothctl", ("devices", "Connected"))

DEVICE_ID_PATTERN = "^bluetooth\\.device\\.[0-9a-f]{64}$"
CONTROLLER_ID_PATTERN = "^bluetooth\\.controller\\.[0-9a-f]{64}$"

DEVICE_STATE_SCHEMA = {
    "type": "object",
    "required": ["paired", "connected"],
    "properties": {
        "paired": {"type": "boolean"},
        "connected": {"type": "boolean"},
    },
    "additionalProperties": False,
}
DEVICE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "state"],
    "properties": {
        "id": {"type": "string", "pattern": DEVICE_ID_PATTERN},
        "label": {"type": "string", "minLength": 1, "maxLength": 160},
        "kind": {"const": "device"},
        "state": DEVICE_STATE_SCHEMA,
    },
    "additionalProperties": False,
}
CONTROLLER_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "state"],
    "properties": {
        "id": {"type": "string", "pattern": CONTROLLER_ID_PATTERN},
        "label": {"type": "string", "minLength": 1, "maxLength": 160},
        "kind": {"const": "controller"},
        "state": {
            "type": "object",
            "required": ["powered", "discovering"],
            "properties": {"powered": {"type": "boolean"}, "discovering": {"type": "boolean"}},
            "additionalProperties": False,
        },
    },
    "additionalProperties": False,
}
RESOURCE_SCHEMA = {"oneOf": [CONTROLLER_SCHEMA, DEVICE_SCHEMA]}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId"],
    "properties": {"resourceId": {"type": "string", "pattern": DEVICE_ID_PATTERN}},
    "additionalProperties": False,
}

SCHEMAS = build_contracts(
    domain=DOMAIN,
    provider_id=PROVIDER_ID,
    resource_kind=RESOURCE_KIND,
    inventory_action=INVENTORY_ACTION,
    operation_action=OPERATION_ACTION,
    operation_capability="bluetooth.audio.pair",
    risk="consequential",
    effects=("mutating", "network"),
    max_resources=32,
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=DEVICE_STATE_SCHEMA,
)

def _parse_device_rows(text: str) -> dict[str, str]:
    rows: dict[str, str] = {}
    for line in text.splitlines():
        if not line:
            continue
        parts = line.split(maxsplit=2)
        if len(parts) < 2 or parts[0] != "Device" or MAC_RE.fullmatch(parts[1]) is None:
            raise ValueError("bluetoothctl returned an invalid device row")
        device_id = parts[1].lower()
        if device_id in rows:
            raise ValueError("bluetoothctl returned a duplicate device")
        label = parts[2].strip() if len(parts) == 3 else "Bluetooth device"
        if not 1 <= len(label) <= 160 or any(ord(character) < 32 or ord(character) == 127 for character in label):
            raise ValueError("Bluetooth device label is invalid")
        rows[device_id] = label
    return rows

def _show_value(text: str, key: str) -> str:
    prefix = f"{key}:"
    matches = [line.strip()[len(prefix) :].strip() for line in text.splitlines() if line.strip().startswith(prefix)]
    if len(matches) != 1:
        raise ValueError(f"bluetoothctl show has no exact {key} field")
    return matches[0]

def _controller_address(text: str) -> str:
    matches: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("Controller "):
            matches.append(stripped.split(maxsplit=2)[1].lower())
    if len(matches) != 1 or MAC_RE.fullmatch(matches[0]) is None:
        raise ValueError("bluetoothctl show has no exact controller address")
    return matches[0]

def _yes_no(value: str) -> bool:
    if value == "yes":
        return True
    if value == "no":
        return False
    raise ValueError("bluetoothctl boolean is not yes or no")

async def _probe_resources(runner: ProbeRunner) -> list[Mapping[str, Any]]:
    show = (await invoke_probe(SHOW_COMMAND, runner)).stdout
    controller_address = _controller_address(show)
    controller_name = _show_value(show, "Name")
    if not 1 <= len(controller_name) <= 160 or any(
        ord(character) < 32 or ord(character) == 127 for character in controller_name
    ):
        raise ValueError("Bluetooth controller name is invalid")
    devices = _parse_device_rows((await invoke_probe(DEVICES_COMMAND, runner)).stdout)
    paired = set(_parse_device_rows((await invoke_probe(PAIRED_COMMAND, runner)).stdout))
    connected = set(_parse_device_rows((await invoke_probe(CONNECTED_COMMAND, runner)).stdout))
    if not paired <= devices.keys() or not connected <= devices.keys() or len(devices) > 31:
        raise ValueError("Bluetooth state references an unknown or excessive device")
    resources: list[Mapping[str, Any]] = [
        {
            "id": stable_resource_id(DOMAIN, "controller", controller_address),
            "label": controller_name,
            "kind": "controller",
            "state": {"powered": _yes_no(_show_value(show, "Powered")), "discovering": _yes_no(_show_value(show, "Discovering"))},
        }
    ]
    for device_id in sorted(devices):
        resources.append(
            {
                "id": stable_resource_id(DOMAIN, "device", device_id),
                "label": devices[device_id],
                "kind": "device",
                "state": {"paired": device_id in paired, "connected": device_id in connected},
            }
        )
    return resources

def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"resourceId": arguments["resourceId"]}

def _propose(current: Mapping[str, Any], _arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"paired": True, "connected": True}

def _describe(current: Mapping[str, Any], proposed: Mapping[str, Any], _arguments: Mapping[str, Any]) -> str:
    if current == proposed:
        return "The Bluetooth audio device is already paired and connected; no change will be made."
    return "Pair and connect the selected Bluetooth audio device."

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
