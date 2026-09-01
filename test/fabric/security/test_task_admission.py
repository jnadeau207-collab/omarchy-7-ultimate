from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "default" / "fabric"))

from omarchy_fabric.daemon import DaemonConfig, FabricDaemon
from omarchy_fabric.models import FabricError
from omarchy_fabric.security.errors import SecurityValidationError
from omarchy_fabric.security.principal import PrincipalKind
from omarchy_fabric.security.task_admission import (
    TASK_ENDPOINT_ID,
    PeerIdentity,
    TaskAdmissionAuthority,
    TaskEndpointBinding,
    read_peer_identity,
)


def peer(**overrides) -> PeerIdentity:
    value = {
        "uid": 1000,
        "pid": 4242,
        "unit": "omarchy-fabric-task-task.one.scope",
        "cgroup": "/user.slice/user-1000.slice/app.slice/omarchy-fabric-task-task.one.scope",
    }
    value.update(overrides)
    return PeerIdentity(**value)


def binding(**overrides) -> TaskEndpointBinding:
    value = {
        "task_id": "task.one",
        "uid": 1000,
        "pid": 4242,
        "unit": "omarchy-fabric-task-task.one.scope",
        "cgroup": "/user.slice/user-1000.slice/app.slice/omarchy-fabric-task-task.one.scope",
        "socket_dev": 18,
        "socket_ino": 9001,
    }
    value.update(overrides)
    return TaskEndpointBinding(**value)


class TaskAdmissionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.authority = TaskAdmissionAuthority()
        self.token = "task-grant-token-one-value"

    def test_matching_sandbox_is_admitted_as_task(self) -> None:
        self.authority.register(binding(), self.token)
        admission = self.authority.admit(
            peer(),
            socket_dev=18,
            socket_ino=9001,
            grant_token=self.token,
        )
        self.assertEqual(admission.kind, PrincipalKind.TASK)
        self.assertEqual(admission.task_id, "task.one")
        self.assertEqual(admission.endpoint_id, TASK_ENDPOINT_ID)

    def test_owner_rpc_cannot_be_a_task_binding(self) -> None:
        with self.assertRaisesRegex(SecurityValidationError, "owner RPC"):
            binding(endpoint_id="fabric.owner-rpc")

    def test_uid_alone_or_socket_alone_is_not_enough(self) -> None:
        self.authority.register(binding(), self.token)
        with self.assertRaisesRegex(SecurityValidationError, "matches"):
            self.authority.admit(peer(pid=9999), socket_dev=18, socket_ino=9001, grant_token=self.token)
        with self.assertRaisesRegex(SecurityValidationError, "matches"):
            self.authority.admit(peer(), socket_dev=18, socket_ino=1, grant_token=self.token)
        with self.assertRaisesRegex(SecurityValidationError, "matches"):
            self.authority.admit(peer(unit="other.scope"), socket_dev=18, socket_ino=9001, grant_token=self.token)
        with self.assertRaisesRegex(SecurityValidationError, "matches"):
            self.authority.admit(peer(), socket_dev=18, socket_ino=9001, grant_token="wrong-grant-token-value")

    def test_unregistered_connection_is_denied(self) -> None:
        with self.assertRaisesRegex(SecurityValidationError, "matches"):
            self.authority.admit(peer(), socket_dev=18, socket_ino=9001, grant_token=self.token)

    def test_revoked_binding_cannot_be_reused_and_pid_cannot_be_shared(self) -> None:
        self.authority.register(binding(), self.token)
        self.authority.revoke("task.one")
        with self.assertRaisesRegex(SecurityValidationError, "matches"):
            self.authority.admit(peer(), socket_dev=18, socket_ino=9001, grant_token=self.token)
        self.authority.register(binding(), self.token)
        with self.assertRaisesRegex(SecurityValidationError, "already owns this process"):
            self.authority.register(binding(task_id="task.two", socket_ino=9002), "other-grant-token-value")

    def test_identity_reader_rejects_stale_presented_peer(self) -> None:
        authority = TaskAdmissionAuthority(identity_reader=lambda pid: peer(pid=pid, unit="live.scope"))
        authority.register(binding(), self.token)
        with self.assertRaisesRegex(SecurityValidationError, "no longer matches"):
            authority.admit(peer(), socket_dev=18, socket_ino=9001, grant_token=self.token)

    def test_proc_identity_reader_uses_kernel_files(self) -> None:
        root = Path(__file__).resolve().parent
        proc = root / "_proc_task_admission"
        process = proc / "4242"
        process.mkdir(parents=True, exist_ok=True)
        (process / "status").write_text("Name:\tagent\nUid:\t1000\t1000\t1000\t1000\n", encoding="utf-8")
        (process / "cgroup").write_text(
            "0::/user.slice/user-1000.slice/app.slice/omarchy-fabric-task-task.one.scope\n",
            encoding="utf-8",
        )
        try:
            identity = read_peer_identity(4242, proc_root=proc)
            self.assertEqual(identity.uid, 1000)
            self.assertEqual(identity.unit, "omarchy-fabric-task-task.one.scope")
            self.assertTrue(identity.cgroup.endswith("omarchy-fabric-task-task.one.scope"))
        finally:
            (process / "status").unlink()
            (process / "cgroup").unlink()
            process.rmdir()
            proc.rmdir()


