from __future__ import annotations

import concurrent.futures
import hashlib
import json
import os
import sqlite3
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

from helper import ACTOR, OTHER_ACTOR, ManagedWorkPlane, budget, create_task, inspect_intent, manifest, policy, template
from omarchy_fabric.managed_work import Actor, CapacityLimits, ManagedWorkError
from omarchy_fabric.managed_work.store import CURRENT_SCHEMA, MIGRATIONS


class RestartAdversarialTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def assert_code(self, code: str, call) -> None:
        with self.assertRaises(ManagedWorkError) as caught:
            call()
        self.assertEqual(code, caught.exception.code)

    def test_restart_recovers_executor_owned_states_without_claiming_success(self) -> None:
        path = self.root / "restart.db"
        plane = ManagedWorkPlane(path).open()
        task = create_task(plane)
        plane.transition_task(ACTOR, task["taskId"], expected_revision=1, target="queued", now=1_002)
        run = plane.create_run_plan(
            ACTOR,
            task["taskId"],
            manifest=manifest(),
            idempotency_key="run.restart",
            now=1_003,
        )
        with plane.store.transaction() as connection:
            connection.execute(
                "UPDATE tasks SET state = 'running' WHERE task_id = ?",
                (task["taskId"],),
            )
            connection.execute(
                "UPDATE runs SET state = 'running' WHERE run_id = ?",
                (run["runId"],),
            )
        plane.close()

        reopened = ManagedWorkPlane(path).open()
        try:
            self.assertEqual("interrupted", reopened.get_task(ACTOR, task["taskId"])["state"])
            recovered_run = reopened.get_run(ACTOR, run["runId"])
            self.assertEqual("interrupted", recovered_run["state"])
            self.assertIsNotNone(recovered_run["interruptedAt"])
            self.assertEqual(2, reopened.store.restart_recoveries)
        finally:
            reopened.close()

    def test_failed_post_recovery_capacity_validation_rolls_back_every_recovery_write(self) -> None:
        path = self.root / "recovery-capacity-rollback.db"
        actor = Actor("p" * 160, "s" * 160)
        plane = ManagedWorkPlane(path).open()
        try:
            task = plane.create_task(
                actor,
                title="Near-frame recovery task",
                intent=inspect_intent(chunks=["x" * 16_000] * 3 + ["x" * 5_700]),
                context_ids=[],
                budget=budget(),
                idempotency_key="task.recovery-capacity",
                now=1_000,
            )
            plane.transition_task(actor, task["taskId"], expected_revision=1, target="queued", now=1_001)
            run = plane.create_run_plan(
                actor,
                task["taskId"],
                manifest=manifest(),
                idempotency_key="run.recovery-capacity",
                now=1_002,
            )
            with plane.store.transaction() as connection:
                connection.execute("UPDATE tasks SET state = 'running' WHERE task_id = ?", (task["taskId"],))
                connection.execute("UPDATE runs SET state = 'running' WHERE run_id = ?", (run["runId"],))
        finally:
            plane.close()

        for _ in range(2):
            refused = ManagedWorkPlane(path)
            self.assert_code("managed-work.database-corrupt", refused.open)
            self.assertIsNone(refused.store.connection)
            connection = sqlite3.connect(path)
            try:
                self.assertEqual(
                    "running",
                    connection.execute(
                        "SELECT state FROM tasks WHERE task_id = ?", (task["taskId"],)
                    ).fetchone()[0],
                )
                self.assertEqual(
                    "running",
                    connection.execute(
                        "SELECT state FROM runs WHERE run_id = ?", (run["runId"],)
                    ).fetchone()[0],
                )
            finally:
                connection.close()

    def test_version_one_migrates_with_backup_and_future_schema_refuses(self) -> None:
        path = self.root / "v1.db"
        connection = sqlite3.connect(path)
        try:
            connection.execute("BEGIN IMMEDIATE")
            for statement in MIGRATIONS[1]:
                connection.execute(statement)
            connection.execute("INSERT INTO managed_metadata(key, value) VALUES ('schema_version', '1')")
            connection.execute("PRAGMA user_version = 1")
            connection.execute("COMMIT")
        finally:
            connection.close()
        plane = ManagedWorkPlane(path).open()
        try:
            self.assertEqual(CURRENT_SCHEMA, plane.store.schema_version())
            self.assertIsNotNone(plane.store.backup_path)
            self.assertTrue(plane.store.backup_path.exists())
        finally:
            plane.close()

        future = self.root / "future.db"
        connection = sqlite3.connect(future)
        connection.execute("PRAGMA user_version = 999")
        connection.close()
        self.assert_code("managed-work.database-future", lambda: ManagedWorkPlane(future).open())

    def test_version_two_migration_preserves_rows_and_cursor_contract(self) -> None:
        path = self.root / "v2.db"
        plane = ManagedWorkPlane(path).open()
        for index in range(4):
            create_task(plane, key=f"task.migration-{index}", now=1_000 + index)
        first = plane.query(ACTOR, "agent.tasks", limit=1, now=1_010)
        cursor = first["nextCursor"]
        first_id = first["items"][0]["task"]["taskId"]
        self.assertIsNotNone(cursor)
        plane.close()

        connection = sqlite3.connect(path)
        try:
            connection.execute("DROP TABLE provider_projections")
            connection.execute("DROP TABLE automation_firings")
            for statement in MIGRATIONS[2]:
                connection.execute(statement)
            connection.execute("UPDATE managed_metadata SET value = '2' WHERE key = 'schema_version'")
            connection.execute("PRAGMA user_version = 2")
            connection.commit()
        finally:
            connection.close()

        migrated = ManagedWorkPlane(path).open()
        try:
            self.assertEqual(CURRENT_SCHEMA, migrated.store.schema_version())
            self.assertIsNotNone(migrated.store.backup_path)
            second = migrated.query(
                ACTOR,
                "agent.tasks",
                limit=1,
                cursor=cursor,
                now=1_010,
            )
            self.assertNotEqual(first_id, second["items"][0]["task"]["taskId"])
            self.assertEqual([], migrated.query(ACTOR, "agent.providers", now=1_010)["items"])
        finally:
            migrated.close()

    def test_schema_three_secret_refuses_before_backup_or_migration_artifacts(self) -> None:
        path = self.root / "v3-secret.db"
        plane = ManagedWorkPlane(path).open()
        context = plane.capture_context(
            ACTOR,
            source="focused-application",
            access_scope="principal",
            content={"note": "safe"},
            sensitivity="personal",
            ttl_seconds=600,
            idempotency_key="context.v3-secret",
            now=1_000,
        )
        plane.close()

        token = "sk-proj-" + "q" * 40
        content = {"note": token}
        content_json = json.dumps(content, separators=(",", ":"), sort_keys=True)
        content_hash = hashlib.sha256(content_json.encode("utf-8")).hexdigest()
        connection = sqlite3.connect(path)
        try:
            result = json.loads(
                connection.execute(
                    """
                    SELECT result_json FROM idempotency
                    WHERE action = 'context.capture' AND idempotency_key = 'context.v3-secret'
                    """
                ).fetchone()[0]
            )
            result["content"] = content
            result["contentHash"] = content_hash
            connection.execute(
                "UPDATE contexts SET content_json = ?, content_hash = ? WHERE context_id = ?",
                (content_json, content_hash, context["contextId"]),
            )
            connection.execute(
                """
                UPDATE idempotency SET result_json = ?
                WHERE action = 'context.capture' AND idempotency_key = 'context.v3-secret'
                """,
                (json.dumps(result, separators=(",", ":"), sort_keys=True),),
            )
            connection.execute("DROP INDEX provider_projections_owner_rows")
            connection.execute("DROP TABLE provider_projections")
            for statement in MIGRATIONS[3]:
                connection.execute(statement)
            connection.execute("UPDATE managed_metadata SET value = '3' WHERE key = 'schema_version'")
            connection.execute("PRAGMA user_version = 3")
            connection.commit()
        finally:
            connection.close()

        before_artifacts = {
            candidate.name for candidate in self.root.glob(f"{path.name}*") if candidate != path
        }
        refused = ManagedWorkPlane(path)
        self.assert_code("managed-work.database-corrupt", refused.open)
        self.assertIsNone(refused.store.connection)
        after_artifacts = {
            candidate.name for candidate in self.root.glob(f"{path.name}*") if candidate != path
        }
        self.assertEqual(before_artifacts, after_artifacts)
        self.assertFalse(any("pre-migrate" in name for name in after_artifacts))
        connection = sqlite3.connect(path)
        try:
            self.assertEqual(3, connection.execute("PRAGMA user_version").fetchone()[0])
        finally:
            connection.close()

    def test_current_schema_corruption_refuses_and_failed_open_can_retry(self) -> None:
        path = self.root / "logical-corruption.db"
        plane = ManagedWorkPlane(path).open()
        task = create_task(plane)
        plane.close()

        connection = sqlite3.connect(path)
        connection.execute("UPDATE tasks SET intent_json = '{' WHERE task_id = ?", (task["taskId"],))
        connection.commit()
        connection.close()

        refused = ManagedWorkPlane(path)
        self.assert_code("managed-work.database-corrupt", refused.open)
        self.assertIsNone(refused.store.connection)

        connection = sqlite3.connect(path)
        connection.execute("UPDATE tasks SET intent_json = '{}' WHERE task_id = ?", (task["taskId"],))
        connection.commit()
        connection.close()
        refused.open()
        try:
            self.assertEqual({}, refused.get_task(ACTOR, task["taskId"])["intent"])
        finally:
            refused.close()

        missing = self.root / "missing-table.db"
        ManagedWorkPlane(missing).open().close()
        connection = sqlite3.connect(missing)
        connection.execute("DROP TABLE provider_projections")
        connection.commit()
        connection.close()
        broken = ManagedWorkPlane(missing)
        self.assert_code("managed-work.database-corrupt", broken.open)
        self.assertIsNone(broken.store.connection)

    def test_current_schema_rejects_every_unexpected_sqlite_master_object_before_recovery(self) -> None:
        mutations = {
            "table": "CREATE TABLE rogue_table(value TEXT)",
            "view": "CREATE VIEW rogue_view AS SELECT task_id FROM tasks",
            "index": "CREATE INDEX rogue_index ON tasks(title)",
            "trigger": (
                "CREATE TRIGGER rogue_trigger AFTER INSERT ON managed_events "
                "BEGIN UPDATE tasks SET state = 'failed'; END"
            ),
            "column": "ALTER TABLE tasks ADD COLUMN rogue_column TEXT",
            "missing-index": "DROP INDEX tasks_owner_rows",
        }
        for name, statement in mutations.items():
            with self.subTest(name=name):
                path = self.root / f"schema-{name}.db"
                plane = ManagedWorkPlane(path).open()
                task = create_task(plane, key=f"task.schema-{name}")
                plane.close()
                connection = sqlite3.connect(path)
                try:
                    connection.execute(statement)
                    connection.commit()
                finally:
                    connection.close()
                refused = ManagedWorkPlane(path)
                self.assert_code("managed-work.database-corrupt", refused.open)
                self.assertIsNone(refused.store.connection)
                connection = sqlite3.connect(path)
                try:
                    state = connection.execute(
                        "SELECT state FROM tasks WHERE task_id = ?", (task["taskId"],)
                    ).fetchone()[0]
                    self.assertEqual("draft", state)
                finally:
                    connection.close()

    def test_projection_scalar_payload_mismatch_and_cross_owner_json_links_refuse_restart(self) -> None:
        permission_path = self.root / "projection-coherence.db"
        plane = ManagedWorkPlane(permission_path).open()
        plane.project_permission(
            ACTOR,
            {
                "sourceRevision": 1,
                "grantId": "grant.coherence",
                "capability": "managed.network",
                "resource": "network.internet",
                "state": "active",
                "riskCeiling": "consequential",
                "issuedAt": 1_000,
                "expiresAt": 2_000,
            },
            now=1_001,
        )
        plane.close()
        connection = sqlite3.connect(permission_path)
        try:
            connection.execute(
                "UPDATE permission_projections SET state = 'revoked' WHERE grant_id = 'grant.coherence'"
            )
            connection.commit()
        finally:
            connection.close()
        refused = ManagedWorkPlane(permission_path)
        self.assert_code("managed-work.database-corrupt", refused.open)
        self.assertIsNone(refused.store.connection)

        provider_path = self.root / "provider-coherence.db"
        plane = ManagedWorkPlane(provider_path).open()
        plane.project_provider_inventory(
            ACTOR,
            [
                {
                    "manifest": {"provider": "provider.coherence", "providerVersion": "v0"},
                    "fingerprint": "a" * 64,
                    "generation": 1,
                    "registrationOrder": 0,
                    "state": "available",
                    "detail": "",
                    "registeredAt": 1_000,
                    "changedAt": 1_000,
                }
            ],
            now=1_001,
        )
        plane.close()
        connection = sqlite3.connect(provider_path)
        try:
            connection.execute(
                """
                UPDATE provider_projections
                SET state = 'degraded', code = 'provider.degraded'
                WHERE provider_id = 'provider.coherence'
                """
            )
            connection.commit()
        finally:
            connection.close()
        refused = ManagedWorkPlane(provider_path)
        self.assert_code("managed-work.database-corrupt", refused.open)
        self.assertIsNone(refused.store.connection)

        provider_type_path = self.root / "provider-type-coherence.db"
        plane = ManagedWorkPlane(provider_type_path).open()
        plane.project_provider_inventory(
            ACTOR,
            [
                {
                    "manifest": {"provider": "provider.types", "providerVersion": "v0"},
                    "fingerprint": "b" * 64,
                    "generation": 1,
                    "registrationOrder": 0,
                    "state": "available",
                    "detail": "",
                    "registeredAt": 1_000,
                    "changedAt": 1_000,
                }
            ],
            now=1_001,
        )
        plane.close()
        connection = sqlite3.connect(provider_type_path)
        try:
            payload = json.loads(
                connection.execute(
                    "SELECT payload_json FROM provider_projections WHERE provider_id = 'provider.types'"
                ).fetchone()[0]
            )
            payload["installed"] = 1
            payload["available"] = 1
            connection.execute(
                "UPDATE provider_projections SET payload_json = ? WHERE provider_id = 'provider.types'",
                (json.dumps(payload, separators=(",", ":"), sort_keys=True),),
            )
            connection.commit()
        finally:
            connection.close()
        refused = ManagedWorkPlane(provider_type_path)
        self.assert_code("managed-work.database-corrupt", refused.open)
        self.assertIsNone(refused.store.connection)

        approval_type_path = self.root / "approval-type-coherence.db"
        plane = ManagedWorkPlane(approval_type_path).open()
        plane.project_approval(
            ACTOR,
            {
                "sourceRevision": 1,
                "approvalId": "approval.types",
                "operationId": "66666666-6666-6666-6666-666666666666",
                "capability": "display.configure",
                "state": "pending",
                "risk": "consequential",
                "summary": "Change display settings",
                "requestedAt": 1_000,
                "expiresAt": 2_000,
            },
            now=1_001,
        )
        plane.close()
        connection = sqlite3.connect(approval_type_path)
        try:
            payload = json.loads(
                connection.execute(
                    "SELECT payload_json FROM approval_projections WHERE approval_id = 'approval.types'"
                ).fetchone()[0]
            )
            payload["sourceRevision"] = 1.0
            connection.execute(
                "UPDATE approval_projections SET payload_json = ? WHERE approval_id = 'approval.types'",
                (json.dumps(payload, separators=(",", ":"), sort_keys=True),),
            )
            connection.commit()
        finally:
            connection.close()
        refused = ManagedWorkPlane(approval_type_path)
        self.assert_code("managed-work.database-corrupt", refused.open)
        self.assertIsNone(refused.store.connection)

        owner_path = self.root / "json-link-owner.db"
        plane = ManagedWorkPlane(owner_path).open()
        own = plane.capture_context(
            ACTOR,
            source="focused-application",
            access_scope="principal",
            content={"owner": "one"},
            sensitivity="personal",
            ttl_seconds=600,
            idempotency_key="context.owner-one",
            now=1_000,
        )
        foreign = plane.capture_context(
            OTHER_ACTOR,
            source="focused-application",
            access_scope="principal",
            content={"owner": "two"},
            sensitivity="personal",
            ttl_seconds=600,
            idempotency_key="context.owner-two",
            now=1_000,
        )
        task = create_task(plane, context_ids=[own["contextId"]], key="task.owner-link")
        plane.close()
        connection = sqlite3.connect(owner_path)
        try:
            connection.execute(
                "UPDATE tasks SET context_ids_json = ? WHERE task_id = ?",
                (f'["{foreign["contextId"]}"]', task["taskId"]),
            )
            connection.commit()
        finally:
            connection.close()
        refused = ManagedWorkPlane(owner_path)
        self.assert_code("managed-work.database-corrupt", refused.open)
        self.assertIsNone(refused.store.connection)

    def test_disk_failure_is_typed_and_rollback_does_not_mask_it(self) -> None:
        class FailingConnection:
            def __init__(self) -> None:
                self.in_transaction = False

            def execute(self, statement, _parameters=()):
                if statement == "BEGIN IMMEDIATE":
                    self.in_transaction = True
                    return self
                if statement == "COMMIT":
                    error = sqlite3.OperationalError("disk full with secret path")
                    error.sqlite_errorcode = sqlite3.SQLITE_FULL
                    raise error
                if statement == "ROLLBACK":
                    raise sqlite3.OperationalError("rollback also failed")
                return self

        plane = ManagedWorkPlane(self.root / "disk-failure.db").open()
        real_connection = plane.store.connection
        plane.store.connection = FailingConnection()
        try:
            with self.assertRaises(ManagedWorkError) as caught:
                with plane.store.transaction():
                    pass
            self.assertEqual("managed-work.database-io", caught.exception.code)
            self.assertNotIn("secret path", caught.exception.detail)
        finally:
            plane.store.connection = real_connection
            plane.close()

    def test_unversioned_corrupt_and_symbolic_link_databases_refuse(self) -> None:
        unknown = self.root / "unknown.db"
        connection = sqlite3.connect(unknown)
        connection.execute("CREATE TABLE mystery(value TEXT)")
        connection.close()
        self.assert_code("managed-work.database-unversioned", lambda: ManagedWorkPlane(unknown).open())

        corrupt = self.root / "corrupt.db"
        corrupt.write_bytes(b"not a sqlite database")
        self.assert_code("managed-work.database-corrupt", lambda: ManagedWorkPlane(corrupt).open())

        if hasattr(os, "symlink"):
            target = self.root / "target.db"
            ManagedWorkPlane(target).open().close()
            link = self.root / "link.db"
            try:
                link.symlink_to(target)
            except OSError:
                return
            self.assert_code("managed-work.database-unsafe", lambda: ManagedWorkPlane(link).open())
            real_directory = self.root / "real-state"
            real_directory.mkdir()
            linked_directory = self.root / "linked-state"
            try:
                linked_directory.symlink_to(real_directory, target_is_directory=True)
            except OSError:
                return
            self.assert_code(
                "managed-work.database-unsafe",
                lambda: ManagedWorkPlane(linked_directory / "managed.db").open(),
            )

    @unittest.skipIf(os.name == "nt", "requires Linux inode replacement semantics")
    def test_connected_inode_swap_refuses_before_decoy_mutation(self) -> None:
        path = self.root / "held.db"
        ManagedWorkPlane(path).open().close()
        decoy = self.root / "decoy.db"
        ManagedWorkPlane(decoy).open().close()
        original_bytes = path.read_bytes()
        decoy_bytes = decoy.read_bytes()
        parked = self.root / "parked.db"
        real_connect = sqlite3.connect
        swapped = False

        def swap_then_connect(database, *args, **kwargs):
            nonlocal swapped
            if Path(database) == path and not swapped:
                swapped = True
                path.replace(parked)
                decoy.replace(path)
            return real_connect(database, *args, **kwargs)

        with mock.patch(
            "omarchy_fabric.managed_work.store.sqlite3.connect",
            side_effect=swap_then_connect,
        ):
            self.assert_code("managed-work.database-unsafe", lambda: ManagedWorkPlane(path).open())
        self.assertTrue(swapped)
        self.assertEqual(original_bytes, parked.read_bytes())
        self.assertEqual(decoy_bytes, path.read_bytes())
        for suffix in ("-journal", "-wal", "-shm"):
            self.assertFalse(Path(f"{path}{suffix}").exists())

    @unittest.skipIf(os.name == "nt", "requires Linux descriptor identity evidence")
    def test_repeated_open_close_survives_descriptor_number_reuse(self) -> None:
        path = self.root / "descriptor-reuse.db"
        for _ in range(20):
            descriptor = os.open(os.devnull, os.O_RDONLY)
            os.close(descriptor)
            plane = ManagedWorkPlane(path).open()
            plane.close()

    def test_concurrent_idempotent_creation_converges_on_one_task(self) -> None:
        path = self.root / "concurrent.db"
        first = ManagedWorkPlane(path).open()
        second = ManagedWorkPlane(path).open()

        def create(plane: ManagedWorkPlane) -> dict[str, object]:
            return plane.create_task(
                ACTOR,
                title="Concurrent task",
                intent=inspect_intent(goal="same"),
                context_ids=[],
                budget=budget(),
                idempotency_key="task.concurrent",
                now=1_000,
            )

        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
                results = list(executor.map(create, (first, second)))
            self.assertEqual(results[0], results[1])
            self.assertEqual(1, first.store.execute("SELECT COUNT(*) FROM tasks").fetchone()[0])
        finally:
            second.close()
            first.close()

    def test_reads_wait_for_shared_connection_transactions_to_commit(self) -> None:
        plane = ManagedWorkPlane(self.root / "read-write.db").open()
        task = create_task(plane)
        writer_ready = threading.Event()
        release_writer = threading.Event()
        reader_started = threading.Event()
        reader_finished = threading.Event()

        def write() -> None:
            with plane.store.transaction() as connection:
                connection.execute(
                    "UPDATE tasks SET title = ? WHERE task_id = ?",
                    ("Committed title", task["taskId"]),
                )
                writer_ready.set()
                if not release_writer.wait(2):
                    raise AssertionError("reader test did not release the writer")

        def read() -> str:
            reader_started.set()
            try:
                return plane.get_task(ACTOR, task["taskId"])["title"]
            finally:
                reader_finished.set()

        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
                writer = executor.submit(write)
                self.assertTrue(writer_ready.wait(1))
                reader = executor.submit(read)
                self.assertTrue(reader_started.wait(1))
                self.assertFalse(reader_finished.wait(0.05))
                release_writer.set()
                writer.result(timeout=2)
                self.assertEqual("Committed title", reader.result(timeout=2))
        finally:
            release_writer.set()
            plane.close()

    def test_active_capacity_is_transactional_and_terminal_tasks_release_it(self) -> None:
        path = self.root / "capacity.db"
        plane = ManagedWorkPlane(path, capacities=CapacityLimits(active_tasks=1)).open()
        try:
            first = create_task(plane, key="task.first")
            self.assert_code(
                "capacity.exceeded",
                lambda: create_task(plane, key="task.second"),
            )
            plane.transition_task(ACTOR, first["taskId"], expected_revision=1, target="cancelled", now=1_002)
            second = create_task(plane, key="task.second", now=1_003)
            self.assertNotEqual(first["taskId"], second["taskId"])
        finally:
            plane.close()

    def test_total_capacity_and_history_retention_are_explicit(self) -> None:
        bounded = ManagedWorkPlane(
            self.root / "total-capacity.db",
            capacities=CapacityLimits(active_tasks=2, total_tasks=2),
        ).open()
        try:
            first = create_task(bounded, key="task.total-one")
            bounded.transition_task(ACTOR, first["taskId"], expected_revision=1, target="cancelled", now=1_002)
            second = create_task(bounded, key="task.total-two", now=1_003)
            bounded.transition_task(ACTOR, second["taskId"], expected_revision=1, target="cancelled", now=1_004)
            self.assert_code(
                "capacity.exceeded",
                lambda: create_task(bounded, key="task.total-three", now=1_005),
            )
        finally:
            bounded.close()

        history = ManagedWorkPlane(
            self.root / "history-capacity.db",
            capacities=CapacityLimits(history_events=3),
        ).open()
        try:
            for index in range(3):
                create_task(history, key=f"task.history-{index}", now=1_000 + index)
            old_page = history.query(ACTOR, "agent.history", limit=1, now=1_010)
            old_cursor = old_page["nextCursor"]
            self.assertIsNotNone(old_cursor)
            for index in range(3, 6):
                create_task(history, key=f"task.history-{index}", now=1_000 + index)
            current = history.query(ACTOR, "agent.history", limit=3, now=1_020)
            self.assertEqual(3, len(current["items"]))
            self.assertGreater(current["summary"]["prunedThrough"], 0)
            self.assert_code(
                "query.cursor-expired",
                lambda: history.query(ACTOR, "agent.history", cursor=old_cursor, now=1_020),
            )
        finally:
            history.close()

    def test_startup_capacity_is_per_owner_and_paginated_items_include_cursor_overhead(self) -> None:
        owner_path = self.root / "per-owner-capacity.db"
        bounded = ManagedWorkPlane(
            owner_path,
            capacities=CapacityLimits(total_contexts=1, live_contexts=1),
        ).open()
        try:
            for actor, key in ((ACTOR, "context.owner-one"), (OTHER_ACTOR, "context.owner-two")):
                bounded.capture_context(
                    actor,
                    source="focused-application",
                    access_scope="principal",
                    content={"owner": actor.principal_id},
                    sensitivity="personal",
                    ttl_seconds=600,
                    idempotency_key=key,
                    now=1_000,
                )
        finally:
            bounded.close()
        reopened = ManagedWorkPlane(
            owner_path,
            capacities=CapacityLimits(total_contexts=1, live_contexts=1),
        ).open()
        try:
            self.assertEqual(1, len(reopened.query(ACTOR, "agent.context", now=1_001)["items"]))
            self.assertEqual(1, len(reopened.query(OTHER_ACTOR, "agent.context", now=1_001)["items"]))
        finally:
            reopened.close()

        reduced_path = self.root / "reduced-live-capacity.db"
        current = time.time()
        plane = ManagedWorkPlane(
            reduced_path,
            capacities=CapacityLimits(total_contexts=2, live_contexts=2),
        ).open()
        try:
            for index in range(2):
                plane.capture_context(
                    ACTOR,
                    source="focused-application",
                    access_scope="principal",
                    content={"index": index},
                    sensitivity="personal",
                    ttl_seconds=600,
                    idempotency_key=f"context.live-{index}",
                    now=current,
                )
        finally:
            plane.close()
        refused = ManagedWorkPlane(
            reduced_path,
            capacities=CapacityLimits(total_contexts=2, live_contexts=1),
        )
        self.assert_code("managed-work.database-corrupt", refused.open)
        self.assertIsNone(refused.store.connection)

        page_path = self.root / "cursor-overhead.db"
        plane = ManagedWorkPlane(page_path).open()
        try:
            plane.capture_context(
                ACTOR,
                source="focused-application",
                access_scope="principal",
                content={"small": True},
                sensitivity="personal",
                ttl_seconds=600,
                idempotency_key="context.cursor-small",
                now=1_000,
            )
            large = plane.capture_context(
                ACTOR,
                source="focused-application",
                access_scope="principal",
                content={"chunks": ["x" * 14_000] * 4},
                sensitivity="personal",
                ttl_seconds=600,
                idempotency_key="context.cursor-large",
                now=1_001,
            )
            first = plane.query(ACTOR, "agent.context", limit=1, now=1_002)
            self.assertEqual(large["contextId"], first["items"][0]["contextId"])
            self.assertIsNotNone(first["nextCursor"])
            second = plane.query(
                ACTOR,
                "agent.context",
                limit=1,
                cursor=first["nextCursor"],
                now=1_002,
            )
            self.assertEqual(1, len(second["items"]))
            before = plane.store.execute("SELECT COUNT(*) FROM contexts").fetchone()[0]
            self.assert_code(
                "validation.query-item-capacity",
                lambda: plane.capture_context(
                    ACTOR,
                    source="focused-application",
                    access_scope="principal",
                    content={"chunks": ["x" * 14_000] * 4 + ["x" * 500]},
                    sensitivity="personal",
                    ttl_seconds=600,
                    idempotency_key="context.cursor-too-large",
                    now=1_003,
                ),
            )
            self.assertEqual(before, plane.store.execute("SELECT COUNT(*) FROM contexts").fetchone()[0])
            self.assertEqual(
                0,
                plane.store.execute(
                    "SELECT COUNT(*) FROM idempotency WHERE idempotency_key = 'context.cursor-too-large'"
                ).fetchone()[0],
            )
        finally:
            plane.close()

    def test_nonfinite_deep_oversized_and_unknown_json_refuses(self) -> None:
        plane = ManagedWorkPlane(self.root / "adversarial.db").open()
        try:
            self.assert_code(
                "validation.json-number",
                lambda: plane.create_task(
                    ACTOR,
                    title="NaN",
                    intent={"value": float("nan")},
                    context_ids=[],
                    budget=budget(),
                    idempotency_key="task.nan",
                    now=1_000,
                ),
            )
            nested: object = "leaf"
            for _ in range(20):
                nested = {"nested": nested}
            self.assert_code(
                "validation.json-depth",
                lambda: plane.create_task(
                    ACTOR,
                    title="Deep",
                    intent={"value": nested},
                    context_ids=[],
                    budget=budget(),
                    idempotency_key="task.deep",
                    now=1_000,
                ),
            )
            self.assert_code(
                "validation.json-string",
                lambda: plane.create_task(
                    ACTOR,
                    title="Huge",
                    intent={"value": "x" * 20_000},
                    context_ids=[],
                    budget=budget(),
                    idempotency_key="task.huge",
                    now=1_000,
                ),
            )
            self.assert_code(
                "validation.secret-field",
                lambda: plane.create_task(
                    ACTOR,
                    title="Secret",
                    intent={"accessToken": "must-not-persist"},
                    context_ids=[],
                    budget=budget(),
                    idempotency_key="task.secret",
                    now=1_000,
                ),
            )
            self.assert_code(
                "validation.secret-field",
                lambda: plane.create_task(
                    ACTOR,
                    title="Camel secret",
                    intent={"clientSecret": "must-not-persist"},
                    context_ids=[],
                    budget=budget(),
                    idempotency_key="task.camel-secret",
                    now=1_000,
                ),
            )
            unsafe_policy = policy()
            unsafe_policy["executable"] = "/bin/bash"
            self.assert_code(
                "validation.unknown-field",
                lambda: plane.create_automation(
                    ACTOR,
                    name="Unsafe",
                    task_template=template(),
                    trigger={"kind": "event", "topic": "test.event"},
                    policy=unsafe_policy,
                    idempotency_key="automation.unsafe",
                    now=1_000,
                ),
            )
        finally:
            plane.close()

    def test_cross_principal_links_and_forged_cursor_never_leak(self) -> None:
        plane = ManagedWorkPlane(self.root / "isolation.db").open()
        try:
            task = create_task(plane)
            self.assert_code(
                "access.denied",
                lambda: plane.register_artifact(
                    OTHER_ACTOR,
                    task_id=task["taskId"],
                    run_id=None,
                    handle="artifact.stolen",
                    label="Stolen",
                    media_type="text/plain",
                    byte_length=0,
                    content_hash="b" * 64,
                    scope="task",
                    idempotency_key="artifact.stolen",
                    now=1_001,
                ),
            )
            self.assert_code(
                "query.cursor",
                lambda: plane.query(ACTOR, "agent.tasks", cursor="bm90LWpzb24", now=1_001),
            )
            shared_operation = "11111111-2222-3333-4444-555555555555"
            for owner, summary in ((ACTOR, "Owner one"), (OTHER_ACTOR, "Owner two")):
                plane.link_operation(
                    owner,
                    {
                        "sourceRevision": 1,
                        "operationId": shared_operation,
                        "taskId": None,
                        "runId": None,
                        "capability": "system.inspect",
                        "status": "failed",
                        "changeState": "none",
                        "summary": summary,
                        "recoveryEligible": False,
                        "artifactIds": [],
                        "createdAt": 1_000,
                        "updatedAt": 1_001,
                    },
                    now=1_001,
                )
            first = plane.query(
                ACTOR,
                "agent.activity",
                entity_type="operation",
                entity_id=shared_operation,
                now=1_002,
            )
            second = plane.query(
                OTHER_ACTOR,
                "agent.activity",
                entity_type="operation",
                entity_id=shared_operation,
                now=1_002,
            )
            self.assertEqual("Owner one", first["items"][0]["summary"])
            self.assertEqual("Owner two", second["items"][0]["summary"])
        finally:
            plane.close()

    def test_cross_owner_child_corruption_is_hidden_live_and_refused_on_restart(self) -> None:
        path = self.root / "owner-corruption.db"
        plane = ManagedWorkPlane(path).open()
        task = create_task(plane)
        plane.transition_task(ACTOR, task["taskId"], expected_revision=1, target="queued", now=1_002)
        run = plane.create_run_plan(
            ACTOR,
            task["taskId"],
            manifest=manifest(),
            idempotency_key="run.owner-corruption",
            now=1_003,
        )
        with plane.store.transaction() as connection:
            connection.execute(
                "UPDATE runs SET principal_id = ? WHERE run_id = ?",
                (OTHER_ACTOR.principal_id, run["runId"]),
            )
            connection.execute(
                "UPDATE steps SET principal_id = ? WHERE run_id = ?",
                (OTHER_ACTOR.principal_id, run["runId"]),
            )
        live = plane.query(ACTOR, "agent.tasks", now=1_004)
        self.assertIsNone(live["items"][0]["run"])
        plane.close()

        refused = ManagedWorkPlane(path)
        self.assert_code("managed-work.database-corrupt", refused.open)
        self.assertIsNone(refused.store.connection)


if __name__ == "__main__":
    unittest.main()
