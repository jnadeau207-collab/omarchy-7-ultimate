from __future__ import annotations

import asyncio
import unittest

from helper import Harness

from omarchy_fabric.models import FabricError
from omarchy_fabric.operations.contracts import OperationCheckpoint, OperationStatus


class OperationLifecycleTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.harness = Harness()

    async def asyncTearDown(self) -> None:
        self.harness.close()

    async def test_success_binds_every_authority_and_validates_postcondition(self) -> None:
        operation_id = await self.harness.preflight()
        plan = self.harness.store.get(operation_id).plan
        request = self.harness.coordinator.approval_request(self.harness.principal, operation_id)
        self.assertEqual(request.arguments["ownerId"], "account.uid.1000")
        self.assertEqual(request.arguments["providerGeneration"], 1)
        self.assertEqual(request.arguments["providerFingerprint"], "a" * 64)
        self.assertEqual(request.arguments["policyRevision"], "policy.revision.1")
        self.assertEqual(request.arguments["idempotencyDigest"], plan.idempotency_digest)
        self.assertEqual(request.arguments["intentDigest"], plan.intent.digest)
        result = await self.harness.start(operation_id)
        self.assertEqual(result["status"], "succeeded")
        self.assertEqual(result["checkpoint"], "finished")
        self.assertTrue(self.harness.executor.state("setting.primary")["value"])
        events = [entry["eventType"] for entry in self.harness.store.ledger(operation_id)["entries"]]
        self.assertEqual(
            events,
            [
                "preflight-frozen",
                "approval-checked",
                "authorized",
                "apply-started",
                "apply-finished",
                "validation-started",
                "postcondition-validated",
            ],
        )

    async def test_idempotent_preflight_replays_exact_request_and_conflicts_on_drift(self) -> None:
        first = await self.harness.coordinator.preflight(
            self.harness.principal,
            provider_id="test.settings",
            action="settings.set",
            arguments={"resourceId": "setting.primary", "desired": True},
            idempotency_key="same.key",
        )
        second = await self.harness.coordinator.preflight(
            self.harness.principal,
            provider_id="test.settings",
            action="settings.set",
            arguments={"resourceId": "setting.primary", "desired": True},
            idempotency_key="same.key",
        )
        self.assertEqual(second["operationId"], first["operationId"])
        self.assertTrue(second["replayed"])
        with self.assertRaises(FabricError) as caught:
            await self.harness.coordinator.preflight(
                self.harness.principal,
                provider_id="test.settings",
                action="settings.set",
                arguments={"resourceId": "setting.primary", "desired": False},
                idempotency_key="same.key",
            )
        self.assertEqual(caught.exception.code, "operation.idempotency-conflict")

    async def test_apply_response_loss_reconciles_desired_state_without_reapplying(self) -> None:
        self.harness.executor.faults["apply"] = "fail-after"
        operation_id = await self.harness.preflight()
        result = await self.harness.start(operation_id)
        self.assertEqual(result["status"], "succeeded")
        self.assertTrue(result["result"]["reconciled"])
        self.assertEqual([call[0] for call in self.harness.executor.calls].count("apply"), 1)
        self.assertTrue(self.harness.executor.state("setting.primary")["value"])

    async def test_partial_apply_is_never_guessed_or_rolled_back(self) -> None:
        self.harness.executor.faults["apply"] = "partial"
        operation_id = await self.harness.preflight()
        result = await self.harness.start(operation_id)
        self.assertEqual(result["status"], "failed")
        self.assertEqual(self.harness.executor.state("setting.primary")["value"], {"partial": True})
        self.assertNotIn("rollback", [call[0] for call in self.harness.executor.calls])
        ledger = str(self.harness.store.ledger(operation_id))
        self.assertIn("manualReconciliationRequired", ledger)

    async def test_validation_failure_rolls_back_and_validates_prior_state(self) -> None:
        self.harness.executor.faults["validate"] = "mismatch"
        operation_id = await self.harness.preflight()
        result = await self.harness.start(operation_id)
        self.assertEqual(result["status"], "failed")
        self.assertFalse(self.harness.executor.state("setting.primary")["value"])
        self.assertEqual([call[0] for call in self.harness.executor.calls].count("rollback"), 1)
        self.assertIn("rollback-validated", str(self.harness.store.ledger(operation_id)))

    async def test_rollback_failure_is_terminal_and_requires_reconciliation(self) -> None:
        self.harness.executor.faults.update({"validate": "mismatch", "rollback": "fail-before"})
        operation_id = await self.harness.preflight()
        result = await self.harness.start(operation_id)
        self.assertEqual(result["status"], "failed")
        self.assertTrue(self.harness.executor.state("setting.primary")["value"])
        self.assertIn("manualReconciliationRequired", str(self.harness.store.ledger(operation_id)))

    async def test_newer_external_revision_blocks_rollback(self) -> None:
        async def hook(operation_id, checkpoint):
            if checkpoint == OperationCheckpoint.VALIDATING.value:
                self.harness.executor.external_set("setting.primary", "newer-intent")

        self.harness.coordinator.checkpoint_hook = hook
        self.harness.executor.faults["validate"] = "mismatch"
        operation_id = await self.harness.preflight()
        result = await self.harness.start(operation_id)
        self.assertEqual(result["status"], "failed")
        self.assertEqual(self.harness.executor.state("setting.primary")["value"], "newer-intent")
        self.assertIn("rollback-superseded", str(self.harness.store.ledger(operation_id)))

    async def test_executor_timeout_enters_reconciliation_instead_of_retrying_apply(self) -> None:
        self.harness.executor.faults["apply"] = "timeout"
        self.harness.coordinator.execution_timeout_seconds = 0.05
        operation_id = await self.harness.preflight()
        result = await self.harness.start(operation_id)
        self.assertEqual(result["status"], "failed")
        self.assertFalse(self.harness.executor.state("setting.primary")["value"])
        self.assertEqual([call[0] for call in self.harness.executor.calls].count("apply"), 1)
        self.assertIn("reconciled-before-state", str(self.harness.store.ledger(operation_id)))

    async def test_backpressure_does_not_consume_waiting_approval(self) -> None:
        self.harness.executor.delay_seconds = 0.15
        self.harness.coordinator = self.harness.make_coordinator(
            max_concurrent=1,
            queue_timeout_seconds=0.03,
            execution_timeout_seconds=1.0,
        )
        first = await self.harness.preflight(resource_id="setting.primary", key="first.key")
        second = await self.harness.preflight(resource_id="setting.secondary", key="second.key")
        first_approval = self.harness.approval(first)
        second_approval = self.harness.approval(second)
        running = asyncio.create_task(self.harness.start(first, first_approval))
        await asyncio.sleep(0.02)
        with self.assertRaises(FabricError) as caught:
            await self.harness.start(second, second_approval)
        self.assertEqual(caught.exception.code, "operation.backpressure")
        self.assertIsNone(self.harness.approvals.get(second_approval.approval_id).consumed_at)
        await running
        result = await self.harness.start(second, second_approval)
        self.assertEqual(result["status"], "succeeded")

    async def test_duplicate_start_waits_are_bounded_and_do_not_consume_second_approval(self) -> None:
        entered = asyncio.Event()

        async def stage_hook(stage, _plan):
            if stage == "apply":
                entered.set()

        self.harness.executor.delay_seconds = 0.15
        self.harness.executor.stage_hook = stage_hook
        self.harness.coordinator = self.harness.make_coordinator(
            max_concurrent=2,
            queue_timeout_seconds=0.03,
            execution_timeout_seconds=1.0,
        )
        operation_id = await self.harness.preflight()
        first_approval = self.harness.approval(operation_id)
        second_approval = self.harness.approval(operation_id)
        running = asyncio.create_task(self.harness.start(operation_id, first_approval))
        await asyncio.wait_for(entered.wait(), timeout=1.0)
        with self.assertRaises(FabricError) as caught:
            await self.harness.start(operation_id, second_approval)
        self.assertEqual(caught.exception.code, "operation.backpressure")
        self.assertIsNone(self.harness.approvals.get(second_approval.approval_id).consumed_at)
        self.assertEqual((await running)["status"], "succeeded")

    async def test_caller_task_cancellation_is_durably_interrupted_and_reconcilable(self) -> None:
        entered = asyncio.Event()

        async def stage_hook(stage, _plan):
            if stage == "apply":
                entered.set()

        self.harness.executor.delay_seconds = 0.5
        self.harness.executor.stage_hook = stage_hook
        operation_id = await self.harness.preflight()
        running = asyncio.create_task(self.harness.start(operation_id))
        await asyncio.wait_for(entered.wait(), timeout=1.0)
        running.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await running
        interrupted = self.harness.store.get(operation_id)
        self.assertEqual(interrupted.status, OperationStatus.INTERRUPTED)
        self.assertIn("runtime-interrupted", str(self.harness.store.ledger(operation_id)))
        self.harness.executor.delay_seconds = 0
        recovered = await self.harness.coordinator.reconcile(self.harness.principal, operation_id)
        self.assertEqual(recovered["status"], "failed")
        self.assertFalse(self.harness.executor.state("setting.primary")["value"])

    async def test_reconciliation_obeys_global_capacity_and_unavailable_executor_is_retryable(self) -> None:
        async def interrupt_after_authorization(_operation_id, checkpoint):
            if checkpoint == OperationCheckpoint.AUTHORIZED.value:
                raise asyncio.CancelledError()

        self.harness.coordinator.checkpoint_hook = interrupt_after_authorization
        first = await self.harness.preflight(resource_id="setting.primary", key="reconcile.first")
        second = await self.harness.preflight(resource_id="setting.secondary", key="reconcile.second")
        for operation_id in (first, second):
            with self.assertRaises(asyncio.CancelledError):
                await self.harness.start(operation_id)
            self.assertEqual(self.harness.store.get(operation_id).status, OperationStatus.INTERRUPTED)

        from omarchy_fabric.operations.executor import UnavailableProductionExecutor

        self.harness.coordinator.checkpoint_hook = None
        self.harness.coordinator.executor = UnavailableProductionExecutor()
        with self.assertRaises(FabricError) as caught:
            await self.harness.coordinator.reconcile(self.harness.principal, first)
        self.assertEqual(caught.exception.code, "executor.production-unavailable")
        self.assertEqual(self.harness.store.get(first).status, OperationStatus.INTERRUPTED)

        entered = asyncio.Event()

        async def reconciliation_hook(stage, plan):
            if stage == "reconcile" and plan.operation_id == first:
                entered.set()

        self.harness.executor.delay_seconds = 0.15
        self.harness.executor.stage_hook = reconciliation_hook
        self.harness.coordinator = self.harness.make_coordinator(
            max_concurrent=1,
            queue_timeout_seconds=0.03,
            execution_timeout_seconds=1.0,
        )
        running = asyncio.create_task(self.harness.coordinator.reconcile(self.harness.principal, first))
        await asyncio.wait_for(entered.wait(), timeout=1.0)
        with self.assertRaises(FabricError) as caught:
            await self.harness.coordinator.reconcile(self.harness.principal, second)
        self.assertEqual(caught.exception.code, "operation.backpressure")
        self.assertEqual((await running)["status"], "failed")
        self.assertEqual(self.harness.store.get(second).status, OperationStatus.INTERRUPTED)


