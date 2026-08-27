"""Owner-scoped durable SQLite state for the provisional managed-work plane."""

from __future__ import annotations

import os
import sqlite3
import stat
import threading
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator, Sequence

from .errors import ManagedWorkError

CURRENT_SCHEMA = 2
MIN_READABLE_SCHEMA = 1
MAX_READABLE_SCHEMA = 2

MIGRATIONS: dict[int, tuple[str, ...]] = {
    1: (
        """
        CREATE TABLE managed_metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        ) STRICT
        """,
        """
        CREATE TABLE contexts (
          row_id INTEGER PRIMARY KEY AUTOINCREMENT,
          context_id TEXT NOT NULL UNIQUE,
          principal_id TEXT NOT NULL,
          owner_session_id TEXT NOT NULL,
          source TEXT NOT NULL,
          access_scope TEXT NOT NULL CHECK(access_scope IN ('session', 'task', 'principal')),
          task_id TEXT,
          captured_at REAL NOT NULL,
          expires_at REAL NOT NULL,
          sensitivity TEXT NOT NULL CHECK(sensitivity IN ('public', 'personal', 'private', 'restricted')),
          content_json TEXT NOT NULL,
          redacted_paths_json TEXT NOT NULL,
          content_hash TEXT NOT NULL,
          revision INTEGER NOT NULL CHECK(revision > 0),
          revoked_at REAL
        ) STRICT
        """,
        "CREATE INDEX contexts_owner_rows ON contexts(principal_id, row_id DESC)",
        "CREATE INDEX contexts_live ON contexts(principal_id, revoked_at, expires_at)",
        """
        CREATE TABLE tasks (
          row_id INTEGER PRIMARY KEY AUTOINCREMENT,
          task_id TEXT NOT NULL UNIQUE,
          principal_id TEXT NOT NULL,
          owner_session_id TEXT NOT NULL,
          title TEXT NOT NULL,
          intent_json TEXT NOT NULL,
          context_ids_json TEXT NOT NULL,
          budget_json TEXT NOT NULL,
          state TEXT NOT NULL CHECK(state IN (
            'draft', 'awaiting-approval', 'queued', 'running', 'waiting', 'retrying',
            'succeeded', 'failed', 'cancelled', 'interrupted'
          )),
          revision INTEGER NOT NULL CHECK(revision > 0),
          retry_count INTEGER NOT NULL DEFAULT 0 CHECK(retry_count >= 0),
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL
        ) STRICT
        """,
        "CREATE INDEX tasks_owner_rows ON tasks(principal_id, row_id DESC)",
        "CREATE INDEX tasks_active ON tasks(principal_id, state)",
        """
        CREATE TABLE runs (
          row_id INTEGER PRIMARY KEY AUTOINCREMENT,
          run_id TEXT NOT NULL UNIQUE,
          task_id TEXT NOT NULL REFERENCES tasks(task_id),
          principal_id TEXT NOT NULL,
          owner_session_id TEXT NOT NULL,
          parent_run_id TEXT REFERENCES runs(run_id),
          manifest_json TEXT NOT NULL,
          manifest_hash TEXT NOT NULL,
          state TEXT NOT NULL CHECK(state IN (
            'queued', 'running', 'waiting', 'retrying', 'succeeded', 'failed', 'cancelled', 'interrupted'
          )),
          revision INTEGER NOT NULL CHECK(revision > 0),
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL,
          interrupted_at REAL
        ) STRICT
        """,
        "CREATE INDEX runs_owner_rows ON runs(principal_id, row_id DESC)",
        "CREATE INDEX runs_task_rows ON runs(task_id, row_id DESC)",
        """
        CREATE TABLE steps (
          row_id INTEGER PRIMARY KEY AUTOINCREMENT,
          step_id TEXT NOT NULL UNIQUE,
          run_id TEXT NOT NULL REFERENCES runs(run_id),
          principal_id TEXT NOT NULL,
          sequence INTEGER NOT NULL CHECK(sequence >= 0),
          label TEXT NOT NULL,
          capability TEXT,
          state TEXT NOT NULL CHECK(state IN ('planned', 'blocked-unavailable', 'cancelled')),
          detail_json TEXT NOT NULL,
          created_at REAL NOT NULL,
          UNIQUE(run_id, sequence)
        ) STRICT
        """,
        "CREATE INDEX steps_run_sequence ON steps(run_id, sequence)",
        """
        CREATE TABLE automations (
          row_id INTEGER PRIMARY KEY AUTOINCREMENT,
          automation_id TEXT NOT NULL UNIQUE,
          principal_id TEXT NOT NULL,
          owner_session_id TEXT NOT NULL,
          name TEXT NOT NULL,
          task_template_json TEXT NOT NULL,
          trigger_json TEXT NOT NULL,
          policy_json TEXT NOT NULL,
          state TEXT NOT NULL CHECK(state IN ('enabled', 'paused', 'disabled')),
          revision INTEGER NOT NULL CHECK(revision > 0),
          next_due_at REAL,
          last_reconciled_at REAL,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL
        ) STRICT
        """,
        "CREATE INDEX automations_owner_rows ON automations(principal_id, row_id DESC)",
        "CREATE INDEX automations_due ON automations(state, next_due_at)",
        """
        CREATE TABLE approval_projections (
          row_id INTEGER PRIMARY KEY AUTOINCREMENT,
          approval_id TEXT NOT NULL,
          principal_id TEXT NOT NULL,
          owner_session_id TEXT NOT NULL,
          source_revision TEXT NOT NULL,
          operation_id TEXT NOT NULL,
          capability TEXT NOT NULL,
          state TEXT NOT NULL CHECK(state IN ('pending', 'approved', 'denied', 'expired', 'cancelled')),
          risk TEXT NOT NULL CHECK(risk IN ('low', 'consequential', 'high')),
          summary TEXT NOT NULL,
          requested_at REAL NOT NULL,
          expires_at REAL NOT NULL,
          projected_at REAL NOT NULL,
          payload_json TEXT NOT NULL,
          UNIQUE(principal_id, approval_id)
        ) STRICT
        """,
        "CREATE INDEX approvals_owner_rows ON approval_projections(principal_id, row_id DESC)",
        "CREATE INDEX approvals_pending ON approval_projections(principal_id, state, expires_at)",
        """
        CREATE TABLE operation_links (
          row_id INTEGER PRIMARY KEY AUTOINCREMENT,
          operation_id TEXT NOT NULL,
          principal_id TEXT NOT NULL,
          owner_session_id TEXT NOT NULL,
          source_revision TEXT NOT NULL,
          task_id TEXT,
          run_id TEXT,
          capability TEXT NOT NULL,
          status TEXT NOT NULL,
          change_state TEXT NOT NULL CHECK(change_state IN ('none', 'partial', 'complete', 'unknown')),
          summary TEXT NOT NULL,
          recovery_eligible INTEGER NOT NULL CHECK(recovery_eligible IN (0, 1)),
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL,
          projected_at REAL NOT NULL,
          payload_json TEXT NOT NULL,
          UNIQUE(principal_id, operation_id)
        ) STRICT
        """,
        "CREATE INDEX operations_owner_rows ON operation_links(principal_id, row_id DESC)",
        """
        CREATE TABLE permission_projections (
          row_id INTEGER PRIMARY KEY AUTOINCREMENT,
          grant_id TEXT NOT NULL,
          principal_id TEXT NOT NULL,
          owner_session_id TEXT NOT NULL,
          source_revision TEXT NOT NULL,
          capability TEXT NOT NULL,
          resource TEXT NOT NULL,
          state TEXT NOT NULL CHECK(state IN ('active', 'revoked', 'expired', 'denied')),
          risk_ceiling TEXT NOT NULL CHECK(risk_ceiling IN ('low', 'consequential')),
          issued_at REAL NOT NULL,
          expires_at REAL,
          projected_at REAL NOT NULL,
          payload_json TEXT NOT NULL,
          UNIQUE(principal_id, grant_id)
        ) STRICT
        """,
        "CREATE INDEX permissions_owner_rows ON permission_projections(principal_id, row_id DESC)",
        """
        CREATE TABLE usage_records (
          row_id INTEGER PRIMARY KEY AUTOINCREMENT,
          usage_id TEXT NOT NULL,
          principal_id TEXT NOT NULL,
          owner_session_id TEXT NOT NULL,
          task_id TEXT,
          run_id TEXT,
          provider TEXT NOT NULL,
          metric TEXT NOT NULL,
          quantity REAL NOT NULL CHECK(quantity >= 0),
          unit TEXT NOT NULL,
          cost_microunits INTEGER NOT NULL CHECK(cost_microunits >= 0),
          recorded_at REAL NOT NULL,
          payload_json TEXT NOT NULL,
          UNIQUE(principal_id, usage_id)
        ) STRICT
        """,
        "CREATE INDEX usage_owner_rows ON usage_records(principal_id, row_id DESC)",
        """
        CREATE TABLE artifacts (
          row_id INTEGER PRIMARY KEY AUTOINCREMENT,
          artifact_id TEXT NOT NULL UNIQUE,
          principal_id TEXT NOT NULL,
          owner_session_id TEXT NOT NULL,
          task_id TEXT NOT NULL REFERENCES tasks(task_id),
          run_id TEXT REFERENCES runs(run_id),
          handle TEXT NOT NULL,
          label TEXT NOT NULL,
          media_type TEXT NOT NULL,
          byte_length INTEGER NOT NULL CHECK(byte_length >= 0),
          content_hash TEXT NOT NULL,
          scope TEXT NOT NULL CHECK(scope IN ('task', 'principal')),
          created_at REAL NOT NULL,
          payload_json TEXT NOT NULL
        ) STRICT
        """,
        "CREATE INDEX artifacts_owner_rows ON artifacts(principal_id, row_id DESC)",
        "CREATE INDEX artifacts_task_rows ON artifacts(task_id, row_id DESC)",
        """
        CREATE TABLE idempotency (
          principal_id TEXT NOT NULL,
          action TEXT NOT NULL,
          idempotency_key TEXT NOT NULL,
          request_hash TEXT NOT NULL,
          result_json TEXT,
          state TEXT NOT NULL CHECK(state IN ('pending', 'complete', 'interrupted')),
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL,
          PRIMARY KEY(principal_id, action, idempotency_key)
        ) WITHOUT ROWID, STRICT
        """,
        """
        CREATE TABLE managed_events (
          row_id INTEGER PRIMARY KEY AUTOINCREMENT,
          event_id TEXT NOT NULL UNIQUE,
          principal_id TEXT NOT NULL,
          owner_session_id TEXT NOT NULL,
          topic TEXT NOT NULL,
          entity_id TEXT,
          payload_json TEXT NOT NULL,
          created_at REAL NOT NULL
        ) STRICT
        """,
        "CREATE INDEX managed_events_owner_rows ON managed_events(principal_id, row_id DESC)",
    ),
    2: (
        """
        CREATE TABLE automation_firings (
          row_id INTEGER PRIMARY KEY AUTOINCREMENT,
          firing_id TEXT NOT NULL UNIQUE,
          automation_id TEXT NOT NULL REFERENCES automations(automation_id),
          principal_id TEXT NOT NULL,
          trigger_kind TEXT NOT NULL CHECK(trigger_kind IN ('schedule', 'event')),
          trigger_id TEXT NOT NULL,
          due_at REAL NOT NULL,
          state TEXT NOT NULL CHECK(state IN ('pending-unavailable', 'skipped', 'cancelled')),
          detail_json TEXT NOT NULL,
          created_at REAL NOT NULL,
          UNIQUE(automation_id, trigger_kind, trigger_id)
        ) STRICT
        """,
        "CREATE INDEX automation_firings_owner_rows ON automation_firings(principal_id, row_id DESC)",
        "CREATE INDEX automation_firings_automation_rows ON automation_firings(automation_id, row_id DESC)",
    ),
}


