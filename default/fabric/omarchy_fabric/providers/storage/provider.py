"""Storage inventory and destructive-preflight models; never live mutation."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from pathlib import PurePosixPath
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .._engine import FakeBackend, LeafProvider
from .._probe import ProbeRunner, invoke_probe, parse_probe_json, run_probe
from .._real import ReadOnlyProbeBackend
from ..process._leaf import LeafDefinition, provider_bundle

DOMAIN = "storage"
PROVIDER_ID = "storage.provider"
OPERATION_ACTION = "change.plan"
STORAGE_COMMAND = FixedArgvCommand(
    "/usr/bin/lsblk",
    ("--json", "--bytes", "--output", "NAME,PATH,TYPE,SIZE,RM,RO,FSTYPE,UUID,MOUNTPOINTS"),
)
ACTIONS = ("mount", "unmount", "eject", "unlock", "lock", "format", "wipe")
FILESYSTEMS = ("btrfs", "ext4", "exfat", "fat32", "ntfs")

PENDING_SCHEMA = {
    "oneOf": [
        {"type": "null"},
        {
            "type": "object",
            "required": ["action", "filesystem", "destructive", "confirmationDigest"],
            "properties": {
                "action": {"type": "string", "enum": list(ACTIONS)},
                "filesystem": {"oneOf": [{"type": "null"}, {"type": "string", "enum": list(FILESYSTEMS)}]},
                "destructive": {"type": "boolean"},
                "confirmationDigest": {"oneOf": [{"type": "null"}, {"type": "string", "pattern": "^sha256\\.[0-9a-f]{64}$"}]},
            },
            "additionalProperties": False,
        },
    ]
}
STATE_SCHEMA = {
    "type": "object",
    "required": ["mounted", "mountPoint", "activeSwap", "encrypted", "locked", "readOnly", "removable", "smartHealth", "observedRevision", "pendingPlan"],
    "properties": {
        "mounted": {"type": "boolean"},
        "mountPoint": {"oneOf": [{"type": "null"}, {"type": "string", "pattern": "^/[^\\x00-\\x1f\\x7f]{0,511}$"}]},
        "activeSwap": {"type": "boolean"},
        "encrypted": {"type": "boolean"},
        "locked": {"type": "boolean"},
        "readOnly": {"type": "boolean"},
        "removable": {"type": "boolean"},
        "smartHealth": {"type": "string", "enum": ["healthy", "failing", "unknown", "unavailable"]},
        "observedRevision": {"type": "string", "pattern": "^sha256\\.[0-9a-f]{64}$"},
        "pendingPlan": PENDING_SCHEMA,
    },
    "additionalProperties": False,
}
RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "devicePath", "deviceType", "sizeBytes", "removable", "filesystem", "state"],
    "properties": {
        "id": {"type": "string", "pattern": "^storage\\.[0-9a-f]{24}$"},
        "label": {"type": "string", "minLength": 1, "maxLength": 128},
        "kind": {"const": "volume"},
        "devicePath": {"type": "string", "pattern": "^/dev/[A-Za-z0-9._+-]+(?:/[A-Za-z0-9._+-]+)*$", "maxLength": 205},
        "deviceType": {"type": "string", "enum": ["disk", "part", "crypt", "lvm", "rom", "loop", "raid", "other"]},
        "sizeBytes": {"type": "integer", "minimum": 0, "maximum": 1152921504606846976},
        "removable": {"type": "boolean"},
        "filesystem": {"oneOf": [{"type": "null"}, {"type": "string", "minLength": 1, "maxLength": 32}]},
        "state": STATE_SCHEMA,
    },
    "additionalProperties": False,
}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "action", "filesystem", "confirmation"],
    "properties": {
        "resourceId": {"type": "string", "pattern": "^storage\\.[0-9a-f]{24}$"},
        "action": {"type": "string", "enum": list(ACTIONS)},
        "filesystem": {"oneOf": [{"type": "null"}, {"type": "string", "enum": list(FILESYSTEMS)}]},
        "confirmation": {"oneOf": [{"type": "null"}, {"type": "string", "pattern": "^ERASE:storage\\.[0-9a-f]{24}$", "maxLength": 128}]},
    },
    "additionalProperties": False,
}


def _device_path(value: object) -> str:
    if not isinstance(value, str) or not 6 <= len(value) <= 205 or "\x00" in value or "\\" in value:
        raise ValueError("storage device path is invalid")
    path = PurePosixPath(value)
    if (
        not path.is_absolute()
        or str(path) != value
        or path.parts[:2] != ("/", "dev")
        or len(path.parts) < 3
        or any(part in {"", ".", ".."} or re.fullmatch(r"[A-Za-z0-9._+-]{1,128}", part) is None for part in path.parts[2:])
    ):
        raise ValueError("storage device path escapes /dev")
    return value


def _identity(item: Mapping[str, Any], *, path: str, size: int, device_type: str) -> str:
    uuid_value = item.get("uuid")
    if uuid_value is not None and (not isinstance(uuid_value, str) or not 1 <= len(uuid_value) <= 256 or any(not character.isprintable() for character in uuid_value)):
        raise ValueError("storage UUID identity is invalid")
    value = f"{uuid_value or 'no-uuid'}:{path}:{size}:{device_type}"
    return f"storage.{hashlib.sha256(value.encode('utf-8')).hexdigest()[:24]}"


def _flatten(items: list[Any]) -> list[Mapping[str, Any]]:
    output: list[Mapping[str, Any]] = []
    pending = list(items)
    while pending:
        item = pending.pop(0)
        if not isinstance(item, Mapping):
            raise ValueError("lsblk item is invalid")
        children = item.get("children", [])
        if not isinstance(children, list):
            raise ValueError("lsblk children are invalid")
        normalized = dict(item)
        normalized.pop("children", None)
        output.append(normalized)
        pending[0:0] = children
        if len(output) > 64:
            raise ValueError("storage inventory exceeds 64 resources")
    return output


def parse_storage(text: str) -> list[dict[str, Any]]:
    document = parse_probe_json(text)
    if not isinstance(document, dict) or set(document) != {"blockdevices"} or not isinstance(document["blockdevices"], list):
        raise ValueError("lsblk document is invalid")
    resources: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in _flatten(document["blockdevices"]):
        path = _device_path(item.get("path"))
        mounts = item.get("mountpoints") or []
        if not isinstance(mounts, list) or any(value is not None and not isinstance(value, str) for value in mounts):
            raise ValueError("storage mount inventory is invalid")
        mount = next((value for value in mounts if value), None)
        active_swap = mount == "[SWAP]"
        if active_swap:
            mount = None
        if mount is not None and (not mount.startswith("/") or len(mount) > 512 or any(not character.isprintable() for character in mount)):
            raise ValueError("storage mount point is invalid")
        raw_type = str(item.get("type") or "other")
        device_type = raw_type if raw_type in {"disk", "part", "crypt", "lvm", "rom", "loop", "raid"} else "other"
        size = item.get("size", 0)
        if isinstance(size, bool) or not isinstance(size, int) or not 0 <= size <= 1152921504606846976:
            raise ValueError("storage size is invalid")
        for flag in ("rm", "ro"):
            if not isinstance(item.get(flag), bool):
                raise ValueError("storage boolean truth is invalid")
        resource_id = _identity(item, path=path, size=size, device_type=device_type)
        if resource_id in seen:
            raise ValueError("storage resource identity is duplicated")
        seen.add(resource_id)
        filesystem = item.get("fstype")
        if filesystem is not None and (not isinstance(filesystem, str) or not 1 <= len(filesystem) <= 32):
            raise ValueError("storage filesystem is invalid")
        name = item.get("name")
        if not isinstance(name, str) or not 1 <= len(name) <= 128 or any(not character.isprintable() for character in name):
            raise ValueError("storage label is invalid")
        encrypted = device_type == "crypt" or filesystem == "crypto_LUKS"
        resources.append(
            {
                "id": resource_id,
                "label": name,
                "kind": "volume",
                "devicePath": path,
                "deviceType": device_type,
                "sizeBytes": size,
                "removable": item["rm"],
                "filesystem": filesystem,
                "state": {
                    "mounted": mount is not None,
                    "mountPoint": mount,
                    "activeSwap": active_swap,
                    "encrypted": encrypted,
                    "locked": filesystem == "crypto_LUKS",
                    "readOnly": item["ro"],
                    "removable": item["rm"],
                    "smartHealth": "unknown" if device_type == "disk" else "unavailable",
                    "observedRevision": "sha256."
                    + hashlib.sha256(
                        json.dumps(
                            [item.get("uuid"), path, size, device_type, filesystem, item["rm"], item["ro"], mounts],
                            ensure_ascii=False,
                            separators=(",", ":"),
                        ).encode("utf-8")
                    ).hexdigest(),
                    "pendingPlan": None,
                },
            }
        )
    return resources


async def _probe_resources(runner: ProbeRunner) -> list[Mapping[str, Any]]:
    return parse_storage((await invoke_probe(STORAGE_COMMAND, runner)).stdout)


def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {key: arguments[key] for key in ("resourceId", "action", "filesystem", "confirmation")}


def destructive_confirmation(resource_id: str) -> str:
    return f"ERASE:{resource_id}"


def _propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    action = arguments["action"]
    if action == "mount" and (current["mounted"] or current["locked"]):
        raise ValueError("volume cannot be mounted in its current state")
    if action == "unmount" and not current["mounted"]:
        raise ValueError("volume is not mounted")
    if action == "eject" and (current["mounted"] or current["activeSwap"] or not current["removable"]):
        raise ValueError("only an unmounted removable volume can be ejected")
    if action == "unlock" and (not current["encrypted"] or not current["locked"]):
        raise ValueError("volume is not a locked encrypted volume")
    if action == "lock" and (not current["encrypted"] or current["locked"] or current["mounted"]):
        raise ValueError("encrypted volume cannot be locked in its current state")
    destructive = action in {"format", "wipe"}
    if destructive and (current["mounted"] or current["activeSwap"]):
        raise ValueError("active storage must be deactivated before a destructive plan")
    expected_confirmation = destructive_confirmation(arguments["resourceId"])
    if destructive and arguments["confirmation"] != expected_confirmation:
        raise ValueError("destructive storage plan lacks exact confirmation")
    if action == "format" and arguments["filesystem"] is None:
        raise ValueError("format plan requires an allowlisted filesystem")
    if action != "format" and arguments["filesystem"] is not None:
        raise ValueError("filesystem is accepted only for format plans")
    confirmation_digest = None
    if destructive:
        confirmation_digest = "sha256." + hashlib.sha256(expected_confirmation.encode("utf-8")).hexdigest()
    return {
        **dict(current),
        "pendingPlan": {
            "action": action,
            "filesystem": arguments["filesystem"],
            "destructive": destructive,
            "confirmationDigest": confirmation_digest,
        },
    }


SPEC, MANIFEST, SCHEMAS = provider_bundle(
    LeafDefinition(DOMAIN, PROVIDER_ID, "volume", OPERATION_ACTION, "storage.change.plan", "destructive", ("mutating", "privileged", "destructive")),
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=STATE_SCHEMA,
    normalize_arguments=_normalize,
    target_id=lambda arguments: arguments["resourceId"],
    propose_state=_propose,
    describe_change=lambda _current, _proposed, arguments: f"Build a fail-closed {arguments['action']} plan; the real provider never executes storage mutations.",
)


def build_provider(*, runner: ProbeRunner = run_probe) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, ReadOnlyProbeBackend(DOMAIN, lambda: _probe_resources(runner)))


def build_fake_provider(resources: list[Mapping[str, Any]], *, state_path: Path | None = None, fail_on: frozenset[str] = frozenset()) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, FakeBackend(DOMAIN, resources, state_path=state_path, fail_on=fail_on))
