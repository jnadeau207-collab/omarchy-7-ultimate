from __future__ import annotations

import json
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path

from omarchy_fabric.providers.compatibility.engine import CompatibilityEngine, deployment_revision
from omarchy_fabric.providers.compatibility.provider import CompatibilityProvider
from omarchy_fabric.providers.compatibility.recipes import RecipeCatalog
from omarchy_fabric.security import EndpointPrincipal, PrincipalKind

ROOT = Path(__file__).resolve().parents[3]


def recipe_document():
    return json.loads((ROOT / "default/ultimate/compatibility/recipes-v0.json").read_text(encoding="utf-8"))


def recipes():
    return RecipeCatalog(recipe_document())


def principal():
    now = datetime(2026, 8, 27, tzinfo=timezone.utc)
    return EndpointPrincipal("principal.compatibility-tests", "session.compatibility-tests", 1000, "shell.compatibility-tests", PrincipalKind.SHELL, now, now + timedelta(hours=1))


def host(**overrides):
    value = {
        "architecture": "x86_64",
        "virtualizationAvailable": True,
        "protonAvailable": True,
        "isolationAvailable": True,
        "browserAvailable": True,
        "availableRuntimes": ["wine", "proton", "container", "browser", "native"],
        "memoryMiB": 16384,
        "diskMiB": 262144,
    }
    value.update(overrides)
    return value


def request(*, identity="workload.test", name="Test workload", workload_type="desktop", artifact_kind="native-package", permissions=None, architecture="x86_64", **constraints):
    limits = {"requiresKernelDriver": False, "requiresAdmin": False, "antiCheat": "none", "offlineRequired": False, "acceptsBrowser": False}
    limits.update(constraints)
    origin = None if artifact_kind == "none" else "https://example.invalid/app"
    digest = "sha256:" + "1" * 64 if artifact_kind not in {"web-url", "none"} else None
    return {"id": identity, "name": name, "workloadType": workload_type, "architecture": architecture, "artifact": {"kind": artifact_kind, "origin": origin, "digest": digest}, "permissions": permissions or [], "constraints": limits}


def reviewed_request(*, identity="workload.adobe-reader", name="Adobe Reader", permissions=None):
    value = request(identity=identity, name=name, workload_type="windows-app", artifact_kind="windows-executable", permissions=permissions or ["network", "filesystem-home"])
    recipe = recipes().by_workload[identity]
    value["artifact"] = {"kind": "windows-executable", "origin": recipe["artifact"]["origin"], "digest": recipe["artifact"]["digest"]}
    return value


def provider(*, deployments=None, **engine_kwargs):
    value = recipes()
    engine = CompatibilityEngine(value, deployments=deepcopy(deployments or []), **engine_kwargs)
    return CompatibilityProvider(value, engine)


def arguments(engine, workload, machine=None, request_id="request.compatibility.test", preserve=True):
    return {"requestId": request_id, "request": workload, "host": machine or host(), "recipeRevision": engine.recipes.revision, "expectedDeploymentRevision": deployment_revision(engine._deployments), "preserveData": preserve}
