from __future__ import annotations

import asyncio
import json
import socket
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from helper import DaemonProcess, hello, raw_request

from omarchy_fabric.models import MAX_FRAME_BYTES, PROTOCOL_NAME, FabricError
from omarchy_fabric.daemon import ClientConnection


class DaemonRpcTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.daemon = DaemonProcess(Path(self.temporary.name), event_retention=32)
        self.daemon.start()

    def tearDown(self) -> None:
        self.daemon.stop()
        self.temporary.cleanup()

    async def test_health_version_and_owner_only_socket(self) -> None:
        client = await self.daemon.client()
        try:
            version = await client.request("version")
            health = await client.request("health")
            self.assertEqual(version["protocol"], PROTOCOL_NAME)
            self.assertEqual(version["version"], 0)
            self.assertEqual(health["status"], "healthy")
            self.assertEqual(health["database"]["journalMode"], "wal")
            self.assertTrue(health["socket"]["ownerOnly"])
            self.assertEqual(stat.S_IMODE(self.daemon.socket_path.stat().st_mode), 0o600)
        finally:
            await client.close()

    async def test_missing_or_unreadable_peer_credentials_fail_closed(self) -> None:
        writer = mock.Mock()
        writer.get_extra_info.return_value = None
        connection = ClientConnection(mock.Mock(), mock.Mock(), writer)
        self.assertFalse(connection._peer_is_owner())

        peer_socket = mock.Mock()
        peer_socket.getsockopt.side_effect = OSError("credentials unavailable")
        writer.get_extra_info.return_value = peer_socket
        self.assertFalse(connection._peer_is_owner())

    async def test_hello_is_required_and_version_range_is_checked(self) -> None:
        response, _reader, writer = await raw_request(
            self.daemon.socket_path,
            {
                "protocol": PROTOCOL_NAME,
                "id": "health-before-hello",
                "method": "health",
                "params": {},
            },
        )
        self.assertEqual(response["error"]["code"], "rpc.hello-required")
        writer.close()
        await writer.wait_closed()

        incompatible = hello("bad-version")
        incompatible["params"]["minVersion"] = 5
        incompatible["params"]["maxVersion"] = 6
        response, reader, writer = await raw_request(self.daemon.socket_path, incompatible)
        self.assertEqual(response["error"]["code"], "rpc.incompatible-version")
        writer.write(json.dumps(hello("good-version")).encode() + b"\n")
        await writer.drain()
        accepted = json.loads(await asyncio.wait_for(reader.readline(), timeout=3))
        self.assertEqual(accepted["result"]["version"], 0)
        writer.close()
        await writer.wait_closed()

    async def test_malformed_frame_recovers_and_oversized_frame_closes(self) -> None:
        response, reader, writer = await raw_request(self.daemon.socket_path, b"{broken\n")
        self.assertEqual(response["error"]["code"], "rpc.invalid-json")
        writer.write(json.dumps(hello()).encode() + b"\n")
        await writer.drain()
        accepted = json.loads(await asyncio.wait_for(reader.readline(), timeout=3))
        self.assertIn("result", accepted)
        writer.close()
        await writer.wait_closed()

        reader, writer = await asyncio.open_unix_connection(
            str(self.daemon.socket_path),
            limit=MAX_FRAME_BYTES + 1,
        )
        writer.write(b'{"payload":"' + (b"x" * MAX_FRAME_BYTES) + b'"}\n')
        await writer.drain()
        response = json.loads(await asyncio.wait_for(reader.readline(), timeout=3))
        self.assertEqual(response["error"]["code"], "rpc.frame-too-large")
        self.assertEqual(await asyncio.wait_for(reader.read(), timeout=3), b"")
        writer.close()
        await writer.wait_closed()

    async def test_request_ids_cannot_repeat_on_one_connection(self) -> None:
        response, reader, writer = await raw_request(self.daemon.socket_path, hello("same-id"))
        self.assertIn("result", response)
        writer.write(
            json.dumps(
                {
                    "protocol": PROTOCOL_NAME,
                    "id": "same-id",
                    "method": "health",
                    "params": {},
                }
            ).encode()
            + b"\n"
        )
        await writer.drain()
        duplicate = json.loads(await asyncio.wait_for(reader.readline(), timeout=3))
        self.assertEqual(duplicate["error"]["code"], "rpc.duplicate-id")
        writer.close()
        await writer.wait_closed()

    async def test_fake_provider_idempotency_survives_reconnect(self) -> None:
        client = await self.daemon.client()
        registration = await client.request(
            "provider.register",
            {
                "provider": "fake.counter",
                "version": "v0",
                "actions": {"count": {"kind": "counter"}},
            },
        )
        self.assertEqual(registration["disposition"], "registered")
        first = await client.request(
            "provider.invoke",
            {
                "provider": "fake.counter",
                "action": "count",
                "arguments": {"value": 1},
                "idempotencyKey": "stable-key",
            },
        )
        self.assertEqual(first["value"]["count"], 1)
        self.assertFalse(first["idempotency"]["replayed"])
        await client.close()

        client = await self.daemon.client("reconnected-test")
        try:
            replay = await client.request(
                "provider.invoke",
                {
                    "provider": "fake.counter",
                    "action": "count",
                    "arguments": {"value": 1},
                    "idempotencyKey": "stable-key",
                },
            )
            self.assertEqual(replay["value"]["count"], 1)
            self.assertTrue(replay["idempotency"]["replayed"])
            with self.assertRaises(FabricError) as caught:
                await client.request(
                    "provider.invoke",
                    {
                        "provider": "fake.counter",
                        "action": "count",
                        "arguments": {"value": 2},
                        "idempotencyKey": "stable-key",
                    },
                )
            self.assertEqual(caught.exception.code, "operation.idempotency-conflict")
        finally:
            await client.close()

    async def test_concurrent_clients_receive_their_own_results(self) -> None:
        owner = await self.daemon.client("provider-owner")
        await owner.request(
            "provider.register",
            {
                "provider": "fake.concurrent",
                "version": "v0",
                "actions": {"echo": {"kind": "delay-echo", "milliseconds": 20}},
            },
        )

        async def invoke(number: int) -> int:
            client = await self.daemon.client(f"concurrent-{number}")
            try:
                result = await client.request(
                    "provider.invoke",
                    {
                        "provider": "fake.concurrent",
                        "action": "echo",
                        "arguments": {"number": number},
                        "idempotencyKey": f"concurrent-{number}",
                    },
                )
                return result["value"]["arguments"]["number"]
            finally:
                await client.close()

        try:
            results = await asyncio.gather(*(invoke(number) for number in range(16)))
            self.assertEqual(sorted(results), list(range(16)))
        finally:
            await owner.close()

    async def test_live_events_and_bounded_replay(self) -> None:
        client = await self.daemon.client()
        try:
            await client.request(
                "provider.register",
                {
                    "provider": "fake.events",
                    "version": "v0",
                    "actions": {"echo": {"kind": "echo"}},
                },
            )
            subscription = await client.request(
                "events.subscribe",
                {"topics": ["provider.invocation-finished"]},
            )
            self.assertEqual(subscription["replay"], [])
            intruder = await self.daemon.client("other-connection")
            try:
                not_removed = await intruder.request(
                    "events.unsubscribe",
                    {"subscriptionId": subscription["subscriptionId"]},
                )
                self.assertFalse(not_removed["removed"])
            finally:
                await intruder.close()
            await client.request(
                "provider.invoke",
                {
                    "provider": "fake.events",
                    "action": "echo",
                    "arguments": {"value": 1},
                    "idempotencyKey": "event-live",
                },
            )
            event = await client.next_event()
            self.assertEqual(event["topic"], "provider.invocation-finished")
            self.assertEqual(event["payload"]["status"], "succeeded")
            removed = await client.request(
                "events.unsubscribe",
                {"subscriptionId": subscription["subscriptionId"]},
            )
            self.assertTrue(removed["removed"])

            starting_cursor = event["sequence"]
            for number in range(4):
                await client.request(
                    "provider.invoke",
                    {
                        "provider": "fake.events",
                        "action": "echo",
                        "arguments": {"number": number},
                        "idempotencyKey": f"event-replay-{number}",
                    },
                )
            with self.assertRaises(FabricError) as caught:
                await client.request(
                    "events.subscribe",
                    {
                        "topics": ["provider.invocation-finished"],
                        "after": starting_cursor,
                        "limit": 2,
                    },
                )
            self.assertEqual(caught.exception.code, "events.replay-limit")
            replay = await client.request(
                "events.subscribe",
                {
                    "topics": ["provider.invocation-finished"],
                    "after": starting_cursor,
                    "limit": 4,
                },
            )
            self.assertEqual(len(replay["replay"]), 4)
        finally:
            await client.close()

    async def test_connection_subscription_count_is_bounded(self) -> None:
        client = await self.daemon.client()
        try:
            for _index in range(32):
                await client.request("events.subscribe", {"topics": ["test.event"]})
            with self.assertRaises(FabricError) as caught:
                await client.request("events.subscribe", {"topics": ["test.event"]})
            self.assertEqual(caught.exception.code, "events.subscription-limit")
            health = await client.request("health")
            self.assertEqual(health["events"]["subscriptions"], 32)
        finally:
            await client.close()

    async def test_unknown_method_cannot_execute_a_command(self) -> None:
        client = await self.daemon.client()
        try:
            with self.assertRaises(FabricError) as caught:
                await client.request(
                    "exec",
                    {"command": "touch /tmp/fabric-must-not-exist"},
                )
            self.assertEqual(caught.exception.code, "rpc.method-not-found")
            with self.assertRaises(FabricError) as caught:
                await client.request(
                    "provider.register",
                    {
                        "provider": "fake.command",
                        "version": "v0",
                        "actions": {"run": {"kind": "exec", "argv": ["/bin/true"]}},
                    },
                )
            self.assertEqual(caught.exception.code, "provider.invalid-definition")
        finally:
            await client.close()

    async def test_provider_and_idempotency_survive_graceful_restart(self) -> None:
        client = await self.daemon.client()
        await client.request(
            "provider.register",
            {
                "provider": "fake.restart",
                "version": "v0",
                "actions": {"count": {"kind": "counter"}},
            },
        )
        first = await client.request(
            "provider.invoke",
            {
                "provider": "fake.restart",
                "action": "count",
                "arguments": {},
                "idempotencyKey": "restart-key",
            },
        )
        await client.close()
        self.daemon.stop()
        self.assertFalse(self.daemon.socket_path.exists())
        self.daemon.start()
        client = await self.daemon.client("after-restart")
        try:
            providers = await client.request("provider.list")
            self.assertEqual(providers["providers"][0]["provider"], "fake.restart")
            replay = await client.request(
                "provider.invoke",
                {
                    "provider": "fake.restart",
                    "action": "count",
                    "arguments": {},
                    "idempotencyKey": "restart-key",
                },
            )
            self.assertEqual(replay["value"], first["value"])
            self.assertTrue(replay["idempotency"]["replayed"])
        finally:
            await client.close()

    async def test_crash_marks_inflight_idempotency_unknown_instead_of_rerunning(self) -> None:
        client = await self.daemon.client()
        await client.request(
            "provider.register",
            {
                "provider": "fake.interrupted",
                "version": "v0",
                "actions": {"wait": {"kind": "delay-echo", "milliseconds": 1000}},
            },
        )
        invocation = asyncio.create_task(
            client.request(
                "provider.invoke",
                {
                    "provider": "fake.interrupted",
                    "action": "wait",
                    "arguments": {"value": "must-not-rerun"},
                    "idempotencyKey": "interrupted-key",
                },
            )
        )
        await asyncio.sleep(0.15)
        self.daemon.crash()
        with self.assertRaises(FabricError) as disconnected:
            await invocation
        self.assertEqual(disconnected.exception.code, "daemon.disconnected")
        await client.close()

        self.daemon.start()
        client = await self.daemon.client("crash-reconciliation")
        try:
            with self.assertRaises(FabricError) as interrupted:
                await client.request(
                    "provider.invoke",
                    {
                        "provider": "fake.interrupted",
                        "action": "wait",
                        "arguments": {"value": "must-not-rerun"},
                        "idempotencyKey": "interrupted-key",
                    },
                )
            self.assertEqual(interrupted.exception.code, "operation.interrupted")
            self.assertEqual(interrupted.exception.change_state, "unknown")
        finally:
            await client.close()

    async def test_graceful_shutdown_finishes_inflight_idempotency_before_closing_database(self) -> None:
        client = await self.daemon.client()
        await client.request(
            "provider.register",
            {
                "provider": "fake.graceful",
                "version": "v0",
                "actions": {"wait": {"kind": "delay-echo", "milliseconds": 300}},
            },
        )
        invocation = asyncio.create_task(
            client.request(
                "provider.invoke",
                {
                    "provider": "fake.graceful",
                    "action": "wait",
                    "arguments": {"value": "finish-before-close"},
                    "idempotencyKey": "graceful-key",
                },
            )
        )
        await asyncio.sleep(0.05)
        await asyncio.to_thread(self.daemon.stop)
        with self.assertRaises(FabricError) as disconnected:
            await invocation
        self.assertEqual(disconnected.exception.code, "daemon.disconnected")
        await client.close()

        self.daemon.start()
        client = await self.daemon.client("graceful-reconciliation")
        try:
            replay = await client.request(
                "provider.invoke",
                {
                    "provider": "fake.graceful",
                    "action": "wait",
                    "arguments": {"value": "finish-before-close"},
                    "idempotencyKey": "graceful-key",
                },
            )
            self.assertTrue(replay["idempotency"]["replayed"])
            self.assertEqual(replay["value"]["arguments"]["value"], "finish-before-close")
        finally:
            await client.close()

    async def test_stale_owned_socket_is_recovered(self) -> None:
        self.daemon.stop()
        stale = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        stale.bind(str(self.daemon.socket_path))
        stale.close()
        self.assertTrue(self.daemon.socket_path.exists())
        self.daemon.start()
        client = await self.daemon.client()
        try:
            health = await client.request("health")
            self.assertEqual(health["status"], "healthy")
        finally:
            await client.close()


if __name__ == "__main__":
    unittest.main()
