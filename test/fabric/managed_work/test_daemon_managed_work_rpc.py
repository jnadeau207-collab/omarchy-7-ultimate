from __future__ import annotations

import os
import socket
import tempfile
import time
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from omarchy_fabric.managed_work import Actor, ManagedWorkError, StableOwnerSessionStore
from omarchy_fabric.models import FabricError
from omarchy_fabric.security import EndpointAdmission, PrincipalKind

if os.name != "nt":
    from omarchy_fabric.daemon import DaemonConfig, FabricDaemon
    from omarchy_fabric.models import RpcRequest
    from omarchy_fabric.protocol import FabricClient


VIEWS = (
    "agent.overview",
    "agent.tasks",
    "agent.approvals",
    "agent.automations",
    "agent.activity",
    "agent.history",
    "agent.context",
    "agent.permissions",
    "agent.usage",
    "agent.providers",
    "agent.artifacts",
    "agent.troubleshooting",
)


def budget() -> dict[str, object]:
    return {
        "timeSeconds": 60,
        "outputBytes": 1024,
        "costMicrounits": 0,
        "network": False,
    }


@unittest.skipIf(os.name == "nt", "daemon imports require the Linux runtime")
class DaemonManagedWorkContractTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.daemon = FabricDaemon(
            DaemonConfig(
                socket_path=root / "fabric.sock",
                database_path=root / "fabric.db",
                typed_providers=(),
            )
        )
        self.daemon.database.open()
        self.daemon.managed_work.open()
        principal, _ = self.daemon.session_bindings.issue(
            self.daemon.daemon_uid,
            EndpointAdmission("fabric.owner-rpc", PrincipalKind.SHELL),
        )
        self.principal = principal
        self.connection = SimpleNamespace(hello_complete=True, principal=principal)

    async def asyncTearDown(self) -> None:
        await self.daemon.reference_operations.shutdown()
        self.daemon.events.close()
        self.daemon.managed_work.close()
        self.daemon.database.close()
        self.temporary.cleanup()

    async def request(self, method: str, params: dict[str, object]) -> object:
        return await self.daemon.dispatch(
            self.connection,
            RpcRequest(f"request-{time.time_ns()}", method, params),
        )

    async def test_one_closed_read_family_exposes_exactly_twelve_views(self) -> None:
        for view in VIEWS:
            with self.subTest(view=view):
                result = await self.request(
                    "managed-work.query",
                    {"version": "v0", "view": view, "limit": 10},
                )
                self.assertEqual("v0", result["schemaVersion"])
                self.assertEqual(view, result["view"])
                self.assertFalse(result["availability"]["executionAvailable"])

        rejected = (
            {"view": "agent.tasks"},
            {"version": "v1", "view": "agent.tasks"},
            {"version": "v0", "view": "agent.unknown"},
            {"version": "v0", "view": "agent.tasks", "limit": True},
            {"version": "v0", "view": "agent.tasks", "limit": 101},
            {"version": "v0", "view": "agent.tasks", "ownerId": "account.uid.1"},
            {"version": "v0", "view": "agent.tasks", "principalId": "account.uid.1"},
            {"version": "v0", "view": "agent.tasks", "sessionId": "session.forged"},
            {"version": "v0", "view": "agent.tasks", "actor": {}},
            {"version": "v0", "view": "agent.tasks", "argv": ["/bin/true"]},
            {"version": "v0", "view": "agent.tasks", "entityType": "task"},
            {"version": "v0", "view": "agent.tasks", "cursor": "x" * 1025},
        )
        for index, params in enumerate(rejected):
            with self.subTest(rejected=index):
                with self.assertRaises(FabricError):
                    await self.request("managed-work.query", params)

        for method in (
            "managed-work.run.start",
            "managed-work.automation.create",
            "managed-work.project",
            "managed-work.execute",
        ):
            with self.subTest(method=method):
                with self.assertRaises(FabricError) as unavailable:
                    await self.request(method, {})
                self.assertEqual("rpc.method-not-found", unavailable.exception.code)

    async def test_task_mutation_and_context_capture_rpcs(self) -> None:
        created = await self.request(
            "managed-work.task.create",
            {
                "version": "v0",
                "title": "RPC inventory",
                "intent": {"goal": "inventory"},
                "budget": budget(),
                "idempotencyKey": "task.rpc-create",
            },
        )
        self.assertEqual("draft", created["state"])
        listed = await self.request("managed-work.task.list", {"version": "v0", "limit": 10})
        self.assertTrue(any(item.get("task", {}).get("taskId") == created["taskId"] for item in listed["items"]))
        cancelled = await self.request(
            "managed-work.task.cancel",
            {"version": "v0", "taskId": created["taskId"], "expectedRevision": created["revision"]},
        )
        self.assertEqual("cancelled", cancelled["state"])
        captured = await self.request(
            "managed-work.context.capture",
            {
                "version": "v0",
                "source": "open-windows",
                "idempotencyKey": "context.rpc-windows",
                "snapshot": {
                    "windows": [{"class": "foot", "title": "term", "address": "0x1", "focused": True}],
                    "focus": {"class": "foot", "title": "term", "address": "0x1"},
                    "selection": {"text": ""},
                },
            },
        )
        self.assertEqual("open-windows", captured["source"])
        self.assertEqual(["foot"], [item["class"] for item in captured["content"]["windows"]])

    async def test_session_expiry_precedes_query_or_projection(self) -> None:
        current = [datetime(2026, 8, 27, 12, 0, tzinfo=timezone.utc)]
        sessions = StableOwnerSessionStore(self.daemon.daemon_uid, clock=lambda: current[0])
        principal, _ = sessions.issue(
            self.daemon.daemon_uid,
            EndpointAdmission("fabric.owner-rpc", PrincipalKind.SHELL),
        )
        self.daemon.session_bindings = sessions
        self.connection.principal = principal
        current[0] += timedelta(hours=9)
        with mock.patch.object(self.daemon.managed_projections, "refresh_providers") as refresh:
            with self.assertRaises(FabricError) as expired:
                await self.request(
                    "managed-work.query",
                    {"version": "v0", "view": "agent.providers"},
                )
        self.assertEqual("principal.expired", expired.exception.code)
        refresh.assert_not_called()

    async def test_oversized_single_record_returns_bounded_typed_error(self) -> None:
        actor = Actor(self.principal.principal_id, self.principal.session_id)
        with self.assertRaises(ManagedWorkError) as oversized:
            self.daemon.managed_work.capture_context(
                actor,
                source="focused-application",
                access_scope="principal",
                content={"chunks": ["x" * 15_000 for _ in range(4)]},
                sensitivity="personal",
                ttl_seconds=60,
                idempotency_key="context.oversized-rpc",
            )
        self.assertEqual("validation.query-item-capacity", oversized.exception.code)
        self.assertNotIn("xxxx", oversized.exception.detail)
        result = await self.request(
            "managed-work.query",
            {"version": "v0", "view": "agent.context", "limit": 1},
        )
        self.assertEqual([], result["items"])
        connection = self.daemon.managed_work.store.require_connection()
        self.assertEqual(0, connection.execute("SELECT COUNT(*) FROM contexts").fetchone()[0])
        self.assertEqual(0, connection.execute("SELECT COUNT(*) FROM idempotency").fetchone()[0])


