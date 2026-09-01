"""Daemon-owned admission for task-scoped Fabric endpoints.

A client is a ``PrincipalKind.TASK`` only when the daemon already registered a
sandbox binding for that exact peer. Reaching ``fabric.owner-rpc``, sending
``kind``/``taskId`` in hello, or sharing the daemon UID is never enough.

The binding is created when a managed-task sandbox starts. It names one
``task_id``, the task socket inode, the sandbox pid, its cgroup and unit, and
the digest of a grant token the daemon placed only in that sandbox. Hello on
the owner socket never consults this authority.
"""

from __future__ import annotations

import hashlib
import hmac
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from .errors import SecurityValidationError
from .principal import EndpointAdmission, PrincipalKind

_STABLE_RE = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$")
_UNIT_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._@:-]{0,255}$")
MAX_BINDINGS = 256
TASK_ENDPOINT_ID = "fabric.task-rpc"


def _require_stable(value: object, code: str, label: str) -> str:
    if not isinstance(value, str) or not _STABLE_RE.fullmatch(value):
        raise SecurityValidationError(code, f"{label} must be a stable identifier.")
    return value


def _require_pid(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0 or value > 2**31 - 1:
        raise SecurityValidationError("task-admission.pid", "Task peer PID must be a positive process ID.")
    return value


def _require_uid(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0 or value > 2**32 - 1:
        raise SecurityValidationError("task-admission.uid", "Task peer UID must be a non-negative Unix UID.")
    return value


def _require_inode(value: object, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise SecurityValidationError("task-admission.socket", f"{label} must be a non-negative inode field.")
    return value


def _require_unit(value: object) -> str:
    if not isinstance(value, str) or not _UNIT_RE.fullmatch(value) or "/" in value:
        raise SecurityValidationError("task-admission.unit", "Task unit must be a bounded systemd unit name.")
    return value


def _require_cgroup(value: object) -> str:
    if (
        not isinstance(value, str)
        or not 1 <= len(value) <= 512
        or "\x00" in value
        or "\n" in value
        or "\r" in value
        or not value.startswith("/")
    ):
        raise SecurityValidationError("task-admission.cgroup", "Task cgroup must be a bounded absolute path.")
    return value


def _require_token(value: object) -> str:
    if not isinstance(value, str) or not 16 <= len(value) <= 256 or any(ord(character) < 32 for character in value):
        raise SecurityValidationError("task-admission.token", "Task grant token is invalid.")
    return value


@dataclass(frozen=True)
class PeerIdentity:
    uid: int
    pid: int
    unit: str
    cgroup: str

    def __post_init__(self) -> None:
        object.__setattr__(self, "uid", _require_uid(self.uid))
        object.__setattr__(self, "pid", _require_pid(self.pid))
        object.__setattr__(self, "unit", _require_unit(self.unit))
        object.__setattr__(self, "cgroup", _require_cgroup(self.cgroup))


@dataclass(frozen=True)
class TaskEndpointBinding:
    """Daemon-owned record of one running task sandbox. Never an RPC field."""

    task_id: str
    uid: int
    pid: int
    unit: str
    cgroup: str
    socket_dev: int
    socket_ino: int
    endpoint_id: str = TASK_ENDPOINT_ID

    def __post_init__(self) -> None:
        object.__setattr__(self, "task_id", _require_stable(self.task_id, "task-admission.task", "Task ID"))
        object.__setattr__(self, "uid", _require_uid(self.uid))
        object.__setattr__(self, "pid", _require_pid(self.pid))
        object.__setattr__(self, "unit", _require_unit(self.unit))
        object.__setattr__(self, "cgroup", _require_cgroup(self.cgroup))
        object.__setattr__(self, "socket_dev", _require_inode(self.socket_dev, "Socket device"))
        object.__setattr__(self, "socket_ino", _require_inode(self.socket_ino, "Socket inode"))
        object.__setattr__(
            self,
            "endpoint_id",
            _require_stable(self.endpoint_id, "task-admission.endpoint", "Task endpoint"),
        )
        if self.endpoint_id == "fabric.owner-rpc":
            raise SecurityValidationError(
                "task-admission.owner-rpc",
                "The owner RPC socket can never carry a task binding.",
            )


@dataclass
class _StoredBinding:
    binding: TaskEndpointBinding
    token_digest: bytes


def read_peer_identity(pid: int, *, proc_root: Path | None = None) -> PeerIdentity:
    """Read uid/cgroup/unit from ``/proc``. Used at accept time, not from RPC."""

    process_id = _require_pid(pid)
    root = proc_root or Path("/proc")
    status_path = root / str(process_id) / "status"
    cgroup_path = root / str(process_id) / "cgroup"
    try:
        status = status_path.read_text(encoding="utf-8")
        cgroup_text = cgroup_path.read_text(encoding="utf-8")
    except OSError as error:
        raise SecurityValidationError(
            "task-admission.peer-unreadable",
            "The connecting process identity could not be read from the kernel.",
        ) from error
    uid = None
    for line in status.splitlines():
        if line.startswith("Uid:"):
            parts = line.split()
            if len(parts) >= 2:
                try:
                    uid = int(parts[1])
                except ValueError:
                    uid = None
            break
    if uid is None:
        raise SecurityValidationError("task-admission.peer-unreadable", "The connecting process UID is unreadable.")
    cgroup = None
    for line in cgroup_text.splitlines():
        if ":" in line:
            cgroup = line.rsplit(":", 1)[-1]
    if not cgroup:
        raise SecurityValidationError("task-admission.peer-unreadable", "The connecting process cgroup is unreadable.")
    unit = Path(cgroup).name
    return PeerIdentity(uid=uid, pid=process_id, unit=unit, cgroup=cgroup)


class TaskAdmissionAuthority:
    """Registers task sandboxes and admits only those exact peers."""

    def __init__(self, *, identity_reader: Callable[[int], PeerIdentity] | None = None) -> None:
        self._bindings: dict[str, _StoredBinding] = {}
        self._identity_reader = identity_reader

    @property
    def binding_count(self) -> int:
        return len(self._bindings)

    def register(self, binding: TaskEndpointBinding, grant_token: str) -> None:
        if not isinstance(binding, TaskEndpointBinding):
            raise SecurityValidationError("task-admission.binding", "Task endpoint binding is invalid.")
        token = _require_token(grant_token)
        if binding.task_id in self._bindings:
            raise SecurityValidationError(
                "task-admission.duplicate",
                "A task endpoint is already registered for this task.",
            )
        if len(self._bindings) >= MAX_BINDINGS:
            raise SecurityValidationError(
                "task-admission.capacity",
                "Task endpoint admission capacity is exhausted.",
            )
        for stored in self._bindings.values():
            if (
                stored.binding.socket_dev == binding.socket_dev
                and stored.binding.socket_ino == binding.socket_ino
            ):
                raise SecurityValidationError(
                    "task-admission.socket-in-use",
                    "Another task already owns this socket identity.",
                )
            if stored.binding.pid == binding.pid:
                raise SecurityValidationError(
                    "task-admission.pid-in-use",
                    "Another task already owns this process identity.",
                )
        self._bindings[binding.task_id] = _StoredBinding(
            binding=binding,
            token_digest=hashlib.sha256(token.encode("utf-8")).digest(),
        )

    def revoke(self, task_id: str) -> None:
        stable = _require_stable(task_id, "task-admission.task", "Task ID")
        if self._bindings.pop(stable, None) is None:
            raise SecurityValidationError("task-admission.unknown", "No task endpoint is registered for this task.")

    def admit(
        self,
        peer: PeerIdentity,
        *,
        socket_dev: int,
        socket_ino: int,
        grant_token: str,
    ) -> EndpointAdmission:
        if not isinstance(peer, PeerIdentity):
            raise SecurityValidationError("task-admission.peer", "Task peer identity is invalid.")
        device = _require_inode(socket_dev, "Socket device")
        inode = _require_inode(socket_ino, "Socket inode")
        token = _require_token(grant_token)
        supplied = hashlib.sha256(token.encode("utf-8")).digest()
        if self._identity_reader is not None:
            observed = self._identity_reader(peer.pid)
            if observed != peer:
                raise SecurityValidationError(
                    "task-admission.peer-drift",
                    "The connecting process identity no longer matches the presented peer.",
                )
        matched: _StoredBinding | None = None
        for stored in self._bindings.values():
            if hmac.compare_digest(stored.token_digest, supplied):
                matched = stored
                break
        dummy = bytes(32)
        if matched is None:
            hmac.compare_digest(dummy, supplied)
            raise SecurityValidationError(
                "task-admission.denied",
                "No registered task sandbox matches this connection.",
            )
        binding = matched.binding
        if (
            binding.uid != peer.uid
            or binding.pid != peer.pid
            or binding.unit != peer.unit
            or binding.cgroup != peer.cgroup
            or binding.socket_dev != device
            or binding.socket_ino != inode
        ):
            raise SecurityValidationError(
                "task-admission.denied",
                "No registered task sandbox matches this connection.",
            )
        return EndpointAdmission(
            endpoint_id=binding.endpoint_id,
            kind=PrincipalKind.TASK,
            task_id=binding.task_id,
        )
