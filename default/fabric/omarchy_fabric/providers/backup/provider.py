"""Restic-style home backup truth, retention, and restore planning."""

from __future__ import annotations

import hashlib
import re
from datetime import datetime
from pathlib import Path, PurePosixPath
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .._engine import FakeBackend, LeafProvider
from .._probe import ProbeRunner, invoke_probe, parse_probe_json, run_probe
from .._real import ReadOnlyProbeBackend
from ..process._leaf import LeafDefinition, provider_bundle

DOMAIN = "backup"
PROVIDER_ID = "backup.provider"
OPERATION_ACTION = "home.plan"
RESOURCE_ID = "backup.home"
BACKUP_COMMAND = FixedArgvCommand("/usr/bin/restic", ("snapshots", "--json", "--no-lock"))
ACTIONS = ("snapshot", "prune", "restore")

RETENTION_SCHEMA = {
    "type": "object",
    "required": ["daily", "weekly", "monthly"],
    "properties": {
        "daily": {"type": "integer", "minimum": 1, "maximum": 365},
        "weekly": {"type": "integer", "minimum": 1, "maximum": 260},
        "monthly": {"type": "integer", "minimum": 1, "maximum": 120},
    },
    "additionalProperties": False,
}
PLAN_SCHEMA = {
    "oneOf": [
        {"type": "null"},
        {
            "type": "object",
            "required": ["action", "scope", "snapshotId", "relativePath", "retention", "threats"],
            "properties": {
                "action": {"type": "string", "enum": list(ACTIONS)},
                "scope": {"const": "home"},
                "snapshotId": {"oneOf": [{"type": "null"}, {"type": "string", "pattern": "^[0-9a-f]{8,64}$"}]},
                "relativePath": {"oneOf": [{"type": "null"}, {"type": "string", "minLength": 1, "maxLength": 512}]},
                "retention": RETENTION_SCHEMA,
                "threats": {"type": "array", "const": ["accidental-deletion", "disk-failure", "malware", "repository-loss"]},
            },
            "additionalProperties": False,
        },
    ]
}
STATE_SCHEMA = {
    "type": "object",
    "required": ["repository", "snapshotCount", "snapshotIds", "snapshotInventoryTruncated", "lastSnapshot", "retention", "threatModel", "pendingPlan"],
    "properties": {
        "repository": {"type": "string", "enum": ["available", "locked", "unconfigured", "unavailable"]},
        "snapshotCount": {"type": "integer", "minimum": 0, "maximum": 1000000},
        "snapshotIds": {"type": "array", "maxItems": 64, "uniqueItems": True, "items": {"type": "string", "pattern": "^[0-9a-f]{8,64}$"}},
        "snapshotInventoryTruncated": {"type": "boolean"},
        "lastSnapshot": {"oneOf": [{"type": "null"}, {"type": "string", "maxLength": 64}]},
        "retention": RETENTION_SCHEMA,
        "threatModel": {"type": "array", "const": ["accidental-deletion", "disk-failure", "malware", "repository-loss"]},
        "pendingPlan": PLAN_SCHEMA,
    },
    "additionalProperties": False,
}
RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "scope", "engine", "state"],
    "properties": {
        "id": {"const": RESOURCE_ID},
        "label": {"const": "Home backup"},
        "kind": {"const": "backup-policy"},
        "scope": {"const": "home"},
        "engine": {"const": "restic"},
        "state": STATE_SCHEMA,
    },
    "additionalProperties": False,
}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "action", "scope", "snapshotId", "relativePath", "retention"],
    "properties": {
        "resourceId": {"const": RESOURCE_ID},
        "action": {"type": "string", "enum": list(ACTIONS)},
        "scope": {"const": "home"},
        "snapshotId": {"oneOf": [{"type": "null"}, {"type": "string", "pattern": "^[0-9a-f]{8,64}$"}]},
        "relativePath": {"oneOf": [{"type": "null"}, {"type": "string", "pattern": "^[^/\\x00][^\\x00]{0,511}$"}]},
        "retention": RETENTION_SCHEMA,
    },
    "additionalProperties": False,
}

DEFAULT_RETENTION = {"daily": 7, "weekly": 4, "monthly": 6}
THREATS = ["accidental-deletion", "disk-failure", "malware", "repository-loss"]


def validate_home_relative_path(value: str) -> str:
    if not isinstance(value, str) or not value or "\x00" in value or "\\" in value:
        raise ValueError("backup restore path is invalid")
    path = PurePosixPath(value)
    if (
        path.is_absolute()
        or str(path) != value
        or len(path.parts) > 32
        or any(
            part in {"", ".", ".."}
            or len(part) > 128
            or re.fullmatch(r"[A-Za-z0-9._ @+-]+", part) is None
            for part in path.parts
        )
    ):
        raise ValueError("backup restore path escapes home scope")
    return str(path)


def _validated_home_root(value: str | PurePosixPath) -> PurePosixPath:
    if not isinstance(value, (str, PurePosixPath)):
        raise ValueError("backup home root is invalid")
    raw = str(value)
    root = PurePosixPath(raw)
    if (
        not root.is_absolute()
        or str(root) != raw
        or len(root.parts) != 3
        or root.parts[1] != "home"
        or re.fullmatch(r"[A-Za-z0-9._-]{1,64}", root.parts[2]) is None
    ):
        raise ValueError("backup home root must identify one canonical /home user")
    return root


def _snapshot_path(value: object, home_root: PurePosixPath) -> None:
    if not isinstance(value, str) or not value or len(value) > 1024 or "\x00" in value or "\\" in value:
        raise ValueError("restic snapshot path is invalid")
    if any(part in {"", ".", ".."} for part in value.split("/")[1:]):
        raise ValueError("restic snapshot path is not canonical")
    path = PurePosixPath(value)
    if not path.is_absolute() or str(path) != value or (path != home_root and home_root not in path.parents):
        raise ValueError("restic snapshot escapes the configured home scope")


