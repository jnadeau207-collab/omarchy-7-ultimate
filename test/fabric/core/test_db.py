from __future__ import annotations

import sqlite3
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from helper import FABRIC_ROOT

from omarchy_fabric.db import FabricDatabase, MIGRATIONS
from omarchy_fabric.models import CURRENT_DATABASE_SCHEMA, FabricError

def create_version_one(path: Path) -> None:
    connection = sqlite3.connect(path, isolation_level=None)
    connection.execute("BEGIN IMMEDIATE")
    try:
        for statement in MIGRATIONS[1]:
            connection.execute(statement)
        connection.execute(
            "INSERT OR REPLACE INTO schema_metadata(key, value) VALUES ('schema_version', '1')"
        )
        connection.execute("PRAGMA user_version = 1")
        connection.execute("COMMIT")
    except Exception:
        connection.execute("ROLLBACK")
        raise
    finally:
        connection.close()

def create_version_two(path: Path) -> None:
    create_version_one(path)
    connection = sqlite3.connect(path, isolation_level=None)
    connection.execute("BEGIN IMMEDIATE")
    try:
        for statement in MIGRATIONS[2]:
            connection.execute(statement)
        connection.execute(
            "INSERT OR REPLACE INTO schema_metadata(key, value) VALUES ('schema_version', '2')"
        )
        connection.execute("PRAGMA user_version = 2")
        connection.execute("COMMIT")
    except Exception:
        connection.execute("ROLLBACK")
        raise
    finally:
        connection.close()

class DatabaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.path = self.root / "fabric.db"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_fresh_database_is_current_owner_only_and_wal(self) -> None:
        database = FabricDatabase(self.path)
        database.open()
        try:
            self.assertEqual(database.opened_schema, CURRENT_DATABASE_SCHEMA)
            self.assertEqual(database.quick_check(), "ok")
            self.assertEqual(database.journal_mode(), "wal")
            if __import__("os").name != "nt":
                self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
            version = database.connection.execute("PRAGMA user_version").fetchone()[0]
            metadata = database.connection.execute(
                "SELECT value FROM schema_metadata WHERE key = 'schema_version'"
            ).fetchone()[0]
            self.assertEqual(version, CURRENT_DATABASE_SCHEMA)
            self.assertEqual(metadata, str(CURRENT_DATABASE_SCHEMA))
            tables = {
                row[0]
                for row in database.connection.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'table'"
                )
            }
            self.assertTrue(
                {
                    "reference_resources",
                    "reference_operations",
                    "reference_operation_ledger",
                } <= tables
            )
            operation_columns = {
                row[1]
                for row in database.connection.execute(
                    "PRAGMA table_info(reference_operations)"
                )
            }
            self.assertTrue(
                {"recovery_token_digest", "ledger_entry_count", "ledger_head_hash"}
                <= operation_columns
            )
        finally:
            database.close()

    def test_version_two_migration_adds_reference_ledger_with_backup(self) -> None:
        create_version_two(self.path)
        database = FabricDatabase(self.path)
        database.open()
        try:
            self.assertIsNotNone(database.backup_path)
            assert database.backup_path is not None
            backup = sqlite3.connect(database.backup_path)
            try:
                self.assertEqual(backup.execute("PRAGMA user_version").fetchone()[0], 2)
                self.assertIsNone(
                    backup.execute(
                        "SELECT name FROM sqlite_master WHERE name = 'reference_operations'"
                    ).fetchone()
                )
            finally:
                backup.close()
            self.assertIsNotNone(
                database.connection.execute(
                    "SELECT name FROM sqlite_master WHERE name = 'reference_operations'"
                ).fetchone()
            )
        finally:
            database.close()

    def test_supported_migration_creates_backup_and_preserves_rows(self) -> None:
        create_version_one(self.path)
        connection = sqlite3.connect(self.path)
        connection.execute(
            "INSERT INTO providers(provider_id, version, definition_json, registered_at) VALUES (?, ?, ?, ?)",
            ("fake.saved", "v0", '{"actions":{"echo":{"kind":"echo"}}}', 1.0),
        )
        connection.commit()
        connection.close()

        database = FabricDatabase(self.path)
        database.open()
        try:
            self.assertIsNotNone(database.backup_path)
            assert database.backup_path is not None
            self.assertTrue(database.backup_path.exists())
            if __import__("os").name != "nt":
                self.assertEqual(stat.S_IMODE(database.backup_path.stat().st_mode), 0o600)
            self.assertEqual(database.provider_count(), 1)
            backup = sqlite3.connect(database.backup_path)
            try:
                self.assertEqual(backup.execute("PRAGMA user_version").fetchone()[0], 1)
                self.assertEqual(backup.execute("SELECT COUNT(*) FROM providers").fetchone()[0], 1)
            finally:
                backup.close()
        finally:
            database.close()

    def test_failed_migration_rolls_back_schema_and_version(self) -> None:
        create_version_one(self.path)
        original = MIGRATIONS[2]
        MIGRATIONS[2] = (
            "CREATE TABLE should_rollback(value TEXT)",
            "THIS IS NOT SQL",
        )
        try:
            database = FabricDatabase(self.path)
            with self.assertRaises(FabricError) as caught:
                database.open()
        finally:
            MIGRATIONS[2] = original
        self.assertEqual(caught.exception.code, "database.migration-failed")
        connection = sqlite3.connect(self.path)
        try:
            self.assertEqual(connection.execute("PRAGMA user_version").fetchone()[0], 1)
            self.assertIsNone(
                connection.execute(
                    "SELECT name FROM sqlite_master WHERE name = 'should_rollback'"
                ).fetchone()
            )
        finally:
            connection.close()

    def test_newer_schema_is_refused_without_mutation(self) -> None:
        connection = sqlite3.connect(self.path)
        connection.execute(f"PRAGMA user_version = {CURRENT_DATABASE_SCHEMA + 1}")
        connection.close()
        before = self.path.read_bytes()
        database = FabricDatabase(self.path)
        with self.assertRaises(FabricError) as caught:
            database.open()
        self.assertEqual(caught.exception.code, "database.schema-too-new")
        self.assertEqual(self.path.read_bytes(), before)

    def test_unversioned_nonempty_and_corrupt_database_are_refused(self) -> None:
        connection = sqlite3.connect(self.path)
        connection.execute("CREATE TABLE mystery(value TEXT)")
        connection.close()
        with self.assertRaises(FabricError) as caught:
            FabricDatabase(self.path).open()
        self.assertEqual(caught.exception.code, "database.unversioned")

        self.path.unlink()
        self.path.write_bytes(b"not a sqlite database")
        with self.assertRaises(FabricError) as caught:
            FabricDatabase(self.path).open()
        self.assertEqual(caught.exception.code, "database.corrupt")

    @unittest.skipIf(__import__("os").name == "nt", "requires Linux inode replacement semantics")
    def test_connected_inode_swap_refuses_before_decoy_mutation(self) -> None:
        original = FabricDatabase(self.path)
        original.open()
        original.close()
        decoy = self.root / "decoy.db"
        decoy_database = FabricDatabase(decoy)
        decoy_database.open()
        decoy_database.close()
        original_bytes = self.path.read_bytes()
        decoy_bytes = decoy.read_bytes()
        parked = self.root / "parked.db"
        real_connect = sqlite3.connect
        swapped = False

        def swap_then_connect(database, *args, **kwargs):
            nonlocal swapped
            if Path(database) == self.path and not swapped:
                swapped = True
                self.path.replace(parked)
                decoy.replace(self.path)
            return real_connect(database, *args, **kwargs)

        with mock.patch("omarchy_fabric.db.sqlite3.connect", side_effect=swap_then_connect):
            with self.assertRaises(FabricError) as caught:
                FabricDatabase(self.path).open()
        self.assertEqual("database.unsafe-path", caught.exception.code)
        self.assertTrue(swapped)
        self.assertEqual(original_bytes, parked.read_bytes())
        self.assertEqual(decoy_bytes, self.path.read_bytes())
        for suffix in ("-journal", "-wal", "-shm"):
            self.assertFalse(Path(f"{self.path}{suffix}").exists())

    def test_event_retention_records_expired_cursor(self) -> None:
        database = FabricDatabase(self.path)
        database.open()
        try:
            for number in range(5):
                database.append_event("test.event", {"number": number}, retention=3)
            self.assertEqual(database.event_pruned_through(), 2)
            self.assertEqual(database.latest_event_sequence(), 5)
            with self.assertRaises(FabricError) as caught:
                database.replay_events(
                    after=1,
                    through=5,
                    topics=("test.event",),
                    limit=3,
                )
            self.assertEqual(caught.exception.code, "events.cursor-expired")
            replay = database.replay_events(
                after=2,
                through=5,
                topics=("test.event",),
                limit=3,
            )
            self.assertEqual([event["payload"]["number"] for event in replay], [2, 3, 4])
        finally:
            database.close()

if __name__ == "__main__":
    unittest.main()
