from __future__ import annotations

import json
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path

from omarchy_fabric.providers.packages.catalog import PackageCatalog
from omarchy_fabric.providers.packages.engine import PackageOperationEngine, inventory_revision
from omarchy_fabric.providers.packages.identity import stable_id
from omarchy_fabric.providers.packages.provider import PackageProvider
from omarchy_fabric.security import EndpointPrincipal, PrincipalKind

ROOT = Path(__file__).resolve().parents[3]

def catalog_document():
    return json.loads((ROOT / "default/ultimate/software/catalog-v0.json").read_text(encoding="utf-8"))

def catalog():
    return PackageCatalog(catalog_document())

def principal():
    now = datetime(2026, 8, 27, tzinfo=timezone.utc)
    return EndpointPrincipal("principal.software-tests", "session.software-tests", 1000, "shell.software-tests", PrincipalKind.SHELL, now, now + timedelta(hours=1))

def installed(app_id="software.curated.neovim", *, adopted=True, digest=None, state="installed"):
    entry = catalog().by_id[app_id]
    return {
        "id": stable_id("installed.software", entry["sourceType"], entry["packageRef"]),
        "catalogId": app_id,
        "sourceType": entry["sourceType"],
        "packageRef": entry["packageRef"],
        "installedVersion": entry["version"],
        "artifactDigest": digest or entry["provenance"]["artifactDigest"],
        "adopted": adopted,
        "state": state,
        "configPaths": ["/home/test/.config/neovim"],
        "dataPaths": ["/home/test/.local/share/neovim"],
    }

def provider(inventory=None, **engine_kwargs):
    value = catalog()
    engine = PackageOperationEngine(value, deepcopy(inventory or []), **engine_kwargs)
    return PackageProvider(value, engine)

def arguments(engine, app_id, request_id="request.software.test", preserve=True):
    return {
        "requestId": request_id,
        "appId": app_id,
        "catalogRevision": engine.catalog.revision,
        "expectedInventoryRevision": inventory_revision(engine._inventory),
        "preserveUserData": preserve,
    }
