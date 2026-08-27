"""SQLite persistence and transactional schema migration for user Fabric."""

from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import stat
import time
import uuid
from pathlib import Path
from typing import Any, Mapping, Sequence

from .models import (
    CURRENT_DATABASE_SCHEMA,
    MAX_READABLE_DATABASE_SCHEMA,
    MIN_READABLE_DATABASE_SCHEMA,
    FabricError,
)

MIGRATIONS: dict[int, tuple[str, ...]] = {
    1: (
        """
        CREATE TABLE schema_metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE providers (
          provider_id TEXT PRIMARY KEY,
          version TEXT NOT NULL,
          definition_json TEXT NOT NULL,
          registered_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE idempotency (
          provider_id TEXT NOT NULL,
          action TEXT NOT NULL,
          idempotency_key TEXT NOT NULL,
          request_hash TEXT NOT NULL,
          request_id TEXT NOT NULL,
          status TEXT NOT NULL CHECK (status IN ('pending', 'complete', 'failed', 'interrupted')),
          response_json TEXT,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL,
          PRIMARY KEY (provider_id, action, idempotency_key)
        )
        """,
        """
        CREATE TABLE events (
          sequence INTEGER PRIMARY KEY AUTOINCREMENT,
          event_id TEXT NOT NULL UNIQUE,
          topic TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          created_at REAL NOT NULL
        )
        """,
        "INSERT INTO schema_metadata(key, value) VALUES ('event_pruned_through', '0')",
    ),
    2: (
        """
        CREATE TABLE daemon_runs (
          run_id TEXT PRIMARY KEY,
          pid INTEGER NOT NULL,
          started_at REAL NOT NULL,
          stopped_at REAL,
          shutdown_reason TEXT,
          clean_shutdown INTEGER NOT NULL DEFAULT 0 CHECK (clean_shutdown IN (0, 1))
        )
        """,
        "CREATE INDEX events_topic_sequence_idx ON events(topic, sequence)",
        "CREATE INDEX idempotency_status_idx ON idempotency(status, updated_at)",
    ),
    3: (
        """
        CREATE TABLE reference_resources (
          resource_id TEXT PRIMARY KEY,
          state TEXT NOT NULL CHECK (state IN ('enabled', 'disabled')),
          revision INTEGER NOT NULL CHECK (revision >= 0),
          updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE reference_operations (
          operation_id TEXT PRIMARY KEY,
          idempotency_key TEXT NOT NULL UNIQUE,
          request_hash TEXT NOT NULL,
          recovery_token_digest TEXT NOT NULL,
          principal_id TEXT NOT NULL,
          session_id TEXT NOT NULL,
          resource_id TEXT NOT NULL,
          provider_version TEXT NOT NULL,
          state_revision TEXT NOT NULL,
          before_state TEXT NOT NULL CHECK (before_state IN ('enabled', 'disabled')),
          desired_state TEXT NOT NULL CHECK (desired_state IN ('enabled', 'disabled')),
          outcome TEXT NOT NULL CHECK (outcome IN ('succeed', 'fail-after-apply')),
          pace TEXT NOT NULL CHECK (pace IN ('immediate', 'observable')),
          status TEXT NOT NULL CHECK (status IN (
            'awaiting-consent', 'queued', 'running', 'interrupted', 'reconciling',
            'succeeded', 'recovered', 'failed', 'cancelled'
          )),
          checkpoint TEXT NOT NULL CHECK (checkpoint IN (
            'preflight', 'authorized', 'validated', 'applied', 'finished', 'reconciled'
          )),
          progress INTEGER NOT NULL CHECK (progress BETWEEN 0 AND 100),
          cancellation_requested INTEGER NOT NULL DEFAULT 0 CHECK (cancellation_requested IN (0, 1)),
          ledger_entry_count INTEGER NOT NULL DEFAULT 0 CHECK (ledger_entry_count BETWEEN 0 AND 128),
          ledger_head_hash TEXT NOT NULL DEFAULT '0000000000000000000000000000000000000000000000000000000000000000'
            CHECK (length(ledger_head_hash) = 64 AND ledger_head_hash NOT GLOB '*[^0-9a-f]*'),
          approval_id TEXT,
          approval_binding_digest TEXT,
          correlation_nonce TEXT,
          authorization_code TEXT,
          error_json TEXT,
          result_json TEXT,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL
        )
        """,
        "CREATE INDEX reference_operations_status_idx ON reference_operations(status, updated_at)",
        "CREATE INDEX reference_operations_resource_idx ON reference_operations(resource_id, created_at)",
        """
        CREATE TABLE reference_operation_ledger (
          sequence INTEGER PRIMARY KEY AUTOINCREMENT,
          entry_id TEXT NOT NULL UNIQUE,
          operation_id TEXT NOT NULL REFERENCES reference_operations(operation_id),
          event_type TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          previous_hash TEXT NOT NULL,
          entry_hash TEXT NOT NULL UNIQUE,
          created_at REAL NOT NULL
        )
        """,
        "CREATE INDEX reference_operation_ledger_operation_idx ON reference_operation_ledger(operation_id, sequence)",
    ),
}


def canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        separators=(",", ":"),
        sort_keys=True,
    )


def request_fingerprint(value: Mapping[str, Any]) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


class FabricDatabase:
    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        self.connection: sqlite3.Connection | None = None
        self.opened_schema: int | None = None
        self.backup_path: Path | None = None

    def open(self) -> None:
        if self.connection is not None:
            return
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        if self.path.parent.is_symlink():
            raise FabricError(
                "database.unsafe-path",
                "Fabric database path is unsafe",
                "The Fabric state directory cannot be a symbolic link.",
            )
        try:
            metadata = self.path.lstat()
        except FileNotFoundError:
            metadata = None
        if metadata is not None:
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
                raise FabricError(
                    "database.unsafe-path",
                    "Fabric database path is unsafe",
                    "Fabric refuses to open a symbolic link or non-regular database path.",
                )
            if metadata.st_uid != os.getuid():
                raise FabricError(
                    "database.wrong-owner",
                    "Fabric database has the wrong owner",
                    "The Fabric database must be owned by the current user.",
                )
        try:
            connection = sqlite3.connect(
                self.path,
                timeout=5.0,
                isolation_level=None,
            )
            connection.row_factory = sqlite3.Row
            connection.execute("PRAGMA busy_timeout = 5000")
            connection.execute("PRAGMA foreign_keys = ON")
            integrity = connection.execute("PRAGMA quick_check").fetchone()
            if integrity is None or integrity[0] != "ok":
                detail = "no integrity result" if integrity is None else str(integrity[0])
                raise FabricError(
                    "database.corrupt",
                    "Fabric database is corrupt",
                    "Fabric refused to open a database that failed SQLite integrity checks.",
                    detail=detail,
                    recovery_actions=("fabric.restore-database",),
                )

            current = int(connection.execute("PRAGMA user_version").fetchone()[0])
            existing_tables = {
                row[0]
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
                )
            }
            if current == 0 and existing_tables:
                raise FabricError(
                    "database.unversioned",
                    "Fabric database schema is unknown",
                    "Fabric will not guess how to migrate an unversioned non-empty database.",
                    recovery_actions=("fabric.restore-database",),
                )
            if current > MAX_READABLE_DATABASE_SCHEMA:
                raise FabricError(
                    "database.schema-too-new",
                    "Fabric database needs a newer daemon",
                    f"Database schema {current} exceeds this daemon's maximum {MAX_READABLE_DATABASE_SCHEMA}.",
                    recovery_actions=("system.update",),
                )
            if current != 0 and current < MIN_READABLE_DATABASE_SCHEMA:
                raise FabricError(
                    "database.schema-too-old",
                    "Fabric database schema is no longer readable",
                    f"Database schema {current} is below this daemon's minimum {MIN_READABLE_DATABASE_SCHEMA}.",
                    recovery_actions=("fabric.migrate-database",),
                )

            if current and current < CURRENT_DATABASE_SCHEMA:
                self.backup_path = self._backup_before_migration(connection, current)
            try:
                self._migrate(connection, current)
            except (sqlite3.DatabaseError, OSError) as error:
                raise FabricError(
                    "database.migration-failed",
                    "Fabric database migration failed",
                    "The schema transaction was rolled back and the pre-migration database was retained.",
                    detail=str(error),
                    recovery_actions=("fabric.restore-database",),
                ) from error

            journal_mode = str(connection.execute("PRAGMA journal_mode = WAL").fetchone()[0]).lower()
            if journal_mode != "wal":
                raise FabricError(
                    "database.wal-unavailable",
                    "Fabric database cannot enter WAL mode",
                    "Durable Fabric state requires SQLite WAL mode.",
                    detail=journal_mode,
                )
            connection.execute("PRAGMA synchronous = FULL")
            connection.execute("PRAGMA wal_autocheckpoint = 100")
            self.connection = connection
            self.opened_schema = CURRENT_DATABASE_SCHEMA
            try:
                os.chmod(self.path, 0o600)
            except OSError as error:
                raise FabricError(
                    "database.permissions",
                    "Fabric database permissions are unsafe",
                    "Fabric could not restrict its database to the current user.",
                    detail=str(error),
                ) from error
            self.reconcile_interrupted_requests()
        except FabricError:
            if "connection" in locals():
                connection.close()
            raise
        except sqlite3.DatabaseError as error:
            if "connection" in locals():
                connection.close()
            raise FabricError(
                "database.corrupt",
                "Fabric database cannot be read",
                "Fabric refused to use a database SQLite could not read safely.",
                detail=str(error),
                recovery_actions=("fabric.restore-database",),
            ) from error
        except OSError as error:
            if "connection" in locals():
                connection.close()
            raise FabricError(
                "database.unavailable",
                "Fabric database is unavailable",
                "Fabric could not create or secure its state database.",
                detail=str(error),
                retryable=True,
            ) from error

    def close(self) -> None:
        if self.connection is not None:
            connection = self.connection
            self.connection = None
            try:
                connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            finally:
                connection.close()

    def _require_connection(self) -> sqlite3.Connection:
        if self.connection is None:
            raise RuntimeError("Fabric database is not open")
        return self.connection

    def _backup_before_migration(
        self,
        connection: sqlite3.Connection,
        current: int,
    ) -> Path:
        stamp = f"{time.time_ns()}-{os.getpid()}"
        backup = self.path.with_name(
            f"{self.path.name}.pre-migrate-v{current}-to-v{CURRENT_DATABASE_SCHEMA}-{stamp}.bak"
        )
        temporary = backup.with_suffix(backup.suffix + ".tmp")
        destination = sqlite3.connect(temporary)
        try:
            connection.backup(destination)
        finally:
            destination.close()
        os.chmod(temporary, 0o600)
        os.replace(temporary, backup)
        return backup

    @staticmethod
    def _migrate(connection: sqlite3.Connection, current: int) -> None:
        for target in range(current + 1, CURRENT_DATABASE_SCHEMA + 1):
            statements = MIGRATIONS.get(target)
            if statements is None:
                raise FabricError(
                    "database.migration-missing",
                    "Fabric database migration is unavailable",
                    f"No migration is registered for schema {target}.",
                )
            connection.execute("BEGIN IMMEDIATE")
            try:
                for statement in statements:
                    connection.execute(statement)
                connection.execute(
                    "INSERT OR REPLACE INTO schema_metadata(key, value) VALUES ('schema_version', ?)",
                    (str(target),),
                )
                connection.execute(f"PRAGMA user_version = {target}")
                connection.execute("COMMIT")
            except Exception:
                connection.execute("ROLLBACK")
                raise

    def quick_check(self) -> str:
        row = self._require_connection().execute("PRAGMA quick_check").fetchone()
        return "missing" if row is None else str(row[0])

    def journal_mode(self) -> str:
        row = self._require_connection().execute("PRAGMA journal_mode").fetchone()
        return "unknown" if row is None else str(row[0]).lower()

    def register_provider(
        self,
        provider_id: str,
        version: str,
        definition: Mapping[str, Any],
    ) -> str:
        connection = self._require_connection()
        definition_json = canonical_json(definition)
        existing = connection.execute(
            "SELECT version, definition_json FROM providers WHERE provider_id = ?",
            (provider_id,),
        ).fetchone()
        if existing is not None:
            if existing["version"] == version and existing["definition_json"] == definition_json:
                return "unchanged"
            raise FabricError(
                "provider.conflict",
                "Fabric provider registration conflicts",
                "A provider with this ID is already registered with a different definition.",
                detail=provider_id,
            )
        connection.execute(
            "INSERT INTO providers(provider_id, version, definition_json, registered_at) VALUES (?, ?, ?, ?)",
            (provider_id, version, definition_json, time.time()),
        )
        return "registered"

    def load_providers(self) -> list[dict[str, Any]]:
        rows = self._require_connection().execute(
            "SELECT provider_id, version, definition_json, registered_at FROM providers ORDER BY provider_id"
        ).fetchall()
        return [
            {
                "provider": row["provider_id"],
                "version": row["version"],
                "definition": json.loads(row["definition_json"]),
                "registeredAt": row["registered_at"],
            }
            for row in rows
        ]

    def provider_count(self) -> int:
        return int(self._require_connection().execute("SELECT COUNT(*) FROM providers").fetchone()[0])

    def claim_idempotency(
        self,
        *,
        provider_id: str,
        action: str,
        idempotency_key: str,
        fingerprint: str,
        request_id: str,
    ) -> tuple[str, dict[str, Any] | None]:
        connection = self._require_connection()
        now = time.time()
        connection.execute("BEGIN IMMEDIATE")
        try:
            row = connection.execute(
                """
                SELECT request_hash, status, response_json
                FROM idempotency
                WHERE provider_id = ? AND action = ? AND idempotency_key = ?
                """,
                (provider_id, action, idempotency_key),
            ).fetchone()
            if row is None:
                connection.execute(
                    """
                    INSERT INTO idempotency(
                      provider_id, action, idempotency_key, request_hash, request_id,
                      status, response_json, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, 'pending', NULL, ?, ?)
                    """,
                    (
                        provider_id,
                        action,
                        idempotency_key,
                        fingerprint,
                        request_id,
                        now,
                        now,
                    ),
                )
                connection.execute("COMMIT")
                return "claimed", None
            if row["request_hash"] != fingerprint:
                connection.execute("COMMIT")
                return "conflict", None
            response = json.loads(row["response_json"]) if row["response_json"] else None
            connection.execute("COMMIT")
            return str(row["status"]), response
        except Exception:
            connection.execute("ROLLBACK")
            raise

    def finish_idempotency(
        self,
        *,
        provider_id: str,
        action: str,
        idempotency_key: str,
        succeeded: bool,
        response: Mapping[str, Any],
        event_topic: str | None = None,
        event_payload: Mapping[str, Any] | None = None,
        event_retention: int | None = None,
    ) -> dict[str, Any] | None:
        status = "complete" if succeeded else "failed"
        connection = self._require_connection()
        if (event_topic is None) != (event_payload is None) or (
            event_topic is not None and event_retention is None
        ):
            raise ValueError("event topic, payload, and retention must be supplied together")
        connection.execute("BEGIN IMMEDIATE")
        try:
            cursor = connection.execute(
                """
                UPDATE idempotency
                SET status = ?, response_json = ?, updated_at = ?
                WHERE provider_id = ? AND action = ? AND idempotency_key = ? AND status = 'pending'
                """,
                (
                    status,
                    canonical_json(response),
                    time.time(),
                    provider_id,
                    action,
                    idempotency_key,
                ),
            )
            if cursor.rowcount != 1:
                raise FabricError(
                    "operation.state-conflict",
                    "Fabric operation state changed unexpectedly",
                    "The idempotency record was not pending when Fabric finalized it.",
                    change_state="unknown",
                    recovery_actions=("fabric.reconcile",),
                )
            event = None
            if event_topic is not None and event_payload is not None and event_retention is not None:
                event = self._append_event_in_transaction(
                    connection,
                    event_topic,
                    event_payload,
                    retention=event_retention,
                )
            connection.execute("COMMIT")
            return event
        except Exception:
            connection.execute("ROLLBACK")
            raise

    def reconcile_interrupted_requests(self) -> int:
        connection = self._require_connection()
        cursor = connection.execute(
            """
            UPDATE idempotency
            SET status = 'interrupted', updated_at = ?
            WHERE status = 'pending'
            """,
            (time.time(),),
        )
        return int(cursor.rowcount)

    def append_event(
        self,
        topic: str,
        payload: Mapping[str, Any],
        *,
        retention: int,
    ) -> dict[str, Any]:
        connection = self._require_connection()
        connection.execute("BEGIN IMMEDIATE")
        try:
            event = self._append_event_in_transaction(
                connection,
                topic,
                payload,
                retention=retention,
            )
            connection.execute("COMMIT")
        except Exception:
            connection.execute("ROLLBACK")
            raise
        return event

    @staticmethod
    def _append_event_in_transaction(
        connection: sqlite3.Connection,
        topic: str,
        payload: Mapping[str, Any],
        *,
        retention: int,
    ) -> dict[str, Any]:
        event_id = str(uuid.uuid4())
        created_at = time.time()
        cursor = connection.execute(
            "INSERT INTO events(event_id, topic, payload_json, created_at) VALUES (?, ?, ?, ?)",
            (event_id, topic, canonical_json(payload), created_at),
        )
        sequence = int(cursor.lastrowid)
        cutoff = connection.execute(
            "SELECT sequence FROM events ORDER BY sequence DESC LIMIT 1 OFFSET ?",
            (retention,),
        ).fetchone()
        if cutoff is not None:
            cutoff_sequence = int(cutoff[0])
            connection.execute("DELETE FROM events WHERE sequence <= ?", (cutoff_sequence,))
            connection.execute(
                "INSERT OR REPLACE INTO schema_metadata(key, value) VALUES ('event_pruned_through', ?)",
                (str(cutoff_sequence),),
            )
        return {
            "sequence": sequence,
            "id": event_id,
            "topic": topic,
            "payload": dict(payload),
            "createdAt": created_at,
        }

    def latest_event_sequence(self) -> int:
        row = self._require_connection().execute("SELECT MAX(sequence) FROM events").fetchone()
        return 0 if row is None or row[0] is None else int(row[0])

    def event_pruned_through(self) -> int:
        row = self._require_connection().execute(
            "SELECT value FROM schema_metadata WHERE key = 'event_pruned_through'"
        ).fetchone()
        return 0 if row is None else int(row[0])

    def replay_events(
        self,
        *,
        after: int,
        through: int,
        topics: Sequence[str],
        limit: int,
    ) -> list[dict[str, Any]]:
        if after < self.event_pruned_through():
            raise FabricError(
                "events.cursor-expired",
                "Fabric event cursor has expired",
                "The requested event cursor is older than the retained event history.",
                detail=f"pruned through {self.event_pruned_through()}",
                recovery_actions=("events.refresh-state",),
            )
        clauses = ["sequence > ?", "sequence <= ?"]
        parameters: list[Any] = [after, through]
        if topics and "*" not in topics:
            placeholders = ",".join("?" for _ in topics)
            clauses.append(f"topic IN ({placeholders})")
            parameters.extend(topics)
        parameters.append(limit + 1)
        rows = self._require_connection().execute(
            f"""
            SELECT sequence, event_id, topic, payload_json, created_at
            FROM events
            WHERE {' AND '.join(clauses)}
            ORDER BY sequence
            LIMIT ?
            """,
            parameters,
        ).fetchall()
        if len(rows) > limit:
            raise FabricError(
                "events.replay-limit",
                "Fabric event replay is too large",
                f"At most {limit} retained events may be attached to one subscription.",
                detail=f"more events remain after sequence {after}",
                retryable=True,
                recovery_actions=("events.refresh-state",),
            )
        return [
            {
                "sequence": int(row["sequence"]),
                "id": row["event_id"],
                "topic": row["topic"],
                "payload": json.loads(row["payload_json"]),
                "createdAt": row["created_at"],
            }
            for row in rows
        ]

    def start_daemon_run(self, pid: int) -> str:
        run_id = str(uuid.uuid4())
        self._require_connection().execute(
            "INSERT INTO daemon_runs(run_id, pid, started_at) VALUES (?, ?, ?)",
            (run_id, pid, time.time()),
        )
        return run_id

    def finish_daemon_run(self, run_id: str, reason: str) -> None:
        self._require_connection().execute(
            """
            UPDATE daemon_runs
            SET stopped_at = ?, shutdown_reason = ?, clean_shutdown = 1
            WHERE run_id = ?
            """,
            (time.time(), reason, run_id),
        )

    def last_daemon_run(self) -> dict[str, Any] | None:
        row = self._require_connection().execute(
            """
            SELECT run_id, pid, started_at, stopped_at, shutdown_reason, clean_shutdown
            FROM daemon_runs ORDER BY started_at DESC LIMIT 1
            """
        ).fetchone()
        if row is None:
            return None
        return {
            "runId": row["run_id"],
            "pid": row["pid"],
            "startedAt": row["started_at"],
            "stoppedAt": row["stopped_at"],
            "shutdownReason": row["shutdown_reason"],
            "cleanShutdown": bool(row["clean_shutdown"]),
        }
