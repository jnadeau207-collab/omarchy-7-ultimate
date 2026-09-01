from __future__ import annotations

import os
import socket
import struct
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from omarchy_fabric.managed_work import StableOwnerSessionStore
from omarchy_fabric.models import FabricError
from omarchy_fabric.security import EndpointAdmission, PrincipalKind
from omarchy_fabric.security.errors import SecurityValidationError

if os.name != "nt":
    from omarchy_fabric.daemon import ClientConnection, DaemonConfig, FabricDaemon

class StableOwnershipTests(unittest.TestCase):
    def test_owner_survives_reconnect_and_restart_while_sessions_do_not(self) -> None:
        current = [datetime(2026, 8, 27, 12, 0, tzinfo=timezone.utc)]
        first_store = StableOwnerSessionStore(1000, clock=lambda: current[0])
        admission = EndpointAdmission("fabric.owner-rpc", PrincipalKind.SHELL)
        first, first_credential = first_store.issue(1000, admission)
        second, _ = first_store.issue(1000, admission)
        restarted, _ = StableOwnerSessionStore(1000, clock=lambda: current[0]).issue(1000, admission)

        self.assertEqual("account.uid.1000", first.principal_id)
        self.assertEqual(first.principal_id, second.principal_id)
        self.assertEqual(first.principal_id, restarted.principal_id)
        self.assertNotEqual(first.session_id, second.session_id)
        self.assertNotEqual(first.session_id, restarted.session_id)
        self.assertEqual(first, first_store.resolve(1000, first_credential))

        with self.assertRaises(SecurityValidationError) as wrong_owner:
            first_store.resolve(1001, first_credential)
        self.assertEqual("principal.peer-owner", wrong_owner.exception.code)
        current[0] += timedelta(hours=9)
        with self.assertRaises(SecurityValidationError) as expired:
            first_store.require_active(first)
        self.assertEqual("principal.expired", expired.exception.code)
        self.assertFalse(first_store.is_active(first.session_id))

    def test_wrong_uid_and_session_capacity_fail_closed(self) -> None:
        store = StableOwnerSessionStore(2000, maximum_active_sessions=1)
        admission = EndpointAdmission("fabric.owner-rpc", PrincipalKind.SHELL)
        with self.assertRaises(SecurityValidationError) as wrong:
            store.issue(2001, admission)
        self.assertEqual("principal.peer-owner", wrong.exception.code)
        principal, _ = store.issue(2000, admission)
        with self.assertRaises(SecurityValidationError) as capacity:
            store.issue(2000, admission)
        self.assertEqual("principal.capacity", capacity.exception.code)
        store.revoke(principal.session_id)
        replacement, _ = store.issue(2000, admission)
        self.assertEqual(principal.principal_id, replacement.principal_id)

    @unittest.skipIf(os.name == "nt", "daemon imports require the Linux runtime")
    def test_hello_label_and_rpc_owner_claims_cannot_select_account_owner(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            daemon = FabricDaemon(
                DaemonConfig(
                    socket_path=root / "fabric.sock",
                    database_path=root / "fabric.db",
                    typed_providers=(),
                )
            )
            daemon.daemon_uid = 4242
            daemon.session_bindings = StableOwnerSessionStore(4242)
            first_connection = SimpleNamespace(
                connection_id="one",
                hello_complete=False,
                principal=None,
                peer_uid=4242,
            )
            second_connection = SimpleNamespace(
                connection_id="two",
                hello_complete=False,
                principal=None,
                peer_uid=4242,
            )
            first = daemon._hello(
                first_connection,
                {"client": "friendly-label", "minVersion": 0, "maxVersion": 0},
            )
            second = daemon._hello(
                second_connection,
                {"client": "different-label", "minVersion": 0, "maxVersion": 0},
            )
            self.assertEqual("account.uid.4242", first["principal"]["ownerId"])
            self.assertEqual(first["principal"]["id"], second["principal"]["id"])
            self.assertNotEqual(first["principal"]["sessionId"], second["principal"]["sessionId"])

            forged = SimpleNamespace(
                connection_id="forged",
                hello_complete=False,
                principal=None,
                peer_uid=4242,
            )
            with self.assertRaises(FabricError) as claim:
                daemon._hello(
                    forged,
                    {
                        "client": "label",
                        "minVersion": 0,
                        "maxVersion": 0,
                        "ownerId": "account.uid.1",
                    },
                )
            self.assertEqual("rpc.invalid-params", claim.exception.code)
            self.assertFalse(forged.hello_complete)

            wrong_peer = SimpleNamespace(
                connection_id="wrong",
                hello_complete=False,
                principal=None,
                peer_uid=7,
            )
            with self.assertRaises(FabricError) as denied:
                daemon._hello(
                    wrong_peer,
                    {"client": "label", "minVersion": 0, "maxVersion": 0},
                )
            self.assertEqual("principal.peer-owner", denied.exception.code)

    @unittest.skipIf(os.name == "nt", "SO_PEERCRED requires the Linux runtime")
    def test_peer_credentials_are_exact_unsigned_and_reset_after_failure(self) -> None:
        high_uid = 2**31 + 17
        daemon = SimpleNamespace(daemon_uid=high_uid)
        peer_socket = mock.Mock()
        peer_socket.getsockopt.return_value = struct.pack("iII", 123, high_uid, high_uid)
        writer = mock.Mock()
        writer.get_extra_info.return_value = peer_socket
        connection = ClientConnection(daemon, mock.Mock(), writer)
        with mock.patch.object(socket, "SO_PEERCRED", 17, create=True):
            self.assertTrue(connection._peer_is_owner())
            self.assertEqual(high_uid, connection.peer_uid)
            peer_socket.getsockopt.return_value = struct.pack("iII", 123, high_uid - 1, high_uid)
            self.assertFalse(connection._peer_is_owner())
            self.assertIsNone(connection.peer_uid)
            peer_socket.getsockopt.return_value = b"short"
            self.assertFalse(connection._peer_is_owner())
            self.assertIsNone(connection.peer_uid)

if __name__ == "__main__":
    unittest.main()
