"""Fixtures for update, recovery, backup, and diagnostics providers."""

from __future__ import annotations

import copy
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Mapping

ROOT = Path(__file__).resolve().parents[3]
FABRIC = ROOT / "default" / "fabric"
if str(FABRIC) not in sys.path:
    sys.path.insert(0, str(FABRIC))

from omarchy_fabric.providers.backup import provider as backup
from omarchy_fabric.providers.diagnostics import provider as diagnostics
from omarchy_fabric.providers.recovery import provider as recovery
from omarchy_fabric.providers.update import provider as update
from omarchy_fabric.security.principal import EndpointPrincipal, PrincipalKind

@dataclass(frozen=True)
class Case:
    module: Any
    resource: Mapping[str, Any]
    arguments: Mapping[str, Any]

def principal() -> EndpointPrincipal:
    now = datetime(2026, 8, 27, tzinfo=timezone.utc)
    return EndpointPrincipal(
        principal_id="principal.recovery-test",
        session_id="session.recovery-test",
        uid=1000,
        endpoint_id="shell.recovery-test",
        kind=PrincipalKind.SHELL,
        issued_at=now,
        expires_at=now + timedelta(hours=1),
    )

def update_resource() -> dict[str, Any]:
    return update.parse_updates("linux 6.1 -> 6.2\nquickshell 1.0 -> 1.1\n")[0]

def recovery_resource() -> dict[str, Any]:
    resource = recovery.parse_restore_points(json.dumps({"data": [{"number": 7, "date": "2026-08-27T00:00:00Z", "description": "Before update"}]}))[0]
    resource["state"].update(eligible=True, readOnly=True, health="healthy")
    return resource

def backup_resource() -> dict[str, Any]:
    return backup.parse_snapshots(json.dumps([{"id": "abcdef1234567890", "time": "2026-08-27T00:00:00Z", "paths": ["/home/jesse"]}]), home_root="/home/jesse")[0]

def diagnostics_resource() -> dict[str, Any]:
    source_text = {
        "service-failures": "No failed units for /home/jesse token=secret-value\n",
        "journal-usage": "Archived and active journals take up 12.0M in the file system.\n",
        "filesystem-usage": "/dev/sda1 40% /home/jesse\n",
    }
    return {
        "id": diagnostics.RESOURCE_ID,
        "label": "System diagnostics",
        "kind": "diagnostics",
        "state": {
            "checks": [
                {"id": "service-failures", "title": "Failed services", "status": "pass", "code": "diagnostics.service-failures.ok", "evidence": "No failed service units were reported."},
                {"id": "journal-usage", "title": "Journal disk use", "status": "info", "code": "diagnostics.journal-usage.info", "evidence": "Archived and active journals take up 12.0M in the file system."},
                {"id": "filesystem-usage", "title": "Filesystem capacity", "status": "pass", "code": "diagnostics.filesystem-usage.ok", "evidence": "Highest filesystem use is 40%."},
            ],
            "lastRun": None,
            "supportPreview": diagnostics.preview_support_bundle(source_text, 32768),
            "pendingPlan": None,
        },
    }

def resource_cases() -> list[Case]:
    update_item = update_resource()
    recovery_item = recovery_resource()
    backup_item = backup_resource()
    diagnostics_item = diagnostics_resource()
    return [
        Case(update, update_item, {"resourceId": update.RESOURCE_ID, "mode": "apply", "createCheckpoint": True}),
        Case(recovery, recovery_item, {"resourceId": recovery_item["id"], "scope": "system", "preserveHome": True, "confirmation": f"RESTORE:{recovery_item['id']}"}),
        Case(backup, backup_item, {"resourceId": backup.RESOURCE_ID, "action": "restore", "scope": "home", "snapshotId": "abcdef1234567890", "relativePath": "Documents/report.txt", "retention": dict(backup.DEFAULT_RETENTION)}),
        Case(diagnostics, diagnostics_item, {"resourceId": diagnostics.RESOURCE_ID, "sources": ["service-failures", "filesystem-usage"], "maximumBytes": 8192}),
    ]

def copied_case(case: Case) -> Case:
    return Case(case.module, copy.deepcopy(case.resource), copy.deepcopy(case.arguments))
