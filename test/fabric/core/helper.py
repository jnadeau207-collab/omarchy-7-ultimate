from __future__ import annotations

import asyncio
import json
import os
import socket
import stat
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FABRIC_ROOT = ROOT / "default" / "fabric"
if str(FABRIC_ROOT) not in sys.path:
    sys.path.insert(0, str(FABRIC_ROOT))

from omarchy_fabric.models import MAX_FRAME_BYTES, PROTOCOL_NAME
from omarchy_fabric.protocol import FabricClient


class DaemonProcess:
    def __init__(self, root: Path, *, event_retention: int = 512) -> None:
        self.root = root
        self.runtime = root / "runtime" / "omarchy"
        self.state = root / "state"
        self.socket_path = self.runtime / "fabric.sock"
        self.database_path = self.state / "fabric.db"
        self.event_retention = event_retention
        self.process: subprocess.Popen[str] | None = None

    def start(self) -> None:
        self.runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.state.mkdir(mode=0o700, parents=True, exist_ok=True)
        environment = os.environ.copy()
        existing = environment.get("PYTHONPATH")
        environment["PYTHONPATH"] = (
            str(FABRIC_ROOT) if not existing else f"{FABRIC_ROOT}{os.pathsep}{existing}"
        )
        self.process = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "omarchy_fabric.daemon",
                "--socket",
                str(self.socket_path),
                "--database",
                str(self.database_path),
                "--event-retention",
                str(self.event_retention),
            ],
            cwd=ROOT,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                stdout, stderr = self.process.communicate(timeout=1)
                raise AssertionError(
                    f"daemon exited {self.process.returncode}\nstdout:\n{stdout}\nstderr:\n{stderr}"
                )
            try:
                metadata = self.socket_path.stat()
                if stat.S_ISSOCK(metadata.st_mode):
                    probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    try:
                        probe.settimeout(0.1)
                        probe.connect(str(self.socket_path))
                        return
                    except (ConnectionRefusedError, FileNotFoundError, socket.timeout):
                        pass
                    finally:
                        probe.close()
            except FileNotFoundError:
                pass
            time.sleep(0.02)
        raise AssertionError("daemon did not create its socket")

    def stop(self) -> None:
        if self.process is None:
            return
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        stdout, stderr = self.process.communicate(timeout=1)
        if self.process.returncode != 0:
            raise AssertionError(
                f"daemon exited {self.process.returncode}\nstdout:\n{stdout}\nstderr:\n{stderr}"
            )
        self.process = None

    def crash(self) -> None:
        if self.process is None:
            return
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait(timeout=5)
        self.process.communicate(timeout=1)
        self.process = None

    async def client(self, name: str = "fabric-core-test") -> FabricClient:
        client = FabricClient(self.socket_path, client_name=name, request_timeout=3)
        await client.connect()
        return client


async def raw_request(
    socket_path: Path,
    message: dict[str, object] | bytes,
) -> tuple[dict[str, object], asyncio.StreamReader, asyncio.StreamWriter]:
    reader, writer = await asyncio.open_unix_connection(
        str(socket_path),
        limit=MAX_FRAME_BYTES + 1,
    )
    if isinstance(message, bytes):
        writer.write(message)
    else:
        writer.write(
            json.dumps(message, separators=(",", ":"), sort_keys=True).encode("utf-8") + b"\n"
        )
    await writer.drain()
    line = await asyncio.wait_for(reader.readline(), timeout=3)
    return json.loads(line), reader, writer


def hello(request_id: str = "hello-1") -> dict[str, object]:
    return {
        "protocol": PROTOCOL_NAME,
        "id": request_id,
        "method": "hello",
        "params": {"client": "raw-test", "minVersion": 0, "maxVersion": 0},
    }
