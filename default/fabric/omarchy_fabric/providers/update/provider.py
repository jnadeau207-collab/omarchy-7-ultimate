"""Update inventory plus checkpoint and reboot-aware plan state."""

from __future__ import annotations

import hashlib
import re
import subprocess
from pathlib import Path
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .._engine import FakeBackend, LeafProvider
from .._probe import ProbeRunner, invoke_probe, run_probe
from .._real import ReadOnlyProbeBackend
from ..process._leaf import LeafDefinition, provider_bundle

DOMAIN = "update"
PROVIDER_ID = "update.provider"
OPERATION_ACTION = "system.plan"
RESOURCE_ID = "update.system"
UPDATE_COMMAND = FixedArgvCommand("/usr/bin/checkupdates", ("--nocolor",))
MODES = ("check", "download", "apply", "reboot")
PHASES = ("idle", "ready", "staged", "applying", "waiting-reboot", "succeeded", "interrupted", "reconciling", "cancelled", "failed")

PLAN_SCHEMA = {
    "oneOf": [
        {"type": "null"},
        {
            "type": "object",
            "required": ["mode", "checkpointRequired", "rebootExpected", "catalogRevision"],
            "properties": {
                "mode": {"type": "string", "enum": list(MODES)},
                "checkpointRequired": {"type": "boolean"},
                "rebootExpected": {"type": "boolean"},
                "catalogRevision": {"type": "string", "pattern": "^sha256\\.[0-9a-f]{64}$"},
            },
            "additionalProperties": False,
        },
    ]
}
STATE_SCHEMA = {
    "type": "object",
    "required": ["phase", "availableCount", "catalogRevision", "checkpoint", "rebootRequired", "pendingPlan"],
    "properties": {
        "phase": {"type": "string", "enum": list(PHASES)},
        "availableCount": {"type": "integer", "minimum": 0, "maximum": 100000},
        "catalogRevision": {"type": "string", "pattern": "^sha256\\.[0-9a-f]{64}$"},
        "checkpoint": {"type": "string", "enum": ["none", "required", "created", "failed"]},
        "rebootRequired": {"type": "boolean"},
        "pendingPlan": PLAN_SCHEMA,
    },
    "additionalProperties": False,
}
RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "channel", "state"],
    "properties": {
        "id": {"const": RESOURCE_ID},
        "label": {"const": "System update"},
        "kind": {"const": "system-update"},
        "channel": {"const": "arch"},
        "state": STATE_SCHEMA,
    },
    "additionalProperties": False,
}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "mode", "createCheckpoint"],
    "properties": {
        "resourceId": {"const": RESOURCE_ID},
        "mode": {"type": "string", "enum": list(MODES)},
        "createCheckpoint": {"type": "boolean"},
    },
    "additionalProperties": False,
}


def parse_updates(text: str) -> list[dict[str, Any]]:
    packages: list[tuple[str, str, str]] = []
    for line in text.splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(r"([A-Za-z0-9@._+:-]{1,160})\s+([^\s]{1,128})\s+->\s+([^\s]{1,128})", line.strip())
        if match is None:
            raise ValueError("update row is invalid")
        packages.append(match.groups())
    if len(packages) > 100000 or len({package[0] for package in packages}) != len(packages):
        raise ValueError("update inventory is duplicated or too large")
    canonical = "\n".join("\t".join(package) for package in sorted(packages))
    revision = "sha256." + hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    return [
        {
            "id": RESOURCE_ID,
            "label": "System update",
            "kind": "system-update",
            "channel": "arch",
            "state": {
                "phase": "ready" if packages else "idle",
                "availableCount": len(packages),
                "catalogRevision": revision,
                "checkpoint": "none",
                "rebootRequired": False,
                "pendingPlan": None,
            },
        }
    ]


async def _probe_resources(runner: ProbeRunner) -> list[Mapping[str, Any]]:
    try:
        output = (await invoke_probe(UPDATE_COMMAND, runner)).stdout
    except subprocess.CalledProcessError as error:
        if error.returncode != 2 or error.stdout not in {None, ""} or error.stderr not in {None, ""}:
            raise
        output = ""
    return parse_updates(output)


def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"resourceId": RESOURCE_ID, "mode": arguments["mode"], "createCheckpoint": arguments["createCheckpoint"]}


def _propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    mode = arguments["mode"]
    required_phase = {"check": {"idle", "ready"}, "download": {"ready"}, "apply": {"ready"}, "reboot": {"waiting-reboot"}}[mode]
    if current["phase"] not in required_phase:
        raise ValueError("update mode is not valid in the current lifecycle phase")
    if mode in {"download", "apply"} and current["availableCount"] == 0:
        raise ValueError("no update is available")
    if mode == "apply" and not arguments["createCheckpoint"]:
        raise ValueError("system update apply requires an explicit checkpoint")
    if mode == "reboot" and not current["rebootRequired"]:
        raise ValueError("system does not currently require a reboot")
    if mode != "apply" and arguments["createCheckpoint"]:
        raise ValueError("checkpoint creation is accepted only for apply")
    pending_plan = {
        "mode": mode,
        "checkpointRequired": mode == "apply",
        "rebootExpected": mode in {"apply", "reboot"},
        "catalogRevision": current["catalogRevision"],
    }
    if current["pendingPlan"] is not None:
        if current["pendingPlan"] == pending_plan:
            return dict(current)
        raise ValueError("a different update plan is already pending")
    return {**dict(current), "checkpoint": "required" if mode == "apply" else current["checkpoint"], "pendingPlan": pending_plan}


SPEC, MANIFEST, SCHEMAS = provider_bundle(
    LeafDefinition(DOMAIN, PROVIDER_ID, "system-update", OPERATION_ACTION, "update.system.plan", "consequential", ("mutating", "privileged", "download", "network", "restart", "reboot"), max_resources=1),
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=STATE_SCHEMA,
    normalize_arguments=_normalize,
    target_id=lambda _arguments: RESOURCE_ID,
    propose_state=_propose,
    describe_change=lambda _current, _proposed, arguments: f"Plan update mode {arguments['mode']} with explicit checkpoint and reboot expectations; no package or reboot command is executed.",
)


def build_provider(*, runner: ProbeRunner = run_probe) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, ReadOnlyProbeBackend(DOMAIN, lambda: _probe_resources(runner)))


def build_fake_provider(resources: list[Mapping[str, Any]], *, state_path: Path | None = None, fail_on: frozenset[str] = frozenset()) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, FakeBackend(DOMAIN, resources, state_path=state_path, fail_on=fail_on))