class ManagedWorkStore:
    """A narrow SQLite owner with explicit schema and restart semantics."""

    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        self.connection: sqlite3.Connection | None = None
        self.backup_path: Path | None = None
        self.restart_recoveries = 0
        self._lock = threading.RLock()

    def open(self) -> None:
        if self.connection is not None:
            raise RuntimeError("managed-work store is already open")
        try:
            self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            parent_metadata = self.path.parent.lstat()
            if stat.S_ISLNK(parent_metadata.st_mode) or not stat.S_ISDIR(parent_metadata.st_mode):
                raise ManagedWorkError(
                    "managed-work.database-unsafe",
                    "The managed-work database directory is unsafe.",
                )
            if hasattr(os, "getuid") and parent_metadata.st_uid != os.getuid():
                raise ManagedWorkError(
                    "managed-work.database-owner",
                    "The managed-work database directory has another owner.",
                )
            if os.name != "nt":
                os.chmod(self.path.parent, 0o700)
            try:
                metadata = self.path.lstat()
            except FileNotFoundError:
                metadata = None
            if metadata is not None:
                if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
                    raise ManagedWorkError("managed-work.database-unsafe", "The managed-work database path is unsafe.")
                if hasattr(os, "getuid") and metadata.st_uid != os.getuid():
                    raise ManagedWorkError("managed-work.database-owner", "The managed-work database has another owner.")

            connection = sqlite3.connect(
                self.path,
                timeout=5.0,
                isolation_level=None,
                check_same_thread=False,
            )
            connection.row_factory = sqlite3.Row
            connection.execute("PRAGMA busy_timeout = 5000")
            connection.execute("PRAGMA foreign_keys = ON")
            connection.execute("PRAGMA trusted_schema = OFF")
            self._check_integrity(connection)
            current = int(connection.execute("PRAGMA user_version").fetchone()[0])
            tables = {
                row[0]
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
                )
            }
            if current == 0 and tables:
                raise ManagedWorkError(
                    "managed-work.database-unversioned",
                    "Managed work refuses to guess the schema of a non-empty unversioned database.",
                )
            if current > MAX_READABLE_SCHEMA:
                raise ManagedWorkError(
                    "managed-work.database-future",
                    "The managed-work database requires newer software.",
                    detail=f"schema {current}",
                    recovery_actions=("system.update",),
                )
            if current != 0 and current < MIN_READABLE_SCHEMA:
                raise ManagedWorkError(
                    "managed-work.database-obsolete",
                    "The managed-work database is too old to read safely.",
                )
            if current and current < CURRENT_SCHEMA:
                self.backup_path = self._backup(connection, current)
            self._migrate(connection, current)
            journal_mode = str(connection.execute("PRAGMA journal_mode = WAL").fetchone()[0]).lower()
            if journal_mode != "wal":
                raise ManagedWorkError("managed-work.database-wal", "Managed work requires SQLite WAL mode.")
            connection.execute("PRAGMA synchronous = FULL")
            connection.execute("PRAGMA wal_autocheckpoint = 100")
            if os.name != "nt":
                os.chmod(self.path, 0o600)
            self.connection = connection
            self.restart_recoveries = self._recover_interrupted()
        except ManagedWorkError:
            if "connection" in locals():
                connection.close()
            raise
        except (sqlite3.DatabaseError, OSError) as error:
            if "connection" in locals():
                connection.close()
            raise ManagedWorkError(
                "managed-work.database-corrupt",
                "Managed work refused a database that could not be opened safely.",
                detail=str(error),
                recovery_actions=("managed-work.restore-database",),
            ) from error

    @staticmethod
    def _check_integrity(connection: sqlite3.Connection) -> None:
        row = connection.execute("PRAGMA quick_check").fetchone()
        if row is None or row[0] != "ok":
            raise ManagedWorkError(
                "managed-work.database-corrupt",
                "Managed work refused a database that failed SQLite integrity checks.",
                detail="missing result" if row is None else str(row[0]),
            )

    def _backup(self, connection: sqlite3.Connection, current: int) -> Path:
        stamp = f"{time.time_ns()}-{os.getpid()}"
        backup = self.path.with_name(f"{self.path.name}.pre-migrate-v{current}-to-v{CURRENT_SCHEMA}-{stamp}.bak")
        temporary = backup.with_suffix(backup.suffix + ".tmp")
        destination = sqlite3.connect(temporary)
        try:
            connection.backup(destination)
        finally:
            destination.close()
        if os.name != "nt":
            os.chmod(temporary, 0o600)
        os.replace(temporary, backup)
        return backup

    @staticmethod
    def _migrate(connection: sqlite3.Connection, current: int) -> None:
        for target in range(current + 1, CURRENT_SCHEMA + 1):
            statements = MIGRATIONS.get(target)
            if statements is None:
                raise ManagedWorkError("managed-work.migration-missing", f"Migration {target} is unavailable.")
            connection.execute("BEGIN IMMEDIATE")
            try:
                for statement in statements:
                    connection.execute(statement)
                connection.execute(
                    "INSERT OR REPLACE INTO managed_metadata(key, value) VALUES ('schema_version', ?)",
                    (str(target),),
                )
                connection.execute(f"PRAGMA user_version = {target}")
                connection.execute("COMMIT")
            except Exception:
                connection.execute("ROLLBACK")
                raise

    def _recover_interrupted(self) -> int:
        now = time.time()
        with self.transaction() as connection:
            runs = connection.execute(
                "UPDATE runs SET state = 'interrupted', revision = revision + 1, updated_at = ?, interrupted_at = ? WHERE state IN ('running', 'waiting', 'retrying')",
                (now, now),
            ).rowcount
            tasks = connection.execute(
                "UPDATE tasks SET state = 'interrupted', revision = revision + 1, updated_at = ? WHERE state IN ('running', 'waiting', 'retrying')",
                (now,),
            ).rowcount
            claims = connection.execute(
                "UPDATE idempotency SET state = 'interrupted', updated_at = ? WHERE state = 'pending'",
                (now,),
            ).rowcount
            total = int(runs + tasks + claims)
            connection.execute(
                "INSERT OR REPLACE INTO managed_metadata(key, value) VALUES ('last_restart_recoveries', ?)",
                (str(total),),
            )
            connection.execute(
                "INSERT OR REPLACE INTO managed_metadata(key, value) VALUES ('last_opened_at', ?)",
                (str(now),),
            )
        return total

    def close(self) -> None:
        if self.connection is None:
            return
        with self._lock:
            connection = self.connection
            self.connection = None
            try:
                connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            finally:
                connection.close()

    def require_connection(self) -> sqlite3.Connection:
        if self.connection is None:
            raise RuntimeError("managed-work store is not open")
        return self.connection

    @contextmanager
    def transaction(self) -> Iterator[sqlite3.Connection]:
        with self._lock:
            connection = self.require_connection()
            connection.execute("BEGIN IMMEDIATE")
            try:
                yield connection
                connection.execute("COMMIT")
            except Exception:
                connection.execute("ROLLBACK")
                raise

    @contextmanager
    def read(self) -> Iterator[sqlite3.Connection]:
        """Serialize reads with writes on the shared SQLite connection."""

        with self._lock:
            yield self.require_connection()

    def execute(self, sql: str, parameters: Sequence[Any] = ()) -> sqlite3.Cursor:
        with self._lock:
            return self.require_connection().execute(sql, parameters)

    def quick_check(self) -> str:
        row = self.execute("PRAGMA quick_check").fetchone()
        return "missing" if row is None else str(row[0])

    def foreign_key_violations(self) -> int:
        return len(self.execute("PRAGMA foreign_key_check").fetchall())

    def schema_version(self) -> int:
        return int(self.execute("PRAGMA user_version").fetchone()[0])
