"""Sandboxed managed-task execution outside the storage plane."""

from __future__ import annotations

import json
import tempfile
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from sandbox.builder import FIXED_AGENT_RUNNER, SandboxSpec, SandboxUnavailable, SandboxViolation, ScopedBind
from sandbox.runner import IsolatedRun, packaged_runner_source, run_isolated

from .desktop_context import capture_desktop_context
from .managed_work import Actor, ManagedWorkError, ManagedWorkPlane
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
                executor_attested=True,
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
        try:
            task = self.plane.get_task(actor, task_id)
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
                    executor_attested=True,
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
            run = self.plane.create_run_plan(
                actor,
                task_id,
                manifest=_probe_manifest(task),
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
            isolated = self._run_sandbox(task_id)
        except (SandboxUnavailable, SandboxViolation) as error:
            current = self.plane.get_run(actor, run["runId"])
            if current["state"] in {"queued", "running"}:
                self.plane.transition_run(
                    actor,
                    run["runId"],
                    expected_revision=current["revision"],
                    target="failed",
                    detail={"code": "sandbox.unavailable", "detail": str(error)},
                    executor_attested=current["state"] == "running",
                )
            raise FabricError(
                "sandbox.unavailable",
                "Sandboxed managed execution failed closed",
                "Managed tasks execute only inside bubblewrap; missing isolation is a failed security gate.",
                detail=str(error),
                change_state="failed",
                recovery_actions=("system.install-bubblewrap",),
            ) from error

        if isolated.returncode != 0 or not isolated.result or isolated.result.get("ok") is not True:
            self.plane.transition_run(
                actor,
                running["runId"],
                expected_revision=running["revision"],
                target="failed",
                detail={"code": "sandbox.probe-failed", "returncode": isolated.returncode},
                executor_attested=True,
            )
            raise FabricError(
                "sandbox.probe-failed",
                "Sandboxed managed execution failed",
                "The isolated runner returned a non-success result.",
                detail=isolated.stderr or isolated.stdout,
                change_state="failed",
            )
        succeeded = self.plane.transition_run(
            actor,
            running["runId"],
            expected_revision=running["revision"],
            target="succeeded",
            detail={"isolation": "bubblewrap", "ok": True},
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

    def _run_sandbox(self, task_id: str) -> IsolatedRun:
        runner = packaged_runner_source()
        with tempfile.TemporaryDirectory(prefix="omarchy-managed-run-") as temporary:
            root = Path(temporary)
            workspace = root / "workspace"
            artifacts = root / "artifacts"
            home = root / "home"
            workspace.mkdir()
            artifacts.mkdir()
            home.mkdir()
            (workspace / "manifest.json").write_text(
                json.dumps({"kind": "sandbox-probe", "taskId": task_id}, separators=(",", ":")),
                encoding="utf-8",
            )
            spec = SandboxSpec(
                task_id,
                (FIXED_AGENT_RUNNER, "--task-id", task_id, "--manifest-fd", "3"),
                binds=(
                    ScopedBind(workspace, workspace, f"/workspace/{task_id}", writable=False),
                    ScopedBind(artifacts, artifacts, f"/artifacts/{task_id}", writable=True),
                ),
                runner_source=runner,
            )
            return run_isolated(spec, protected_home=home)


def _probe_manifest(task: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "provider": "provider.managed-runtime",
        "model": "model.sandbox-probe",
        "capabilities": ["system.inspect"],
        "contextIds": list(task.get("contextIds") or []),
        "workspaceHandles": ["workspace.probe"],
        "artifactHandle": "artifact.probe",
        "budgets": task["budget"],
        "networkGranted": False,
        "sandboxRequired": True,
        "steps": [{"label": "Sandboxed probe", "capability": "system.inspect"}],
    }