class OwnerRpcHelloAdmissionTests(unittest.TestCase):
    def test_owner_hello_is_always_shell_and_rejects_task_fields(self) -> None:
        daemon = FabricDaemon(
            DaemonConfig(
                socket_path=Path("unused-owner.sock"),
                database_path=Path("unused-owner.db"),
                typed_providers=(),
            )
        )
        connection = SimpleNamespace(
            connection_id="owner-hello",
            hello_complete=False,
            principal=None,
            peer_uid=daemon.daemon_uid,
            peer_pid=7,
            peer_unit="app.scope",
            peer_cgroup="/user.slice/app.scope",
            endpoint_scope="owner",
            socket_dev=1,
            socket_ino=1,
        )
        accepted = daemon._hello(
            connection,
            {"client": "owner-client", "minVersion": 0, "maxVersion": 0},
        )
        self.assertEqual(accepted["principal"]["kind"], "shell")
        self.assertNotIn("taskId", accepted["principal"])
        with self.assertRaises(FabricError) as extra:
            daemon._hello(
                SimpleNamespace(
                    connection_id="forged",
                    hello_complete=False,
                    principal=None,
                    peer_uid=daemon.daemon_uid,
                    endpoint_scope="owner",
                ),
                {
                    "client": "forged-task",
                    "minVersion": 0,
                    "maxVersion": 0,
                    "kind": "task",
                    "taskId": "task.one",
                },
            )
        self.assertEqual(extra.exception.code, "rpc.invalid-params")

    def test_task_hello_requires_a_registered_sandbox(self) -> None:
        daemon = FabricDaemon(
            DaemonConfig(
                socket_path=Path("unused-task.sock"),
                database_path=Path("unused-task.db"),
                typed_providers=(),
            )
        )
        token = "task-grant-token-hello-value"
        connection = SimpleNamespace(
            connection_id="task-hello",
            hello_complete=False,
            principal=None,
            peer_uid=daemon.daemon_uid,
            peer_pid=4242,
            peer_unit="omarchy-fabric-task-task.one.scope",
            peer_cgroup="/user.slice/user-1000.slice/app.slice/omarchy-fabric-task-task.one.scope",
            endpoint_scope="task",
            socket_dev=18,
            socket_ino=9001,
        )
        with self.assertRaises(FabricError) as denied:
            daemon._hello(
                connection,
                {"client": "task-client", "minVersion": 0, "maxVersion": 0, "grantToken": token},
            )
        self.assertEqual(denied.exception.code, "task-admission.denied")
        self.assertFalse(connection.hello_complete)
        daemon.task_admissions.register(
            binding(uid=daemon.daemon_uid),
            token,
        )
        accepted = daemon._hello(
            connection,
            {"client": "task-client", "minVersion": 0, "maxVersion": 0, "grantToken": token},
        )
        self.assertEqual(accepted["principal"]["kind"], "task")
        self.assertEqual(accepted["principal"]["taskId"], "task.one")
        self.assertEqual(accepted["principal"]["endpoint"], TASK_ENDPOINT_ID)
        self.assertTrue(connection.hello_complete)

    def test_owner_socket_cannot_be_opened_as_a_task_endpoint(self) -> None:
        daemon = FabricDaemon(
            DaemonConfig(
                socket_path=Path("fabric.sock"),
                database_path=Path("unused-task-path.db"),
                typed_providers=(),
            )
        )
        with self.assertRaisesRegex(SecurityValidationError, "owner RPC"):
            daemon.require_task_socket_path(Path("fabric.sock"))
        with self.assertRaisesRegex(SecurityValidationError, "owner RPC"):
            daemon.require_task_socket_path(daemon.config.socket_path)
        allowed = daemon.require_task_socket_path(Path("task.one.sock"))
        self.assertEqual(allowed.name, "task.one.sock")

    def test_task_accept_stamps_scope_and_socket_not_owner_rpc(self) -> None:
        daemon = FabricDaemon(
            DaemonConfig(
                socket_path=Path("fabric.sock"),
                database_path=Path("unused-task-stamp.db"),
                typed_providers=(),
            )
        )
        connection = SimpleNamespace(endpoint_scope="owner", socket_dev=None, socket_ino=None)
        daemon.attach_task_connection(connection, (18, 9001))
        self.assertEqual(connection.endpoint_scope, "task")
        self.assertEqual(connection.socket_dev, 18)
        self.assertEqual(connection.socket_ino, 9001)


if __name__ == "__main__":
    unittest.main()
