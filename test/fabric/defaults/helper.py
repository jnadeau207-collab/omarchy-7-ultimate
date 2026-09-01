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
from omarchy_fabric.providers.defaults import provider as defaults
from omarchy_fabric.security.principal import EndpointPrincipal, PrincipalKind

def principal() -> EndpointPrincipal:
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    return EndpointPrincipal(
        "principal.defaults-tests",
        "session.defaults-tests",
        1000,
        "shell.defaults-tests",
        PrincipalKind.SHELL,
        now,
        now + timedelta(hours=1),
    )

def application(
    desktop_id: str,
    name: str,
    *,
    mime_types: tuple[str, ...] = (),
    protocols: tuple[str, ...] = (),
    state: str = "available",
) -> dict[str, object]:
    return {
        "id": defaults._application_id(desktop_id),
        "desktopId": desktop_id,
        "name": name,
        "state": state,
        "icon": None,
        "mimeTypes": sorted(mime_types),
        "protocols": sorted(protocols),
        "source": "user",
        "identity": state_revision({"desktopId": desktop_id, "generation": 1}),
        "reason": None,
    }

def association(
    kind: str,
    key: str,
    candidates: list[str],
    default_app_id: str | None,
    *,
    writable: bool = True,
) -> dict[str, object]:
    value = {
        "id": defaults._association_id(kind, key),
        "kind": kind,
        "key": key,
        "defaultAppId": default_app_id,
        "candidateAppIds": sorted(candidates),
        "writable": writable,
        "source": "user" if default_app_id else "none",
        "status": "configured" if default_app_id else "unconfigured",
        "identity": "",
    }
    value["identity"] = defaults._association_identity(value)
    return value

def database() -> dict[str, object]:
    editor = application("editor.desktop", "Editor", mime_types=("application/json", "text/plain"))
    browser = application("browser.desktop", "Browser", mime_types=("text/html",), protocols=("http", "https"))
    mailer = application("mailer.desktop", "Mailer", protocols=("mailto",))
    alternate = application("alternate.desktop", "Alternate", mime_types=("text/plain",), protocols=("http",))
    return {
        "schemaVersion": "v0",
        "databaseId": "defaults.database.primary",
        "applications": [editor, browser, mailer, alternate],
        "associations": [
            association("mime", "text/plain", [editor["id"], alternate["id"]], editor["id"]),
            association("mime", "text/html", [browser["id"]], browser["id"]),
            association("protocol", "http", [browser["id"], alternate["id"]], browser["id"]),
            association("protocol", "https", [browser["id"]], browser["id"]),
            association("protocol", "mailto", [mailer["id"]], mailer["id"]),
        ],
    }

def clone_database() -> dict[str, object]:
    return deepcopy(database())
