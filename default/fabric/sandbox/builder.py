"""Hermetic bubblewrap argv construction for managed Fabric tasks."""

from __future__ import annotations

import os
import re
import stat
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
from typing import Mapping, Sequence

FIXED_AGENT_RUNNER = "/usr/lib/omarchy/fabric/agent-runner"
TRUSTED_BWRAP_PATHS = frozenset({"/usr/bin/bwrap", "/bin/bwrap"})
_TASK_RE = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$")
_HOST_RE = re.compile(r"^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
_ENV_ALLOWLIST = frozenset({"LANG", "LC_ALL", "TZ", "TERM", "NO_COLOR"})
_SENSITIVE_PARTS = frozenset(
    {
        ".ssh",
        ".gnupg",
        ".password-store",
        "keyrings",
        "google-chrome",
        "chromium",
        "chrome",
        "firefox",
        ".mozilla",
        "brave-browser",
        "vivaldi",
        ".xauthority",
        ".pki",
    }
)
_RUNNER_VALUE_FLAGS = {
    "--task-id": "task",
    "--manifest-fd": "fd",
    "--input-fd": "fd",
    "--output-fd": "fd",
    "--model": "stable",
    "--reasoning-effort": "effort",
}
_EFFORTS = frozenset({"none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"})


class SandboxViolation(ValueError):
    pass


class SandboxUnavailable(RuntimeError):
    pass


@dataclass(frozen=True)
class ScopedBind:
    source: Path
    source_root: Path
    target: str
    writable: bool = False


@dataclass(frozen=True)
class NetworkScope:
    host: str
    port: int
    protocol: str = "https"

    def __post_init__(self) -> None:
        if not isinstance(self.host, str):
            raise SandboxViolation("Task proxy host must be an explicit DNS name.")
        normalized_host = self.host.lower().rstrip(".")
        if self.protocol != "https":
            raise SandboxViolation("Task proxy scopes support HTTPS only.")
        if not _HOST_RE.fullmatch(normalized_host) or normalized_host in {"localhost", "localhost.localdomain"}:
            raise SandboxViolation("Task proxy host must be an explicit DNS name.")
        if not isinstance(self.port, int) or isinstance(self.port, bool) or not 1 <= self.port <= 65535:
            raise SandboxViolation("Task proxy port is invalid.")
        object.__setattr__(self, "host", normalized_host)


@dataclass(frozen=True)
class TaskProxy:
    source: Path
    source_root: Path
    task_id: str
    scopes: tuple[NetworkScope, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.task_id, str) or not _TASK_RE.fullmatch(self.task_id):
            raise SandboxViolation("Task proxy ID must be a stable identifier.")
        if not isinstance(self.scopes, tuple) or not self.scopes:
            raise SandboxViolation("Task proxy access requires explicit network scopes.")
        if any(not isinstance(scope, NetworkScope) for scope in self.scopes):
            raise SandboxViolation("Task proxy scopes must be validated NetworkScope values.")
        if len(set(self.scopes)) != len(self.scopes):
            raise SandboxViolation("Task proxy network scopes must be unique.")


@dataclass(frozen=True)
class SandboxSpec:
    task_id: str
    runner_argv: tuple[str, ...]
    binds: tuple[ScopedBind, ...] = ()
    environment: Mapping[str, str] = field(default_factory=dict)
    task_proxy: TaskProxy | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.task_id, str) or not _TASK_RE.fullmatch(self.task_id):
            raise SandboxViolation("Task ID must be a stable identifier.")
        validate_runner_argv(self.runner_argv, task_id=self.task_id)
        _validate_environment(self.environment)


