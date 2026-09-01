from __future__ import annotations

import json
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

from .builder import (
    FIXED_AGENT_RUNNER,
    HOST_AGENT_RUNNER,
    SandboxSpec,
    SandboxUnavailable,
    SandboxViolation,
    ScopedBind,
    prepare_bwrap_command,
    require_bwrap,
    validate_runner_argv,
)

INSPECT_CAPABILITY = "system.info.read"

@dataclass(frozen=True)
class IsolatedRun:
    returncode: int
    stdout: str
    stderr: str
    argv: tuple[str, ...]
    result: Mapping[str, object] | None

def packaged_runner_source() -> Path:
    candidates = []
    omarchy = os.environ.get("OMARCHY_PATH")
    if omarchy:
        candidates.append(Path(omarchy) / "default" / "fabric" / "agent-runner")
    candidates.append(Path(__file__).resolve().parents[1] / "agent-runner")
    candidates.append(Path(HOST_AGENT_RUNNER))
    for path in candidates:
        try:
            if path.is_file() and not path.is_symlink() and os.access(path, os.R_OK):
                return path.resolve(strict=True)
        except OSError:
            continue
    raise SandboxUnavailable("packaged agent runner is unavailable; managed execution fails closed.")

def canonical_manifest(value: Mapping[str, object]) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)

def inspect_manifest() -> dict[str, object]:
    return {
        "provider": "provider.managed-runtime",
        "model": "model.sandbox-inspect",
        "capabilities": [INSPECT_CAPABILITY],
        "contextIds": [],
        "workspaceHandles": ["workspace.inspect"],
        "artifactHandle": "artifact.inspect",
        "budgets": {
            "timeSeconds": 60,
            "outputBytes": 1024,
            "costMicrounits": 0,
            "network": False,
        },
        "networkGranted": False,
        "sandboxRequired": True,
        "steps": [{"label": "Sandboxed inspect", "capability": INSPECT_CAPABILITY}],
    }

def run_isolated(
    spec: SandboxSpec,
    *,
    timeout: float = 15,
    bwrap_path: str = "/usr/bin/bwrap",
    protected_home: Path | None = None,
    extra_env: Mapping[str, str] | None = None,
) -> IsolatedRun:
    validate_runner_argv(spec.runner_argv, task_id=spec.task_id)
    argv = prepare_bwrap_command(spec, bwrap_path=bwrap_path, protected_home=protected_home)
    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    try:
        completed = subprocess.run(
            argv,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
    except FileNotFoundError as error:
        raise SandboxUnavailable("bubblewrap is unavailable; managed execution fails closed.") from error
    except subprocess.TimeoutExpired as error:
        raise SandboxUnavailable("sandboxed run exceeded its timeout and failed closed.") from error
    stdout = completed.stdout or ""
    stderr = completed.stderr or ""
    parsed: Mapping[str, object] | None = None
    if stdout.strip():
        try:
            payload = json.loads(stdout.splitlines()[-1])
        except json.JSONDecodeError:
            payload = None
        if isinstance(payload, dict):
            parsed = payload
    return IsolatedRun(
        returncode=completed.returncode,
        stdout=stdout,
        stderr=stderr,
        argv=argv,
        result=parsed,
    )

def run_representative_inspect(
    *,
    task_id: str,
    workspace: Path,
    artifacts: Path,
    protected_home: Path,
    host_home: Path,
    timeout: float = 15,
) -> IsolatedRun:
    require_bwrap()
    if not isinstance(task_id, str) or not task_id.startswith("task."):
        raise SandboxViolation("Representative inspect task ID must be a stable task identifier.")
    runner = packaged_runner_source()
    workspace.mkdir(parents=True, exist_ok=True)
    artifacts.mkdir(parents=True, exist_ok=True)
    (workspace / "visible.txt").write_text("workspace-visible\n", encoding="utf-8")
    (workspace / "manifest.json").write_text(canonical_manifest(inspect_manifest()), encoding="utf-8")
    spec = SandboxSpec(
        task_id,
        (FIXED_AGENT_RUNNER, "--task-id", task_id, "--manifest-fd", "3"),
        binds=(
            ScopedBind(workspace, workspace, f"/workspace/{task_id}", writable=False),
            ScopedBind(artifacts, artifacts, f"/artifacts/{task_id}", writable=True),
        ),
        runner_source=runner,
    )
    extra_env = {
        "HOME": str(host_home),
        "XDG_RUNTIME_DIR": str(host_home / "runtime"),
        "WAYLAND_DISPLAY": "wayland-test",
        "DBUS_SESSION_BUS_ADDRESS": f"unix:path={host_home / 'runtime' / 'bus'}",
        "SSH_AUTH_SOCK": str(host_home / "runtime" / "ssh-agent.sock"),
    }
    return run_isolated(
        spec,
        timeout=timeout,
        protected_home=protected_home,
        extra_env=extra_env,
    )
