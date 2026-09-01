"""Process inventory with group identity and PID-reuse-safe planning."""

from __future__ import annotations

import asyncio
import hashlib
import re
from pathlib import Path
from typing import Any, Callable, Mapping

from omarchy_fabric.models import FixedArgvCommand

from .._engine import FakeBackend, LeafProvider
from .._probe import ProbeRunner, invoke_probe, run_probe
from .._real import ReadOnlyProbeBackend
from ._leaf import LeafDefinition, provider_bundle

DOMAIN = "process"
PROVIDER_ID = "process.provider"
OPERATION_ACTION = "termination.plan"
PROCESS_COMMAND = FixedArgvCommand(
    "/usr/bin/ps",
    ("-ww", "-eo", "pid=,uid=,pcpu=,pmem=,rss=,comm=,cgroup="),
)
BOOT_ID_PATH = Path("/proc/sys/kernel/random/boot_id")
PROC_ROOT = Path("/proc")
ProcReader = Callable[[Path, int], str]

TOKEN_PATTERN = "^[0-9a-f]{16}$"
STATE_SCHEMA = {
    "type": "object",
    "required": ["lifecycle", "startToken", "identityRevision", "plannedSignal"],
    "properties": {
        "lifecycle": {"type": "string", "enum": ["running", "termination-planned", "stopped"]},
        "startToken": {"type": "string", "pattern": TOKEN_PATTERN},
        "identityRevision": {"type": "string", "pattern": "^sha256\\.[0-9a-f]{64}$"},
        "plannedSignal": {"oneOf": [{"type": "null"}, {"type": "string", "enum": ["term", "kill"]}]},
    },
    "additionalProperties": False,
}
RESOURCE_SCHEMA = {
    "type": "object",
    "required": ["id", "label", "kind", "pid", "uid", "command", "cpuPercent", "memoryPercent", "residentKb", "groupId", "observedCount", "inventoryTruncated", "state"],
    "properties": {
        "id": {"type": "string", "pattern": "^process\\.[0-9]+\\.[0-9a-f]{16}$"},
        "label": {"type": "string", "minLength": 1, "maxLength": 128},
        "kind": {"const": "process"},
        "pid": {"type": "integer", "minimum": 1, "maximum": 4194304},
        "uid": {"type": "integer", "minimum": 0, "maximum": 4294967295},
        "command": {"type": "string", "minLength": 1, "maxLength": 128},
        "cpuPercent": {"type": "number", "minimum": 0, "maximum": 100},
        "memoryPercent": {"type": "number", "minimum": 0, "maximum": 100},
        "residentKb": {"type": "integer", "minimum": 0, "maximum": 4294967295},
        "groupId": {"type": "string", "pattern": "^process-group\\.[0-9a-f]{16}$"},
        "observedCount": {"type": "integer", "minimum": 1, "maximum": 4194304},
        "inventoryTruncated": {"type": "boolean"},
        "state": STATE_SCHEMA,
    },
    "additionalProperties": False,
}
ARGUMENTS_SCHEMA = {
    "type": "object",
    "required": ["resourceId", "expectedStartToken", "signal"],
    "properties": {
        "resourceId": {"type": "string", "pattern": "^process\\.[0-9]+\\.[0-9a-f]{16}$"},
        "expectedStartToken": {"type": "string", "pattern": TOKEN_PATTERN},
        "signal": {"type": "string", "enum": ["term", "kill"]},
    },
    "additionalProperties": False,
}

def _token(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:16]

def _safe_text(value: str, *, maximum: int) -> str:
    cleaned = "".join(character for character in value if character.isprintable() and character not in "\r\n\x00").strip()
    if not cleaned:
        raise ValueError("process text is empty")
    return cleaned[:maximum]

def _ratio(value: str, label: str) -> float:
    try:
        ratio = float(value)
    except ValueError:
        raise ValueError(f"process {label} is invalid") from None
    if ratio != ratio or ratio in (float("inf"), float("-inf")) or not 0.0 <= ratio <= 100.0:
        raise ValueError(f"process {label} is out of range")
    return round(ratio, 1)

