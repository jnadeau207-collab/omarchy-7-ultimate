from __future__ import annotations

import argparse
import asyncio
import json
import os
import stat
import sys
import time
from pathlib import Path
from typing import Any, Mapping, Sequence

from .db import FabricDatabase
from .models import (
    CURRENT_DATABASE_SCHEMA,
    MAX_READABLE_DATABASE_SCHEMA,
    MAX_PROTOCOL_VERSION,
    MIN_READABLE_DATABASE_SCHEMA,
    MIN_PROTOCOL_VERSION,
    PROTOCOL_NAME,
    PROTOCOL_VERSION,
    FabricError,
)

def socket_health(path: Path) -> dict[str, Any]:
    try:
        metadata = path.stat()
    except OSError as error:
        return {
            "path": str(path),
            "present": False,
            "ownerOnly": False,
            "detail": str(error),
        }
    mode = stat.S_IMODE(metadata.st_mode)
    return {
        "path": str(path),
        "present": stat.S_ISSOCK(metadata.st_mode),
        "mode": f"{mode:04o}",
        "uid": metadata.st_uid,
        "ownerOnly": stat.S_ISSOCK(metadata.st_mode)
        and metadata.st_uid == os.getuid()
        and mode == 0o600,
    }

def daemon_health(
    *,
    database: FabricDatabase,
    socket_path: Path,
    started_monotonic: float,
    run_id: str,
    provider_count: int,
    subscription_count: int,
    fake_provider_count: int = 0,
    typed_provider_count: int = 0,
    available_typed_provider_count: int = 0,
    degraded_typed_provider_count: int = 0,
    usable_typed_provider_count: int | None = None,
) -> dict[str, Any]:
    integrity = database.quick_check()
    journal_mode = database.journal_mode()
    socket = socket_health(socket_path)
    healthy = integrity == "ok" and journal_mode == "wal" and socket.get("ownerOnly") is True
    if usable_typed_provider_count is None:
        usable_typed_provider_count = available_typed_provider_count + degraded_typed_provider_count
    return {
        "status": "healthy" if healthy else "unhealthy",
        "protocol": {
            "name": PROTOCOL_NAME,
            "version": PROTOCOL_VERSION,
            "minimum": MIN_PROTOCOL_VERSION,
            "maximum": MAX_PROTOCOL_VERSION,
        },
        "database": {
            "path": str(database.path),
            "schema": CURRENT_DATABASE_SCHEMA,
            "minimumReadable": MIN_READABLE_DATABASE_SCHEMA,
            "maximumReadable": MAX_READABLE_DATABASE_SCHEMA,
            "journalMode": journal_mode,
            "integrity": integrity,
        },
        "socket": socket,
        "daemon": {
            "pid": os.getpid(),
            "runId": run_id,
            "uptimeSeconds": max(0.0, time.monotonic() - started_monotonic),
        },
        "providers": {
            "registered": provider_count,
            "fake": fake_provider_count,
            "typed": typed_provider_count,
            "availableTyped": available_typed_provider_count,
            "degradedTyped": degraded_typed_provider_count,
            "usableTyped": usable_typed_provider_count,
        },
        "events": {"subscriptions": subscription_count},
    }

def doctor_report(health: dict[str, Any]) -> dict[str, Any]:
    checks = [
        {
            "id": "daemon.health",
            "status": "pass" if health.get("status") == "healthy" else "fail",
            "explanation": "The daemon reports a healthy control plane.",
        },
        {
            "id": "database.integrity",
            "status": "pass"
            if health.get("database", {}).get("integrity") == "ok"
            else "fail",
            "explanation": "SQLite quick_check reports an intact Fabric database.",
        },
        {
            "id": "database.wal",
            "status": "pass"
            if health.get("database", {}).get("journalMode") == "wal"
            else "fail",
            "explanation": "The Fabric database is operating in WAL mode.",
        },
        {
            "id": "socket.owner-only",
            "status": "pass"
            if health.get("socket", {}).get("ownerOnly") is True
            else "fail",
            "explanation": "The Fabric socket is owned by this UID with mode 0600.",
        },
    ]
    return {
        "status": "healthy" if all(check["status"] == "pass" for check in checks) else "unhealthy",
        "checks": checks,
        "health": health,
    }

