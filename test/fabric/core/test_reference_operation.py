from __future__ import annotations

import asyncio
import hashlib
import json
import secrets
import sqlite3
import tempfile
import unittest
import uuid
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

from helper import DaemonProcess

from omarchy_fabric.db import canonical_json
from omarchy_fabric.models import MAX_FRAME_BYTES, FabricError
from omarchy_fabric.reference_operation import ReferenceOperationStore

SCHEMA_DIRECTORY = Path(__file__).resolve().parents[3] / "default" / "fabric" / "schema"
REFERENCE_SCHEMA = json.loads((SCHEMA_DIRECTORY / "reference-operation-v0.json").read_text())
COMMON_SCHEMA = json.loads((SCHEMA_DIRECTORY / "common-v0.json").read_text())
SCHEMA_REGISTRY = Registry().with_resources(
    [
        (REFERENCE_SCHEMA["$id"], Resource.from_contents(REFERENCE_SCHEMA)),
        (COMMON_SCHEMA["$id"], Resource.from_contents(COMMON_SCHEMA)),
        ("common-v0.json", Resource.from_contents(COMMON_SCHEMA)),
    ]
)
METHOD_RESULT_VALIDATOR = Draft202012Validator(
    REFERENCE_SCHEMA,
    registry=SCHEMA_REGISTRY,
).evolve(schema=REFERENCE_SCHEMA["$defs"]["methodResultContract"])

def preflight_params(
    *,
    operation_id: str | None = None,
    idempotency_key: str | None = None,
    recovery_token: str | None = None,
    resource_id: str = "reference.display-mode",
    desired_state: str = "enabled",
    outcome: str = "succeed",
    pace: str = "observable",
) -> dict[str, object]:
    operation_id = operation_id or str(uuid.uuid4())
    recovery_token = recovery_token or secrets.token_urlsafe(32)
    return {
        "operationId": operation_id,
        "idempotencyKey": idempotency_key or f"reference-{operation_id}",
        "recoveryToken": recovery_token,
        "resourceId": resource_id,
        "arguments": {
            "desiredState": desired_state,
            "outcome": outcome,
            "pace": pace,
        },
    }

class ReferenceOperationRpcTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.daemon = DaemonProcess(Path(self.temporary.name), event_retention=128)
        self.daemon.start()

    def tearDown(self) -> None:
        self.daemon.stop()
        self.temporary.cleanup()

    async def wait_for_status(
        self,
        client,
        operation_id: str,
        statuses: set[str],
        *,
        timeout: float = 4.0,
    ) -> dict[str, object]:
        deadline = asyncio.get_running_loop().time() + timeout
        while asyncio.get_running_loop().time() < deadline:
            operation = await client.request(
                "reference.operation.get",
                {"operationId": operation_id},
            )
            if operation["status"] in statuses:
                return operation
            await asyncio.sleep(0.01)
        self.fail(f"operation {operation_id} did not reach {sorted(statuses)}")

    async def approve_and_start(self, client, operation_id: str) -> tuple[dict, dict]:
        approval = await client.request(
            "reference.operation.approve",
            {
                "operationId": operation_id,
                "confirmation": "approve-exact-operation",
            },
        )
        started = await client.request(
            "reference.operation.start",
            {
                "operationId": operation_id,
                "approvalId": approval["approval"]["approvalId"],
            },
        )
        return approval, started

    def assert_method_result(self, method: str, result: object) -> None:
        errors = sorted(
            METHOD_RESULT_VALIDATOR.iter_errors({"method": method, "result": result}),
            key=lambda error: list(error.absolute_path),
        )
        self.assertEqual([], errors, "\n".join(error.message for error in errors))

    async def test_success_uses_exact_approval_progress_validation_and_idempotency(self) -> None:
        client = await self.daemon.client("reference-success")
        params = preflight_params()
        operation_id = params["operationId"]
        try:
            await client.request(
                "events.subscribe",
                {"topics": ["reference.operation-progress", "reference.operation-finished"]},
            )
            preflight = await client.request("reference.operation.preflight", params)
            self.assert_method_result("reference.operation.preflight", preflight)
            self.assertEqual(preflight["status"], "awaiting-consent")
            self.assertEqual(preflight["risk"], "consequential")
            self.assertTrue(preflight["preflight"]["requiresConsent"])
            self.assertFalse(preflight["preflight"]["hostMutation"])
            replay = await client.request("reference.operation.preflight", params)
            self.assertTrue(replay["idempotency"]["replayed"])

            conflicting = dict(params)
            conflicting["arguments"] = dict(params["arguments"], desiredState="disabled")
            with self.assertRaises(FabricError) as conflict:
                await client.request("reference.operation.preflight", conflicting)
            self.assertEqual(conflict.exception.code, "operation.idempotency-conflict")

            with self.assertRaises(FabricError) as unapproved:
                await client.request(
                    "reference.operation.start",
                    {
                        "operationId": operation_id,
                        "approvalId": "approval." + ("0" * 32),
                    },
                )
            self.assertEqual(unapproved.exception.code, "approval.required")

            approval, started = await self.approve_and_start(client, operation_id)
            self.assert_method_result("reference.operation.approve", approval)
            self.assert_method_result("reference.operation.start", started)
            self.assertEqual(started["authorizationCode"], "policy.approved")
            self.assertTrue(approval["approval"]["oneUse"])
            finished = await self.wait_for_status(client, operation_id, {"succeeded"})
            self.assert_method_result("reference.operation.get", finished)
            self.assertEqual(finished["checkpoint"], "finished")
            self.assertTrue(finished["result"]["validated"])
            self.assertEqual(finished["resourceState"]["state"], "enabled")

            replayed_start = await client.request(
                "reference.operation.start",
                {
                    "operationId": operation_id,
                    "approvalId": approval["approval"]["approvalId"],
                },
            )
            self.assertTrue(replayed_start["idempotency"]["replayed"])

            phases: list[str] = []
            progress: list[int] = []
            while "post-apply-validation-complete" not in phases:
                event = await client.next_event(timeout=2)
                phases.append(event["payload"]["phase"])
                progress.append(event["payload"]["progress"])
            self.assertEqual(progress, sorted(progress))
            self.assertTrue(
                {
                    "preflight-complete",
                    "consent-recorded",
                    "authorization-complete",
                    "execution-started",
                    "pre-apply-validation-complete",
                    "fake-state-applied",
                    "post-apply-validation-complete",
                }.issubset(phases)
            )
            ledger = await client.request(
                "reference.operation.ledger",
                {"operationId": operation_id},
            )
            self.assert_method_result("reference.operation.ledger", ledger)
            self.assertTrue(ledger["verified"])
            self.assertEqual(ledger["entryCount"], len(ledger["entries"]))
            self.assertEqual(ledger["headHash"], ledger["entries"][-1]["entryHash"])
            self.assertIn("authorization.allowed", [entry["eventType"] for entry in ledger["entries"]])
            self.assertNotIn(params["recoveryToken"], str(ledger))
        finally:
            await client.close()

    async def test_approval_is_bound_to_the_admitted_connection_principal(self) -> None:
        owner = await self.daemon.client("reference-approval-owner")
        other = await self.daemon.client("reference-approval-other")
        params = preflight_params(pace="immediate")
        operation_id = params["operationId"]
        try:
            await owner.request("reference.operation.preflight", params)
            database = sqlite3.connect(self.daemon.database_path)
            try:
                frozen_identity = database.execute(
                    """
                    SELECT principal_id, session_id, recovery_token_digest
                    FROM reference_operations WHERE operation_id = ?
                    """,
                    (operation_id,),
                ).fetchone()
            finally:
                database.close()
            self.assertEqual(
                frozen_identity[2],
                hashlib.sha256(params["recoveryToken"].encode("ascii")).hexdigest(),
            )
            self.assertNotEqual(frozen_identity[2], params["recoveryToken"])
            with self.assertRaises(FabricError) as preflight_replay:
                await other.request("reference.operation.preflight", params)
            self.assertEqual(preflight_replay.exception.code, "principal.request-spoof")
            with self.assertRaises(FabricError) as cross_session_approval:
                await other.request(
                    "reference.operation.approve",
                    {
                        "operationId": operation_id,
                        "confirmation": "approve-exact-operation",
                    },
                )
            self.assertEqual(cross_session_approval.exception.code, "principal.request-spoof")
            database = sqlite3.connect(self.daemon.database_path)
            try:
                identity_after_attack = database.execute(
                    """
                    SELECT principal_id, session_id, recovery_token_digest
                    FROM reference_operations WHERE operation_id = ?
                    """,
                    (operation_id,),
                ).fetchone()
            finally:
                database.close()
            self.assertEqual(identity_after_attack, frozen_identity)
            approval = await owner.request(
                "reference.operation.approve",
                {
                    "operationId": operation_id,
                    "confirmation": "approve-exact-operation",
                },
            )
            with self.assertRaises(FabricError) as drift:
                await other.request(
                    "reference.operation.start",
                    {
                        "operationId": operation_id,
                        "approvalId": approval["approval"]["approvalId"],
                    },
                )
            self.assertEqual(drift.exception.code, "principal.request-spoof")
            await owner.request(
                "reference.operation.start",
                {
                    "operationId": operation_id,
                    "approvalId": approval["approval"]["approvalId"],
                },
            )
            await self.wait_for_status(owner, operation_id, {"succeeded"})
        finally:
            await owner.close()
            await other.close()

    async def test_cross_session_reads_replay_and_cancel_require_exact_authority(self) -> None:
        owner = await self.daemon.client("reference-access-owner")
        other = await self.daemon.client("reference-access-other")
        params = preflight_params(pace="observable")
        operation_id = params["operationId"]
        wrong_token = "Z" * 43
        try:
            await owner.request("reference.operation.preflight", params)
            approval, _started = await self.approve_and_start(owner, operation_id)
            await self.wait_for_status(owner, operation_id, {"running"})

            for method in ("reference.operation.get", "reference.operation.ledger"):
                with self.assertRaises(FabricError) as missing:
                    await other.request(method, {"operationId": operation_id})
                self.assertEqual(missing.exception.code, "principal.request-spoof")
                with self.assertRaises(FabricError) as wrong:
                    await other.request(
                        method,
                        {"operationId": operation_id, "recoveryToken": wrong_token},
                    )
                self.assertEqual(wrong.exception.code, "operation.recovery-credential")

            recovered_read = await other.request(
                "reference.operation.get",
                {
                    "operationId": operation_id,
                    "recoveryToken": params["recoveryToken"],
                },
            )
            self.assertEqual(recovered_read["operationId"], operation_id)

            for cancel_params in (
                {"operationId": operation_id},
                {
                    "operationId": operation_id,
                    "recoveryToken": params["recoveryToken"],
                },
            ):
                with self.assertRaises(FabricError) as cross_cancel:
                    await other.request("reference.operation.cancel", cancel_params)
                self.assertEqual(cross_cancel.exception.code, "principal.request-spoof")

            await self.wait_for_status(owner, operation_id, {"succeeded"})
            with self.assertRaises(FabricError) as replay:
                await other.request(
                    "reference.operation.start",
                    {
                        "operationId": operation_id,
                        "approvalId": approval["approval"]["approvalId"],
                    },
                )
            self.assertEqual(replay.exception.code, "principal.request-spoof")
            recovered_ledger = await other.request(
                "reference.operation.ledger",
                {
                    "operationId": operation_id,
                    "recoveryToken": params["recoveryToken"],
                },
            )
            self.assertTrue(recovered_ledger["verified"])
        finally:
            await owner.close()
            await other.close()

    async def test_active_resource_is_exclusive_without_consuming_the_waiting_approval(self) -> None:
        client = await self.daemon.client("reference-resource-ownership")
        first = preflight_params(resource_id="reference.shared-resource", pace="observable")
        second = preflight_params(resource_id="reference.shared-resource", pace="immediate")
        try:
            await client.request("reference.operation.preflight", first)
            await client.request("reference.operation.preflight", second)
            first_approval = await client.request(
                "reference.operation.approve",
                {
                    "operationId": first["operationId"],
                    "confirmation": "approve-exact-operation",
                },
            )
            second_approval = await client.request(
                "reference.operation.approve",
                {
                    "operationId": second["operationId"],
                    "confirmation": "approve-exact-operation",
                },
            )
            await client.request(
                "reference.operation.start",
                {
                    "operationId": first["operationId"],
                    "approvalId": first_approval["approval"]["approvalId"],
                },
            )
            for _attempt in range(2):
                with self.assertRaises(FabricError) as busy:
                    await client.request(
                        "reference.operation.start",
                        {
                            "operationId": second["operationId"],
                            "approvalId": second_approval["approval"]["approvalId"],
                        },
                    )
                self.assertEqual(busy.exception.code, "operation.resource-busy")
            await self.wait_for_status(client, first["operationId"], {"succeeded"})
        finally:
            await client.close()

    async def test_rejected_approval_attempts_are_bounded_without_state_drift(self) -> None:
        client = await self.daemon.client("reference-approval-cap")
        params = preflight_params(pace="immediate")
        operation_id = params["operationId"]
        try:
            await client.request("reference.operation.preflight", params)
            approvals = []
            for _attempt in range(4):
                approvals.append(
                    await client.request(
                        "reference.operation.approve",
                        {
                            "operationId": operation_id,
                            "confirmation": "approve-exact-operation",
                        },
                    )
                )
            for _attempt in range(20):
                with self.assertRaises(FabricError) as exhausted:
                    await client.request(
                        "reference.operation.approve",
                        {
                            "operationId": operation_id,
                            "confirmation": "approve-exact-operation",
                        },
                    )
                self.assertEqual(exhausted.exception.code, "approval.issue-limit")
            current = await client.request(
                "reference.operation.get",
                {"operationId": operation_id},
            )
            self.assertEqual(current["status"], "awaiting-consent")
            self.assertEqual(current["approvalId"], approvals[-1]["approval"]["approvalId"])
            ledger = await client.request(
                "reference.operation.ledger",
                {"operationId": operation_id},
            )
            self.assertEqual(ledger["totalEntryCount"], 5)
        finally:
            await client.close()

    async def test_deterministic_failure_rolls_back_and_records_evidence(self) -> None:
        client = await self.daemon.client("reference-failure")
        params = preflight_params(outcome="fail-after-apply", pace="immediate")
        operation_id = params["operationId"]
        try:
            preflight = await client.request("reference.operation.preflight", params)
            await self.approve_and_start(client, operation_id)
            failed = await self.wait_for_status(client, operation_id, {"failed"})
            self.assertEqual(failed["error"]["code"], "reference.validation-failed")
            self.assertEqual(failed["error"]["changeState"], "none")
            self.assertEqual(failed["resourceState"]["state"], preflight["beforeState"])
            self.assertTrue(failed["result"]["reconciled"])
            ledger = await client.request("reference.operation.ledger", {"operationId": operation_id})
            self.assertIn(
                "validation.failed-reconciled",
                [entry["eventType"] for entry in ledger["entries"]],
            )
        finally:
            await client.close()

    async def test_cancellation_after_apply_reconciles_the_fake_resource(self) -> None:
        client = await self.daemon.client("reference-cancel")
        params = preflight_params(pace="observable")
        operation_id = params["operationId"]
        try:
            preflight = await client.request("reference.operation.preflight", params)
            await self.approve_and_start(client, operation_id)
            await self.wait_for_status(client, operation_id, {"running"})
            deadline = asyncio.get_running_loop().time() + 4
            while True:
                current = await client.request(
                    "reference.operation.get",
                    {"operationId": operation_id},
                )
                if current["checkpoint"] == "applied":
                    break
                if asyncio.get_running_loop().time() >= deadline:
                    self.fail("reference operation never reached the applied cancellation point")
                await asyncio.sleep(0.01)
            requested = await client.request(
                "reference.operation.cancel",
                {"operationId": operation_id},
            )
            self.assertTrue(requested["cancellationRequested"])
            cancelled = await self.wait_for_status(client, operation_id, {"cancelled"})
            self.assertEqual(cancelled["checkpoint"], "reconciled")
            self.assertEqual(cancelled["resourceState"]["state"], preflight["beforeState"])
            self.assertTrue(cancelled["result"]["reconciled"])
        finally:
            await client.close()

    async def test_cancellation_while_awaiting_consent_is_immediately_terminal(self) -> None:
        client = await self.daemon.client("reference-cancel-before-start")
        params = preflight_params(pace="immediate")
        operation_id = params["operationId"]
        try:
            await client.request("reference.operation.preflight", params)
            approval = await client.request(
                "reference.operation.approve",
                {
                    "operationId": operation_id,
                    "confirmation": "approve-exact-operation",
                },
            )
            cancelled = await client.request(
                "reference.operation.cancel",
                {"operationId": operation_id},
            )
            self.assert_method_result("reference.operation.cancel", cancelled)
            self.assertEqual(cancelled["status"], "cancelled")
            self.assertEqual(cancelled["checkpoint"], "finished")
            self.assertEqual(cancelled["progress"], 100)
            self.assertTrue(cancelled["cancellationRequested"])
            self.assertTrue(cancelled["result"]["validated"])
            self.assertFalse(cancelled["result"]["reconciled"])
            replay = await client.request(
                "reference.operation.cancel",
                {"operationId": operation_id},
            )
            self.assertTrue(replay["idempotency"]["replayed"])
            start_replay = await client.request(
                "reference.operation.start",
                {
                    "operationId": operation_id,
                    "approvalId": approval["approval"]["approvalId"],
                },
            )
            self.assertEqual(start_replay["status"], "cancelled")
            self.assertTrue(start_replay["idempotency"]["replayed"])
            ledger = await client.request(
                "reference.operation.ledger",
                {"operationId": operation_id},
            )
            self.assertEqual(ledger["entries"][-1]["eventType"], "cancellation.completed")
        finally:
            await client.close()

    async def test_crash_after_apply_requires_reconciliation_and_recovers(self) -> None:
        client = await self.daemon.client("reference-crash")
        params = preflight_params(pace="observable")
        operation_id = params["operationId"]
        await client.request("reference.operation.preflight", params)
        await self.approve_and_start(client, operation_id)
        deadline = asyncio.get_running_loop().time() + 4
        while True:
            current = await client.request("reference.operation.get", {"operationId": operation_id})
            if current["checkpoint"] == "applied":
                break
            if asyncio.get_running_loop().time() >= deadline:
                self.fail("reference operation never reached the durable applied checkpoint")
            await asyncio.sleep(0.01)
        self.daemon.crash()
        await client.close()

        self.daemon.start()
        recovered_client = await self.daemon.client("reference-recovery")
        try:
            for method in (
                "reference.operation.get",
                "reference.operation.cancel",
                "reference.operation.reconcile",
            ):
                with self.assertRaises(FabricError) as missing_recovery:
                    await recovered_client.request(method, {"operationId": operation_id})
                self.assertEqual(missing_recovery.exception.code, "principal.request-spoof")
            with self.assertRaises(FabricError) as wrong_recovery:
                await recovered_client.request(
                    "reference.operation.get",
                    {"operationId": operation_id, "recoveryToken": "Z" * 43},
                )
            self.assertEqual(wrong_recovery.exception.code, "operation.recovery-credential")
            interrupted = await recovered_client.request(
                "reference.operation.get",
                {
                    "operationId": operation_id,
                    "recoveryToken": params["recoveryToken"],
                },
            )
            self.assertEqual(interrupted["status"], "interrupted")
            self.assertEqual(interrupted["checkpoint"], "applied")
            recovered = await recovered_client.request(
                "reference.operation.reconcile",
                {
                    "operationId": operation_id,
                    "recoveryToken": params["recoveryToken"],
                },
            )
            self.assert_method_result("reference.operation.reconcile", recovered)
            self.assertEqual(recovered["status"], "recovered")
            self.assertTrue(recovered["result"]["validated"])
            self.assertTrue(recovered["result"]["reconciled"])
            ledger = await recovered_client.request(
                "reference.operation.ledger",
                {
                    "operationId": operation_id,
                    "recoveryToken": params["recoveryToken"],
                },
            )
            event_types = [entry["eventType"] for entry in ledger["entries"]]
            self.assertIn("daemon.recovery-required", event_types)
            self.assertIn("reconciliation.recovered", event_types)
        finally:
            await recovered_client.close()

    async def test_recovery_token_can_cancel_only_after_restart_and_reconcile_rollback(self) -> None:
        client = await self.daemon.client("reference-crash-cancel")
        params = preflight_params(pace="observable")
        operation_id = params["operationId"]
        preflight = await client.request("reference.operation.preflight", params)
        await self.approve_and_start(client, operation_id)
        deadline = asyncio.get_running_loop().time() + 4
        while True:
            current = await client.request("reference.operation.get", {"operationId": operation_id})
            if current["checkpoint"] == "applied":
                break
            if asyncio.get_running_loop().time() >= deadline:
                self.fail("reference operation never reached applied before recovery cancellation")
            await asyncio.sleep(0.01)
        self.daemon.crash()
        await client.close()

        self.daemon.start()
        recovery = await self.daemon.client("reference-crash-cancel-recovery")
        try:
            requested = await recovery.request(
                "reference.operation.cancel",
                {
                    "operationId": operation_id,
                    "recoveryToken": params["recoveryToken"],
                },
            )
            self.assertEqual(requested["status"], "interrupted")
            self.assertTrue(requested["cancellationRequested"])
            cancelled = await recovery.request(
                "reference.operation.reconcile",
                {
                    "operationId": operation_id,
                    "recoveryToken": params["recoveryToken"],
                },
            )
            self.assertEqual(cancelled["status"], "cancelled")
            self.assertEqual(cancelled["checkpoint"], "reconciled")
            self.assertEqual(cancelled["result"]["state"], preflight["beforeState"])
            self.assertTrue(cancelled["result"]["reconciled"])
        finally:
            await recovery.close()

    async def test_recovery_token_terminally_cancels_orphaned_consent_after_restart(self) -> None:
        owner = await self.daemon.client("reference-orphaned-consent-owner")
        unapproved = preflight_params(pace="immediate")
        approved = preflight_params(pace="immediate")
        await owner.request("reference.operation.preflight", unapproved)
        await owner.request("reference.operation.preflight", approved)
        approval = await owner.request(
            "reference.operation.approve",
            {
                "operationId": approved["operationId"],
                "confirmation": "approve-exact-operation",
            },
        )
        active_other = await self.daemon.client("reference-orphaned-consent-active-other")
        try:
            with self.assertRaises(FabricError) as active_origin:
                await active_other.request(
                    "reference.operation.cancel",
                    {
                        "operationId": approved["operationId"],
                        "recoveryToken": approved["recoveryToken"],
                    },
                )
            self.assertEqual(active_origin.exception.code, "principal.request-spoof")
        finally:
            await active_other.close()
        self.daemon.crash()
        await owner.close()

        self.daemon.start()
        recovery = await self.daemon.client("reference-orphaned-consent-recovery")
        try:
            for params in (unapproved, approved):
                operation_id = params["operationId"]
                orphaned = await recovery.request(
                    "reference.operation.get",
                    {
                        "operationId": operation_id,
                        "recoveryToken": params["recoveryToken"],
                    },
                )
                self.assertEqual(orphaned["status"], "awaiting-consent")
                with self.assertRaises(FabricError) as approve_spoof:
                    await recovery.request(
                        "reference.operation.approve",
                        {
                            "operationId": operation_id,
                            "confirmation": "approve-exact-operation",
                        },
                    )
                self.assertEqual(approve_spoof.exception.code, "principal.request-spoof")
                if operation_id == approved["operationId"]:
                    with self.assertRaises(FabricError) as start_spoof:
                        await recovery.request(
                            "reference.operation.start",
                            {
                                "operationId": operation_id,
                                "approvalId": approval["approval"]["approvalId"],
                            },
                        )
                    self.assertEqual(start_spoof.exception.code, "principal.request-spoof")
                with self.assertRaises(FabricError) as missing_token:
                    await recovery.request(
                        "reference.operation.cancel",
                        {"operationId": operation_id},
                    )
                self.assertEqual(missing_token.exception.code, "principal.request-spoof")
                cancelled = await recovery.request(
                    "reference.operation.cancel",
                    {
                        "operationId": operation_id,
                        "recoveryToken": params["recoveryToken"],
                    },
                )
                self.assertEqual(cancelled["status"], "cancelled")
                self.assertEqual(cancelled["checkpoint"], "finished")
                self.assertTrue(cancelled["cancellationRequested"])
        finally:
            await recovery.close()

    async def test_reconciliation_conflict_remains_interrupted_and_is_retriable(self) -> None:
        client = await self.daemon.client("reference-reconcile-conflict")
        params = preflight_params(pace="observable")
        operation_id = params["operationId"]
        await client.request("reference.operation.preflight", params)
        await self.approve_and_start(client, operation_id)
        deadline = asyncio.get_running_loop().time() + 4
        while True:
            current = await client.request("reference.operation.get", {"operationId": operation_id})
            if current["checkpoint"] == "applied":
                break
            if asyncio.get_running_loop().time() >= deadline:
                self.fail("reference operation never reached applied before conflict test")
            await asyncio.sleep(0.01)
        self.daemon.crash()
        await client.close()

        self.daemon.start()
        recovery = await self.daemon.client("reference-reconcile-conflict-recovery")
        try:
            connection = sqlite3.connect(self.daemon.database_path)
            try:
                resource_id, desired_state, state_revision = connection.execute(
                    """
                    SELECT resource_id, desired_state, state_revision
                    FROM reference_operations WHERE operation_id = ?
                    """,
                    (operation_id,),
                ).fetchone()
                base_revision = int(state_revision.removeprefix("revision."))
                connection.execute(
                    "UPDATE reference_resources SET revision = ? WHERE resource_id = ?",
                    (base_revision + 9, resource_id),
                )
                connection.commit()
            finally:
                connection.close()
            with self.assertRaises(FabricError) as conflict:
                await recovery.request(
                    "reference.operation.reconcile",
                    {
                        "operationId": operation_id,
                        "recoveryToken": params["recoveryToken"],
                    },
                )
            self.assertEqual(conflict.exception.code, "operation.reconciliation-conflict")
            still_interrupted = await recovery.request(
                "reference.operation.get",
                {
                    "operationId": operation_id,
                    "recoveryToken": params["recoveryToken"],
                },
            )
            self.assertEqual(still_interrupted["status"], "interrupted")
            self.assertEqual(still_interrupted["checkpoint"], "applied")

            connection = sqlite3.connect(self.daemon.database_path)
            try:
                connection.execute(
                    """
                    UPDATE reference_resources SET state = ?, revision = ?
                    WHERE resource_id = ?
                    """,
                    (desired_state, base_revision + 1, resource_id),
                )
                connection.commit()
            finally:
                connection.close()
            recovered = await recovery.request(
                "reference.operation.reconcile",
                {
                    "operationId": operation_id,
                    "recoveryToken": params["recoveryToken"],
                },
            )
            self.assertEqual(recovered["status"], "recovered")
        finally:
            await recovery.close()

    async def test_live_post_apply_validation_drift_remains_reconcilable(self) -> None:
        client = await self.daemon.client("reference-live-validation-drift")
        params = preflight_params(pace="observable")
        operation_id = params["operationId"]
        try:
            await client.request("reference.operation.preflight", params)
            await self.approve_and_start(client, operation_id)
            deadline = asyncio.get_running_loop().time() + 4
            while True:
                current = await client.request(
                    "reference.operation.get",
                    {"operationId": operation_id},
                )
                if current["checkpoint"] == "applied":
                    break
                if asyncio.get_running_loop().time() >= deadline:
                    self.fail("reference operation never reached applied before live drift")
                await asyncio.sleep(0.01)

            connection = sqlite3.connect(self.daemon.database_path)
            try:
                resource_id, desired_state, state_revision = connection.execute(
                    """
                    SELECT resource_id, desired_state, state_revision
                    FROM reference_operations WHERE operation_id = ?
                    """,
                    (operation_id,),
                ).fetchone()
                base_revision = int(state_revision.removeprefix("revision."))
                connection.execute(
                    "UPDATE reference_resources SET revision = ? WHERE resource_id = ?",
                    (base_revision + 9, resource_id),
                )
                connection.commit()
            finally:
                connection.close()

            interrupted = await self.wait_for_status(client, operation_id, {"interrupted"})
            self.assertEqual(interrupted["checkpoint"], "applied")
            self.assertEqual(interrupted["error"]["code"], "reference.validation-failed")
            self.assertEqual(interrupted["error"]["changeState"], "unknown")
            self.assertIn(
                "reference.operation.reconcile",
                interrupted["error"]["recoveryActions"],
            )
            with self.assertRaises(FabricError) as conflict:
                await client.request(
                    "reference.operation.reconcile",
                    {"operationId": operation_id},
                )
            self.assertEqual(conflict.exception.code, "operation.reconciliation-conflict")
            still_interrupted = await client.request(
                "reference.operation.get",
                {"operationId": operation_id},
            )
            self.assertEqual(still_interrupted["status"], "interrupted")

            connection = sqlite3.connect(self.daemon.database_path)
            try:
                connection.execute(
                    """
                    UPDATE reference_resources SET state = ?, revision = ?
                    WHERE resource_id = ?
                    """,
                    (desired_state, base_revision + 1, resource_id),
                )
                connection.commit()
            finally:
                connection.close()
            recovered = await client.request(
                "reference.operation.reconcile",
                {"operationId": operation_id},
            )
            self.assertEqual(recovered["status"], "recovered")
            self.assertIsNone(recovered["error"])
            self.assertTrue(recovered["result"]["validated"])
            self.assertTrue(recovered["result"]["reconciled"])
            ledger = await client.request(
                "reference.operation.ledger",
                {"operationId": operation_id},
            )
            event_types = [entry["eventType"] for entry in ledger["entries"]]
            self.assertIn("validation.recovery-required", event_types)
            self.assertIn("reconciliation.recovered", event_types)
        finally:
            await client.close()

    async def test_ledger_is_anchored_paginated_and_rejects_any_truncation(self) -> None:
        client = await self.daemon.client("reference-ledger-anchor")
        params = preflight_params(pace="immediate")
        operation_id = params["operationId"]
        try:
            await client.request("reference.operation.preflight", params)
            await self.approve_and_start(client, operation_id)
            await self.wait_for_status(client, operation_id, {"succeeded"})
            after_sequence = 0
            gathered: list[dict] = []
            expected_total = None
            expected_head = None
            while True:
                page = await client.request(
                    "reference.operation.ledger",
                    {
                        "operationId": operation_id,
                        "afterSequence": after_sequence,
                        "limit": 2,
                    },
                )
                self.assert_method_result("reference.operation.ledger", page)
                self.assertLess(len(canonical_json(page).encode("utf-8")), MAX_FRAME_BYTES)
                self.assertLessEqual(page["entryCount"], 2)
                expected_total = page["totalEntryCount"] if expected_total is None else expected_total
                expected_head = page["headHash"] if expected_head is None else expected_head
                self.assertEqual(page["totalEntryCount"], expected_total)
                self.assertEqual(page["headHash"], expected_head)
                gathered.extend(page["entries"])
                if page["nextAfterSequence"] is None:
                    break
                after_sequence = page["nextAfterSequence"]
            self.assertEqual(len(gathered), expected_total)
            self.assertEqual(gathered[-1]["entryHash"], expected_head)
            with self.assertRaises(FabricError) as oversized_page:
                await client.request(
                    "reference.operation.ledger",
                    {"operationId": operation_id, "limit": 9},
                )
            self.assertEqual(oversized_page.exception.code, "rpc.invalid-params")

            connection = sqlite3.connect(self.daemon.database_path)
            try:
                connection.execute(
                    """
                    DELETE FROM reference_operation_ledger
                    WHERE operation_id = ? AND sequence = (
                      SELECT MAX(sequence) FROM reference_operation_ledger WHERE operation_id = ?
                    )
                    """,
                    (operation_id, operation_id),
                )
                connection.commit()
            finally:
                connection.close()
            with self.assertRaises(FabricError) as tail_truncation:
                await client.request(
                    "reference.operation.ledger",
                    {"operationId": operation_id},
                )
            self.assertEqual(tail_truncation.exception.code, "ledger.integrity-failed")

            connection = sqlite3.connect(self.daemon.database_path)
            try:
                connection.execute(
                    "DELETE FROM reference_operation_ledger WHERE operation_id = ?",
                    (operation_id,),
                )
                connection.commit()
            finally:
                connection.close()
            with self.assertRaises(FabricError) as full_truncation:
                await client.request(
                    "reference.operation.ledger",
                    {"operationId": operation_id},
                )
            self.assertEqual(full_truncation.exception.code, "ledger.integrity-failed")
        finally:
            await client.close()

    async def test_append_rejects_middle_chain_corruption_before_lifecycle_mutation(self) -> None:
        client = await self.daemon.client("reference-ledger-append-integrity")
        params = preflight_params(pace="immediate")
        operation_id = params["operationId"]
        try:
            await client.request("reference.operation.preflight", params)
            approvals = []
            for _attempt in range(2):
                approvals.append(
                    await client.request(
                        "reference.operation.approve",
                        {
                            "operationId": operation_id,
                            "confirmation": "approve-exact-operation",
                        },
                    )
                )
            connection = sqlite3.connect(self.daemon.database_path)
            try:
                middle_sequence = connection.execute(
                    """
                    SELECT sequence FROM reference_operation_ledger
                    WHERE operation_id = ? ORDER BY sequence LIMIT 1 OFFSET 1
                    """,
                    (operation_id,),
                ).fetchone()[0]
                connection.execute(
                    "UPDATE reference_operation_ledger SET payload_json = ? WHERE sequence = ?",
                    ('{"operationId":"tampered"}', middle_sequence),
                )
                connection.commit()
            finally:
                connection.close()

            with self.assertRaises(FabricError) as integrity:
                await client.request(
                    "reference.operation.approve",
                    {
                        "operationId": operation_id,
                        "confirmation": "approve-exact-operation",
                    },
                )
            self.assertEqual(integrity.exception.code, "ledger.integrity-failed")
            contained = await client.request(
                "reference.operation.get",
                {"operationId": operation_id},
            )
            self.assertEqual(contained["status"], "failed")
            self.assertEqual(contained["checkpoint"], "finished")
            self.assertEqual(contained["error"]["code"], "ledger.integrity-failed")
            self.assertEqual(
                contained["approvalId"],
                approvals[-1]["approval"]["approvalId"],
            )
            self.assertEqual(contained["resourceState"]["state"], contained["beforeState"])
            self.assertEqual(contained["resourceState"]["revision"], contained["stateRevision"])
            connection = sqlite3.connect(self.daemon.database_path)
            try:
                ledger_count, approval_id = connection.execute(
                    """
                    SELECT ledger_entry_count, approval_id
                    FROM reference_operations WHERE operation_id = ?
                    """,
                    (operation_id,),
                ).fetchone()
                physical_count = connection.execute(
                    "SELECT COUNT(*) FROM reference_operation_ledger WHERE operation_id = ?",
                    (operation_id,),
                ).fetchone()[0]
            finally:
                connection.close()
            self.assertEqual((ledger_count, physical_count), (3, 3))
            self.assertEqual(approval_id, approvals[-1]["approval"]["approvalId"])
            for malformed_payload in ("[]", "{"):
                connection = sqlite3.connect(self.daemon.database_path)
                try:
                    connection.execute(
                        "UPDATE reference_operation_ledger SET payload_json = ? WHERE sequence = ?",
                        (malformed_payload, middle_sequence),
                    )
                    connection.commit()
                finally:
                    connection.close()
                with self.assertRaises(FabricError) as malformed:
                    await client.request(
                        "reference.operation.ledger",
                        {"operationId": operation_id},
                    )
                self.assertEqual(malformed.exception.code, "ledger.integrity-failed")

            malformed_params = preflight_params(pace="immediate")
            malformed_operation_id = malformed_params["operationId"]
            await client.request("reference.operation.preflight", malformed_params)
            connection = sqlite3.connect(self.daemon.database_path)
            try:
                connection.execute(
                    """
                    UPDATE reference_operation_ledger SET payload_json = '[]'
                    WHERE operation_id = ?
                    """,
                    (malformed_operation_id,),
                )
                connection.commit()
            finally:
                connection.close()
            with self.assertRaises(FabricError) as malformed_active:
                await client.request(
                    "reference.operation.ledger",
                    {"operationId": malformed_operation_id},
                )
            self.assertEqual(malformed_active.exception.code, "ledger.integrity-failed")
            malformed_contained = await client.request(
                "reference.operation.get",
                {"operationId": malformed_operation_id},
            )
            self.assertEqual(malformed_contained["status"], "failed")
            self.assertEqual(malformed_contained["error"]["code"], "ledger.integrity-failed")
        finally:
            await client.close()

    async def test_evidence_capacity_degrades_one_operation_without_blocking_restart(self) -> None:
        client = await self.daemon.client("reference-ledger-capacity")
        params = preflight_params(pace="immediate")
        operation_id = params["operationId"]
        await client.request("reference.operation.preflight", params)
        connection = sqlite3.connect(self.daemon.database_path)
        try:
            anchor_count, previous_hash = connection.execute(
                """
                SELECT ledger_entry_count, ledger_head_hash
                FROM reference_operations WHERE operation_id = ?
                """,
                (operation_id,),
            ).fetchone()
            for index in range(anchor_count, 128):
                entry_id = str(uuid.uuid4())
                created_at = 1_800_000_000.0 + index
                payload = {
                    "operationId": operation_id,
                    "phase": "capacity-fill",
                    "status": "queued",
                    "checkpoint": "authorized",
                    "progress": 5,
                }
                entry_hash = ReferenceOperationStore._ledger_hash(
                    entry_id=entry_id,
                    operation_id=operation_id,
                    event_type="capacity.fill",
                    payload=payload,
                    previous_hash=previous_hash,
                    created_at=created_at,
                )
                connection.execute(
                    """
                    INSERT INTO reference_operation_ledger(
                      entry_id, operation_id, event_type, payload_json,
                      previous_hash, entry_hash, created_at
                    ) VALUES (?, ?, 'capacity.fill', ?, ?, ?, ?)
                    """,
                    (
                        entry_id,
                        operation_id,
                        canonical_json(payload),
                        previous_hash,
                        entry_hash,
                        created_at,
                    ),
                )
                previous_hash = entry_hash
            connection.execute(
                """
                UPDATE reference_operations
                SET status = 'queued', checkpoint = 'authorized', progress = 5,
                    ledger_entry_count = 128, ledger_head_hash = ?
                WHERE operation_id = ?
                """,
                (previous_hash, operation_id),
            )
            connection.commit()
        finally:
            connection.close()
        self.daemon.crash()
        await client.close()

        self.daemon.start()
        recovery = await self.daemon.client("reference-ledger-capacity-recovery")
        try:
            failed = await recovery.request(
                "reference.operation.get",
                {
                    "operationId": operation_id,
                    "recoveryToken": params["recoveryToken"],
                },
            )
            self.assertEqual(failed["status"], "failed")
            self.assertEqual(failed["error"]["code"], "ledger.capacity-exhausted")
            health = await recovery.request("health", {})
            self.assertEqual(health["status"], "healthy")
            page = await recovery.request(
                "reference.operation.ledger",
                {
                    "operationId": operation_id,
                    "recoveryToken": params["recoveryToken"],
                    "limit": 8,
                },
            )
            self.assertTrue(page["verified"])
            self.assertEqual(page["totalEntryCount"], 128)
            self.assertEqual(page["entryCount"], 8)
            self.assertLess(len(canonical_json(page).encode("utf-8")), MAX_FRAME_BYTES)
        finally:
            await recovery.close()

    async def test_contract_is_closed_and_ledger_tampering_is_detected(self) -> None:
        client = await self.daemon.client("reference-validation")
        params = preflight_params(pace="immediate")
        operation_id = params["operationId"]
        try:
            malformed = dict(params)
            malformed["unexpected"] = True
            with self.assertRaises(FabricError) as closed:
                await client.request("reference.operation.preflight", malformed)
            self.assertEqual(closed.exception.code, "rpc.invalid-params")
            path_params = preflight_params(resource_id="../../host")
            with self.assertRaises(FabricError) as path:
                await client.request("reference.operation.preflight", path_params)
            self.assertEqual(path.exception.code, "rpc.invalid-params")

            await client.request("reference.operation.preflight", params)
            await self.approve_and_start(client, operation_id)
            await self.wait_for_status(client, operation_id, {"succeeded"})
            connection = sqlite3.connect(self.daemon.database_path)
            try:
                connection.execute(
                    """
                    UPDATE reference_operation_ledger SET payload_json = '{"tampered":true}'
                    WHERE operation_id = ? AND sequence = (
                      SELECT MIN(sequence) FROM reference_operation_ledger WHERE operation_id = ?
                    )
                    """,
                    (operation_id, operation_id),
                )
                connection.commit()
            finally:
                connection.close()
            with self.assertRaises(FabricError) as integrity:
                await client.request("reference.operation.ledger", {"operationId": operation_id})
            self.assertEqual(integrity.exception.code, "ledger.integrity-failed")
        finally:
            await client.close()

if __name__ == "__main__":
    unittest.main()
