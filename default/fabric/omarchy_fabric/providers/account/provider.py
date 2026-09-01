"""Local account inventory and guarded account-change planning."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .._engine import FakeBackend, LeafProvider
from .._probe import ProbeRunner, invoke_probe, run_probe
from .._real import ReadOnlyProbeBackend
from ..process._leaf import LeafDefinition, provider_bundle

DOMAIN = "account"
PROVIDER_ID = "account.provider"
OPERATION_ACTION = "change.plan"
ACCOUNT_COMMAND = FixedArgvCommand("/usr/bin/getent", ("passwd",))
ACTIONS = ("lock", "unlock", "promote", "demote")

STATE_SCHEMA = {
    "type": "object",
    "required": ["lockState", "role", "mutable", "pendingAction"],
    "properties": {
        "lockState": {"type": "string", "enum": ["locked", "unlocked", "unknown"]},
        "role": {"type": "string", "enum": ["administrator", "standard", "system", "unknown"]},
        "mutable": {"type": "boolean"},
        "pendingAction": {"oneOf": [{"type": "null"}, {"type": "string", "enum": list(ACTIONS)}]},
    },
    "additionalProperties": False,
}
RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "uid", "homeClass", "shell", "state"],
    "properties": {
        "id": {"type": "string", "pattern": "^account\\.[0-9a-f]{24}$"},
        "label": {"type": "string", "pattern": "^[a-z_][a-z0-9_-]{0,31}$"},
        "kind": {"const": "account"},
        "uid": {"type": "integer", "minimum": 0, "maximum": 4294967295},
        "homeClass": {"type": "string", "enum": ["home", "root", "service", "other"]},
        "shell": {"type": "string", "enum": ["interactive", "nologin", "other"]},
        "state": STATE_SCHEMA,
    },
    "additionalProperties": False,
}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "action"],
    "properties": {
        "resourceId": {"type": "string", "pattern": "^account\\.[0-9a-f]{24}$"},
        "action": {"type": "string", "enum": list(ACTIONS)},
    },
    "additionalProperties": False,
}

def parse_accounts(text: str) -> list[dict[str, Any]]:
    resources: list[dict[str, Any]] = []
    seen_uid: set[int] = set()
    for line in text.splitlines():
        fields = line.split(":")
        if len(fields) != 7:
            raise ValueError("passwd row is invalid")
        name, _password, uid_text, _gid, _gecos, home, shell = fields
        if not uid_text.isdecimal() or re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", name) is None:
            raise ValueError("account identity is invalid")
        uid = int(uid_text)
        if uid > 4294967295 or uid in seen_uid:
            raise ValueError("account UID is duplicated")
        seen_uid.add(uid)
        if uid == 0:
            home_class, role, mutable = "root", "administrator", False
        elif uid < 1000:
            home_class, role, mutable = "service", "system", False
        else:
            home_class, role, mutable = ("home" if home.startswith("/home/") else "other"), "unknown", True
        shell_class = "nologin" if shell.endswith(("/nologin", "/false")) else ("interactive" if shell.endswith(("/bash", "/zsh", "/fish")) else "other")
        resources.append(
            {
                "id": f"account.{hashlib.sha256(f'{uid}:{name}'.encode('utf-8')).hexdigest()[:24]}",
                "label": name,
                "kind": "account",
                "uid": uid,
                "homeClass": home_class,
                "shell": shell_class,
                "state": {"lockState": "unknown", "role": role, "mutable": mutable, "pendingAction": None},
            }
        )
        if len(resources) > 64:
            raise ValueError("account inventory exceeds 64 resources")
    return resources

async def _probe_resources(runner: ProbeRunner) -> list[Mapping[str, Any]]:
    return parse_accounts((await invoke_probe(ACCOUNT_COMMAND, runner)).stdout)

def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"resourceId": arguments["resourceId"], "action": arguments["action"]}

def _propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    if not current["mutable"]:
        raise ValueError("system and root accounts cannot be changed through this provider")
    action = arguments["action"]
    if action in {"lock", "unlock"} and current["lockState"] == ("locked" if action == "lock" else "unlocked"):
        raise ValueError("account already has requested lock state")
    if action in {"promote", "demote"} and current["role"] == ("administrator" if action == "promote" else "standard"):
        raise ValueError("account already has requested role")
    return {**dict(current), "pendingAction": action}

SPEC, MANIFEST, SCHEMAS = provider_bundle(
    LeafDefinition(DOMAIN, PROVIDER_ID, "account", OPERATION_ACTION, "account.change.plan", "consequential", ("mutating", "privileged")),
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=STATE_SCHEMA,
    normalize_arguments=_normalize,
    target_id=lambda arguments: arguments["resourceId"],
    propose_state=_propose,
    describe_change=lambda _current, _proposed, arguments: f"Plan allowlisted account action {arguments['action']}; no account database is changed.",
)

def build_provider(*, runner: ProbeRunner = run_probe) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, ReadOnlyProbeBackend(DOMAIN, lambda: _probe_resources(runner)))

def build_fake_provider(resources: list[Mapping[str, Any]], *, state_path: Path | None = None, fail_on: frozenset[str] = frozenset()) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, FakeBackend(DOMAIN, resources, state_path=state_path, fail_on=fail_on))
