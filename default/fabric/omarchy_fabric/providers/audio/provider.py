"""Audio sink inventory and hermetic output-volume operation."""

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

DOMAIN = "audio"
PROVIDER_ID = "audio.provider"
INVENTORY_ACTION = "inspect"
OPERATION_ACTION = "output-volume.set"
RESOURCE_KIND = "audio-sink"
RESOURCE_ID_PATTERN = "^audio\\.sink\\.[0-9a-f]{64}$"
PORT_ID_PATTERN = "^audio\\.port\\.[0-9a-f]{64}$"
PERCENT_RE = re.compile(r"^(\d{1,3})%$")
CHANNEL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
PORT_AVAILABILITY = {
    "available": "yes",
    "not available": "no",
    "availability unknown": "unknown",
}

SINKS_COMMAND = FixedArgvCommand("/usr/bin/pactl", ("--format=json", "list", "sinks"))
DEFAULT_SINK_COMMAND = FixedArgvCommand("/usr/bin/pactl", ("get-default-sink",))

VOLUME_STATE_SCHEMA = {
    "type": "object",
    "required": ["muted", "channels"],
    "properties": {
        "muted": {"type": "boolean"},
        "channels": {
            "type": "object",
            "minProperties": 1,
            "maxProperties": 16,
            "propertyNames": {"type": "string", "pattern": "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"},
            "patternProperties": {
                "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$": {"type": "integer", "minimum": 0, "maximum": 150}
            },
            "additionalProperties": False,
        },
    },
    "additionalProperties": False,
}
PORT_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "availability"],
    "properties": {
        "id": {"type": "string", "pattern": PORT_ID_PATTERN},
        "label": {"type": "string", "minLength": 1, "maxLength": 160},
        "availability": {"type": "string", "enum": ["yes", "no", "unknown"]},
    },
    "additionalProperties": False,
}
RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "default", "physical", "ports", "activePort", "state"],
    "properties": {
        "id": {"type": "string", "pattern": RESOURCE_ID_PATTERN},
        "label": {"type": "string", "minLength": 1, "maxLength": 160},
        "kind": {"const": "sink"},
        "default": {"type": "boolean"},
        "physical": {"type": "boolean"},
        "ports": {"type": "array", "maxItems": 8, "items": PORT_SCHEMA},
        "activePort": {"type": ["string", "null"], "pattern": PORT_ID_PATTERN},
        "state": VOLUME_STATE_SCHEMA,
    },
    "additionalProperties": False,
}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "percent"],
    "properties": {
        "resourceId": {"type": "string", "pattern": RESOURCE_ID_PATTERN},
        "percent": {"type": "integer", "minimum": 0, "maximum": 100},
    },
    "additionalProperties": False,
}

SCHEMAS = build_contracts(
    domain=DOMAIN,
    provider_id=PROVIDER_ID,
    resource_kind=RESOURCE_KIND,
    inventory_action=INVENTORY_ACTION,
    operation_action=OPERATION_ACTION,
    operation_capability="audio.volume.set",
    risk="low",
    effects=("mutating",),
    max_resources=8,
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=VOLUME_STATE_SCHEMA,
)


def _bounded_text(value: Any, label: str, maximum: int = 160) -> str:
    if not isinstance(value, str) or not 1 <= len(value) <= maximum:
        raise ValueError(f"audio {label} is not a bounded string")
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise ValueError(f"audio {label} contains a control character")
    return value


def _volume(value: Any) -> dict[str, int]:
    if not isinstance(value, dict) or not 1 <= len(value) <= 16:
        raise ValueError("pactl sink volume is invalid or excessive")
    channels: dict[str, int] = {}
    for name in sorted(value):
        bounded_name = _bounded_text(name, "channel name", 64)
        if CHANNEL_RE.fullmatch(bounded_name) is None:
            raise ValueError("pactl channel name is invalid")
        channel = value[name]
        if not isinstance(channel, dict):
            raise ValueError("pactl channel volume is not an object")
        match = PERCENT_RE.fullmatch(str(channel.get("value_percent", "")))
        if match is None or not 0 <= int(match.group(1)) <= 150:
            raise ValueError("pactl channel percentage is invalid")
        channels[bounded_name] = int(match.group(1))
    return channels


def _ports(sink_name: str, value: Any) -> tuple[list[dict[str, Any]], dict[str, str]]:
    if value is None:
        return [], {}
    if not isinstance(value, list) or len(value) > 8 or any(not isinstance(port, dict) for port in value):
        raise ValueError("pactl sink ports are invalid or excessive")
    ports: list[dict[str, Any]] = []
    identities: dict[str, str] = {}
    for port in value:
        native = _bounded_text(port.get("name"), "port name")
        if native in identities:
            raise ValueError("pactl returned a duplicate sink port")
        availability = PORT_AVAILABILITY.get(port.get("availability"))
        if availability is None:
            raise ValueError("pactl port availability is invalid")
        port_id = stable_resource_id(DOMAIN, "port", f"{sink_name}\0{native}")
        identities[native] = port_id
        ports.append(
            {
                "id": port_id,
                "label": _bounded_text(port.get("description") or "Audio port", "port description"),
                "availability": availability,
            }
        )
    return sorted(ports, key=lambda port: port["id"]), identities


async def _probe_resources(runner: ProbeRunner) -> list[Mapping[str, Any]]:
    document = parse_probe_json((await invoke_probe(SINKS_COMMAND, runner)).stdout)
    default_sink = (await invoke_probe(DEFAULT_SINK_COMMAND, runner)).stdout.strip()
    _bounded_text(default_sink, "default sink")
    if not isinstance(document, list) or len(document) > 8 or any(not isinstance(sink, dict) for sink in document):
        raise ValueError("pactl sink inventory is invalid or excessive")
    resources: list[Mapping[str, Any]] = []
    seen_names: set[str] = set()
    for sink in document:
        name = _bounded_text(sink.get("name"), "sink name")
        if name in seen_names:
            raise ValueError("pactl returned a duplicate sink name")
        seen_names.add(name)
        ports, port_ids = _ports(name, sink.get("ports"))
        active_native = sink.get("active_port") or None
        if active_native is not None and active_native not in port_ids:
            raise ValueError("pactl active port is not in the sink port list")
        properties = sink.get("properties")
        if not isinstance(properties, dict):
            raise ValueError("pactl sink properties are not an object")
        device_api = properties.get("device.api")
        muted = sink.get("mute")
        if not isinstance(muted, bool):
            raise ValueError("pactl sink mute state is not a boolean")
        resources.append(
            {
                "id": stable_resource_id(DOMAIN, "sink", name),
                "label": _bounded_text(sink.get("description") or "Audio output", "sink description"),
                "kind": "sink",
                "default": name == default_sink,
                "physical": device_api in {"alsa", "bluez5"},
                "ports": ports,
                "activePort": port_ids.get(active_native),
                "state": {"muted": muted, "channels": _volume(sink.get("volume"))},
            }
        )
    if default_sink not in seen_names:
        raise ValueError("pactl default sink is absent from the sink inventory")
    return resources


def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"resourceId": arguments["resourceId"], "percent": arguments["percent"]}


def _propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "muted": current["muted"],
        "channels": {name: arguments["percent"] for name in current["channels"]},
    }


def _describe(current: Mapping[str, Any], proposed: Mapping[str, Any], _arguments: Mapping[str, Any]) -> str:
    if current == proposed:
        return "The audio output already uses the requested volume; no change will be made."
    return f"Set every channel on the selected audio output to {next(iter(proposed['channels'].values()))} percent without changing mute."


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
