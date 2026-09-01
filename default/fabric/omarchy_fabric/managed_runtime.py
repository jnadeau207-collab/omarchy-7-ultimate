from __future__ import annotations

import hashlib
import json
import tempfile
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from sandbox.builder import FIXED_AGENT_RUNNER, SandboxSpec, SandboxUnavailable, SandboxViolation, ScopedBind
from sandbox.runner import IsolatedRun, packaged_runner_source, run_isolated

from .desktop_context import capture_desktop_context
from .managed_work import Actor, ManagedWorkError, ManagedWorkPlane
from .managed_work.plane import SANDBOX_CAPABILITIES
from .models import FabricError

def _as_fabric_error(error: ManagedWorkError) -> FabricError:
    return FabricError(
        error.code,
        "Managed-work request was refused",
        error.explanation,
        detail=error.detail,
        retryable=error.retryable,
        change_state="none",
        recovery_actions=error.recovery_actions,
    )

def _canonical_manifest(value: Mapping[str, Any]) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)

def _workspace_listing(workspace: Path) -> list[str]:
    names: list[str] = []
    for path in sorted(workspace.rglob("*")):
        if path.is_file():
            names.append(path.relative_to(workspace).as_posix())
    return names

def _task_capability(task: Mapping[str, Any]) -> str:
    intent = task.get("intent")
    capability = intent.get("capability") if isinstance(intent, Mapping) else None
    if capability not in SANDBOX_CAPABILITIES:
        raise ManagedWorkError(
            "task.capability",
            "A sandboxed run requires a catalog capability from the Phase 2 sandbox allowlist.",
            detail="missing" if capability is None else str(capability),
        )
    return str(capability)

def _run_manifest(task: Mapping[str, Any], capability: str) -> dict[str, Any]:
    return {
        "provider": "provider.managed-runtime",
        "model": "model.sandbox-inspect",
        "capabilities": [capability],
        "contextIds": list(task.get("contextIds") or []),
        "workspaceHandles": ["workspace.inspect"],
        "artifactHandle": "artifact.inspect",
        "budgets": task["budget"],
        "networkGranted": False,
        "sandboxRequired": True,
        "steps": [{"label": "Sandboxed inspect", "capability": capability}],
    }

def _artifact_matches(
    result: Mapping[str, Any],
    *,
    capability: str,
    manifest: Mapping[str, Any],
    listing: list[str],
) -> bool:
    isolation = result.get("isolation")
    if not isinstance(isolation, Mapping):
        return False
    expected_hash = hashlib.sha256(_canonical_manifest(manifest).encode("utf-8")).hexdigest()
    return (
        result.get("ok") is True
        and result.get("capability") == capability
        and result.get("manifestHash") == expected_hash
        and result.get("workspace") == listing
        and isolation.get("forbiddenEnv") == []
        and isolation.get("homeVisible") is False
        and isolation.get("runUserVisible") is False
        and isolation.get("fabricSocketVisible") is False
    )

