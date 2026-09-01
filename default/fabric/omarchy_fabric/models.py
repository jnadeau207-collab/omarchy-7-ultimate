"""Shared provisional Fabric transport and execution models."""

from __future__ import annotations

import json
import os
import posixpath
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping, Sequence

PROTOCOL_NAME = "omarchy.fabric.rpc/v0"
PROTOCOL_VERSION = 0
MIN_PROTOCOL_VERSION = 0
MAX_PROTOCOL_VERSION = 0

CURRENT_DATABASE_SCHEMA = 3
MIN_READABLE_DATABASE_SCHEMA = 1
MAX_READABLE_DATABASE_SCHEMA = 3

MAX_FRAME_BYTES = 64 * 1024
MAX_REQUEST_ID_BYTES = 128
MAX_EVENT_REPLAY = 128
DEFAULT_EVENT_RETENTION = 512
MAX_SUBSCRIBER_BACKLOG = 256

@dataclass(frozen=True)
class FabricError(Exception):
    """Structured error returned over the Fabric protocol."""

    code: str
    title: str
    explanation: str
    detail: str = ""
    retryable: bool = False
    change_state: str = "none"
    recovery_actions: tuple[str, ...] = field(default_factory=tuple)

    def __str__(self) -> str:
        return f"{self.code}: {self.explanation}"

    def to_dict(self) -> dict[str, Any]:
        error: dict[str, Any] = {
            "code": self.code,
            "title": self.title,
            "explanation": self.explanation,
            "detail": self.detail,
            "retryable": self.retryable,
            "changeState": self.change_state,
        }
        if self.recovery_actions:
            error["recoveryActions"] = list(self.recovery_actions)
        return error

@dataclass(frozen=True)
class RpcRequest:
    request_id: str
    method: str
    params: Mapping[str, Any]

@dataclass(frozen=True)
class FixedArgvCommand:
    """A code-owned process invocation whose argv cannot be extended by RPC data.

    Providers may construct these constants in Python code. RPC arguments belong
    in a typed stdin payload or another provider-owned channel; they are never
    appended to this vector and never interpreted by a shell.
    """

    executable: str
    arguments: tuple[str, ...] = field(default_factory=tuple)

    def __post_init__(self) -> None:
        if not isinstance(self.executable, str) or not self.executable:
            raise ValueError("fixed argv executable must be a non-empty string")
        # Linux-target helpers are POSIX-absolute. os.path.isabs rejects them on a Windows checkout.
        if not os.path.isabs(self.executable) and not posixpath.isabs(self.executable):
            raise ValueError("fixed argv executable must be an absolute path")
        if "\x00" in self.executable:
            raise ValueError("fixed argv executable contains NUL")
        if not isinstance(self.arguments, tuple):
            raise TypeError("fixed argv arguments must be an immutable tuple")
        for argument in self.arguments:
            if not isinstance(argument, str):
                raise TypeError("fixed argv arguments must be strings")
            if "\x00" in argument:
                raise ValueError("fixed argv argument contains NUL")

    @property
    def argv(self) -> tuple[str, ...]:
        return (self.executable, *self.arguments)

def run_fixed_argv(
    command: FixedArgvCommand,
    *,
    stdin_payload: Mapping[str, Any] | Sequence[Any] | None = None,
    timeout_seconds: float = 30.0,
) -> subprocess.CompletedProcess[str]:
    """Run an immutable argv vector without a shell.

    This helper is intentionally not reachable through provisional RPC. Domain
    providers must own the command constant and the typed input contract before
    using it.
    """

    if not isinstance(command, FixedArgvCommand):
        raise TypeError("run_fixed_argv requires a FixedArgvCommand")
    if timeout_seconds <= 0:
        raise ValueError("timeout_seconds must be positive")

    stdin_text = None
    if stdin_payload is not None:
        stdin_text = json.dumps(
            stdin_payload,
            ensure_ascii=False,
            allow_nan=False,
            separators=(",", ":"),
            sort_keys=True,
        )

    return subprocess.run(
        list(command.argv),
        check=False,
        input=stdin_text,
        text=True,
        capture_output=True,
        timeout=timeout_seconds,
        shell=False,
    )

def default_runtime_directory() -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise FabricError(
            "runtime.unavailable",
            "Fabric runtime directory is unavailable",
            "XDG_RUNTIME_DIR is not set, so Fabric cannot create an owner-scoped socket.",
            recovery_actions=("session.restart",),
        )
    return Path(runtime) / "omarchy"

def default_socket_path() -> Path:
    return default_runtime_directory() / "fabric.sock"

def default_state_directory() -> Path:
    state_home = os.environ.get("XDG_STATE_HOME")
    if state_home:
        return Path(state_home) / "omarchy" / "fabric"
    return Path.home() / ".local" / "state" / "omarchy" / "fabric"
