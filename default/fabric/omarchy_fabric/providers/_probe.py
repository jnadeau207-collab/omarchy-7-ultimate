"""Bounded fixed-argv probes used only for read-only real inventories."""

from __future__ import annotations

import asyncio
import json
import os
import signal
import subprocess
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from omarchy_fabric.models import FabricError, FixedArgvCommand

MAX_PROBE_BYTES = 256 * 1024
MAX_PROBE_SECONDS = 5.0


@dataclass(frozen=True)
class ProbeOutput:
    stdout: str
    stderr: str


ProbeRunner = Callable[[FixedArgvCommand], ProbeOutput]


def parse_probe_json(text: str) -> object:
    """Decode finite JSON while rejecting duplicate object keys."""

    def unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
        document: dict[str, object] = {}
        for key, value in pairs:
            if key in document:
                raise ValueError(f"probe JSON contains duplicate key: {key[:80]}")
            document[key] = value
        return document

    def reject_constant(value: str) -> object:
        raise ValueError(f"probe JSON contains non-finite number: {value}")

    return json.loads(text, object_pairs_hook=unique_object, parse_constant=reject_constant)


def run_probe(command: FixedArgvCommand) -> ProbeOutput:
    if not isinstance(command, FixedArgvCommand):
        raise TypeError("provider probes require a FixedArgvCommand")
    executable = Path(command.executable)
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise FileNotFoundError(command.executable)
    process = subprocess.Popen(
        list(command.argv),
        env={**os.environ, "LANG": "C", "LC_ALL": "C"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        shell=False,
        start_new_session=os.name == "posix",
    )
    assert process.stdout is not None and process.stderr is not None
    buffers = {"stdout": bytearray(), "stderr": bytearray()}
    total_bytes = 0
    lock = threading.Lock()
    overflow = threading.Event()

    def drain(name: str, stream: Any) -> None:
        nonlocal total_bytes
        while True:
            chunk = stream.read1(64 * 1024)
            if not chunk:
                return
            with lock:
                total_bytes += len(chunk)
                remaining = max(0, MAX_PROBE_BYTES + 1 - len(buffers[name]))
                buffers[name].extend(chunk[:remaining])
                if total_bytes > MAX_PROBE_BYTES:
                    overflow.set()

    readers = (
        threading.Thread(target=drain, args=("stdout", process.stdout), daemon=True),
        threading.Thread(target=drain, args=("stderr", process.stderr), daemon=True),
    )
    for reader in readers:
        reader.start()

    def terminate() -> None:
        if process.poll() is not None:
            return
        try:
            if os.name == "posix":
                os.killpg(process.pid, signal.SIGKILL)
            else:
                process.kill()
        except ProcessLookupError:
            pass

    deadline = time.monotonic() + MAX_PROBE_SECONDS
    timed_out = False
    while process.poll() is None:
        if overflow.is_set():
            terminate()
            break
        if time.monotonic() >= deadline:
            timed_out = True
            terminate()
            break
        overflow.wait(timeout=min(0.01, max(0.0, deadline - time.monotonic())))
    process.wait()
    for reader in readers:
        reader.join(timeout=1)
    process.stdout.close()
    process.stderr.close()
    if any(reader.is_alive() for reader in readers):
        raise RuntimeError("probe output reader did not terminate")
    if timed_out:
        raise TimeoutError(command.executable)
    if overflow.is_set() or total_bytes > MAX_PROBE_BYTES:
        raise ValueError("probe output exceeded 256 KiB")
    stdout = bytes(buffers["stdout"]).decode("utf-8", errors="strict")
    stderr = bytes(buffers["stderr"]).decode("utf-8", errors="replace")[:2000]
    if process.returncode != 0:
        raise subprocess.CalledProcessError(process.returncode, command.argv, stdout, stderr)
    return ProbeOutput(stdout=stdout, stderr=stderr)


async def invoke_probe(command: FixedArgvCommand, runner: ProbeRunner = run_probe) -> ProbeOutput:
    return await asyncio.to_thread(runner, command)


def probe_error(domain: str, error: Exception) -> FabricError:
    if isinstance(error, FileNotFoundError):
        return FabricError(
            "provider.dependency-missing",
            f"{domain.title()} inventory is unavailable",
            "The fixed read-only system probe is not installed.",
            detail=str(error)[:2000],
            retryable=True,
            recovery_actions=("provider.install-dependency",),
        )
    if isinstance(error, TimeoutError):
        return FabricError(
            "provider.probe-timeout",
            f"{domain.title()} inventory timed out",
            "The fixed read-only system probe did not finish within five seconds.",
            retryable=True,
            recovery_actions=("provider.retry",),
        )
    if isinstance(error, subprocess.CalledProcessError):
        return FabricError(
            "provider.probe-failed",
            f"{domain.title()} inventory failed",
            "The fixed read-only system probe returned a failure status.",
            detail=f"exit status {error.returncode}",
            retryable=True,
            recovery_actions=("provider.retry",),
        )
    return FabricError(
        "provider.probe-invalid",
        f"{domain.title()} inventory is invalid",
        "The read-only system probe returned data that cannot be trusted.",
        detail=str(error)[:2000],
        retryable=True,
        recovery_actions=("provider.retry",),
    )