def validate_runner_argv(argv: Sequence[str], *, task_id: str) -> tuple[str, ...]:
    if not isinstance(argv, (list, tuple)) or not argv or argv[0] != FIXED_AGENT_RUNNER:
        raise SandboxViolation("Managed tasks use only the fixed packaged agent runner.")
    normalized = tuple(argv)
    index = 1
    seen: set[str] = set()
    while index < len(normalized):
        flag = normalized[index]
        if not isinstance(flag, str):
            raise SandboxViolation("Runner argv options must be strings.")
        kind = _RUNNER_VALUE_FLAGS.get(flag)
        if kind is None or flag in seen or index + 1 >= len(normalized):
            raise SandboxViolation("Runner argv contains an unknown, duplicate, or incomplete option.")
        value = normalized[index + 1]
        if not isinstance(value, str) or not value or "\x00" in value or "\n" in value or "\r" in value:
            raise SandboxViolation("Runner argv contains an unsafe value.")
        if value.startswith("/") or "\\" in value or value in {".", ".."} or "/../" in f"/{value}/":
            raise SandboxViolation("Runner argv cannot carry host paths or traversal.")
        if kind == "task" and value != task_id:
            raise SandboxViolation("Runner task ID must match the sandbox task scope.")
        if kind == "fd" and (not value.isascii() or not value.isdigit() or not 3 <= int(value) <= 1024):
            raise SandboxViolation("Runner file descriptor is outside the allowed range.")
        if kind == "stable" and not _TASK_RE.fullmatch(value):
            raise SandboxViolation("Runner stable option value is invalid.")
        if kind == "effort" and value not in _EFFORTS:
            raise SandboxViolation("Runner reasoning effort is invalid.")
        seen.add(flag)
        index += 2
    if "--task-id" not in seen or "--manifest-fd" not in seen:
        raise SandboxViolation("Runner argv must bind task identity and a manifest file descriptor.")
    return normalized


def _validate_environment(environment: Mapping[str, str]) -> None:
    if not isinstance(environment, Mapping):
        raise SandboxViolation("Sandbox environment must be a mapping.")
    for key, value in environment.items():
        if not isinstance(key, str) or key not in _ENV_ALLOWLIST:
            raise SandboxViolation(f"Environment variable {key!r} is not allowed.")
        if not isinstance(value, str) or len(value) > 256 or "\x00" in value or "\n" in value or "\r" in value:
            raise SandboxViolation("Sandbox environment value is invalid.")


def _has_symlink_component(path: Path) -> bool:
    current = Path(path.anchor) if path.anchor else Path()
    parts = path.parts[1:] if path.anchor else path.parts
    for part in parts:
        current = current / part
        try:
            if current.is_symlink():
                return True
        except OSError:
            return True
    return False


def _validate_host_source(
    source: Path,
    source_root: Path,
    *,
    protected_home: Path,
    task_proxy: bool = False,
) -> Path:
    try:
        source = Path(source)
        source_root = Path(source_root)
    except TypeError:
        raise SandboxViolation("Bind sources and roots must be filesystem paths.") from None
    if not source.is_absolute() or not source_root.is_absolute():
        raise SandboxViolation("Bind sources and roots must be absolute.")
    if _has_symlink_component(source) or _has_symlink_component(source_root):
        raise SandboxViolation("Symlink-sensitive bind inputs are forbidden.")
    try:
        resolved_source = source.resolve(strict=True)
        resolved_root = source_root.resolve(strict=True)
        resolved_source.relative_to(resolved_root)
    except (OSError, ValueError):
        raise SandboxViolation("Bind source must exist inside its explicit scoped root.") from None
    if resolved_root == Path(resolved_root.anchor) or len(resolved_root.parts) <= 2:
        raise SandboxViolation("Bind source root is too broad to be a task scope.")
    try:
        source_mode = resolved_source.stat().st_mode
    except OSError:
        raise SandboxViolation("Bind source could not be inspected.") from None
    if task_proxy:
        if not stat.S_ISSOCK(source_mode):
            raise SandboxViolation("Task proxy source must be one exact Unix socket.")
    elif stat.S_ISSOCK(source_mode):
        raise SandboxViolation("Sockets are forbidden in workspace and artifact binds.")
    parts = {part.lower() for part in resolved_source.parts}
    if parts & _SENSITIVE_PARTS or resolved_source.name.lower() in {
        "fabric.sock",
        "ssh_auth_sock",
        "keyring",
    }:
        raise SandboxViolation("Sensitive host state cannot be mounted into a managed task.")
    try:
        resolved_home = protected_home.resolve(strict=True)
    except OSError:
        resolved_home = protected_home.resolve(strict=False)
    if resolved_source == resolved_home or resolved_root == resolved_home:
        raise SandboxViolation("General home-directory access is forbidden.")
    return resolved_source


