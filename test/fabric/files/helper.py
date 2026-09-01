from __future__ import annotations

import sys
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FABRIC_ROOT = ROOT / "default" / "fabric"
if str(FABRIC_ROOT) not in sys.path:
    sys.path.insert(0, str(FABRIC_ROOT))

from omarchy_fabric.providers._engine import state_revision
from omarchy_fabric.security.principal import EndpointPrincipal, PrincipalKind

def principal() -> EndpointPrincipal:
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    return EndpointPrincipal(
        "principal.files-tests",
        "session.files-tests",
        1000,
        "shell.files-tests",
        PrincipalKind.SHELL,
        now,
        now + timedelta(hours=1),
    )

def reason(code: str, title: str) -> dict[str, object]:
    return {
        "code": code,
        "title": title,
        "explanation": "The fixture models an unavailable resource.",
        "detail": "fixture",
        "retryable": True,
        "changeState": "none",
        "recoveryActions": ["provider.retry"],
    }

def location(
    identifier: str,
    kind: str,
    label: str,
    *,
    state: str = "available",
    writable: bool = True,
) -> dict[str, object]:
    unavailable = reason("files.location-unavailable", f"{label} unavailable") if state != "available" else None
    return {
        "id": identifier,
        "kind": kind,
        "label": label,
        "state": state,
        "writable": writable if state == "available" else False,
        "rootToken": state_revision({"location": identifier}),
        "reason": unavailable,
    }

def entry(
    identifier: str,
    location_id: str,
    name: str,
    relative_path: str,
    kind: str,
    *,
    parent_id: str | None = None,
    writable: bool = True,
) -> dict[str, object]:
    return {
        "id": identifier,
        "locationId": location_id,
        "parentId": parent_id,
        "name": name,
        "relativePath": relative_path,
        "kind": kind,
        "sizeBytes": 128 if kind == "file" else None,
        "modifiedNs": 1000,
        "mimeType": "text/plain" if kind == "file" else None,
        "hidden": name.startswith("."),
        "writable": writable if kind != "symlink" else False,
        "identity": state_revision({"entry": identifier, "generation": 1}),
        "symlinkTargetState": "outside-root" if kind == "symlink" else None,
        "trash": None,
    }

def workspace() -> dict[str, object]:
    desktop = "files.location.desktop"
    trash = "files.location.trash"
    removable = "files.location.removable"
    network = "files.location.network"
    project = "files.entry.project"
    document = "files.entry.notes"
    return {
        "schemaVersion": "v0",
        "workspaceId": "files.workspace.primary",
        "locations": [
            location("files.location.this-pc", "this-pc", "This PC", writable=False),
            location(desktop, "desktop", "Desktop"),
            location(trash, "trash", "Trash"),
            location(removable, "mount", "USB", state="unavailable"),
            location(network, "network", "Team Share"),
        ],
        "entries": [
            entry(document, desktop, "notes.txt", "notes.txt", "file"),
            entry(project, desktop, "Project", "Project", "directory"),
            entry("files.entry.readme", desktop, "README.txt", "Project/README.txt", "file", parent_id=project),
            entry("files.entry.unsafe-link", desktop, "outside", "outside", "symlink"),
        ],
        "mounts": [
            {
                "id": "files.mount.usb",
                "kind": "removable",
                "label": "USB",
                "state": "unmounted",
                "writable": True,
                "locationId": removable,
                "source": {"scheme": "device", "display": "USB", "host": None, "share": None},
                "reason": None,
            },
            {
                "id": "files.mount.team",
                "kind": "smb",
                "label": "Team Share",
                "state": "mounted",
                "writable": True,
                "locationId": network,
                "source": {"scheme": "smb", "display": "//files/team", "host": "files", "share": "team"},
                "reason": None,
            },
        ],
        "recent": [{"entryId": document, "rank": 0}],
    }

def clone_workspace() -> dict[str, object]:
    return deepcopy(workspace())