def _snapshot_time(value: object) -> tuple[datetime, str]:
    if not isinstance(value, str) or not 1 <= len(value) <= 64:
        raise ValueError("restic snapshot timestamp is invalid")
    try:
        parsed = datetime.fromisoformat(value.removesuffix("Z") + ("+00:00" if value.endswith("Z") else ""))
    except ValueError as error:
        raise ValueError("restic snapshot timestamp is invalid") from error
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("restic snapshot timestamp lacks timezone truth")
    return parsed, value


def parse_snapshots(text: str, *, home_root: str | PurePosixPath) -> list[dict[str, Any]]:
    document = parse_probe_json(text)
    if not isinstance(document, list) or len(document) > 1000000:
        raise ValueError("restic snapshot inventory is invalid")
    trusted_home = _validated_home_root(home_root)
    identities: set[str] = set()
    snapshots: list[tuple[datetime, str, str]] = []
    for snapshot in document:
        if not isinstance(snapshot, dict):
            raise ValueError("restic snapshot row is invalid")
        snapshot_id = snapshot.get("id") or snapshot.get("short_id")
        timestamp = snapshot.get("time")
        if not isinstance(snapshot_id, str) or re.fullmatch(r"[0-9a-f]{8,64}", snapshot_id) is None:
            raise ValueError("restic snapshot identity is invalid")
        if snapshot_id in identities:
            raise ValueError("restic snapshot is duplicated or invalid")
        paths = snapshot.get("paths")
        if (
            not isinstance(paths, list)
            or not 1 <= len(paths) <= 128
            or any(not isinstance(path, str) for path in paths)
            or len(paths) != len(set(paths))
        ):
            raise ValueError("restic snapshot lacks bounded path truth")
        for path in paths:
            _snapshot_path(path, trusted_home)
        parsed_time, timestamp_text = _snapshot_time(timestamp)
        identities.add(snapshot_id)
        snapshots.append((parsed_time, snapshot_id, timestamp_text))
    snapshots.sort(key=lambda item: (item[0], item[1]), reverse=True)
    selected_ids = [snapshot_id for _parsed, snapshot_id, _text in snapshots[:64]]
    return [
        {
            "id": RESOURCE_ID,
            "label": "Home backup",
            "kind": "backup-policy",
            "scope": "home",
            "engine": "restic",
            "state": {
                "repository": "available",
                "snapshotCount": len(identities),
                "snapshotIds": selected_ids,
                "snapshotInventoryTruncated": len(snapshots) > len(selected_ids),
                "lastSnapshot": snapshots[0][2] if snapshots else None,
                "retention": dict(DEFAULT_RETENTION),
                "threatModel": list(THREATS),
                "pendingPlan": None,
            },
        }
    ]


async def _probe_resources(runner: ProbeRunner, home_root: str | PurePosixPath) -> list[Mapping[str, Any]]:
    return parse_snapshots((await invoke_probe(BACKUP_COMMAND, runner)).stdout, home_root=home_root)


def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    normalized = {key: arguments[key] for key in ("resourceId", "action", "scope", "snapshotId", "relativePath", "retention")}
    if normalized["relativePath"] is not None:
        normalized["relativePath"] = validate_home_relative_path(normalized["relativePath"])
    return normalized


def _propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    if current["repository"] != "available":
        raise ValueError("backup repository is unavailable")
    action = arguments["action"]
    snapshot_id, relative_path = arguments["snapshotId"], arguments["relativePath"]
    if action == "restore" and (snapshot_id is None or relative_path is None):
        raise ValueError("restore requires a snapshot and a home-relative path")
    if action == "restore" and snapshot_id not in current["snapshotIds"]:
        raise ValueError("restore snapshot is absent from the bounded trusted inventory")
    if action != "restore" and (snapshot_id is not None or relative_path is not None):
        raise ValueError("snapshot identity and path are accepted only for restore")
    pending_plan = {
        "action": action,
        "scope": "home",
        "snapshotId": snapshot_id,
        "relativePath": relative_path,
        "retention": dict(arguments["retention"]),
        "threats": list(THREATS),
    }
    if current["pendingPlan"] is not None:
        if current["pendingPlan"] == pending_plan:
            return dict(current)
        raise ValueError("a different backup plan is already pending")
    return {**dict(current), "retention": dict(arguments["retention"]), "pendingPlan": pending_plan}


SPEC, MANIFEST, SCHEMAS = provider_bundle(
    LeafDefinition(DOMAIN, PROVIDER_ID, "backup-policy", OPERATION_ACTION, "backup.home.plan", "consequential", ("mutating", "network"), max_resources=1),
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=STATE_SCHEMA,
    normalize_arguments=_normalize,
    target_id=lambda _arguments: RESOURCE_ID,
    propose_state=_propose,
    describe_change=lambda _current, _proposed, arguments: f"Plan restic-style home {arguments['action']} within the closed home scope; no repository operation is executed.",
)


def build_provider(*, runner: ProbeRunner = run_probe, home_root: str | PurePosixPath | None = None) -> LeafProvider:
    trusted_home = _validated_home_root(Path.home().as_posix() if home_root is None else home_root)
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, ReadOnlyProbeBackend(DOMAIN, lambda: _probe_resources(runner, trusted_home)))


def build_fake_provider(resources: list[Mapping[str, Any]], *, state_path: Path | None = None, fail_on: frozenset[str] = frozenset()) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, FakeBackend(DOMAIN, resources, state_path=state_path, fail_on=fail_on))
