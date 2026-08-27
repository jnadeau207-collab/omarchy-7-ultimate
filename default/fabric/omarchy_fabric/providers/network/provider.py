"""Network inventory and hermetic Wi-Fi radio operation."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .._contracts import build_contracts
from .._engine import DomainSpec, FakeBackend, LeafProvider
from .._identity import stable_resource_id
from .._immutable import load_frozen_json
from .._probe import ProbeRunner, invoke_probe, run_probe
from .._real import ReadOnlyProbeBackend

DOMAIN = "network"
PROVIDER_ID = "network.provider"
INVENTORY_ACTION = "inspect"
OPERATION_ACTION = "wifi.set-enabled"
RESOURCE_KIND = "network-resource"
WIFI_ID = "network.radio.wifi"

WIFI_COMMAND = FixedArgvCommand("/usr/bin/nmcli", ("-t", "-f", "RUNNING,WIFI-HW,WIFI", "general"))
DEVICES_COMMAND = FixedArgvCommand(
    "/usr/bin/nmcli",
    ("-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"),
)

_STATE_VALUES = ["connected", "connecting", "disconnected", "disconnecting", "unavailable", "unmanaged", "unknown"]
_TYPE_VALUES = ["wifi", "ethernet", "bridge", "tun", "loopback", "wireguard", "other"]

RADIO_STATE_SCHEMA = {
    "type": "object",
    "required": ["managerRunning", "hardwareEnabled", "enabled"],
    "properties": {
        "managerRunning": {"type": "boolean"},
        "hardwareEnabled": {"type": "boolean"},
        "enabled": {"type": "boolean"},
    },
    "additionalProperties": False,
}
INTERFACE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "state"],
    "properties": {
        "id": {"type": "string", "pattern": "^network\\.interface\\.[0-9a-f]{64}$"},
        "label": {"type": "string", "minLength": 1, "maxLength": 160},
        "kind": {"type": "string", "enum": _TYPE_VALUES},
        "state": {
            "type": "object",
            "required": ["status", "connection"],
            "properties": {
                "status": {"type": "string", "enum": _STATE_VALUES},
                "connection": {"type": ["string", "null"], "maxLength": 160},
            },
            "additionalProperties": False,
        },
    },
    "additionalProperties": False,
}
RADIO_RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "state"],
    "properties": {
        "id": {"const": WIFI_ID},
        "label": {"const": "Wi-Fi radio"},
        "kind": {"const": "wifi-radio"},
        "state": RADIO_STATE_SCHEMA,
    },
    "additionalProperties": False,
}
RESOURCE_SCHEMA = {"oneOf": [RADIO_RESOURCE_SCHEMA, INTERFACE_SCHEMA]}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "enabled"],
    "properties": {"resourceId": {"const": WIFI_ID}, "enabled": {"type": "boolean"}},
    "additionalProperties": False,
}

SCHEMAS = build_contracts(
    domain=DOMAIN,
    provider_id=PROVIDER_ID,
    resource_kind=RESOURCE_KIND,
    inventory_action=INVENTORY_ACTION,
    operation_action=OPERATION_ACTION,
    operation_capability="network.manage",
    risk="consequential",
    effects=("mutating", "network"),
    max_resources=32,
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=RADIO_STATE_SCHEMA,
)


def _split_terse(line: str) -> list[str]:
    fields: list[str] = []
    current: list[str] = []
    escaped = False
    for character in line:
        if escaped:
            current.append(character)
            escaped = False
        elif character == "\\":
            escaped = True
        elif character == ":":
            fields.append("".join(current))
            current = []
        else:
            current.append(character)
    if escaped:
        raise ValueError("nmcli output ends with an escape")
    fields.append("".join(current))
    return fields


def _network_type(value: str) -> str:
    normalized = value.lower()
    return normalized if normalized in _TYPE_VALUES[:-1] else "other"


def _network_state(value: str) -> str:
    normalized = value.lower()
    return normalized if normalized in _STATE_VALUES[:-1] else "unknown"


async def _probe_resources(runner: ProbeRunner) -> list[Mapping[str, Any]]:
    general = _split_terse((await invoke_probe(WIFI_COMMAND, runner)).stdout.strip())
    if (
        len(general) != 3
        or general[0] not in {"running", "stopped"}
        or general[1] not in {"enabled", "disabled", "missing"}
        or general[2] not in {"enabled", "disabled"}
    ):
        raise ValueError("nmcli general radio state is invalid")
    resources: list[Mapping[str, Any]] = [
        {
            "id": WIFI_ID,
            "label": "Wi-Fi radio",
            "kind": "wifi-radio",
            "state": {
                "managerRunning": general[0] == "running",
                "hardwareEnabled": general[1] == "enabled",
                "enabled": general[2] == "enabled",
            },
        }
    ]
    lines = (await invoke_probe(DEVICES_COMMAND, runner)).stdout.splitlines()
    if len(lines) > 31:
        raise ValueError("network interface inventory exceeds 31 entries")
    seen_native: set[str] = set()
    for line in lines:
        if not line:
            continue
        fields = _split_terse(line)
        if len(fields) != 4:
            raise ValueError("nmcli device row does not have four fields")
        device, kind, status, connection = fields
        if (
            not device
            or len(device) > 128
            or any(ord(character) < 32 or ord(character) == 127 for character in device)
            or device in seen_native
        ):
            raise ValueError("nmcli returned an invalid or duplicate interface ID")
        seen_native.add(device)
        connection_value = None if connection in {"", "--"} else connection
        if connection_value is not None and (
            len(connection_value) > 160
            or any(ord(character) < 32 or ord(character) == 127 for character in connection_value)
        ):
            raise ValueError("nmcli connection label is invalid")
        resources.append(
            {
                "id": stable_resource_id(DOMAIN, "interface", device),
                "label": device,
                "kind": _network_type(kind),
                "state": {"status": _network_state(status), "connection": connection_value},
            }
        )
    return resources


def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"resourceId": WIFI_ID, "enabled": arguments["enabled"]}


def _propose(_current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    if arguments["enabled"] and (not _current["managerRunning"] or not _current["hardwareEnabled"]):
        raise ValueError("Wi-Fi cannot be enabled while its manager or hardware is unavailable")
    return {
        "managerRunning": _current["managerRunning"],
        "hardwareEnabled": _current["hardwareEnabled"],
        "enabled": arguments["enabled"],
    }


def _describe(current: Mapping[str, Any], proposed: Mapping[str, Any], _arguments: Mapping[str, Any]) -> str:
    if current == proposed:
        return "Wi-Fi radio already has the requested state; no change will be made."
    return "Turn the Wi-Fi radio on." if proposed["enabled"] else "Turn the Wi-Fi radio off and disconnect Wi-Fi links."


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
    backend = ReadOnlyProbeBackend(DOMAIN, lambda: _probe_resources(runner))
    return LeafProvider(SPEC, _manifest(), SCHEMAS, backend)


def build_fake_provider(
    resources: list[Mapping[str, Any]],
    *,
    state_path: Path | None = None,
    fail_on: frozenset[str] = frozenset(),
) -> LeafProvider:
    backend = FakeBackend(DOMAIN, resources, state_path=state_path, fail_on=fail_on)
    return LeafProvider(SPEC, _manifest(), SCHEMAS, backend)
