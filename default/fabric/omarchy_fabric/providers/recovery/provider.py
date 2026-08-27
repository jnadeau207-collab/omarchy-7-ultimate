"""System-only restore point truth and non-executing restore plans."""

from __future__ import annotations

import hashlib
from datetime import datetime
from pathlib import Path
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .._engine import FakeBackend, LeafProvider
from .._probe import ProbeRunner, invoke_probe, parse_probe_json, run_probe
from .._real import ReadOnlyProbeBackend
from ..process._leaf import LeafDefinition, provider_bundle

DOMAIN = "recovery"
PROVIDER_ID = "recovery.provider"
OPERATION_ACTION = "restore.plan"
RECOVERY_COMMAND = FixedArgvCommand("/usr/bin/snapper", ("--config", "root", "--utc", "--iso", "--jsonout", "list"))

PLAN_SCHEMA = {
    "oneOf": [
        {"type": "null"},
        {
            "type": "object",
            "required": ["scope", "preservesHome", "requiresReboot", "restorePointRevision", "confirmationDigest"],
            "properties": {
                "scope": {"const": "system"},
                "preservesHome": {"const": True},
                "requiresReboot": {"const": True},
                "restorePointRevision": {"type": "string", "pattern": "^sha256\\.[0-9a-f]{64}$"},
                "confirmationDigest": {"type": "string", "pattern": "^sha256\\.[0-9a-f]{64}$"},
            },
            "additionalProperties": False,
        },
    ]
}
STATE_SCHEMA = {
    "type": "object",
    "required": ["eligible", "readOnly", "health", "revision", "pendingPlan"],
    "properties": {
        "eligible": {"type": "boolean"},
        "readOnly": {"oneOf": [{"type": "null"}, {"type": "boolean"}]},
        "health": {"type": "string", "enum": ["healthy", "degraded", "unavailable", "unknown"]},
        "revision": {"type": "string", "pattern": "^sha256\\.[0-9a-f]{64}$"},
        "pendingPlan": PLAN_SCHEMA,
    },
    "additionalProperties": False,
}
RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "scope", "source", "createdAt", "description", "state"],
    "properties": {
        "id": {"type": "string", "pattern": "^restore-point\\.[0-9a-f]{24}$"},
        "label": {"type": "string", "minLength": 1, "maxLength": 160},
        "kind": {"const": "restore-point"},
        "scope": {"const": "system"},
        "source": {"type": "string", "enum": ["snapshot", "transaction"]},
        "createdAt": {"type": "string", "minLength": 1, "maxLength": 64},
        "description": {"type": "string", "maxLength": 512},
        "state": STATE_SCHEMA,
    },
    "additionalProperties": False,
}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "scope", "preserveHome", "confirmation"],
    "properties": {
        "resourceId": {"type": "string", "pattern": "^restore-point\\.[0-9a-f]{24}$"},
        "scope": {"const": "system"},
        "preserveHome": {"const": True},
        "confirmation": {"type": "string", "pattern": "^RESTORE:restore-point\\.[0-9a-f]{24}$", "maxLength": 128},
    },
    "additionalProperties": False,
}


def _bounded_text(value: object, maximum: int) -> str:
    if not isinstance(value, str):
        return ""
    return "".join(character for character in value if character.isprintable() and character not in "\r\n\x00")[:maximum]


def _created_at(value: object) -> str:
    text = _bounded_text(value, 64)
    if not text:
        raise ValueError("restore point creation time is invalid")
    try:
        parsed = datetime.fromisoformat(text.removesuffix("Z") + ("+00:00" if text.endswith("Z") else ""))
    except ValueError as error:
        raise ValueError("restore point creation time is invalid") from error
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("restore point creation time lacks timezone truth")
    return text


