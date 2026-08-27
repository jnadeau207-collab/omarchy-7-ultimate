"""Health and diagnostic reporting for the provisional user daemon."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import stat
import sys
import time
from pathlib import Path
from typing import Any, Sequence

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
) -> dict[str, Any]:
    integrity = database.quick_check()
    journal_mode = database.journal_mode()
    socket = socket_health(socket_path)
    healthy = integrity == "ok" and journal_mode == "wal" and socket.get("ownerOnly") is True
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


async def _query(socket_path: Path, method: str) -> dict[str, Any]:
    from .protocol import FabricClient

    client = FabricClient(socket_path, client_name="omarchy-fabricctl")
    try:
        await client.connect()
        result = await client.request(method)
        if not isinstance(result, dict):
            raise FabricError(
                "rpc.invalid-response",
                "Fabric diagnostic response is invalid",
                "The daemon returned a non-object diagnostic response.",
            )
        return result
    finally:
        await client.close()


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Inspect the provisional Omarchy Fabric daemon")
    parser.add_argument("--socket", type=Path, help="override the Fabric Unix socket path")
    parser.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    parser.add_argument("command", choices=("health", "doctor", "version"))
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


def main(argv: Sequence[str] | None = None) -> int:
    from .models import default_socket_path

    args = _parser().parse_args(argv)
    try:
        socket_path = args.socket or default_socket_path()
        method = "version" if args.command == "version" else "health"
        result = asyncio.run(_query(socket_path, method))
        if args.command == "doctor":
            result = doctor_report(result)
        if args.json:
            print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        else:
            _print_text(args.command, result)
        return 0 if result.get("status", "healthy") == "healthy" else 1
    except FabricError as error:
        payload = {"status": "unavailable", "error": error.to_dict()}
        if args.json:
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        else:
            print(f"Fabric: unavailable ({error.code})", file=sys.stderr)
            print(error.explanation, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
