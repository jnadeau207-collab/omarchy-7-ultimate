from __future__ import annotations

import asyncio
import errno
import os
import sqlite3
import stat
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest import mock

from helper import Harness

from omarchy_fabric.models import FabricError
from omarchy_fabric.operations.contracts import OperationCheckpoint, OperationStatus
from omarchy_fabric.operations.store import OperationStore


class OperationRecoveryTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.harness = Harness()

    async def asyncTearDown(self) -> None:
        self.harness.close()

    def _reopen(self) -> None:
        self.harness.store.close()
        self.harness.store = OperationStore(self.harness.store_path, clock=self.harness.clock)
        self.harness.store.open()
        self.harness.coordinator = self.harness.make_coordinator()

    async def test_restart_after_authorization_requires_owner_reconciliation_and_does_not_apply(self) -> None:
        async def crash(operation_id, checkpoint):
            if checkpoint == OperationCheckpoint.AUTHORIZED.value:
                raise RuntimeError("simulated process death")

        self.harness.coordinator.checkpoint_hook = crash
        operation_id = await self.harness.preflight()
        with self.assertRaisesRegex(RuntimeError, "simulated"):
            await self.harness.start(operation_id)
        self.assertEqual(self.harness.store.get(operation_id).status, OperationStatus.AUTHORIZED)
        self.assertFalse(self.harness.executor.state("setting.primary")["value"])
        self._reopen()
        self.assertEqual(self.harness.coordinator.recover_startup(), [operation_id])
        self.assertEqual(self.harness.coordinator.recover_startup(), [])
        replacement = self.harness.replacement_session()
        cancelled = self.harness.coordinator.cancel(replacement, operation_id)
        self.assertTrue(cancelled["cancellationRequested"])
        result = await self.harness.coordinator.reconcile(replacement, operation_id)
        self.assertEqual(result["status"], "cancelled")
        self.assertFalse(self.harness.executor.state("setting.primary")["value"])
        self.assertEqual([call[0] for call in self.harness.executor.calls].count("apply"), 0)

    async def test_restart_after_applied_checkpoint_validates_without_reapplying(self) -> None:
        async def crash(operation_id, checkpoint):
            if checkpoint == OperationCheckpoint.APPLIED.value:
                raise RuntimeError("simulated process death")

        self.harness.coordinator.checkpoint_hook = crash
        operation_id = await self.harness.preflight()
        with self.assertRaisesRegex(RuntimeError, "simulated"):
            await self.harness.start(operation_id)
        self.assertTrue(self.harness.executor.state("setting.primary")["value"])
        self._reopen()
        self.harness.coordinator.recover_startup()
        replacement = self.harness.replacement_session()
        result = await self.harness.coordinator.reconcile(replacement, operation_id)
        self.assertEqual(result["status"], "succeeded")
        self.assertTrue(result["result"]["reconciled"])
        self.assertEqual([call[0] for call in self.harness.executor.calls].count("apply"), 1)

    async def test_disk_full_after_apply_never_reports_false_checkpoint_and_restart_reconciles(self) -> None:
        def probe(label: str) -> None:
            if label == "append-apply-finished":
                raise OSError(errno.ENOSPC, "simulated full disk")

        self.harness.store.durability_probe = probe
        operation_id = await self.harness.preflight()
        with self.assertRaises(FabricError) as caught:
            await self.harness.start(operation_id)
        self.assertEqual(caught.exception.code, "operation.storage-unavailable")
        self.assertTrue(self.harness.executor.state("setting.primary")["value"])
        self.assertEqual(self.harness.store.get(operation_id).checkpoint, OperationCheckpoint.APPLYING)
        self.harness.store.durability_probe = None
        self._reopen()
        self.harness.coordinator.recover_startup()
        result = await self.harness.coordinator.reconcile(self.harness.replacement_session(), operation_id)
        self.assertEqual(result["status"], "succeeded")
        self.assertEqual([call[0] for call in self.harness.executor.calls].count("apply"), 1)

    async def test_crash_after_external_approval_consumption_before_authorization_is_safe(self) -> None:
        def probe(label: str) -> None:
            if label == "append-authorized":
                raise OSError(errno.ENOSPC, "simulated full disk")

        operation_id = await self.harness.preflight()
        approval = self.harness.approval(operation_id)
        self.harness.store.durability_probe = probe
        with self.assertRaises(FabricError) as caught:
            await self.harness.start(operation_id, approval)
        self.assertEqual(caught.exception.code, "operation.storage-unavailable")
        self.assertIsNotNone(self.harness.approvals.get(approval.approval_id).consumed_at)
        state = self.harness.store.get(operation_id)
        self.assertEqual(state.status, OperationStatus.AWAITING_APPROVAL)
        self.assertEqual(state.checkpoint, OperationCheckpoint.APPROVAL)
        self.assertFalse(self.harness.executor.calls)
        self.harness.store.durability_probe = None
        replacement = self.harness.approval(operation_id)
        result = await self.harness.start(operation_id, replacement)
        self.assertEqual(result["status"], "succeeded")

    async def test_replacement_session_cannot_reconcile_non_interrupted_work(self) -> None:
        operation_id = await self.harness.preflight()
        with self.assertRaises(FabricError) as caught:
            await self.harness.coordinator.reconcile(self.harness.replacement_session(), operation_id)
        self.assertEqual(caught.exception.code, "operation.reconcile-state")
        with self.assertRaises(FabricError) as caught:
            self.harness.coordinator.cancel(self.harness.replacement_session(), operation_id)
        self.assertEqual(caught.exception.code, "operation.recovery-session-required")