TASK_METHODS = {
    "create": "managed-work.task.create",
    "list": "managed-work.task.list",
    "cancel": "managed-work.task.cancel",
    "recover": "managed-work.task.recover",
}

async def _query(
    socket_path: Path,
    method: str,
    params: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    from .protocol import FabricClient

    client = FabricClient(socket_path, client_name="omarchy-fabricctl")
    try:
        await client.connect()
        result = await client.request(method, params)
        if not isinstance(result, dict):
            raise FabricError(
                "rpc.invalid-response",
                "Fabric diagnostic response is invalid",
                "The daemon returned a non-object diagnostic response.",
            )
        return result
    finally:
        await client.close()

def _payload(raw: str) -> dict[str, Any]:
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as error:
        raise FabricError(
            "rpc.invalid-params",
            "Fabric CLI payload is not JSON",
            "Typed fabricctl verbs require a JSON object payload.",
            detail=str(error),
        ) from error
    if not isinstance(data, dict):
        raise FabricError(
            "rpc.invalid-params",
            "Fabric CLI payload is not an object",
            "Typed fabricctl verbs require a JSON object payload.",
        )
    if "version" not in data:
        data = {**data, "version": "v0"}
    return data

def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Inspect the provisional Omarchy Fabric daemon")
    parser.add_argument("--socket", type=Path, help="override the Fabric Unix socket path")
    parser.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("health", "doctor", "version"):
        sub.add_parser(name)
    task = sub.add_parser("task")
    task_sub = task.add_subparsers(dest="task_command", required=True)
    for name in ("create", "list", "cancel", "recover"):
        command = task_sub.add_parser(name)
        command.add_argument("payload", nargs="?", default="{}")
    context = sub.add_parser("context")
    context_sub = context.add_subparsers(dest="context_command", required=True)
    capture = context_sub.add_parser("capture")
    capture.add_argument("payload")
    run = sub.add_parser("run")
    run_sub = run.add_subparsers(dest="run_command", required=True)
    execute = run_sub.add_parser("execute")
    execute.add_argument("payload")
    return parser

def _print_text(command: str, result: dict[str, Any]) -> None:
    if command == "health":
        print(f"Fabric: {result['status']}")
        print(f"Protocol: {result['protocol']['name']} version {result['protocol']['version']}")
        print(
            f"Database: schema {result['database']['schema']}, "
            f"{result['database']['journalMode']}, integrity {result['database']['integrity']}"
        )
        print(
            f"Socket: {result['socket']['path']} mode {result['socket'].get('mode', 'unknown')}"
        )
        return
    if command == "version":
        print(f"{result['protocol']} version {result['version']}")
        print(f"Database schema: {result['databaseSchema']}")
        return
    print(f"Fabric doctor: {result['status']}")
    for check in result["checks"]:
        print(f"[{check['status']}] {check['id']}: {check['explanation']}")

def _rpc_target(args: argparse.Namespace) -> tuple[str, dict[str, Any] | None, bool]:
    if args.command == "version":
        return "version", None, False
    if args.command in {"health", "doctor"}:
        return "health", None, False
    if args.command == "task":
        return TASK_METHODS[args.task_command], _payload(args.payload), True
    if args.command == "context":
        return "managed-work.context.capture", _payload(args.payload), True
    return "managed-work.run.execute", _payload(args.payload), True

def main(argv: Sequence[str] | None = None) -> int:
    from .models import default_socket_path

    args = _parser().parse_args(argv)
    try:
        socket_path = args.socket or default_socket_path()
        method, params, typed = _rpc_target(args)
        result = asyncio.run(_query(socket_path, method, params))
        if args.command == "doctor":
            result = doctor_report(result)
        if typed or args.json:
            print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        else:
            _print_text(args.command, result)
        if typed:
            return 0
        return 0 if result.get("status", "healthy") == "healthy" else 1
    except FabricError as error:
        payload = {"status": "unavailable", "error": error.to_dict()}
        typed = args.command in {"task", "context", "run"}
        if typed or args.json:
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        else:
            print(f"Fabric: unavailable ({error.code})", file=sys.stderr)
            print(error.explanation, file=sys.stderr)
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
