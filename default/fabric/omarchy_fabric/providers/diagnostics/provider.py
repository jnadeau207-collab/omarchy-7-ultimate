"""Structured diagnostic checks and redacted support-bundle preview."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path
from typing import Any, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .._engine import FakeBackend, LeafProvider
from .._probe import ProbeRunner, invoke_probe, probe_error, run_probe
from .._real import ReadOnlyProbeBackend
from ..process._leaf import LeafDefinition, provider_bundle

DOMAIN = "diagnostics"
PROVIDER_ID = "diagnostics.provider"
OPERATION_ACTION = "bundle.plan"
RESOURCE_ID = "diagnostics.system"
SOURCE_IDS = ("service-failures", "journal-usage", "filesystem-usage")
MAXIMUM_BUNDLE_BYTES = 1024 * 1024
MAXIMUM_SOURCE_BYTES = 256 * 1024
COMMANDS = {
    "service-failures": FixedArgvCommand("/usr/bin/systemctl", ("--failed", "--no-legend", "--plain", "--no-pager")),
    "journal-usage": FixedArgvCommand("/usr/bin/journalctl", ("--disk-usage", "--no-pager")),
    "filesystem-usage": FixedArgvCommand("/usr/bin/df", ("--output=source,pcent,target", "-x", "tmpfs", "-x", "devtmpfs")),
}

CHECK_SCHEMA = {
    "type": "object",
    "required": ["id", "title", "status", "code", "evidence"],
    "properties": {
        "id": {"type": "string", "enum": list(SOURCE_IDS)},
        "title": {"type": "string", "minLength": 1, "maxLength": 128},
        "status": {"type": "string", "enum": ["pass", "info", "warn", "fail", "unavailable"]},
        "code": {"type": "string", "pattern": "^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$", "maxLength": 160},
        "evidence": {"type": "string", "maxLength": 512},
    },
    "additionalProperties": False,
}
PREVIEW_SCHEMA = {
    "type": "object",
    "required": ["source", "included", "bytes", "redactions", "excerpt"],
    "properties": {
        "source": {"type": "string", "enum": list(SOURCE_IDS)},
        "included": {"type": "boolean"},
        "bytes": {"type": "integer", "minimum": 0, "maximum": 1048576},
        "redactions": {"type": "integer", "minimum": 0, "maximum": 100000},
        "excerpt": {"type": "string", "maxLength": 512},
    },
    "additionalProperties": False,
}
PLAN_SCHEMA = {
    "oneOf": [
        {"type": "null"},
        {
            "type": "object",
            "required": ["sources", "maximumBytes", "estimatedBytes", "redacted"],
            "properties": {
                "sources": {"type": "array", "minItems": 1, "maxItems": 3, "uniqueItems": True, "items": {"type": "string", "enum": list(SOURCE_IDS)}},
                "maximumBytes": {"type": "integer", "minimum": 1024, "maximum": 1048576},
                "estimatedBytes": {"type": "integer", "minimum": 0, "maximum": 1048576},
                "redacted": {"const": True},
            },
            "additionalProperties": False,
        },
    ]
}
STATE_SCHEMA = {
    "type": "object",
    "required": ["checks", "lastRun", "supportPreview", "pendingPlan"],
    "properties": {
        "checks": {"type": "array", "minItems": 3, "maxItems": 3, "items": CHECK_SCHEMA},
        "lastRun": {"oneOf": [{"type": "null"}, {"type": "string", "maxLength": 64}]},
        "supportPreview": {"type": "array", "maxItems": 3, "items": PREVIEW_SCHEMA},
        "pendingPlan": PLAN_SCHEMA,
    },
    "additionalProperties": False,
}
RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "state"],
    "properties": {
        "id": {"const": RESOURCE_ID},
        "label": {"const": "System diagnostics"},
        "kind": {"const": "diagnostics"},
        "state": STATE_SCHEMA,
    },
    "additionalProperties": False,
}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "sources", "maximumBytes"],
    "properties": {
        "resourceId": {"const": RESOURCE_ID},
        "sources": {"type": "array", "minItems": 1, "maxItems": 3, "uniqueItems": True, "items": {"type": "string", "enum": list(SOURCE_IDS)}},
        "maximumBytes": {"type": "integer", "minimum": 1024, "maximum": 1048576},
    },
    "additionalProperties": False,
}

_REDACTIONS = (
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"), "[REDACTED_PRIVATE_KEY]"),
    (re.compile(r"(?i)\b(bearer\s+)[A-Za-z0-9._~+/-]{8,}"), r"\1[REDACTED]"),
    (re.compile(r"(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}(?![A-Za-z0-9_-])"), "[REDACTED_TOKEN]"),
    (
        re.compile(
            r"(?i)(?<![A-Za-z0-9_-])[\"']?([a-z0-9_-]{0,64}(?:password|passwd|token|secret|api[_-]?key|access[_-]?key|private[_-]?key)[a-z0-9_-]{0,64})[\"']?\s*[:=]\s*(?:\"[^\"\r\n]*\"|'[^'\r\n]*'|[^\s,;]+)"
        ),
        r"\1=[REDACTED]",
    ),
    (re.compile(r"(?i)\b([a-z][a-z0-9+.-]{0,31}://)[^/@\s]{1,512}@"), r"\1[REDACTED]@"),
    (re.compile(r"(?<![A-Za-z0-9._-])(/home/)[A-Za-z0-9._-]+"), "$HOME"),
    (re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"), "[REDACTED_EMAIL]"),
    (re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"), "[REDACTED_IP]"),
    (re.compile(r"(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b"), "[REDACTED_MAC]"),
)


def redact_support_text(value: str) -> tuple[str, int]:
    if not isinstance(value, str):
        raise TypeError("support text must be a string")
    redacted = value.replace("\x00", "")
    count = 0
    for pattern, replacement in _REDACTIONS:
        redacted, substitutions = pattern.subn(replacement, redacted)
        count += substitutions
    return redacted, count


def preview_support_bundle(sources: Mapping[str, str], maximum_bytes: int) -> list[dict[str, Any]]:
    if set(sources) - set(SOURCE_IDS) or isinstance(maximum_bytes, bool) or not 1024 <= maximum_bytes <= MAXIMUM_BUNDLE_BYTES:
        raise ValueError("support preview request is outside its closed allowlist")
    if any(not isinstance(value, str) or len(value.encode("utf-8")) > MAXIMUM_SOURCE_BYTES for value in sources.values()):
        raise ValueError("support preview source exceeds its trusted byte bound")
    previews: list[dict[str, Any]] = []
    remaining = maximum_bytes
    for source in SOURCE_IDS:
        if source not in sources:
            continue
        redacted, count = redact_support_text(sources[source])
        encoded = redacted.encode("utf-8")
        included = remaining > 0
        selected = encoded[:remaining]
        while selected:
            try:
                excerpt = selected.decode("utf-8")
                break
            except UnicodeDecodeError:
                selected = selected[:-1]
        else:
            excerpt = ""
        remaining -= len(selected)
        previews.append(
            {
                "source": source,
                "included": included,
                "bytes": len(selected),
                "redactions": count,
                "excerpt": excerpt[:512],
            }
        )
    return previews


def _service_check(text: str) -> tuple[str, str]:
    units = []
    for line in text.splitlines():
        fields = line.strip().split(maxsplit=1)
        if fields:
            unit = fields[0]
            if re.fullmatch(r"(?:[A-Za-z0-9_.@:-]|\\x[0-9A-Fa-f]{2})+\.service", unit) is None or len(unit) > 128:
                raise ValueError("failed service output is invalid")
            units.append(unit)
    if units:
        return "fail", f"{len(units)} failed service unit(s) were reported."
    return "pass", "No failed service units were reported."


def _journal_check(text: str) -> tuple[str, str]:
    value = text.strip()
    if len(value) > 512 or re.fullmatch(r"Archived and active journals take up [0-9]+(?:\.[0-9]+)?[KMGTPE]? in the file system\.", value) is None:
        raise ValueError("journal usage output is invalid")
    return "info", value


def _filesystem_check(text: str) -> tuple[str, str]:
    rows = [line for line in text.splitlines() if line.strip()]
    if len(rows) < 2 or rows[0].split() != ["Filesystem", "Use%", "Mounted", "on"]:
        raise ValueError("filesystem output is empty")
    highest = 0
    offender_count = 0
    for line in rows[1:]:
        match = re.fullmatch(r"\s*(\S+)\s+(\d{1,3})%\s+(.+?)\s*", line)
        if match is None or int(match.group(2)) > 100 or not match.group(3).startswith("/") or any(not character.isprintable() for character in match.group(3)):
            raise ValueError("filesystem usage row is invalid")
        percent = int(match.group(2))
        highest = max(highest, percent)
        if percent >= 90:
            offender_count += 1
    status = "fail" if highest >= 98 else ("warn" if highest >= 90 else "pass")
    evidence = f"Highest filesystem use is {highest}%."
    if offender_count:
        evidence += f" {offender_count} filesystem target(s) are at or above 90%."
    return status, evidence


PARSERS = {
    "service-failures": ("Failed services", _service_check),
    "journal-usage": ("Journal disk use", _journal_check),
    "filesystem-usage": ("Filesystem capacity", _filesystem_check),
}


async def _probe_resources(runner: ProbeRunner) -> list[Mapping[str, Any]]:
    checks: list[dict[str, Any]] = []
    raw_sources: dict[str, str] = {}
    for source in SOURCE_IDS:
        title, parser = PARSERS[source]
        try:
            output = await invoke_probe(COMMANDS[source], runner)
            status, evidence = parser(output.stdout)
            evidence, _ = redact_support_text(evidence)
            code = f"diagnostics.{source}.ok" if status == "pass" else f"diagnostics.{source}.{status}"
            raw_sources[source] = f"{title}: {status}. {evidence}\n"
        except Exception as error:
            normalized = probe_error(DOMAIN, error if isinstance(error, (FileNotFoundError, TimeoutError, subprocess.CalledProcessError, ValueError)) else ValueError("untrusted diagnostic failure"))
            status, code, evidence = "unavailable", normalized.code, "The fixed diagnostic probe did not return trusted structured data."
        checks.append({"id": source, "title": title, "status": status, "code": code, "evidence": evidence[:512]})
    return [
        {
            "id": RESOURCE_ID,
            "label": "System diagnostics",
            "kind": "diagnostics",
            "state": {
                "checks": checks,
                "lastRun": None,
                "supportPreview": preview_support_bundle(raw_sources, MAXIMUM_BUNDLE_BYTES),
                "pendingPlan": None,
            },
        }
    ]


def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"resourceId": RESOURCE_ID, "sources": sorted(arguments["sources"]), "maximumBytes": arguments["maximumBytes"]}


def _propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    selected = [item for item in current["supportPreview"] if item["source"] in arguments["sources"]]
    if len(selected) != len(arguments["sources"]) or any(not item["included"] for item in selected):
        raise ValueError("support bundle source is unavailable in the trusted preview")
    estimated = min(sum(item["bytes"] for item in selected), arguments["maximumBytes"])
    pending_plan = {"sources": list(arguments["sources"]), "maximumBytes": arguments["maximumBytes"], "estimatedBytes": estimated, "redacted": True}
    if current["pendingPlan"] is not None:
        if current["pendingPlan"] == pending_plan:
            return dict(current)
        raise ValueError("a different diagnostics plan is already pending")
    return {**dict(current), "pendingPlan": pending_plan}


SPEC, MANIFEST, SCHEMAS = provider_bundle(
    LeafDefinition(DOMAIN, PROVIDER_ID, "diagnostics", OPERATION_ACTION, "diagnostics.bundle.plan", "low", ("mutating",), max_resources=1),
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=STATE_SCHEMA,
    normalize_arguments=_normalize,
    target_id=lambda _arguments: RESOURCE_ID,
    propose_state=_propose,
    describe_change=lambda _current, _proposed, arguments: f"Plan a redacted support preview from {len(arguments['sources'])} allowlisted source(s); no archive or upload is created.",
)


def build_provider(*, runner: ProbeRunner = run_probe) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, ReadOnlyProbeBackend(DOMAIN, lambda: _probe_resources(runner)))


def build_fake_provider(resources: list[Mapping[str, Any]], *, state_path: Path | None = None, fail_on: frozenset[str] = frozenset()) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, FakeBackend(DOMAIN, resources, state_path=state_path, fail_on=fail_on))