@unittest.skipUnless(
    hasattr(socket, "SO_PEERCRED") and hasattr(os, "getuid"),
    "requires Linux SO_PEERCRED",
)
class DaemonManagedWorkMetalTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.config = DaemonConfig(
            socket_path=root / "runtime" / "fabric.sock",
            database_path=root / "state" / "fabric.db",
        )
        self.daemon = FabricDaemon(self.config)
        await self.daemon.start()
        self.clients: list[FabricClient] = []

    async def asyncTearDown(self) -> None:
        for client in self.clients:
            await client.close()
        if not self.daemon._stopped:
            await self.daemon.stop("test")
        self.temporary.cleanup()

    async def connect(self, label: str) -> tuple[FabricClient, dict[str, object]]:
        client = FabricClient(self.config.socket_path, client_name=label, request_timeout=4)
        hello = await client.connect()
        self.clients.append(client)
        return client, hello

    async def test_reconnect_restart_cursor_and_session_context_isolation(self) -> None:
        first_client, first_hello = await self.connect("first-label")
        first_principal = first_hello["principal"]
        actor = Actor(first_principal["id"], first_principal["sessionId"])
        now = time.time()
        principal_context = self.daemon.managed_work.capture_context(
            actor,
            source="focused-application",
            access_scope="principal",
            content={"title": "visible", "accessToken": "must-never-leak"},
            sensitivity="personal",
            ttl_seconds=600,
            idempotency_key="context.principal",
            now=now,
        )
        self.daemon.managed_work.capture_context(
            actor,
            source="focused-application",
            access_scope="session",
            content={"title": "old-session-only"},
            sensitivity="personal",
            ttl_seconds=600,
            idempotency_key="context.session",
            now=now,
        )
        for index in range(3):
            self.daemon.managed_work.create_task(
                actor,
                title=f"Durable task {index}",
                intent={"goal": "read-only inventory"},
                context_ids=[principal_context["contextId"]],
                budget=budget(),
                idempotency_key=f"task.durable-{index}",
                now=now + index,
            )
        original_context = await first_client.request(
            "managed-work.query",
            {"version": "v0", "view": "agent.context"},
        )
        self.assertEqual(2, len(original_context["items"]))
        self.assertNotIn("must-never-leak", str(original_context))
        page = await first_client.request(
            "managed-work.query",
            {"version": "v0", "view": "agent.tasks", "limit": 1},
        )
        self.assertIsNotNone(page["nextCursor"])
        await first_client.close()

        second_client, second_hello = await self.connect("forged-owner-label-account.uid.1")
        second_principal = second_hello["principal"]
        self.assertEqual(first_principal["id"], second_principal["id"])
        self.assertNotEqual(first_principal["sessionId"], second_principal["sessionId"])
        reconnected_context = await second_client.request(
            "managed-work.query",
            {"version": "v0", "view": "agent.context"},
        )
        self.assertEqual([principal_context["contextId"]], [item["contextId"] for item in reconnected_context["items"]])
        continued = await second_client.request(
            "managed-work.query",
            {
                "version": "v0",
                "view": "agent.tasks",
                "limit": 1,
                "cursor": page["nextCursor"],
            },
        )
        self.assertEqual(1, len(continued["items"]))
        for view in VIEWS:
            result = await second_client.request(
                "managed-work.query",
                {"version": "v0", "view": view, "limit": 10},
            )
            self.assertEqual(view, result["view"])
        provider_before = await second_client.request(
            "managed-work.query",
            {"version": "v0", "view": "agent.providers"},
        )
        self.assertTrue(provider_before["items"])
        revisions_before = {item["providerId"]: item["sourceRevision"] for item in provider_before["items"]}
        await second_client.close()
        await self.daemon.stop("restart-test")

        self.daemon = FabricDaemon(self.config)
        await self.daemon.start()
        restarted_client, restarted_hello = await self.connect("after-restart")
        self.assertEqual(first_principal["id"], restarted_hello["principal"]["id"])
        self.assertNotEqual(second_principal["sessionId"], restarted_hello["principal"]["sessionId"])
        tasks = await restarted_client.request(
            "managed-work.query",
            {"version": "v0", "view": "agent.tasks"},
        )
        self.assertEqual(3, len(tasks["items"]))
        provider_after = await restarted_client.request(
            "managed-work.query",
            {"version": "v0", "view": "agent.providers"},
        )
        for item in provider_after["items"]:
            self.assertGreaterEqual(item["sourceRevision"], revisions_before[item["providerId"]])

    async def test_reference_projection_is_verified_redacted_and_session_safe(self) -> None:
        origin, hello = await self.connect("reference-origin")
        owner = hello["principal"]["id"]
        origin_session = hello["principal"]["sessionId"]
        operation_id = "11111111-2222-3333-4444-555555555555"
        recovery_token = "A" * 43
        await origin.request(
            "reference.operation.preflight",
            {
                "operationId": operation_id,
                "idempotencyKey": "reference.managed-projection",
                "recoveryToken": recovery_token,
                "resourceId": "resource.managed-projection",
                "arguments": {
                    "desiredState": "enabled",
                    "outcome": "succeed",
                    "pace": "immediate",
                },
            },
        )
        initial = await origin.request(
            "managed-work.query",
            {"version": "v0", "view": "agent.activity"},
        )
        item = initial["items"][0]
        self.assertEqual(1, item["sourceRevision"])
        self.assertEqual(owner, item["owner"]["principalId"])
        self.assertEqual(origin_session, item["owner"]["sessionId"])
        self.assertNotIn(recovery_token, str(initial))
        approval = await origin.request(
            "reference.operation.approve",
            {"operationId": operation_id, "confirmation": "approve-exact-operation"},
        )
        updated = await origin.request(
            "managed-work.query",
            {"version": "v0", "view": "agent.activity"},
        )
        self.assertEqual(2, updated["items"][0]["sourceRevision"])
        await origin.close()

        recovery, recovery_hello = await self.connect("reference-recovery")
        self.assertEqual(owner, recovery_hello["principal"]["id"])
        self.assertNotEqual(origin_session, recovery_hello["principal"]["sessionId"])
        with self.assertRaises(FabricError) as approve_denied:
            await recovery.request(
                "reference.operation.approve",
                {"operationId": operation_id, "confirmation": "approve-exact-operation"},
            )
        self.assertEqual("principal.request-spoof", approve_denied.exception.code)
        with self.assertRaises(FabricError) as start_denied:
            await recovery.request(
                "reference.operation.start",
                {
                    "operationId": operation_id,
                    "approvalId": approval["approval"]["approvalId"],
                },
            )
        self.assertEqual("principal.request-spoof", start_denied.exception.code)
        recovered = await recovery.request(
            "reference.operation.get",
            {"operationId": operation_id, "recoveryToken": recovery_token},
        )
        self.assertEqual(operation_id, recovered["operationId"])
        projected = await recovery.request(
            "managed-work.query",
            {"version": "v0", "view": "agent.activity"},
        )
        self.assertEqual(origin_session, projected["items"][0]["owner"]["sessionId"])

        self.daemon.database._require_connection().execute(
            "UPDATE reference_operation_ledger SET payload_json = '{}' WHERE operation_id = ?",
            (operation_id,),
        )
        with self.assertRaises(FabricError) as corrupt:
            await recovery.request(
                "managed-work.query",
                {"version": "v0", "view": "agent.activity"},
            )
        self.assertEqual("ledger.integrity-failed", corrupt.exception.code)


if __name__ == "__main__":
    unittest.main()