class CancellationCheckpointTests(unittest.IsolatedAsyncioTestCase):
    async def _run_checkpoint(self, checkpoint: str) -> tuple[Harness, str, dict]:
        harness = Harness()

        async def hook(operation_id, observed):
            if observed == checkpoint:
                harness.store.request_cancel(operation_id)

        harness.coordinator.checkpoint_hook = hook
        if checkpoint == OperationCheckpoint.RECONCILING.value:
            harness.executor.faults["apply"] = "fail-after"
        if checkpoint == OperationCheckpoint.ROLLING_BACK.value:
            harness.executor.faults["validate"] = "mismatch"
        operation_id = await harness.preflight()
        if checkpoint == OperationCheckpoint.PREFLIGHT.value:
            result = harness.coordinator.cancel(harness.principal, operation_id)
        else:
            result = await harness.start(operation_id)
        return harness, operation_id, result

    async def test_cancellation_is_durable_at_every_mutation_checkpoint(self) -> None:
        for checkpoint in (
            OperationCheckpoint.PREFLIGHT.value,
            OperationCheckpoint.APPROVAL.value,
            OperationCheckpoint.AUTHORIZED.value,
            OperationCheckpoint.APPLYING.value,
            OperationCheckpoint.APPLIED.value,
            OperationCheckpoint.VALIDATING.value,
            OperationCheckpoint.RECONCILING.value,
            OperationCheckpoint.ROLLING_BACK.value,
        ):
            with self.subTest(checkpoint=checkpoint):
                harness, operation_id, result = await self._run_checkpoint(checkpoint)
                try:
                    self.assertTrue(harness.store.get(operation_id).cancellation_requested)
                    self.assertIn(result["status"], {"cancelled", "failed"})
                    self.assertFalse(harness.executor.state("setting.primary")["value"])
                    if checkpoint == OperationCheckpoint.ROLLING_BACK.value:
                        self.assertIn("rollback-validated", str(harness.store.ledger(operation_id)))
                finally:
                    harness.close()


if __name__ == "__main__":
    unittest.main()