def _validate_target(target: str) -> str:
    if not isinstance(target, str) or "\x00" in target:
        raise SandboxViolation("Bind target is invalid.")
    posix = PurePosixPath(target)
    if not posix.is_absolute() or ".." in posix.parts or "." in posix.parts:
        raise SandboxViolation("Bind target must be a normalized absolute sandbox path.")
    normalized = str(posix)
    if not (normalized.startswith("/workspace/") or normalized.startswith("/artifacts/")):
        raise SandboxViolation("Scoped binds are limited to workspace and artifact namespaces.")
    return normalized


def require_bwrap(path: str = "/usr/bin/bwrap") -> str:
    if path not in TRUSTED_BWRAP_PATHS:
        raise SandboxUnavailable("bubblewrap must be the packaged system binary.")
    candidate = Path(path)
    if not candidate.is_file() or candidate.is_symlink() or not os.access(candidate, os.X_OK):
        raise SandboxUnavailable("bubblewrap is unavailable; managed execution fails closed.")
    return path


def build_bwrap_command(
    spec: SandboxSpec,
    *,
    bwrap_path: str = "/usr/bin/bwrap",
    protected_home: Path | None = None,
) -> tuple[str, ...]:
    """Build argv without executing or searching PATH.

    Call ``prepare_bwrap_command`` at the execution boundary to also prove the
    packaged bubblewrap binary exists. There is intentionally no unsandboxed path.
    """

    if bwrap_path not in TRUSTED_BWRAP_PATHS:
        raise SandboxViolation("bubblewrap path must be the fixed packaged location.")
    home = protected_home or Path.home()
    command = [
        bwrap_path,
        "--die-with-parent",
        "--new-session",
        "--unshare-all",
        "--clearenv",
        "--ro-bind",
        "/usr",
        "/usr",
        "--ro-bind-try",
        "/lib",
        "/lib",
        "--ro-bind-try",
        "/lib64",
        "/lib64",
        "--proc",
        "/proc",
        "--dev",
        "/dev",
        "--tmpfs",
        "/tmp",
        "--tmpfs",
        "/home",
        "--dir",
        "/run",
        "--dir",
        "/run/omarchy",
        "--dir",
        "/workspace",
        "--dir",
        "/artifacts",
        "--setenv",
        "HOME",
        "/nonexistent",
        "--setenv",
        "PATH",
        "/usr/bin",
    ]
    targets: set[str] = set()
    for bind in spec.binds:
        source = _validate_host_source(bind.source, bind.source_root, protected_home=home)
        target = _validate_target(bind.target)
        if target in targets:
            raise SandboxViolation("Sandbox bind targets must be unique.")
        targets.add(target)
        command.extend(("--bind" if bind.writable else "--ro-bind", str(source), target))
    if spec.task_proxy is not None:
        if spec.task_proxy.task_id != spec.task_id:
            raise SandboxViolation("Task proxy identity does not match the sandbox task scope.")
        proxy = _validate_host_source(
            spec.task_proxy.source,
            spec.task_proxy.source_root,
            protected_home=home,
            task_proxy=True,
        )
        if proxy.name.lower() == "fabric.sock":
            raise SandboxViolation("The main Fabric socket can never be a task proxy.")
        command.extend(("--ro-bind", str(proxy), "/run/omarchy/task-proxy.sock"))
        command.extend(("--setenv", "OMARCHY_TASK_PROXY", "/run/omarchy/task-proxy.sock"))
        scopes = ",".join(f"{scope.protocol}://{scope.host}:{scope.port}" for scope in spec.task_proxy.scopes)
        command.extend(("--setenv", "OMARCHY_TASK_NETWORK_SCOPES", scopes))
    for key in sorted(spec.environment):
        command.extend(("--setenv", key, spec.environment[key]))
    command.extend(spec.runner_argv)
    return tuple(command)


def prepare_bwrap_command(
    spec: SandboxSpec,
    *,
    bwrap_path: str = "/usr/bin/bwrap",
    protected_home: Path | None = None,
) -> tuple[str, ...]:
    require_bwrap(bwrap_path)
    return build_bwrap_command(spec, bwrap_path=bwrap_path, protected_home=protected_home)
