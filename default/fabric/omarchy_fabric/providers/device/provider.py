"""Device inventory and authorization planning without live mutation."""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .._engine import FakeBackend, LeafProvider
from .._probe import ProbeRunner, invoke_probe, parse_probe_json, run_probe
from .._real import ReadOnlyProbeBackend
from ..process._leaf import LeafDefinition, provider_bundle

DOMAIN = "device"
PROVIDER_ID = "device.provider"
OPERATION_ACTION = "authorization.plan"
SUPPORTED_SUBSYSTEMS = {"block", "bluetooth", "drm", "hid", "input", "net", "nvme", "pci", "scsi", "sound", "thunderbolt", "tty", "usb", "video4linux"}
DEVICE_COMMAND = FixedArgvCommand(
    "/usr/bin/udevadm",
    (
        "info",
        "--export-db",
        "--json=short",
        *(f"--subsystem-match={subsystem}" for subsystem in sorted(SUPPORTED_SUBSYSTEMS)),
    ),
)

STATE_SCHEMA = {
    "type": "object",
    "required": ["online", "authorized", "driver", "pendingAuthorization"],
    "properties": {
        "online": {"type": "boolean"},
        "authorized": {"oneOf": [{"type": "null"}, {"type": "boolean"}]},
        "driver": {"oneOf": [{"type": "null"}, {"type": "string", "minLength": 1, "maxLength": 128}]},
        "pendingAuthorization": {"oneOf": [{"type": "null"}, {"type": "boolean"}]},
    },
    "additionalProperties": False,
}
RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "subsystem", "bus", "removable", "observedCount", "inventoryTruncated", "state"],
    "properties": {
        "id": {"type": "string", "pattern": "^device\\.[0-9a-f]{24}$"},
        "label": {"type": "string", "minLength": 1, "maxLength": 160},
        "kind": {"const": "device"},
        "subsystem": {"type": "string", "pattern": "^[a-z0-9_-]{1,32}$"},
        "bus": {"type": "string", "pattern": "^[a-z0-9_-]{1,32}$"},
        "removable": {"type": "boolean"},
        "observedCount": {"type": "integer", "minimum": 1, "maximum": 1000000},
        "inventoryTruncated": {"type": "boolean"},
        "state": STATE_SCHEMA,
    },
    "additionalProperties": False,
}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "authorized"],
    "properties": {
        "resourceId": {"type": "string", "pattern": "^device\\.[0-9a-f]{24}$"},
        "authorized": {"type": "boolean"},
    },
    "additionalProperties": False,
}

def _trusted_text(value: object, maximum: int) -> str:
    if not isinstance(value, str):
        raise ValueError("udev text field is invalid")
    cleaned = "".join(character for character in value if character.isprintable() and character not in "\r\n\x00").strip()
    if not cleaned or len(cleaned) > maximum:
        raise ValueError("udev text field is empty or exceeds its bound")
    return cleaned

def parse_devices(text: str) -> list[dict[str, Any]]:
    resources: list[dict[str, Any]] = []
    seen: set[str] = set()
    for line in text.splitlines():
        if not line.strip():
            continue
        item = parse_probe_json(line)
        if not isinstance(item, dict) or len(item) > 256:
            raise ValueError("udev row is invalid")
        devpath = item.get("DEVPATH")
        subsystem = _trusted_text(item.get("SUBSYSTEM"), 32).lower()
        if (
            not isinstance(devpath, str)
            or not devpath.startswith("/devices/")
            or len(devpath) > 1024
            or any(not character.isprintable() for character in devpath)
            or subsystem == "unknown"
        ):
            raise ValueError("udev identity is invalid")
        if subsystem not in SUPPORTED_SUBSYSTEMS:
            continue
        serial_value = item.get("ID_SERIAL_SHORT")
        if serial_value is None:
            serial_value = item.get("ID_SERIAL")
        serial = "" if serial_value is None else _trusted_text(serial_value, 256)
        identity = f"{serial}:{devpath}"
        resource_id = f"device.{hashlib.sha256(identity.encode('utf-8')).hexdigest()[:24]}"
        if resource_id in seen:
            raise ValueError("device identity is duplicated")
        seen.add(resource_id)
        driver = item.get("DRIVER")
        if driver is not None:
            driver = _trusted_text(driver, 128)
        authorization = item.get("AUTHORIZED")
        if authorization is not None and authorization not in ("0", "1"):
            raise ValueError("udev authorization truth is invalid")
        removable_values = (item.get("ID_DRIVE_FLASH_SD"), item.get("ID_DRIVE_THUMB"))
        if any(value is not None and value not in ("0", "1") for value in removable_values):
            raise ValueError("udev removable truth is invalid")
        label_value = item.get("ID_MODEL_FROM_DATABASE")
        if label_value is None:
            label_value = item.get("ID_MODEL")
        if label_value is None:
            label_value = item.get("DEVNAME")
        label = subsystem if label_value is None else _trusted_text(label_value, 160)
        bus_value = item.get("ID_BUS")
        bus = "unknown" if bus_value is None else _trusted_text(bus_value, 32).lower()
        resources.append(
            {
                "id": resource_id,
                "label": label,
                "kind": "device",
                "subsystem": subsystem,
                "bus": bus,
                "removable": item.get("ID_DRIVE_FLASH_SD") == "1" or item.get("ID_DRIVE_THUMB") == "1",
                "observedCount": 1,
                "inventoryTruncated": False,
                "state": {
                    "online": True,
                    "authorized": None if authorization is None else authorization == "1",
                    "driver": driver,
                    "pendingAuthorization": None,
                },
            }
        )
    observed_count = len(resources)
    resources.sort(key=lambda resource: (not resource["removable"], resource["subsystem"], resource["label"], resource["id"]))
    resources = resources[:64]
    for resource in resources:
        resource["observedCount"] = observed_count
        resource["inventoryTruncated"] = observed_count > len(resources)
    return resources

async def _probe_resources(runner: ProbeRunner) -> list[Mapping[str, Any]]:
    return parse_devices((await invoke_probe(DEVICE_COMMAND, runner)).stdout)

def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"resourceId": arguments["resourceId"], "authorized": arguments["authorized"]}

def _propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    if not current["online"]:
        raise ValueError("device is offline")
    return {**dict(current), "pendingAuthorization": arguments["authorized"]}

SPEC, MANIFEST, SCHEMAS = provider_bundle(
    LeafDefinition(DOMAIN, PROVIDER_ID, "device", OPERATION_ACTION, "device.authorization.plan", "consequential", ("mutating", "privileged")),
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=STATE_SCHEMA,
    normalize_arguments=_normalize,
    target_id=lambda arguments: arguments["resourceId"],
    propose_state=_propose,
    describe_change=lambda _current, _proposed, arguments: f"Plan device authorization={str(arguments['authorized']).lower()}; this provider does not change hardware state.",
)

def build_provider(*, runner: ProbeRunner = run_probe) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, ReadOnlyProbeBackend(DOMAIN, lambda: _probe_resources(runner)))

def build_fake_provider(resources: list[Mapping[str, Any]], *, state_path: Path | None = None, fail_on: frozenset[str] = frozenset()) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, FakeBackend(DOMAIN, resources, state_path=state_path, fail_on=fail_on))
