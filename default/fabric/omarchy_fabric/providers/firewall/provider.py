"""Firewall zone inventory and strict rule planning."""

from __future__ import annotations

import hashlib
import ipaddress
import re
from pathlib import Path
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .._engine import FakeBackend, LeafProvider
from .._probe import ProbeRunner, invoke_probe, run_probe
from .._real import ReadOnlyProbeBackend
from ..process._leaf import LeafDefinition, provider_bundle

DOMAIN = "firewall"
PROVIDER_ID = "firewall.provider"
OPERATION_ACTION = "rule.plan"
RESOURCE_ID = "firewall.system"
FIREWALL_COMMAND = FixedArgvCommand("/usr/bin/firewall-cmd", ("--get-active-zones",))

RULE_SCHEMA = {
    "oneOf": [
        {"type": "null"},
        {
            "type": "object",
            "required": ["id", "operation", "protocol", "port", "direction", "source"],
            "properties": {
                "id": {"type": "string", "pattern": "^rule\\.[0-9a-f]{24}$"},
                "operation": {"type": "string", "enum": ["allow", "deny", "remove"]},
                "protocol": {"type": "string", "enum": ["tcp", "udp"]},
                "port": {"type": "integer", "minimum": 1, "maximum": 65535},
                "direction": {"type": "string", "enum": ["inbound", "outbound"]},
                "source": {"oneOf": [{"type": "null"}, {"type": "string", "maxLength": 64}]},
            },
            "additionalProperties": False,
        },
    ]
}
ZONE_SCHEMA = {
    "type": "object",
    "required": ["name", "interfaces"],
    "properties": {
        "name": {"type": "string", "pattern": "^[A-Za-z0-9_-]{1,64}$"},
        "interfaces": {
            "type": "array",
            "maxItems": 32,
            "uniqueItems": True,
            "items": {"type": "string", "pattern": "^[A-Za-z0-9_.:@-]{1,64}$"},
        },
    },
    "additionalProperties": False,
}
STATE_SCHEMA = {
    "type": "object",
    "required": ["enabled", "defaultPolicy", "zones", "pendingRule"],
    "properties": {
        "enabled": {"type": "boolean"},
        "defaultPolicy": {"type": "string", "enum": ["allow", "deny", "unknown"]},
        "zones": {"type": "array", "maxItems": 32, "items": ZONE_SCHEMA},
        "pendingRule": RULE_SCHEMA,
    },
    "additionalProperties": False,
}
RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "state"],
    "properties": {
        "id": {"const": RESOURCE_ID},
        "label": {"const": "System firewall"},
        "kind": {"const": "firewall"},
        "state": STATE_SCHEMA,
    },
    "additionalProperties": False,
}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "operation", "protocol", "port", "direction", "source"],
    "properties": {
        "resourceId": {"const": RESOURCE_ID},
        "operation": {"type": "string", "enum": ["allow", "deny", "remove"]},
        "protocol": {"type": "string", "enum": ["tcp", "udp"]},
        "port": {"type": "integer", "minimum": 1, "maximum": 65535},
        "direction": {"type": "string", "enum": ["inbound", "outbound"]},
        "source": {"oneOf": [{"type": "null"}, {"type": "string", "pattern": "^[0-9A-Fa-f:.]+(?:/[0-9]{1,3})?$", "maxLength": 64}]},
    },
    "additionalProperties": False,
}

def parse_firewall(text: str) -> list[dict[str, Any]]:
    zones: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    seen: set[str] = set()
    for line in text.splitlines():
        if not line.strip():
            continue
        if not line[0].isspace():
            name = line.strip()
            if not name or len(name) > 64 or name in seen or any(character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" for character in name):
                raise ValueError("firewall zone is invalid")
            current = {"name": name, "interfaces": []}
            zones.append(current)
            if len(zones) > 32:
                raise ValueError("firewall zone inventory exceeds its bound")
            seen.add(name)
            continue
        if current is None or not line.strip().startswith("interfaces:"):
            raise ValueError("firewall zone detail is invalid")
        interfaces = line.strip().removeprefix("interfaces:").strip().split()
        if len(interfaces) > 32 or any(re.fullmatch(r"[A-Za-z0-9_.:@-]{1,64}", interface) is None for interface in interfaces):
            raise ValueError("firewall interface list is invalid")
        current["interfaces"] = sorted(set(interfaces))
    return [
        {
            "id": RESOURCE_ID,
            "label": "System firewall",
            "kind": "firewall",
            "state": {"enabled": True, "defaultPolicy": "unknown", "zones": zones, "pendingRule": None},
        }
    ]

async def _probe_resources(runner: ProbeRunner) -> list[Mapping[str, Any]]:
    return parse_firewall((await invoke_probe(FIREWALL_COMMAND, runner)).stdout)

def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    source = arguments["source"]
    if source is not None:
        try:
            source = str(ipaddress.ip_network(source, strict=False))
        except ValueError as error:
            raise ValueError("firewall source is not a valid network") from error
    return {**dict(arguments), "source": source}

def _propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    identity = ":".join(str(arguments[key]) for key in ("operation", "protocol", "port", "direction", "source"))
    rule = {
        "id": f"rule.{hashlib.sha256(identity.encode('utf-8')).hexdigest()[:24]}",
        "operation": arguments["operation"],
        "protocol": arguments["protocol"],
        "port": arguments["port"],
        "direction": arguments["direction"],
        "source": arguments["source"],
    }
    return {**dict(current), "pendingRule": rule}

SPEC, MANIFEST, SCHEMAS = provider_bundle(
    LeafDefinition(DOMAIN, PROVIDER_ID, "firewall", OPERATION_ACTION, "firewall.rule.plan", "consequential", ("mutating", "privileged", "network"), max_resources=1),
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=STATE_SCHEMA,
    normalize_arguments=_normalize,
    target_id=lambda _arguments: RESOURCE_ID,
    propose_state=_propose,
    describe_change=lambda _current, _proposed, arguments: f"Plan an allowlisted {arguments['operation']} rule for {arguments['protocol']}/{arguments['port']}; no firewall command is executed.",
)

def build_provider(*, runner: ProbeRunner = run_probe) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, ReadOnlyProbeBackend(DOMAIN, lambda: _probe_resources(runner)))

def build_fake_provider(resources: list[Mapping[str, Any]], *, state_path: Path | None = None, fail_on: frozenset[str] = frozenset()) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, FakeBackend(DOMAIN, resources, state_path=state_path, fail_on=fail_on))