def parse_restore_points(text: str) -> list[dict[str, Any]]:
    document = parse_probe_json(text)
    if isinstance(document, dict):
        rows = document.get("data")
    else:
        rows = document
    if not isinstance(rows, list) or len(rows) > 64:
        raise ValueError("restore point inventory is invalid")
    resources: list[dict[str, Any]] = []
    seen: set[str] = set()
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("restore point row is invalid")
        number = row.get("number")
        raw_created_at = row.get("date") or row.get("createdAt")
        raw_description = _bounded_text(row.get("description"), 512)
        if isinstance(number, bool) or not isinstance(number, (int, str)) or not str(number).isdigit():
            raise ValueError("restore point identity is invalid")
        number_text = str(number)
        number_value = int(number_text)
        if number_value == 0:
            continue
        created_at = _created_at(raw_created_at)
        if number_text != str(number_value) or number_value > 9223372036854775807 or not created_at:
            raise ValueError("restore point identity is invalid")
        identity = f"snapper:{number_value}:{created_at}"
        resource_id = f"restore-point.{hashlib.sha256(identity.encode('utf-8')).hexdigest()[:24]}"
        if resource_id in seen:
            raise ValueError("restore point identity is duplicated")
        seen.add(resource_id)
        revision = "sha256." + hashlib.sha256((identity + ":" + raw_description).encode("utf-8")).hexdigest()
        resources.append(
            {
                "id": resource_id,
                "label": f"System restore point {number_value}"[:160],
                "kind": "restore-point",
                "scope": "system",
                "source": "snapshot",
                "createdAt": created_at,
                "description": "Snapshot description is present but withheld." if raw_description else "",
                "state": {"eligible": False, "readOnly": None, "health": "unknown", "revision": revision, "pendingPlan": None},
            }
        )
    return resources


def require_system_only(resources: list[Mapping[str, Any]]) -> None:
    if any(resource.get("scope") != "system" for resource in resources):
        raise ValueError("restore inventory contains a non-system restore point")


async def _probe_resources(runner: ProbeRunner) -> list[Mapping[str, Any]]:
    resources = parse_restore_points((await invoke_probe(RECOVERY_COMMAND, runner)).stdout)
    require_system_only(resources)
    return resources


def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {key: arguments[key] for key in ("resourceId", "scope", "preserveHome", "confirmation")}


def _propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    expected = f"RESTORE:{arguments['resourceId']}"
    if arguments["scope"] != "system" or not arguments["preserveHome"]:
        raise ValueError("restore plans are system-only and must preserve home")
    if arguments["confirmation"] != expected:
        raise ValueError("restore plan lacks exact confirmation")
    if not current["eligible"] or current["health"] != "healthy" or current["readOnly"] is not True:
        raise ValueError("restore point lacks verified health, eligibility, or read-only truth")
    pending_plan = {
        "scope": "system",
        "preservesHome": True,
        "requiresReboot": True,
        "restorePointRevision": current["revision"],
        "confirmationDigest": "sha256." + hashlib.sha256(expected.encode("utf-8")).hexdigest(),
    }
    if current["pendingPlan"] is not None:
        if current["pendingPlan"] == pending_plan:
            return dict(current)
        raise ValueError("a different restore plan is already pending")
    return {**dict(current), "pendingPlan": pending_plan}


SPEC, MANIFEST, SCHEMAS = provider_bundle(
    LeafDefinition(DOMAIN, PROVIDER_ID, "restore-point", OPERATION_ACTION, "recovery.restore.plan", "destructive", ("mutating", "privileged", "destructive", "reboot")),
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=STATE_SCHEMA,
    normalize_arguments=_normalize,
    target_id=lambda arguments: arguments["resourceId"],
    propose_state=_propose,
    describe_change=lambda _current, _proposed, _arguments: "Plan a system-only restore that preserves home and requires reboot; this provider never applies the restore.",
)


def build_provider(*, runner: ProbeRunner = run_probe) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, ReadOnlyProbeBackend(DOMAIN, lambda: _probe_resources(runner)))


def build_fake_provider(resources: list[Mapping[str, Any]], *, state_path: Path | None = None, fail_on: frozenset[str] = frozenset()) -> LeafProvider:
    require_system_only(resources)
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, FakeBackend(DOMAIN, resources, state_path=state_path, fail_on=fail_on))
