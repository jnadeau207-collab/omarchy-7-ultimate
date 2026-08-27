from __future__ import annotations

import concurrent.futures
import os
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path

from helper import ACTOR, OTHER_ACTOR, ManagedWorkPlane, budget, create_task, manifest, policy, template
from omarchy_fabric.managed_work import CapacityLimits, ManagedWorkError
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

    def test_concurrent_idempotent_creation_converges_on_one_task(self) -> None:
        path = self.root / "concurrent.db"
        first = ManagedWorkPlane(path).open()
        second = ManagedWorkPlane(path).open()

        def create(plane: ManagedWorkPlane) -> dict[str, object]:
            return plane.create_task(
                ACTOR,
                title="Concurrent task",
                intent={"goal": "same"},
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
        finally:
            plane.close()


if __name__ == "__main__":
    unittest.main()