class ManagedRuntime:
    def __init__(self, plane: ManagedWorkPlane) -> None:
        self.plane = plane

    def create_task(self, actor: Actor, params: Mapping[str, Any]) -> dict[str, Any]:
        try:
            return self.plane.create_task(
                actor,
                title=params["title"],
                intent=params["intent"],
                context_ids=params.get("contextIds", []),
                budget=params["budget"],
                idempotency_key=params["idempotencyKey"],
            )
        except ManagedWorkError as error:
            raise _as_fabric_error(error) from error

    def cancel_task(self, actor: Actor, params: Mapping[str, Any]) -> dict[str, Any]:
        try:
            return self.plane.transition_task(
                actor,
                params["taskId"],
                expected_revision=params["expectedRevision"],
                target="cancelled",
            )
        except ManagedWorkError as error:
            raise _as_fabric_error(error) from error

    def recover_task(self, actor: Actor, params: Mapping[str, Any]) -> dict[str, Any]:
        try:
            return self.plane.transition_task(
                actor,
                params["taskId"],
                expected_revision=params["expectedRevision"],
                target="retrying",
                reason="caller-recover",
            )
        except ManagedWorkError as error:
            raise _as_fabric_error(error) from error

    def list_tasks(self, actor: Actor, params: Mapping[str, Any]) -> dict[str, Any]:
        try:
            return self.plane.query(
                actor,
                "agent.tasks",
                limit=params.get("limit", 50),
                cursor=params.get("cursor"),
            )
        except ManagedWorkError as error:
            raise _as_fabric_error(error) from error

    def capture_context(self, actor: Actor, params: Mapping[str, Any]) -> dict[str, Any]:
        snapshot = params.get("snapshot")
        try:
            return capture_desktop_context(
                self.plane,
                actor,
                source=params["source"],
                snapshot=snapshot if isinstance(snapshot, Mapping) else None,
                access_scope=params.get("accessScope", "principal"),
                sensitivity=params.get("sensitivity", "personal"),
                ttl_seconds=int(params.get("ttlSeconds", 600)),
                idempotency_key=params["idempotencyKey"],
            )
        except ManagedWorkError as error:
            raise _as_fabric_error(error) from error

    def execute(self, actor: Actor, params: Mapping[str, Any]) -> dict[str, Any]:
        task_id = params["taskId"]
        status = ManagedWorkPlane.execution_status()
        if not status["available"]:
            raise FabricError(
                status["code"],
                "Sandboxed managed execution failed closed",
                status["explanation"],
                change_state="none",
                recovery_actions=("system.install-bubblewrap",),
            )
        try:
            task = self.plane.get_task(actor, task_id)
            capability = _task_capability(task)
            if task["state"] == "draft":
                task = self.plane.transition_task(
                    actor,
                    task_id,
                    expected_revision=task["revision"],
                    target="queued",
                )
            elif task["state"] == "interrupted":
                task = self.plane.transition_task(
                    actor,
                    task_id,
                    expected_revision=task["revision"],
                    target="retrying",
                    reason="execute-recover",
                )
            if task["state"] == "retrying":
                task = self.plane.transition_task(
                    actor,
                    task_id,
                    expected_revision=task["revision"],
                    target="queued",
                )
            if task["state"] != "queued":
                raise ManagedWorkError(
                    "run.task-state",
                    "A sandboxed run may start only from a queued task.",
                    detail=task["state"],
                )
            manifest = _run_manifest(task, capability)
            run = self.plane.create_run_plan(
                actor,
                task_id,
                manifest=manifest,
                idempotency_key=params["idempotencyKey"],
            )
        except ManagedWorkError as error:
            raise _as_fabric_error(error) from error

        try:
            running = self.plane.transition_run(
                actor,
                run["runId"],
                expected_revision=run["revision"],
                target="running",
                detail={"isolation": "bubblewrap"},
                executor_attested=True,
            )
            isolated, listing = self._run_sandbox(task_id, manifest)
        except (SandboxUnavailable, SandboxViolation) as error:
            current = self.plane.get_run(actor, run["runId"])
            if current["state"] in {"queued", "running"}:
                self.plane.transition_run(
                    actor,
                    run["runId"],
                    expected_revision=current["revision"],
                    target="failed",
                    detail={"code": status["code"], "detail": str(error)},
                    executor_attested=current["state"] == "running",
                )
            raise FabricError(
                status["code"],
                "Sandboxed managed execution failed closed",
                "Managed tasks execute only inside bubblewrap; missing isolation is a failed security gate.",
                detail=str(error),
                change_state="complete",
                recovery_actions=("system.install-bubblewrap",),
            ) from error

        if (
            isolated.returncode != 0
            or not isolated.result
            or not _artifact_matches(
                isolated.result,
                capability=capability,
                manifest=manifest,
                listing=listing,
            )
        ):
            self.plane.transition_run(
                actor,
                running["runId"],
                expected_revision=running["revision"],
                target="failed",
                detail={"code": "sandbox.run-failed", "returncode": isolated.returncode},
                executor_attested=True,
            )
            raise FabricError(
                "sandbox.run-failed",
                "Sandboxed managed execution failed",
                "The isolated runner did not return a matching inspect artifact.",
                detail=isolated.stderr or isolated.stdout,
                change_state="complete",
            )
        succeeded = self.plane.transition_run(
            actor,
            running["runId"],
            expected_revision=running["revision"],
            target="succeeded",
            detail={"isolation": "bubblewrap", "ok": True, "capability": capability},
            executor_attested=True,
        )
        return {
            "schemaVersion": "v0",
            "kind": "sandboxed-run",
            "task": self.plane.get_task(actor, task_id),
            "run": succeeded,
            "isolation": {
                "kind": "bubblewrap",
                "argv0": isolated.argv[0] if isolated.argv else "",
                "unshareAll": "--unshare-all" in isolated.argv,
            },
            "result": dict(isolated.result),
        }

    def _run_sandbox(self, task_id: str, manifest: Mapping[str, Any]) -> tuple[IsolatedRun, list[str]]:
        runner = packaged_runner_source()
        with tempfile.TemporaryDirectory(prefix="omarchy-managed-run-") as temporary:
            root = Path(temporary)
            workspace = root / "workspace"
            artifacts = root / "artifacts"
            home = root / "home"
            workspace.mkdir()
            artifacts.mkdir()
            home.mkdir()
            (workspace / "manifest.json").write_text(_canonical_manifest(manifest), encoding="utf-8")
            listing = _workspace_listing(workspace)
            spec = SandboxSpec(
                task_id,
                (FIXED_AGENT_RUNNER, "--task-id", task_id, "--manifest-fd", "3"),
                binds=(
                    ScopedBind(workspace, workspace, f"/workspace/{task_id}", writable=False),
                    ScopedBind(artifacts, artifacts, f"/artifacts/{task_id}", writable=True),
                ),
                runner_source=runner,
            )
            return run_isolated(spec, protected_home=home), listing