def _process_rows(text: str) -> list[tuple[int, int, float, float, int, str, str]]:
    rows: list[tuple[int, int, float, float, int, str, str]] = []
    seen: set[int] = set()
    for raw_line in text.splitlines():
        fields = raw_line.strip().split(maxsplit=6)
        if len(fields) != 7:
            raise ValueError("process row is invalid")
        pid_text, uid_text, cpu_text, memory_text, resident_text, command, cgroup = fields
        if not pid_text.isdecimal() or not uid_text.isdecimal() or not resident_text.isdecimal():
            raise ValueError("process identity is invalid")
        pid, uid, resident = int(pid_text), int(uid_text), int(resident_text)
        if not 1 <= pid <= 4194304 or not 0 <= uid <= 4294967295 or pid in seen:
            raise ValueError("process identity is out of range or duplicated")
        if not 0 <= resident <= 4294967295:
            raise ValueError("process resident memory is out of range")
        seen.add(pid)
        rows.append((pid, uid, _ratio(cpu_text, "cpu share"), _ratio(memory_text, "memory share"), resident,
                     _safe_text(command, maximum=128), _safe_text(cgroup, maximum=512)))
    return rows

def _selected_rows(rows: list[tuple[int, int, float, float, int, str, str]]) -> list[tuple[int, int, float, float, int, str, str]]:
    users = sorted((row for row in rows if row[1] >= 1000), key=lambda row: (row[1], row[0]))
    system = sorted((row for row in rows if row[1] < 1000), key=lambda row: row[0])
    selected = users[:48] + system[:16]
    selected_ids = {row[0] for row in selected}
    remaining = sorted((row for row in rows if row[0] not in selected_ids), key=lambda row: (row[1] < 1000, row[1], row[0]))
    return (selected + remaining)[:64]

def parse_processes(text: str, *, boot_id: str, start_ticks_by_pid: Mapping[int, int]) -> list[dict[str, Any]]:
    if re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", boot_id) is None:
        raise ValueError("kernel boot identity is invalid")
    resources: list[dict[str, Any]] = []
    observed_rows = _process_rows(text)
    rows = _selected_rows(observed_rows)
    if not {pid for pid, _uid, _cpu, _memory, _resident, _command, _cgroup in rows} <= set(start_ticks_by_pid):
        raise ValueError("kernel process identities do not match the process inventory")
    for pid, uid, cpu_percent, memory_percent, resident, command, cgroup in rows:
        start_ticks = start_ticks_by_pid[pid]
        if isinstance(start_ticks, bool) or not isinstance(start_ticks, int) or start_ticks < 0:
            raise ValueError("kernel process start ticks are invalid")
        start_token = _token(f"{boot_id}:{pid}:{start_ticks}")
        group_id = f"process-group.{_token(cgroup)}"
        resources.append(
            {
                "id": f"process.{pid}.{start_token}",
                "label": command,
                "kind": "process",
                "pid": pid,
                "uid": uid,
                "command": command,
                "cpuPercent": cpu_percent,
                "memoryPercent": memory_percent,
                "residentKb": resident,
                "groupId": group_id,
                "observedCount": len(observed_rows),
                "inventoryTruncated": len(observed_rows) > len(rows),
                "state": {
                    "lifecycle": "running",
                    "startToken": start_token,
                    "identityRevision": "sha256." + hashlib.sha256(f"{uid}\x00{command}\x00{cgroup}".encode("utf-8")).hexdigest(),
                    "plannedSignal": None,
                },
            }
        )
    return resources

