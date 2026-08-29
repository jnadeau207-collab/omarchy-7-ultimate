from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FABRIC_ROOT = ROOT / "default" / "fabric"
if str(FABRIC_ROOT) not in sys.path:
    sys.path.insert(0, str(FABRIC_ROOT))

from omarchy_fabric.managed_work import Actor, ManagedWorkPlane
from omarchy_fabric.managed_work.plane import SANDBOX_CAPABILITIES

INSPECT_CAPABILITY = next(iter(SANDBOX_CAPABILITIES))


ACTOR = Actor("principal.test", "session.one")
OTHER_ACTOR = Actor("principal.other", "session.other")
OTHER_SESSION = Actor("principal.test", "session.two")


def inspect_intent(**extra: object) -> dict[str, object]:
    intent: dict[str, object] = {
        "goal": "inventory",
        "readOnly": True,
        "capability": INSPECT_CAPABILITY,
    }
    intent.update(extra)
    return intent


def budget(*, network: bool = False) -> dict[str, object]:
    return {
        "timeSeconds": 600,
        "outputBytes": 1_048_576,
        "costMicrounits": 50_000,
        "network": network,
    }


def policy(
    *,
    missed: str = "run-once",
    coalescing: str = "latest",
    max_catch_up: int = 4,
) -> dict[str, object]:
    return {
        "missedRun": missed,
        "coalescing": coalescing,
        "maxCatchUp": max_catch_up,
        "concurrency": "forbid",
        "maxConcurrent": 1,
        "retry": {"maxAttempts": 2, "backoffSeconds": 30},
        "limits": {"timeSeconds": 600, "costMicrounits": 50_000},
        "signedOut": "pause",
    }


def template(context_ids: list[str] | None = None) -> dict[str, object]:
    return {
        "title": "Scheduled inventory",
        "intent": inspect_intent(),
        "contextIds": list(context_ids or []),
        "budget": budget(),
    }


def create_context(
    plane: ManagedWorkPlane,
    *,
    actor: Actor = ACTOR,
    key: str = "context.default",
    scope: str = "principal",
    now: float = 1_000,
) -> dict[str, object]:
    return plane.capture_context(
        actor,
        source="focused-application",
        access_scope=scope,
        content={"application": "test", "document": {"title": "Example"}},
        sensitivity="personal",
        ttl_seconds=86_400,
        idempotency_key=key,
        now=now,
    )


def create_task(
    plane: ManagedWorkPlane,
    *,
    actor: Actor = ACTOR,
    context_ids: list[str] | None = None,
    key: str = "task.default",
    now: float = 1_001,
) -> dict[str, object]:
    return plane.create_task(
        actor,
        title="Inspect system state",
        intent=inspect_intent(),
        context_ids=list(context_ids or []),
        budget=budget(),
        idempotency_key=key,
        now=now,
    )


def manifest(context_ids: list[str] | None = None) -> dict[str, object]:
    return {
        "provider": "provider.test",
        "model": "model.test",
        "capabilities": ["system.inspect"],
        "contextIds": list(context_ids or []),
        "workspaceHandles": ["workspace.test"],
        "artifactHandle": "artifact.output",
        "budgets": budget(),
        "networkGranted": False,
        "sandboxRequired": True,
        "steps": [
            {"label": "Read inventory", "capability": "system.inspect"},
            {"label": "Write report"},
        ],
    }