class OperationStoreAdversarialTests(unittest.IsolatedAsyncioTestCase):
    async def test_arbitrary_durability_probe_failure_rolls_back_and_store_remains_live(self) -> None:
        armed = True

        def probe(label: str) -> None:
            nonlocal armed
            if armed and label == "create-plan":
                armed = False
                raise RuntimeError("injected non-storage probe failure")

        harness = Harness(store_kwargs={"durability_probe": probe})
        try:
            connection = harness.store.connection
            with self.assertRaisesRegex(RuntimeError, "non-storage probe"):
                await harness.preflight()
            self.assertIsNotNone(connection)
            self.assertFalse(connection.in_transaction)
            self.assertEqual(harness.store.verify_all(), 0)
            harness.store.durability_probe = None
            operation_id = await harness.preflight(key="probe.failure.retry")
            self.assertEqual(harness.store.get(operation_id).status, OperationStatus.AWAITING_APPROVAL)
        finally:
            harness.close()

    async def test_disk_full_during_plan_is_atomic_and_retriable(self) -> None:
        armed = True

        def probe(label: str) -> None:
            nonlocal armed
            if armed and label == "create-plan":
                armed = False
                raise OSError(errno.ENOSPC, "simulated full disk")

        harness = Harness(store_kwargs={"durability_probe": probe})
        try:
            with self.assertRaises(FabricError) as caught:
                await harness.preflight()
            self.assertEqual(caught.exception.code, "operation.storage-unavailable")
            self.assertEqual(harness.store.verify_all(), 0)
            operation_id = await harness.preflight()
            self.assertEqual(harness.store.get(operation_id).status, OperationStatus.AWAITING_APPROVAL)
        finally:
            harness.close()

    async def test_event_retention_is_bounded_and_stops_before_approval_consumption(self) -> None:
        harness = Harness(store_kwargs={"max_events_per_operation": 16})
        try:
            operation_id = await harness.preflight()
            approval = harness.approval(operation_id)
            for index in range(15):
                harness.store.append(
                    operation_id,
                    "checkpoint-observed",
                    OperationCheckpoint.PREFLIGHT,
                    OperationStatus.AWAITING_APPROVAL,
                    {"index": index},
                )
            self.assertEqual(harness.store.get(operation_id).event_count, 16)
            with self.assertRaises(FabricError) as caught:
                await harness.start(operation_id, approval)
            self.assertEqual(caught.exception.code, "operation.ledger-capacity")
            self.assertIsNone(harness.approvals.get(approval.approval_id).consumed_at)
        finally:
            harness.close()

    async def test_ledger_pagination_is_bounded_and_hash_chain_verifies(self) -> None:
        harness = Harness()
        try:
            operation_id = await harness.preflight()
            await harness.start(operation_id)
            first = harness.store.ledger(operation_id, limit=2)
            self.assertEqual(len(first["entries"]), 2)
            self.assertTrue(first["hasMore"])
            second = harness.store.ledger(operation_id, after_sequence=first["nextSequence"], limit=64)
            self.assertGreater(len(second["entries"]), 0)
            self.assertFalse(second["hasMore"])
            with self.assertRaises(FabricError):
                harness.store.ledger(operation_id, limit=65)
            self.assertEqual(harness.store.verify_all(), 1)
        finally:
            harness.close()

    async def test_terminal_state_is_append_only_and_cannot_be_reopened(self) -> None:
        harness = Harness()
        try:
            operation_id = await harness.preflight()
            await harness.start(operation_id)
            with self.assertRaises(FabricError) as caught:
                harness.store.append(
                    operation_id,
                    "illegal-reopen",
                    OperationCheckpoint.APPLYING,
                    OperationStatus.RUNNING,
                    {},
                )
            self.assertEqual(caught.exception.code, "operation.terminal")
        finally:
            harness.close()

    async def test_cancel_vs_terminal_race_is_idempotent(self) -> None:
        for index in range(12):
            harness = Harness()
            try:
                operation_id = await harness.preflight(key=f"cancel.race.{index}")
                with ThreadPoolExecutor(max_workers=2) as pool:
                    cancel_future = pool.submit(harness.store.request_cancel, operation_id)
                    finish_future = pool.submit(
                        harness.store.append,
                        operation_id,
                        "cancelled-before-authorization",
                        OperationCheckpoint.FINISHED,
                        OperationStatus.CANCELLED,
                        {"result": {"cancelled": True, "mutationApplied": False}},
                    )
                    outcomes = []
                    for future in (cancel_future, finish_future):
                        try:
                            outcomes.append(future.result())
                        except FabricError as error:
                            # A direct internal terminal append can lose the race;
                            # the coordinator converts this exact result to state.
                            self.assertEqual(error.code, "operation.terminal")
                state = harness.store.get(operation_id)
                self.assertEqual(state.status, OperationStatus.CANCELLED)
                self.assertLessEqual(
                    sum(entry["eventType"] == "cancellation-requested" for entry in harness.store.ledger(operation_id)["entries"]),
                    1,
                )
            finally:
                harness.close()

    async def test_two_store_instances_replay_one_immutable_idempotency_claim(self) -> None:
        harness = Harness()
        second_store = None
        original_store = harness.store
        try:
            first = await harness.coordinator.preflight(
                harness.principal,
                provider_id="test.settings",
                action="settings.set",
                arguments={"resourceId": "setting.primary", "desired": True},
                idempotency_key="cross.instance",
            )
            second_store = OperationStore(harness.store_path, clock=harness.clock)
            second_store.open()
            harness.store = second_store
            second_coordinator = harness.make_coordinator()
            replay = await second_coordinator.preflight(
                harness.principal,
                provider_id="test.settings",
                action="settings.set",
                arguments={"resourceId": "setting.primary", "desired": True},
                idempotency_key="cross.instance",
            )
            self.assertEqual(replay["operationId"], first["operationId"])
            self.assertTrue(replay["replayed"])
        finally:
            if second_store is not None:
                second_store.close()
            harness.store = original_store
            harness.close()

    async def test_semantic_journal_corruption_fails_closed_on_reopen(self) -> None:
        harness = Harness()
        path = harness.store_path
        operation_id = await harness.preflight()
        harness.store.close()
        connection = sqlite3.connect(path)
        connection.execute("DROP TRIGGER operation_events_no_update")
        connection.execute(
            "UPDATE operation_events SET payload_json='{}' WHERE operation_id=? AND sequence=1",
            (operation_id,),
        )
        connection.execute(
            "CREATE TRIGGER operation_events_no_update BEFORE UPDATE ON operation_events "
            "BEGIN SELECT RAISE(ABORT, 'append-only events'); END"
        )
        connection.commit()
        connection.close()
        store = OperationStore(path, clock=harness.clock)
        try:
            with self.assertRaises(FabricError) as caught:
                store.open()
            self.assertEqual(caught.exception.code, "operation.ledger-corrupt")
            self.assertIsNone(store.connection)
        finally:
            store.close()
            harness.temp.cleanup()

    async def test_extra_schema_object_and_scalar_plan_drift_fail_closed(self) -> None:
        for mutation, expected_code in (
            (
                "CREATE TRIGGER injected_trigger AFTER INSERT ON operations BEGIN SELECT 1; END",
                "operation.store-schema",
            ),
            (
                "DROP TRIGGER operations_no_update; "
                "UPDATE operations SET owner_id='account.uid.9999'; "
                "CREATE TRIGGER operations_no_update BEFORE UPDATE ON operations "
                "BEGIN SELECT RAISE(ABORT, 'append-only operations'); END",
                "operation.plan-corrupt",
            ),
        ):
            harness = Harness()
            path = harness.store_path
            await harness.preflight()
            harness.store.close()
            connection = sqlite3.connect(path)
            connection.executescript(mutation)
            connection.commit()
            connection.close()
            store = OperationStore(path, clock=harness.clock)
            try:
                with self.assertRaises(FabricError) as caught:
                    store.open()
                self.assertEqual(caught.exception.code, expected_code)
            finally:
                store.close()
                harness.temp.cleanup()

    async def test_table_sql_check_generated_and_strict_tampering_fails_closed(self) -> None:
        for mutation in ("check", "generated", "strict"):
            with self.subTest(mutation=mutation):
                harness = Harness()
                path = harness.store_path
                await harness.preflight(key=f"schema.{mutation}")
                harness.store.close()
                connection = sqlite3.connect(path)
                if mutation == "generated":
                    connection.execute(
                        "ALTER TABLE operations ADD COLUMN injected TEXT GENERATED ALWAYS AS ('x') VIRTUAL"
                    )
                else:
                    schema_version = int(connection.execute("PRAGMA schema_version").fetchone()[0])
                    connection.execute("PRAGMA writable_schema = ON")
                    if mutation == "check":
                        connection.execute(
                            "UPDATE sqlite_master SET sql=replace(sql, "
                            "'created_at TEXT NOT NULL,', "
                            "'created_at TEXT NOT NULL CHECK(length(created_at) > 0),') "
                            "WHERE type='table' AND name='operations'"
                        )
                    else:
                        connection.execute(
                            "UPDATE sqlite_master SET sql=sql || ' STRICT' "
                            "WHERE type='table' AND name='operations'"
                        )
                    connection.execute(f"PRAGMA schema_version = {schema_version + 1}")
                    connection.execute("PRAGMA writable_schema = OFF")
                connection.commit()
                connection.close()
                store = OperationStore(path, clock=harness.clock)
                try:
                    with self.assertRaises(FabricError) as caught:
                        store.open()
                    self.assertEqual(caught.exception.code, "operation.store-schema")
                finally:
                    store.close()
                    harness.temp.cleanup()

    async def test_failed_structural_closure_does_not_mutate_database(self) -> None:
        harness = Harness()
        path = harness.store_path
        await harness.preflight()
        harness.store.close()
        connection = sqlite3.connect(path)
        connection.execute("CREATE TRIGGER injected_order_probe AFTER INSERT ON operations BEGIN SELECT 1; END")
        connection.commit()
        connection.close()
        before = path.read_bytes()
        store = OperationStore(path, clock=harness.clock)
        try:
            with self.assertRaises(FabricError) as caught:
                store.open()
            self.assertEqual(caught.exception.code, "operation.store-schema")
            self.assertEqual(path.read_bytes(), before)
            self.assertFalse(Path(f"{path}-journal").exists())
        finally:
            store.close()
            harness.temp.cleanup()

    async def test_consumed_approval_relation_corruption_fails_closed(self) -> None:
        harness = Harness()
        path = harness.store_path
        operation_id = await harness.preflight()
        await harness.start(operation_id)
        harness.store.close()
        connection = sqlite3.connect(path)
        connection.executescript(
            "DROP TRIGGER approvals_no_update; "
            "UPDATE consumed_operation_approvals SET binding_digest='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'; "
            "CREATE TRIGGER approvals_no_update BEFORE UPDATE ON consumed_operation_approvals "
            "BEGIN SELECT RAISE(ABORT, 'append-only approvals'); END"
        )
        connection.commit()
        connection.close()
        store = OperationStore(path, clock=harness.clock)
        try:
            with self.assertRaises(FabricError) as caught:
                store.open()
            self.assertEqual(caught.exception.code, "operation.ledger-corrupt")
        finally:
            store.close()
            harness.temp.cleanup()

    async def test_startup_row_and_event_bounds_fail_before_unbounded_load(self) -> None:
        harness = Harness()
        path = harness.store_path
        operation_id = await harness.preflight()
        harness.store.close()
        connection = sqlite3.connect(path)
        source = connection.execute("SELECT * FROM operations WHERE operation_id=?", (operation_id,)).fetchone()
        columns = [row[1] for row in connection.execute("PRAGMA table_info(operations)") if row[1] != "ordinal"]
        placeholders = ",".join("?" for _ in columns)
        for index in range(16):
            values = list(source[1:])
            values[0] = str(uuid.uuid4())
            values[9] = f"{'b' * 62}{index:02x}"
            connection.execute(
                f"INSERT INTO operations({','.join(columns)}) VALUES ({placeholders})",
                values,
            )
        connection.commit()
        connection.close()
        store = OperationStore(path, clock=harness.clock, max_operations=16)
        try:
            with self.assertRaises(FabricError) as caught:
                store.open()
            self.assertEqual(caught.exception.code, "operation.store-corrupt")
        finally:
            store.close()
            harness.temp.cleanup()

    async def test_operation_lock_map_is_bounded_and_evicts_idle_entries(self) -> None:
        harness = Harness()
        try:
            harness.coordinator = harness.make_coordinator(max_operation_locks=1)
            held = await harness.coordinator._acquire_operation_lock("operation.one")
            with self.assertRaises(FabricError) as caught:
                await harness.coordinator._acquire_operation_lock("operation.two")
            self.assertEqual(caught.exception.code, "operation.lock-backpressure")
            harness.coordinator._release_operation_lock_reference("operation.one", held, acquired=True)
            self.assertEqual(harness.coordinator._operation_locks, {})
            operation_id = await harness.preflight()
            await harness.start(operation_id)
            self.assertEqual(harness.coordinator._operation_locks, {})
        finally:
            harness.close()

    @unittest.skipIf(os.name == "nt", "POSIX inode and symlink semantics")
    async def test_symlink_and_hardlink_database_paths_are_rejected(self) -> None:
        harness = Harness()
        original = harness.store_path
        harness.store.close()
        symlink = original.with_name("linked.db")
        symlink.symlink_to(original)
        with self.assertRaises(FabricError) as caught:
            OperationStore(symlink).open()
        self.assertEqual(caught.exception.code, "operation.store-unsafe-path")
        symlink.unlink()
        hardlink = original.with_name("hard.db")
        os.link(original, hardlink)
        with self.assertRaises(FabricError) as caught:
            OperationStore(hardlink).open()
        self.assertEqual(caught.exception.code, "operation.store-unsafe-path")
        hardlink.unlink()
        harness.temp.cleanup()

    @unittest.skipIf(os.name == "nt", "POSIX descriptor identity semantics")
    async def test_rollback_journal_requires_a_live_sqlite_descriptor(self) -> None:
        harness = Harness()
        try:
            connection = harness.store.connection
            original = harness.store._matching_descriptors

            def hide_journal(identity, *, exclude=frozenset()):
                if Path(f"{harness.store_path}-journal").exists():
                    return frozenset()
                return original(identity, exclude=exclude)

            harness.store._matching_descriptors = hide_journal
            with self.assertRaises(FabricError) as caught:
                await harness.preflight(key="journal.fd.hidden")
            self.assertEqual(caught.exception.code, "operation.store-unsafe-path")
            self.assertFalse(connection.in_transaction)
            harness.store._matching_descriptors = original
            operation_id = await harness.preflight(key="journal.fd.retry")
            self.assertEqual(harness.store.get(operation_id).status, OperationStatus.AWAITING_APPROVAL)
        finally:
            harness.close()

    @unittest.skipIf(os.name == "nt", "POSIX symlink semantics")
    async def test_rollback_journal_symlink_is_rejected_before_open(self) -> None:
        harness = Harness()
        path = harness.store_path
        harness.store.close()
        target = path.with_name("journal-target")
        target.write_bytes(b"not a journal")
        journal = Path(f"{path}-journal")
        journal.symlink_to(target)
        store = OperationStore(path, clock=harness.clock)
        try:
            with self.assertRaises(FabricError) as caught:
                store.open()
            self.assertEqual(caught.exception.code, "operation.store-unsafe-path")
        finally:
            store.close()
            journal.unlink(missing_ok=True)
            target.unlink(missing_ok=True)
            harness.temp.cleanup()

    @unittest.skipIf(os.name == "nt", "POSIX inode identity semantics")
    async def test_database_path_swap_fails_closed_and_can_reopen_after_restore(self) -> None:
        harness = Harness()
        path = harness.store_path
        displaced = path.with_name("operations.displaced.db")
        path.rename(displaced)
        path.touch(mode=0o600)
        try:
            with self.assertRaises(FabricError) as caught:
                harness.store.verify_all()
            self.assertEqual(caught.exception.code, "operation.store-unsafe-path")
        finally:
            harness.store.close()
            path.unlink(missing_ok=True)
            displaced.rename(path)
        try:
            harness.store.open()
            operation_id = await harness.preflight(key="path.swap.recovered")
            self.assertEqual(harness.store.get(operation_id).status, OperationStatus.AWAITING_APPROVAL)
        finally:
            harness.close()

    @unittest.skipIf(os.name == "nt", "POSIX descriptor accounting")
    async def test_close_failure_releases_connection_and_all_held_descriptors(self) -> None:
        harness = Harness()
        store = harness.store
        sqlite_descriptor = store._sqlite_descriptor
        held_descriptors = (store._held_descriptor, store._held_directory_descriptor)
        wrapped = store.connection

        class CloseFailure:
            def __init__(self, connection) -> None:
                self.connection = connection

            def close(self) -> None:
                self.connection.close()
                raise OSError(errno.EIO, "injected close failure")

            def __getattr__(self, name):
                return getattr(self.connection, name)

        store.connection = CloseFailure(wrapped)
        try:
            with self.assertRaises(OSError):
                store.close()
            self.assertIsNone(store.connection)
            self.assertIsNone(store._held_descriptor)
            self.assertIsNone(store._held_directory_descriptor)
            for descriptor in (*held_descriptors, sqlite_descriptor):
                with self.assertRaises(OSError):
                    os.fstat(descriptor)
        finally:
            harness.close()

    @unittest.skipIf(os.name == "nt", "POSIX descriptor accounting")
    async def test_one_descriptor_close_failure_does_not_skip_other_cleanup(self) -> None:
        harness = Harness()
        store = harness.store
        database_descriptor = store._held_descriptor
        directory_descriptor = store._held_directory_descriptor
        real_close = os.close
        failed_once = False

        def flaky_close(descriptor: int) -> None:
            nonlocal failed_once
            if descriptor == database_descriptor and not failed_once:
                failed_once = True
                raise OSError(errno.EIO, "injected descriptor close failure")
            real_close(descriptor)

        try:
            with mock.patch("omarchy_fabric.operations.store.os.close", side_effect=flaky_close):
                with self.assertRaises(OSError):
                    store.close()
            self.assertTrue(failed_once)
            self.assertIsNone(store.connection)
            for descriptor in (database_descriptor, directory_descriptor):
                with self.assertRaises(OSError):
                    os.fstat(descriptor)
        finally:
            harness.close()

    @unittest.skipIf(os.name == "nt", "POSIX permissions")
    async def test_database_and_private_directory_modes_are_enforced(self) -> None:
        harness = Harness()
        try:
            self.assertEqual(stat.S_IMODE(harness.store_path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(harness.store_path.parent.stat().st_mode), 0o700)
        finally:
            harness.close()


if __name__ == "__main__":
    unittest.main()