def group_processes(resources: list[Mapping[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[str]] = {}
    for resource in resources:
        grouped.setdefault(str(resource["groupId"]), []).append(str(resource["id"]))
    return [
        {"id": group_id, "members": sorted(members), "count": len(members)}
        for group_id, members in sorted(grouped.items())
    ]

def assert_pid_identity(resource: Mapping[str, Any], expected_start_token: str) -> None:
    if resource.get("state", {}).get("startToken") != expected_start_token:
        raise ValueError("process PID has been reused")

def _read_proc_text(path: Path, maximum_bytes: int) -> str:
    raw = path.read_bytes()
    if len(raw) > maximum_bytes:
        raise ValueError("proc identity record exceeds its bound")
    return raw.decode("utf-8", errors="strict").strip()

def _start_ticks(stat: str) -> int:
    close = stat.rfind(") ")
    if close < 2:
        raise ValueError("proc stat record is invalid")
    fields = stat[close + 2 :].split()
    if len(fields) < 20 or not fields[19].isdecimal():
        raise ValueError("proc start ticks are invalid")
    return int(fields[19])

def _stat_identity(value: str) -> tuple[str, int]:
    opening = value.find("(")
    closing = value.rfind(") ")
    if opening < 1 or closing <= opening + 1:
        raise ValueError("proc stat identity is invalid")
    command = _safe_text(value[opening + 1 : closing], maximum=128)
    return command, _start_ticks(value)

def _status_identity(value: str) -> tuple[str, int]:
    fields: dict[str, str] = {}
    for line in value.splitlines():
        if ":" not in line:
            continue
        key, raw = line.split(":", 1)
        if key in {"Name", "Uid"}:
            if key in fields:
                raise ValueError("proc status identity is duplicated")
            fields[key] = raw.strip()
    uid_fields = fields.get("Uid", "").split()
    if set(fields) != {"Name", "Uid"} or len(uid_fields) != 4 or any(not item.isdecimal() for item in uid_fields):
        raise ValueError("proc status identity is invalid")
    if len(set(uid_fields)) != 1:
        raise ValueError("proc status reports changing credentials")
    return _safe_text(fields["Name"], maximum=128), int(uid_fields[0])

async def _probe_resources(runner: ProbeRunner, proc_reader: ProcReader) -> list[Mapping[str, Any]]:
    output = (await invoke_probe(PROCESS_COMMAND, runner)).stdout
    observed_rows = _process_rows(output)
    rows = _selected_rows(observed_rows)
    boot_id = await asyncio.to_thread(proc_reader, BOOT_ID_PATH, 128)
    start_ticks_by_pid: dict[int, int] = {}
    stable_rows: list[tuple[int, int, str, str]] = []
    for pid, uid, cpu_percent, memory_percent, resident, command, cgroup in rows:
        process_root = PROC_ROOT / str(pid)
        try:
            stat_before = await asyncio.to_thread(proc_reader, process_root / "stat", 8192)
            status = await asyncio.to_thread(proc_reader, process_root / "status", 16384)
            stat_after = await asyncio.to_thread(proc_reader, process_root / "stat", 8192)
        except FileNotFoundError:
            continue
        command_before, start_before = _stat_identity(stat_before)
        command_after, start_after = _stat_identity(stat_after)
        status_command, status_uid = _status_identity(status)
        if command_before != command_after or start_before != start_after or command != command_before or status_command != command_before or uid != status_uid:
            continue
        start_ticks_by_pid[pid] = start_before
        stable_rows.append((pid, uid, command, cgroup))
    boot_id_after = await asyncio.to_thread(proc_reader, BOOT_ID_PATH, 128)
    if boot_id_after != boot_id:
        raise ValueError("kernel boot identity changed during process inventory")
    if observed_rows and not stable_rows:
        raise ValueError("no process identity remained stable across the kernel probe")
    stable_text = "\n".join(
        f"{pid} {uid} {cpu_percent} {memory_percent} {resident} {command} {cgroup}"
        for pid, uid, cpu_percent, memory_percent, resident, command, cgroup in stable_rows
    )
    if stable_text:
        stable_text += "\n"
    resources = parse_processes(stable_text, boot_id=boot_id, start_ticks_by_pid=start_ticks_by_pid)
    for resource in resources:
        resource["observedCount"] = len(observed_rows)
        resource["inventoryTruncated"] = len(observed_rows) > len(resources)
    return resources

def _normalize(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "resourceId": arguments["resourceId"],
        "expectedStartToken": arguments["expectedStartToken"],
        "signal": arguments["signal"],
    }

def _propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    if current["startToken"] != arguments["expectedStartToken"]:
        raise ValueError("process PID has been reused")
    if current["lifecycle"] == "stopped":
        raise ValueError("process is no longer running")
    return {
        "lifecycle": "termination-planned",
        "startToken": current["startToken"],
        "identityRevision": current["identityRevision"],
        "plannedSignal": arguments["signal"],
    }

def _describe(current: Mapping[str, Any], proposed: Mapping[str, Any], arguments: Mapping[str, Any]) -> str:
    if current == proposed:
        return "The exact process identity already has this termination plan."
    return f"Plan {arguments['signal']} for the exact PID and start identity; no signal is sent by this provider."

SPEC, MANIFEST, SCHEMAS = provider_bundle(
    LeafDefinition(DOMAIN, PROVIDER_ID, "process", OPERATION_ACTION, "process.termination.plan", "consequential", ("mutating",)),
    resource_schema=RESOURCE_SCHEMA,
    arguments_schema=ARGUMENTS_SCHEMA,
    state_schema=STATE_SCHEMA,
    normalize_arguments=_normalize,
    target_id=lambda arguments: arguments["resourceId"],
    propose_state=_propose,
    describe_change=_describe,
)

def build_provider(*, runner: ProbeRunner = run_probe, proc_reader: ProcReader = _read_proc_text) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, ReadOnlyProbeBackend(DOMAIN, lambda: _probe_resources(runner, proc_reader)))

def build_fake_provider(
    resources: list[Mapping[str, Any]],
    *,
    state_path: Path | None = None,
    fail_on: frozenset[str] = frozenset(),
) -> LeafProvider:
    return LeafProvider(SPEC, MANIFEST, SCHEMAS, FakeBackend(DOMAIN, resources, state_path=state_path, fail_on=fail_on))
