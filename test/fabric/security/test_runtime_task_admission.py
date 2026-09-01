from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "default" / "fabric"))

from omarchy_fabric.daemon import DaemonConfig, FabricDaemon
from omarchy_fabric.managed_runtime import ManagedRuntime
from omarchy_fabric.managed_work import Actor, ManagedWorkPlane
from omarchy_fabric.managed_work.plane import SANDBOX_CAPABILITIES
from omarchy_fabric.models import FabricError
from omarchy_fabric.security.principal import PrincipalKind
from omarchy_fabric.security.task_admission import PeerIdentity, TaskEndpointBinding
from sandbox.builder import GrantTokenBind
from sandbox.runner import IsolatedRun

ACTOR = Actor("principal.test", "session.one")
INSPECT_CAPABILITY = next(iter(SANDBOX_CAPABILITIES))


def inspect_intent() -> dict[str, object]:
    return {"goal": "inventory", "readOnly": True, "capability": INSPECT_CAPABILITY}


def budget() -> dict[str, object]:
    return {"timeSeconds": 600, "outputBytes": 1_048_576, "costMicrounits": 50_000, "network": False}


def peer(**overrides) -> PeerIdentity:
    value = {
        "uid": 1000,
        "pid": 4242,
        "unit": "omarchy-fabric-task-task.one.scope",
        "cgroup": "/user.slice/user-1000.slice/app.slice/omarchy-fabric-task-task.one.scope",
    }
    value.update(overrides)
    return PeerIdentity(**value)


class FakeTaskHost:
    def __init__(self, daemon: FabricDaemon) -> None:
        self.daemon = daemon
        self.identity = (18, 9001)
        self.opened: list[Path] = []
        self.closed: list[Path] = []

    def require_task_socket_path(self, socket_path: Path) -> Path:
        return self.daemon.require_task_socket_path(socket_path)

    def open_task_endpoint(self, socket_path: Path) -> tuple[int, int]:
        path = self.require_task_socket_path(socket_path)
        self.opened.append(path)
        return self.identity

    def close_task_endpoint(self, socket_path: Path) -> None:
        self.closed.append(socket_path)

    def register_task_sandbox(self, binding: TaskEndpointBinding, grant_token: str) -> None:
        self.daemon.register_task_sandbox(binding, grant_token)

    def revoke_task_sandbox(self, task_id: str) -> None:
        self.daemon.revoke_task_sandbox(task_id)

    def read_sandbox_identity(self, pid: int) -> PeerIdentity:
        return peer(pid=pid, uid=self.daemon.daemon_uid)


class RuntimeTaskAdmissionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.plane = ManagedWorkPlane(Path(self.temporary.name) / "managed-work.db").open()
        self.daemon = FabricDaemon(
            DaemonConfig(
                socket_path=Path("unused-runtime.sock"),
                database_path=Path("unused-runtime.db"),
                typed_providers=(),
            )
        )
        self.host = FakeTaskHost(self.daemon)
        self.hello_results: dict[str, object] = {}

    def tearDown(self) -> None:
        self.plane.close()
        self.temporary.cleanup()

    def _connection(self, *, pid: int) -> SimpleNamespace:
        identity = self.host.read_sandbox_identity(pid)
        return SimpleNamespace(
            connection_id=f"task-hello.{pid}",
            hello_complete=False,
            principal=None,
            peer_uid=identity.uid,
            peer_pid=identity.pid,
            peer_unit=identity.unit,
            peer_cgroup=identity.cgroup,
            endpoint_scope="task",
            socket_dev=self.host.identity[0],
            socket_ino=self.host.identity[1],
        )

    def _runner(self, spec, *, on_spawn=None, protected_home=None, **kwargs):
        self.assertIsInstance(spec.grant_token, GrantTokenBind)
        token = spec.grant_token.source.read_text(encoding="utf-8")
        self.assertGreaterEqual(len(token), 16)
        self.assertNotIn("GRANT_TOKEN", spec.environment)
        if on_spawn is not None:
            on_spawn(4242)
        sandbox = self._connection(pid=4242)
        self.daemon.attach_task_connection(sandbox, self.host.identity)
        accepted = self.daemon._hello(
            sandbox,
            {"client": "task-client", "minVersion": 0, "maxVersion": 0, "grantToken": token},
        )
        outsider = self._connection(pid=9999)
        self.daemon.attach_task_connection(outsider, self.host.identity)
        try:
            self.daemon._hello(
                outsider,
                {"client": "task-client", "minVersion": 0, "maxVersion": 0, "grantToken": token},
            )
            denied = None
        except FabricError as error:
            denied = error
        self.hello_results["accepted"] = accepted
        self.hello_results["denied"] = denied
        return IsolatedRun(0, "{}", "", ("/usr/bin/bwrap", "--unshare-all"), {"ok": True})

    def test_sandbox_path_becomes_task_and_non_sandbox_is_denied(self) -> None:
        runtime = ManagedRuntime(
            self.plane,
            task_host=self.host,
            identity_reader=self.host.read_sandbox_identity,
            isolated_runner=self._runner,
        )
        task = runtime.create_task(
            ACTOR,
            {
                "title": "Sandbox admit",
                "intent": inspect_intent(),
                "contextIds": [],
                "budget": budget(),
                "idempotencyKey": "task.runtime-admit",
            },
        )
        runtime._run_sandbox(task["taskId"], {"provider": "provider.managed-runtime"})
        accepted = self.hello_results["accepted"]
        denied = self.hello_results["denied"]
        self.assertEqual(accepted["principal"]["kind"], PrincipalKind.TASK.value)
        self.assertEqual(accepted["principal"]["taskId"], task["taskId"])
        self.assertIsInstance(denied, FabricError)
        self.assertEqual(denied.code, "task-admission.denied")
        self.assertTrue(self.host.opened)
        self.assertTrue(self.host.closed)
        self.assertEqual(self.daemon.task_admissions.binding_count, 0)


if __name__ == "__main__":
    unittest.main()
