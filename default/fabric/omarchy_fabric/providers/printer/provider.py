"""Credential-safe printer inventory and queue-change planning."""

from __future__ import annotations

import hashlib
import subprocess
from pathlib import Path
from typing import Any, Mapping
from urllib.parse import urlsplit

from omarchy_fabric.models import FixedArgvCommand

from .._engine import FakeBackend, LeafProvider
from .._probe import ProbeRunner, invoke_probe, run_probe
from .._real import ReadOnlyProbeBackend
from ..process._leaf import LeafDefinition, provider_bundle

DOMAIN = "printer"
PROVIDER_ID = "printer.provider"
OPERATION_ACTION = "queue.plan"
PRINTER_COMMAND = FixedArgvCommand("/usr/bin/lpstat", ("-v",))
ACTIONS = ("pause", "resume", "set-default", "test-page")

STATE_SCHEMA = {
    "type": "object",
    "required": ["availability", "accepting", "configurationRevision", "pendingAction"],
    "properties": {
        "availability": {"type": "string", "enum": ["available", "unavailable", "unknown"]},
        "accepting": {"oneOf": [{"type": "null"}, {"type": "boolean"}]},
        "configurationRevision": {"type": "string", "pattern": "^sha256\\.[0-9a-f]{64}$"},
        "pendingAction": {"oneOf": [{"type": "null"}, {"type": "string", "enum": list(ACTIONS)}]},
    },
    "additionalProperties": False,
}
RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "connection", "endpoint", "state"],
    "properties": {
        "id": {"type": "string", "pattern": "^printer\\.[0-9a-f]{24}$"},
        "label": {"type": "string", "pattern": "^[A-Za-z0-9._-]{1,128}$"},
        "kind": {"const": "printer"},
        "connection": {"type": "string", "enum": ["local", "network", "unknown"]},
        "endpoint": {"type": "string", "minLength": 1, "maxLength": 253},
        "state": STATE_SCHEMA,
    },
    "additionalProperties": False,
}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "action"],
    "properties": {
        "resourceId": {"type": "string", "pattern": "^printer\\.[0-9a-f]{24}$"},
        "action": {"type": "string", "enum": list(ACTIONS)},
    },
    "additionalProperties": False,
}

def _safe_endpoint(uri: str) -> tuple[str, str]:
    parsed = urlsplit(uri)
    if parsed.username is not None or parsed.password is not None:
        raise ValueError("printer URI contains credentials")
    scheme = parsed.scheme.lower()
    if scheme in {"ipp", "ipps", "http", "https", "socket", "lpd"}:
        if not parsed.hostname:
            raise ValueError("network printer URI lacks a host")
        return "network", parsed.hostname[:253]
    if scheme in {"usb", "serial", "parallel", "file"}:
        return "local", scheme
    return "unknown", scheme[:32] or "unknown"

def parse_printers(text: str) -> list[dict[str, Any]]:
    resources: list[dict[str, Any]] = []
    seen: set[str] = set()
    for line in text.splitlines():
        prefix = "device for "
        if not line.startswith(prefix) or ": " not in line:
            raise ValueError("printer row is invalid")
        name, uri = line[len(prefix):].split(": ", 1)
        if not name or len(name) > 128 or any(character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-" for character in name):
            raise ValueError("printer name is invalid")
        connection, endpoint = _safe_endpoint(uri)
        resource_id = f"printer.{hashlib.sha256(name.encode('utf-8')).hexdigest()[:24]}"
        if resource_id in seen:
            raise ValueError("printer identity is duplicated")
        seen.add(resource_id)
        resources.append(
            {
                "id": resource_id,
                "label": name,
                "kind": "printer",
                "connection": connection,
                "endpoint": endpoint,
                "state": {
                    "availability": "unknown",
                    "accepting": None,
                    "configurationRevision": "sha256." + hashlib.sha256(f"{name}\x00{uri}".encode("utf-8")).hexdigest(),
                    "pendingAction": None,
                },
            }
        )
    return resources

async def _probe_resources(runner: ProbeRunner) -> list[Mapping[str, Any]]:
    try:
        output = (await invoke_probe(PRINTER_COMMAND, runner)).stdout
    except subprocess.CalledProcessError as error:
        empty_messages = {"lpstat: No destinations added.", "lpstat: No destinations."}
        if error.returncode != 1 or error.stdout not in {None, ""} or str(error.stderr).strip() not in empty_messages:
            raise
        output = ""
    return parse_printers(output)

def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"resourceId": arguments["resourceId"], "action": arguments["action"]}

def _propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    action = arguments["action"]
    if action == "pause" and current["accepting"] is False:
        raise ValueError("printer is already paused")
    if action == "resume" and current["accepting"] is True:
        raise ValueError("printer is already accepting jobs")
    return {**dict(current), "pendingAction": action}

SPEC, MANIFEST, SCHEMAS = provider_bundle(
    LeafDefinition(DOMAIN, PROVIDER_ID, "printer", OPERATION_ACTION, "printer.queue.plan", "consequential", ("mutating", "privileged")),
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=STATE_SCHEMA,
    normalize_arguments=_normalize,
    target_id=lambda arguments: arguments["resourceId"],
    propose_state=_propose,
    describe_change=lambda _current, _proposed, arguments: f"Plan printer action {arguments['action']}; no CUPS mutation is executed.",
)

def build_provider(*, runner: ProbeRunner = run_probe) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, ReadOnlyProbeBackend(DOMAIN, lambda: _probe_resources(runner)))

def build_fake_provider(resources: list[Mapping[str, Any]], *, state_path: Path | None = None, fail_on: frozenset[str] = frozenset()) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, FakeBackend(DOMAIN, resources, state_path=state_path, fail_on=fail_on))
