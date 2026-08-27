"""Owner-scoped durable SQLite state for the provisional managed-work plane."""

from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import stat
import threading
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator, Sequence

from .errors import ManagedWorkError
from .validation import scan_secret_fields

CURRENT_SCHEMA = 4
MIN_READABLE_SCHEMA = 1
MAX_READABLE_SCHEMA = 4
MAX_DATABASE_BYTES = 512 * 1024 * 1024
MIN_DATABASE_BYTES = 256 * 1024

JSON_COLUMNS: dict[str, tuple[str, ...]] = {
    "approval_projections": ("payload_json",),
    "artifacts": ("payload_json",),
    "automation_firings": ("detail_json",),
    "automations": ("task_template_json", "trigger_json", "policy_json"),
    "contexts": ("content_json", "redacted_paths_json"),
    "idempotency": ("result_json",),
    "managed_events": ("payload_json",),
    "operation_links": ("payload_json",),
    "permission_projections": ("payload_json",),
    "provider_projections": ("payload_json",),
    "runs": ("manifest_json",),
    "steps": ("detail_json",),
    "tasks": ("intent_json", "context_ids_json", "budget_json"),
    "usage_records": ("payload_json",),
}

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
    3: (
        """
        CREATE TABLE provider_projections (
          row_id INTEGER PRIMARY KEY AUTOINCREMENT,
          provider_id TEXT NOT NULL,
          principal_id TEXT NOT NULL,
          owner_session_id TEXT NOT NULL,
          source_revision INTEGER NOT NULL CHECK(source_revision > 0),
          provider_version TEXT NOT NULL,
          registry_generation INTEGER NOT NULL CHECK(registry_generation > 0),
          installed INTEGER NOT NULL CHECK(installed IN (0, 1)),
          available INTEGER NOT NULL CHECK(available IN (0, 1)),
          state TEXT NOT NULL CHECK(state IN ('available', 'unavailable', 'incompatible', 'not-registered')),
          code TEXT NOT NULL,
          explanation TEXT NOT NULL,
          registered_at REAL NOT NULL,
          changed_at REAL NOT NULL,
          projected_at REAL NOT NULL,
          payload_json TEXT NOT NULL,
          UNIQUE(principal_id, provider_id)
        ) STRICT
        """,
        "CREATE INDEX provider_projections_owner_rows ON provider_projections(principal_id, row_id DESC)",
    ),
    4: (
        """
        CREATE TABLE provider_projections_v4 (
          row_id INTEGER PRIMARY KEY AUTOINCREMENT,
          provider_id TEXT NOT NULL,
          principal_id TEXT NOT NULL,
          owner_session_id TEXT NOT NULL,
          source_revision INTEGER NOT NULL CHECK(source_revision > 0),
          provider_version TEXT NOT NULL,
          registry_generation INTEGER NOT NULL CHECK(registry_generation > 0),
          registration_order INTEGER NOT NULL CHECK(registration_order >= 0),
          installed INTEGER NOT NULL CHECK(installed IN (0, 1)),
          available INTEGER NOT NULL CHECK(available IN (0, 1)),
          state TEXT NOT NULL CHECK(state IN ('available', 'degraded', 'unavailable', 'incompatible', 'not-registered')),
          code TEXT NOT NULL,
          explanation TEXT NOT NULL,
          registered_at REAL NOT NULL,
          changed_at REAL NOT NULL,
          projected_at REAL NOT NULL,
          payload_json TEXT NOT NULL,
          UNIQUE(principal_id, provider_id)
        ) STRICT
        """,
        """
        INSERT INTO provider_projections_v4(
          row_id, provider_id, principal_id, owner_session_id, source_revision,
          provider_version, registry_generation, registration_order, installed,
          available, state, code, explanation, registered_at, changed_at,
          projected_at, payload_json
        )
        SELECT row_id, provider_id, principal_id, owner_session_id, source_revision,
               provider_version, registry_generation, 0, installed, available,
               state, code, explanation, registered_at, changed_at, projected_at,
               payload_json
        FROM provider_projections
        """,
        "UPDATE provider_projections_v4 SET payload_json = json_set(payload_json, '$.registrationOrder', 0)",
        "UPDATE operation_links SET payload_json = json_set(payload_json, '$.legacyOwner', json('false')) WHERE json_type(payload_json, '$.legacyOwner') IS NULL",
        "DROP TABLE provider_projections",
        "ALTER TABLE provider_projections_v4 RENAME TO provider_projections",
        "CREATE INDEX provider_projections_owner_rows ON provider_projections(principal_id, registration_order, provider_id)",
    ),
}

EXPECTED_TABLES = frozenset(
    {
        "approval_projections",
        "artifacts",
        "automation_firings",
        "automations",
        "contexts",
        "idempotency",
        "managed_events",
        "managed_metadata",
        "operation_links",
        "permission_projections",
        "provider_projections",
        "runs",
        "steps",
        "tasks",
        "usage_records",
    }
)
_EXPECTED_SCHEMA_CACHE: dict[int, dict[tuple[str, str], tuple[str, str]]] = {}


def _normalized_schema_sql(value: str | None) -> str:
    return "" if value is None else " ".join(value.split())


def _schema_objects(connection: sqlite3.Connection) -> dict[tuple[str, str], tuple[str, str]]:
    return {
        (str(row[0]), str(row[1])): (str(row[2]), _normalized_schema_sql(row[3]))
        for row in connection.execute(
            """
            SELECT type, name, tbl_name, sql
            FROM sqlite_master
            WHERE name NOT LIKE 'sqlite_%'
              AND type IN ('table', 'index', 'trigger', 'view')
            ORDER BY type, name
            """
        )
    }


def _expected_schema_objects(version: int) -> dict[tuple[str, str], tuple[str, str]]:
    cached = _EXPECTED_SCHEMA_CACHE.get(version)
    if cached is not None:
        return cached
    connection = sqlite3.connect(":memory:")
    try:
        for target in range(1, version + 1):
            statements = MIGRATIONS.get(target)
            if statements is None:
                raise RuntimeError(f"missing managed-work schema {target}")
            for statement in statements:
                connection.execute(statement)
        expected = _schema_objects(connection)
    finally:
        connection.close()
    _EXPECTED_SCHEMA_CACHE[version] = expected
    return expected


class ManagedWorkStore:
    """A narrow SQLite owner with explicit schema and restart semantics."""

    def __init__(self, path: Path, *, maximum_database_bytes: int = MAX_DATABASE_BYTES) -> None:
        self.path = Path(path)
        if (
            isinstance(maximum_database_bytes, bool)
            or not isinstance(maximum_database_bytes, int)
            or not MIN_DATABASE_BYTES <= maximum_database_bytes <= MAX_DATABASE_BYTES
        ):
            raise ValueError(
                f"maximum database bytes must be between {MIN_DATABASE_BYTES} and {MAX_DATABASE_BYTES}"
            )
        self.maximum_database_bytes = maximum_database_bytes
        self.connection: sqlite3.Connection | None = None
        self.backup_path: Path | None = None
        self.restart_recoveries = 0
        self._lock = threading.RLock()
        self._savepoint_sequence = 0
        self._sidecar_holds: dict[str, tuple[int, tuple[int, int]]] = {}

    def _check_sidecars(self) -> None:
        for suffix in ("-journal", "-wal", "-shm"):
            sidecar = Path(f"{self.path}{suffix}")
            try:
                metadata = sidecar.lstat()
            except FileNotFoundError:
                continue
            if (
                stat.S_ISLNK(metadata.st_mode)
                or not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
            ):
                raise ManagedWorkError(
                    "managed-work.database-unsafe",
                    "A managed-work SQLite sidecar path is unsafe.",
                    detail=suffix,
                )
            if hasattr(os, "getuid") and metadata.st_uid != os.getuid():
                raise ManagedWorkError(
                    "managed-work.database-owner",
                    "A managed-work SQLite sidecar has another owner.",
                    detail=suffix,
                )
            if os.name != "nt":
                os.chmod(sidecar, 0o600)

    def _hold_existing_sidecars(self) -> None:
        held: dict[str, tuple[int, tuple[int, int]]] = {}
        try:
            for suffix in ("-journal", "-wal", "-shm"):
                sidecar = Path(f"{self.path}{suffix}")
                try:
                    expected = sidecar.lstat()
                except FileNotFoundError:
                    continue
                flags = os.O_RDWR
                if hasattr(os, "O_CLOEXEC"):
                    flags |= os.O_CLOEXEC
                if hasattr(os, "O_NOFOLLOW"):
                    flags |= os.O_NOFOLLOW
                descriptor = os.open(sidecar, flags)
                metadata = os.fstat(descriptor)
                identity = (metadata.st_dev, metadata.st_ino)
                if (
                    not stat.S_ISREG(metadata.st_mode)
                    or metadata.st_nlink != 1
                    or (hasattr(os, "getuid") and metadata.st_uid != os.getuid())
                    or identity != (expected.st_dev, expected.st_ino)
                ):
                    os.close(descriptor)
                    raise ManagedWorkError(
                        "managed-work.database-unsafe",
                        "A managed-work SQLite sidecar changed while it was held.",
                        detail=suffix,
                    )
                if os.name != "nt":
                    os.fchmod(descriptor, 0o600)
                if suffix == "-journal":
                    os.close(descriptor)
                else:
                    held[suffix] = (descriptor, identity)
        except Exception:
            for descriptor, _identity in held.values():
                os.close(descriptor)
            raise
        self._sidecar_holds = held

    def _release_sidecar_holds(self) -> None:
        held = self._sidecar_holds
        self._sidecar_holds = {}
        for descriptor, _identity in held.values():
            try:
                os.close(descriptor)
            except OSError:
                pass

    def _verify_open_sidecars(
        self,
        suffixes: Sequence[str],
        *,
        require_open: bool,
    ) -> None:
        descriptor_directory = Path("/proc/self/fd")
        if os.name != "nt" and not descriptor_directory.is_dir():
            raise ManagedWorkError(
                "managed-work.database-unsafe",
                "Fabric cannot prove managed-work SQLite sidecar identities.",
            )
        if os.name == "nt":
            descriptors: list[int] = []
        else:
            try:
                descriptors = [
                    int(entry.name)
                    for entry in descriptor_directory.iterdir()
                    if entry.name.isdigit()
                ]
            except OSError as error:
                raise ManagedWorkError(
                    "managed-work.database-unsafe",
                    "Fabric could not enumerate managed-work SQLite sidecars.",
                    detail=type(error).__name__,
                ) from error
        for suffix in suffixes:
            path = Path(f"{self.path}{suffix}")
            try:
                metadata = path.lstat()
            except FileNotFoundError:
                if require_open:
                    raise ManagedWorkError(
                        "managed-work.database-unsafe",
                        "A managed-work SQLite sidecar is missing at its use boundary.",
                        detail=suffix,
                    )
                continue
            identity = (metadata.st_dev, metadata.st_ino)
            if (
                not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
                or (hasattr(os, "getuid") and metadata.st_uid != os.getuid())
            ):
                raise ManagedWorkError(
                    "managed-work.database-unsafe",
                    "A managed-work SQLite sidecar is unsafe.",
                    detail=suffix,
                )
            held = self._sidecar_holds.get(suffix)
            if held is not None and held[1] != identity:
                raise ManagedWorkError(
                    "managed-work.database-unsafe",
                    "A held managed-work SQLite sidecar changed identity.",
                    detail=suffix,
                )
            if os.name != "nt":
                excluded = None if held is None else held[0]
                matched = False
                for descriptor in descriptors:
                    if descriptor == excluded:
                        continue
                    try:
                        opened = os.fstat(descriptor)
                    except OSError:
                        continue
                    if stat.S_ISREG(opened.st_mode) and (opened.st_dev, opened.st_ino) == identity:
                        matched = True
                        break
                if require_open and not matched:
                    raise ManagedWorkError(
                        "managed-work.database-unsafe",
                        "Fabric could not prove SQLite's opened managed-work sidecar inode.",
                        detail=suffix,
                    )
            if os.name != "nt":
                os.chmod(path, 0o600)

    def _open_held_database(self, expected: os.stat_result | None) -> tuple[int, tuple[int, int]]:
        flags = os.O_RDWR | os.O_CREAT
        if hasattr(os, "O_CLOEXEC"):
            flags |= os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = os.open(self.path, flags, 0o600)
        metadata = os.fstat(descriptor)
        identity = (metadata.st_dev, metadata.st_ino)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            os.close(descriptor)
            raise ManagedWorkError(
                "managed-work.database-unsafe",
                "The held managed-work database file is unsafe.",
            )
        if hasattr(os, "getuid") and metadata.st_uid != os.getuid():
            os.close(descriptor)
            raise ManagedWorkError(
                "managed-work.database-owner",
                "The held managed-work database file has another owner.",
            )
        if expected is not None and identity != (expected.st_dev, expected.st_ino):
            os.close(descriptor)
            raise ManagedWorkError(
                "managed-work.database-unsafe",
                "The managed-work database identity changed before it could be opened.",
            )
        if os.name != "nt":
            os.fchmod(descriptor, 0o600)
        return descriptor, identity

    def _verify_connected_identity(
        self,
        *,
        connection: sqlite3.Connection,
        held_descriptor: int,
        identity: tuple[int, int],
        existing_matches: frozenset[int],
    ) -> None:
        path_metadata = self.path.lstat()
        if (
            not stat.S_ISREG(path_metadata.st_mode)
            or path_metadata.st_nlink != 1
            or (path_metadata.st_dev, path_metadata.st_ino) != identity
        ):
            raise ManagedWorkError(
                "managed-work.database-unsafe",
                "The managed-work database path changed while SQLite opened it.",
            )
        database_rows = connection.execute("PRAGMA database_list").fetchall()
        main_rows = [row for row in database_rows if str(row[1]) == "main"]
        if len(main_rows) != 1:
            raise ManagedWorkError(
                "managed-work.database-unsafe",
                "Fabric could not verify SQLite's main managed-work database.",
            )
        try:
            connected_path = Path(str(main_rows[0][2])).resolve(strict=True)
        except (OSError, RuntimeError) as error:
            raise ManagedWorkError(
                "managed-work.database-unsafe",
                "Fabric could not resolve SQLite's opened managed-work database path.",
                detail=type(error).__name__,
            ) from error
        if connected_path != self.path.resolve(strict=True):
            raise ManagedWorkError(
                "managed-work.database-unsafe",
                "SQLite opened an unexpected managed-work database path.",
            )
        if os.name == "nt":
            return

        descriptor_directory = Path("/proc/self/fd")
        if not descriptor_directory.is_dir():
            raise ManagedWorkError(
                "managed-work.database-unsafe",
                "Fabric cannot prove SQLite's managed-work database inode on this platform.",
            )
        try:
            descriptors = [
                int(entry.name)
                for entry in descriptor_directory.iterdir()
                if entry.name.isdigit()
            ]
        except OSError as error:
            raise ManagedWorkError(
                "managed-work.database-unsafe",
                "Fabric could not enumerate SQLite's live database descriptors.",
                detail=type(error).__name__,
            ) from error

        matches: set[int] = set()
        for descriptor in descriptors:
            if descriptor == held_descriptor:
                continue
            try:
                metadata = os.fstat(descriptor)
            except OSError:
                continue
            if stat.S_ISREG(metadata.st_mode) and (metadata.st_dev, metadata.st_ino) == identity:
                matches.add(descriptor)
        new_matches = matches - existing_matches
        if not existing_matches.issubset(matches) or len(new_matches) != 1:
            raise ManagedWorkError(
                "managed-work.database-unsafe",
                "Fabric could not verify SQLite's opened managed-work database inode.",
                detail=f"matching descriptors: {len(matches)}; new: {len(new_matches)}",
            )

    @staticmethod
    def _matching_descriptors(identity: tuple[int, int], *, exclude: int) -> frozenset[int]:
        if os.name == "nt":
            return frozenset()
        descriptor_directory = Path("/proc/self/fd")
        if not descriptor_directory.is_dir():
            raise ManagedWorkError(
                "managed-work.database-unsafe",
                "Fabric cannot enumerate SQLite descriptors before connect.",
            )
        try:
            descriptors = [
                int(entry.name)
                for entry in descriptor_directory.iterdir()
                if entry.name.isdigit()
            ]
        except OSError as error:
            raise ManagedWorkError(
                "managed-work.database-unsafe",
                "Fabric could not enumerate SQLite descriptors before connect.",
                detail=type(error).__name__,
            ) from error
        matches: set[int] = set()
        for descriptor in descriptors:
            if descriptor == exclude:
                continue
            try:
                metadata = os.fstat(descriptor)
            except OSError:
                continue
            if stat.S_ISREG(metadata.st_mode) and (metadata.st_dev, metadata.st_ino) == identity:
                matches.add(descriptor)
        return frozenset(matches)

    def open(self, *, database_lease_descriptor: int | None = None) -> None:
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
                if metadata.st_size > self.maximum_database_bytes:
                    raise ManagedWorkError(
                        "managed-work.database-capacity",
                        "The managed-work database exceeds its bounded on-disk capacity.",
                    )
                if hasattr(os, "getuid") and metadata.st_uid != os.getuid():
                    raise ManagedWorkError("managed-work.database-owner", "The managed-work database has another owner.")
            self._check_sidecars()
            self._hold_existing_sidecars()
            close_held_descriptor = database_lease_descriptor is None
            if database_lease_descriptor is None:
                held_descriptor, held_identity = self._open_held_database(metadata)
            else:
                held_descriptor = database_lease_descriptor
                held_metadata = os.fstat(held_descriptor)
                held_identity = (held_metadata.st_dev, held_metadata.st_ino)
                path_metadata = self.path.lstat()
                if (
                    not stat.S_ISREG(held_metadata.st_mode)
                    or held_metadata.st_nlink != 1
                    or (hasattr(os, "getuid") and held_metadata.st_uid != os.getuid())
                    or held_identity != (path_metadata.st_dev, path_metadata.st_ino)
                ):
                    raise ManagedWorkError(
                        "managed-work.database-unsafe",
                        "The daemon's managed-work database lease is unsafe.",
                    )
            try:
                existing_matches = self._matching_descriptors(
                    held_identity,
                    exclude=held_descriptor,
                )
                connection = sqlite3.connect(
                    self.path,
                    timeout=5.0,
                    isolation_level=None,
                    check_same_thread=False,
                )
                self._verify_connected_identity(
                    connection=connection,
                    held_descriptor=held_descriptor,
                    identity=held_identity,
                    existing_matches=existing_matches,
                )
            finally:
                if close_held_descriptor:
                    os.close(held_descriptor)
            connection.row_factory = sqlite3.Row
            connection.execute("PRAGMA busy_timeout = 5000")
            connection.execute("PRAGMA foreign_keys = ON")
            connection.execute("PRAGMA trusted_schema = OFF")
            if self._sidecar_holds:
                connection.execute("PRAGMA schema_version").fetchone()
                self._verify_open_sidecars(
                    tuple(self._sidecar_holds),
                    require_open=True,
                )
            page_size = int(connection.execute("PRAGMA page_size").fetchone()[0])
            maximum_pages = self.maximum_database_bytes // page_size
            applied_maximum = int(
                connection.execute(f"PRAGMA max_page_count = {maximum_pages}").fetchone()[0]
            )
            if applied_maximum > maximum_pages:
                raise ManagedWorkError(
                    "managed-work.database-capacity",
                    "The managed-work database already exceeds its configured logical page capacity.",
                )
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
            if current:
                self._check_closed_schema(connection, current)
                self._check_no_unredacted_secrets(connection)
            if current and current < CURRENT_SCHEMA:
                self.backup_path = self._backup(connection, current)
            migration_mode = str(connection.execute("PRAGMA journal_mode").fetchone()[0]).lower()
            migration_sidecars = ("-wal", "-shm") if migration_mode == "wal" else ("-journal",)
            self._migrate(connection, current, sidecars=migration_sidecars)
            self._check_closed_schema(connection, CURRENT_SCHEMA)
            migrated_tables = {
                row[0]
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
                )
            }
            if migrated_tables != EXPECTED_TABLES:
                missing = sorted(EXPECTED_TABLES - migrated_tables)
                extra = sorted(migrated_tables - EXPECTED_TABLES)
                detail = []
                if missing:
                    detail.append(f"missing: {', '.join(missing)}")
                if extra:
                    detail.append(f"unknown: {', '.join(extra)}")
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused a database whose closed schema does not match its version.",
                    detail="; ".join(detail),
                    recovery_actions=("managed-work.restore-database",),
                )
            foreign_key_violation = connection.execute("PRAGMA foreign_key_check").fetchone()
            if foreign_key_violation is not None:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused a database with broken ownership references.",
                    detail=str(foreign_key_violation[0]),
                    recovery_actions=("managed-work.restore-database",),
                )
            self._check_json_columns(connection)
            self._check_json_semantics(connection)
            self._check_owner_relations(connection)
            journal_mode = str(connection.execute("PRAGMA journal_mode = WAL").fetchone()[0]).lower()
            if journal_mode != "wal":
                raise ManagedWorkError("managed-work.database-wal", "Managed work requires SQLite WAL mode.")
            connection.execute("PRAGMA synchronous = FULL")
            connection.execute("PRAGMA wal_autocheckpoint = 100")
            connection.execute(
                f"PRAGMA journal_size_limit = {min(self.maximum_database_bytes // 16, 16 * 1024 * 1024)}"
            )
            connection.execute("BEGIN IMMEDIATE")
            try:
                connection.execute(
                    "UPDATE managed_metadata SET value = value WHERE key = 'schema_version'"
                )
                self._verify_open_sidecars(
                    ("-wal", "-shm"),
                    require_open=True,
                )
            finally:
                connection.execute("ROLLBACK")
            self._check_sidecars()
            if os.name != "nt":
                os.chmod(self.path, 0o600)
            self.connection = connection
        except ManagedWorkError:
            if "connection" in locals():
                connection.close()
            self.connection = None
            self._release_sidecar_holds()
            raise
        except (sqlite3.DatabaseError, OSError) as error:
            if "connection" in locals():
                connection.close()
            self.connection = None
            self._release_sidecar_holds()
            raise self._database_error(error, context="open") from error

    @staticmethod
    def _database_error(error: BaseException, *, context: str) -> ManagedWorkError:
        sqlite_code = getattr(error, "sqlite_errorcode", None)
        primary = None if not isinstance(sqlite_code, int) else sqlite_code & 0xFF
        io_codes = {
            sqlite3.SQLITE_BUSY,
            sqlite3.SQLITE_CANTOPEN,
            sqlite3.SQLITE_FULL,
            sqlite3.SQLITE_IOERR,
            sqlite3.SQLITE_LOCKED,
            sqlite3.SQLITE_READONLY,
        }
        if isinstance(error, OSError) or primary in io_codes:
            return ManagedWorkError(
                "managed-work.database-io",
                "Managed work could not durably access its database.",
                retryable=primary in {sqlite3.SQLITE_BUSY, sqlite3.SQLITE_LOCKED},
                detail=f"{context}: {type(error).__name__}",
                recovery_actions=("managed-work.check-storage",),
            )
        return ManagedWorkError(
            "managed-work.database-corrupt",
            "Managed work refused malformed or inconsistent database state.",
            detail=f"{context}: {type(error).__name__}",
            recovery_actions=("managed-work.restore-database",),
        )

    @staticmethod
    def _rollback_preserving(connection: sqlite3.Connection) -> None:
        try:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
        except sqlite3.DatabaseError:
            pass

    @staticmethod
    def _check_integrity(connection: sqlite3.Connection) -> None:
        row = connection.execute("PRAGMA quick_check").fetchone()
        if row is None or row[0] != "ok":
            raise ManagedWorkError(
                "managed-work.database-corrupt",
                "Managed work refused a database that failed SQLite integrity checks.",
                detail="missing result" if row is None else str(row[0]),
            )

    @staticmethod
    def _check_closed_schema(connection: sqlite3.Connection, version: int) -> None:
        actual = _schema_objects(connection)
        expected = _expected_schema_objects(version)
        if actual == expected:
            return
        actual_keys = set(actual)
        expected_keys = set(expected)
        missing = sorted(f"{kind}:{name}" for kind, name in expected_keys - actual_keys)
        extra = sorted(f"{kind}:{name}" for kind, name in actual_keys - expected_keys)
        changed = sorted(
            f"{kind}:{name}"
            for kind, name in actual_keys & expected_keys
            if actual[(kind, name)] != expected[(kind, name)]
        )
        detail_parts = []
        if missing:
            detail_parts.append(f"missing {', '.join(missing[:8])}")
        if extra:
            detail_parts.append(f"unexpected {', '.join(extra[:8])}")
        if changed:
            detail_parts.append(f"changed {', '.join(changed[:8])}")
        raise ManagedWorkError(
            "managed-work.database-corrupt",
            "Managed work refused a database whose versioned schema objects are not exact.",
            detail="; ".join(detail_parts),
            recovery_actions=("managed-work.restore-database",),
        )

    @staticmethod
    def _check_json_columns(connection: sqlite3.Connection) -> None:
        for table, columns in JSON_COLUMNS.items():
            for column in columns:
                invalid = connection.execute(
                    f"SELECT 1 FROM {table} WHERE {column} IS NOT NULL AND json_valid({column}) = 0 LIMIT 1"
                ).fetchone()
                if invalid is not None:
                    raise ManagedWorkError(
                        "managed-work.database-corrupt",
                        "Managed work refused malformed durable JSON.",
                        detail=f"{table}.{column}",
                        recovery_actions=("managed-work.restore-database",),
                    )

    @staticmethod
    def _check_no_unredacted_secrets(connection: sqlite3.Connection) -> None:
        tables = {
            str(row[0])
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
            )
        }
        for table, columns in JSON_COLUMNS.items():
            if table not in tables:
                continue
            actual_columns = {
                str(row[1]) for row in connection.execute(f'PRAGMA table_info("{table}")')
            }
            for column in columns:
                if column not in actual_columns:
                    continue
                for row in connection.execute(
                    f"SELECT {column} FROM {table} WHERE {column} IS NOT NULL"
                ):
                    try:
                        value = json.loads(row[0])
                    except (TypeError, ValueError, json.JSONDecodeError) as error:
                        raise ManagedWorkError(
                            "managed-work.database-corrupt",
                            "Managed work refused malformed durable JSON before migration.",
                            detail=f"{table}.{column}",
                            recovery_actions=("managed-work.restore-database",),
                        ) from error
                    findings = scan_secret_fields(value, allow_redacted_keys=True)
                    if findings:
                        path, kind = findings[0]
                        raise ManagedWorkError(
                            "managed-work.database-corrupt",
                            "Managed work refused durable content containing unredacted secret-shaped data.",
                            detail=f"{table}.{column}:{kind} at {path}",
                            recovery_actions=("managed-work.restore-database",),
                        )
        for table in sorted(tables & EXPECTED_TABLES):
            json_columns = set(JSON_COLUMNS.get(table, ()))
            text_columns = [
                str(row[1])
                for row in connection.execute(f'PRAGMA table_info("{table}")')
                if str(row[2]).upper() == "TEXT" and str(row[1]) not in json_columns
            ]
            for column in text_columns:
                for row in connection.execute(
                    f'SELECT "{column}" FROM "{table}" WHERE "{column}" IS NOT NULL'
                ):
                    findings = scan_secret_fields(row[0])
                    if findings:
                        path, kind = findings[0]
                        raise ManagedWorkError(
                            "managed-work.database-corrupt",
                            "Managed work refused durable text containing secret-shaped data.",
                            detail=f"{table}.{column}:{kind} at {path}",
                            recovery_actions=("managed-work.restore-database",),
                        )

    @staticmethod
    def _check_json_semantics(connection: sqlite3.Connection) -> None:
        ManagedWorkStore._check_no_unredacted_secrets(connection)
        object_columns = {
            "approval_projections": ("payload_json",),
            "artifacts": ("payload_json",),
            "automation_firings": ("detail_json",),
            "automations": ("task_template_json", "trigger_json", "policy_json"),
            "managed_events": ("payload_json",),
            "operation_links": ("payload_json",),
            "permission_projections": ("payload_json",),
            "provider_projections": ("payload_json",),
            "runs": ("manifest_json",),
            "steps": ("detail_json",),
            "tasks": ("intent_json", "budget_json"),
            "usage_records": ("payload_json",),
        }
        for table, columns in object_columns.items():
            for column in columns:
                row = connection.execute(
                    f"SELECT 1 FROM {table} WHERE {column} IS NOT NULL AND json_type({column}) != 'object' LIMIT 1"
                ).fetchone()
                if row is not None:
                    raise ManagedWorkError(
                        "managed-work.database-corrupt",
                        "Managed work refused durable JSON with the wrong semantic type.",
                        detail=f"{table}.{column}",
                        recovery_actions=("managed-work.restore-database",),
                    )
        nullable_objects = connection.execute(
            "SELECT 1 FROM idempotency WHERE result_json IS NOT NULL AND json_type(result_json) != 'object' LIMIT 1"
        ).fetchone()
        if nullable_objects is not None:
            raise ManagedWorkError(
                "managed-work.database-corrupt",
                "Managed work refused an idempotency result with the wrong semantic type.",
                detail="idempotency.result_json",
                recovery_actions=("managed-work.restore-database",),
            )
        list_columns = {
            "contexts": ("redacted_paths_json",),
            "tasks": ("context_ids_json",),
        }
        for table, columns in list_columns.items():
            for column in columns:
                row = connection.execute(
                    f"SELECT 1 FROM {table} WHERE json_type({column}) != 'array' LIMIT 1"
                ).fetchone()
                if row is not None:
                    raise ManagedWorkError(
                        "managed-work.database-corrupt",
                        "Managed work refused a durable JSON list with the wrong semantic type.",
                        detail=f"{table}.{column}",
                        recovery_actions=("managed-work.restore-database",),
                    )
        for row in connection.execute(
            "SELECT context_id, content_json, content_hash, redacted_paths_json FROM contexts"
        ):
            content = json.loads(row["content_json"])
            canonical = json.dumps(
                content,
                ensure_ascii=False,
                allow_nan=False,
                separators=(",", ":"),
                sort_keys=True,
            )
            if hashlib.sha256(canonical.encode("utf-8")).hexdigest() != row["content_hash"]:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused a context snapshot whose content hash does not match.",
                    detail=str(row["context_id"]),
                    recovery_actions=("managed-work.restore-database",),
                )
            redacted_paths = json.loads(row["redacted_paths_json"])
            if not all(isinstance(value, str) for value in redacted_paths):
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused malformed context redaction evidence.",
                    detail=str(row["context_id"]),
                    recovery_actions=("managed-work.restore-database",),
                )
        for row in connection.execute("SELECT run_id, manifest_json, manifest_hash FROM runs"):
            manifest = json.loads(row["manifest_json"])
            canonical = json.dumps(
                manifest,
                ensure_ascii=False,
                allow_nan=False,
                separators=(",", ":"),
                sort_keys=True,
            )
            if hashlib.sha256(canonical.encode("utf-8")).hexdigest() != row["manifest_hash"]:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused a run whose manifest hash does not match.",
                    detail=str(row["run_id"]),
                    recovery_actions=("managed-work.restore-database",),
                )
        required_provider_fields = {
            "providerId",
            "providerVersion",
            "registryFingerprint",
            "detailDigest",
            "registryGeneration",
            "registrationOrder",
            "installed",
            "available",
            "state",
            "code",
            "explanation",
            "registeredAt",
            "changedAt",
        }
        for row in connection.execute(
            "SELECT * FROM provider_projections"
        ):
            payload = json.loads(row["payload_json"])
            fingerprint_value = payload.get("registryFingerprint") if isinstance(payload, dict) else None
            detail_digest = payload.get("detailDigest") if isinstance(payload, dict) else None
            valid_hashes = all(
                isinstance(value, str)
                and len(value) == 64
                and all(character in "0123456789abcdef" for character in value)
                for value in (fingerprint_value, detail_digest)
            )
            expected = {
                "providerId": row["provider_id"],
                "providerVersion": row["provider_version"],
                "registryFingerprint": fingerprint_value,
                "detailDigest": detail_digest,
                "registryGeneration": int(row["registry_generation"]),
                "registrationOrder": int(row["registration_order"]),
                "installed": bool(row["installed"]),
                "available": bool(row["available"]),
                "state": row["state"],
                "code": row["code"],
                "explanation": row["explanation"],
                "registeredAt": float(row["registered_at"]),
                "changedAt": float(row["changed_at"]),
            }
            expected_json = json.dumps(
                expected,
                ensure_ascii=False,
                allow_nan=False,
                separators=(",", ":"),
                sort_keys=True,
            )
            if (
                not isinstance(payload, dict)
                or set(payload) != required_provider_fields
                or not valid_hashes
                or row["payload_json"] != expected_json
            ):
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused an incoherent provider projection.",
                    detail=str(row["provider_id"]),
                    recovery_actions=("managed-work.restore-database",),
                )

        def require_payload_match(
            *,
            table: str,
            identity: str,
            payload_json: str,
            expected: dict[str, Any],
        ) -> None:
            expected_json = json.dumps(
                expected,
                ensure_ascii=False,
                allow_nan=False,
                separators=(",", ":"),
                sort_keys=True,
            )
            if payload_json != expected_json:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused a projection whose canonical payload disagrees with its scalar columns.",
                    detail=f"{table}:{identity}",
                    recovery_actions=("managed-work.restore-database",),
                )

        for row in connection.execute("SELECT * FROM approval_projections"):
            try:
                revision = int(row["source_revision"])
            except (TypeError, ValueError) as error:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused a malformed approval source revision.",
                    recovery_actions=("managed-work.restore-database",),
                ) from error
            if revision < 1 or str(revision) != row["source_revision"]:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused a non-canonical approval source revision.",
                    recovery_actions=("managed-work.restore-database",),
                )
            require_payload_match(
                table="approval_projections",
                identity=str(row["approval_id"]),
                payload_json=row["payload_json"],
                expected={
                    "sourceRevision": revision,
                    "approvalId": row["approval_id"],
                    "operationId": row["operation_id"],
                    "capability": row["capability"],
                    "state": row["state"],
                    "risk": row["risk"],
                    "summary": row["summary"],
                    "requestedAt": float(row["requested_at"]),
                    "expiresAt": float(row["expires_at"]),
                },
            )
        for row in connection.execute("SELECT * FROM operation_links"):
            try:
                revision = int(row["source_revision"])
                payload = json.loads(row["payload_json"])
            except (TypeError, ValueError, json.JSONDecodeError) as error:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused malformed operation projection metadata.",
                    recovery_actions=("managed-work.restore-database",),
                ) from error
            if revision < 1 or str(revision) != row["source_revision"]:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused a non-canonical operation source revision.",
                    recovery_actions=("managed-work.restore-database",),
                )
            artifact_ids = payload.get("artifactIds") if isinstance(payload, dict) else None
            legacy_owner = payload.get("legacyOwner") if isinstance(payload, dict) else None
            require_payload_match(
                table="operation_links",
                identity=str(row["operation_id"]),
                payload_json=row["payload_json"],
                expected={
                    "sourceRevision": revision,
                    "legacyOwner": legacy_owner,
                    "operationId": row["operation_id"],
                    "taskId": row["task_id"],
                    "runId": row["run_id"],
                    "capability": row["capability"],
                    "status": row["status"],
                    "changeState": row["change_state"],
                    "summary": row["summary"],
                    "recoveryEligible": bool(row["recovery_eligible"]),
                    "artifactIds": artifact_ids,
                    "createdAt": float(row["created_at"]),
                    "updatedAt": float(row["updated_at"]),
                },
            )
            if not isinstance(legacy_owner, bool) or not isinstance(artifact_ids, list):
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused malformed operation provenance metadata.",
                    detail=str(row["operation_id"]),
                    recovery_actions=("managed-work.restore-database",),
                )
        for row in connection.execute("SELECT * FROM permission_projections"):
            try:
                revision = int(row["source_revision"])
            except (TypeError, ValueError) as error:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused a malformed permission source revision.",
                    recovery_actions=("managed-work.restore-database",),
                ) from error
            if revision < 1 or str(revision) != row["source_revision"]:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused a non-canonical permission source revision.",
                    recovery_actions=("managed-work.restore-database",),
                )
            require_payload_match(
                table="permission_projections",
                identity=str(row["grant_id"]),
                payload_json=row["payload_json"],
                expected={
                    "sourceRevision": revision,
                    "grantId": row["grant_id"],
                    "capability": row["capability"],
                    "resource": row["resource"],
                    "state": row["state"],
                    "riskCeiling": row["risk_ceiling"],
                    "issuedAt": float(row["issued_at"]),
                    "expiresAt": None if row["expires_at"] is None else float(row["expires_at"]),
                },
            )
        for row in connection.execute("SELECT * FROM usage_records"):
            require_payload_match(
                table="usage_records",
                identity=str(row["usage_id"]),
                payload_json=row["payload_json"],
                expected={
                    "usageId": row["usage_id"],
                    "taskId": row["task_id"],
                    "runId": row["run_id"],
                    "provider": row["provider"],
                    "metric": row["metric"],
                    "quantity": float(row["quantity"]),
                    "unit": row["unit"],
                    "costMicrounits": int(row["cost_microunits"]),
                    "recordedAt": float(row["recorded_at"]),
                },
            )
        for row in connection.execute("SELECT * FROM artifacts"):
            require_payload_match(
                table="artifacts",
                identity=str(row["artifact_id"]),
                payload_json=row["payload_json"],
                expected={
                    "taskId": row["task_id"],
                    "runId": row["run_id"],
                    "handle": row["handle"],
                    "label": row["label"],
                    "mediaType": row["media_type"],
                    "byteLength": int(row["byte_length"]),
                    "contentHash": row["content_hash"],
                    "scope": row["scope"],
                },
            )

    @staticmethod
    def _check_owner_relations(connection: sqlite3.Connection) -> None:
        checks = {
            "contexts.task": """
                SELECT 1 FROM contexts child
                JOIN tasks parent ON parent.task_id = child.task_id
                WHERE child.task_id IS NOT NULL AND child.principal_id != parent.principal_id
                LIMIT 1
            """,
            "runs.task": """
                SELECT 1 FROM runs child
                JOIN tasks parent ON parent.task_id = child.task_id
                WHERE child.principal_id != parent.principal_id
                LIMIT 1
            """,
            "runs.parent": """
                SELECT 1 FROM runs child
                JOIN runs parent ON parent.run_id = child.parent_run_id
                WHERE child.parent_run_id IS NOT NULL
                  AND (child.principal_id != parent.principal_id OR child.task_id != parent.task_id)
                LIMIT 1
            """,
            "steps.run": """
                SELECT 1 FROM steps child
                JOIN runs parent ON parent.run_id = child.run_id
                WHERE child.principal_id != parent.principal_id
                LIMIT 1
            """,
            "automation-firings.automation": """
                SELECT 1 FROM automation_firings child
                JOIN automations parent ON parent.automation_id = child.automation_id
                WHERE child.principal_id != parent.principal_id
                LIMIT 1
            """,
            "artifacts.task": """
                SELECT 1 FROM artifacts child
                JOIN tasks parent ON parent.task_id = child.task_id
                WHERE child.principal_id != parent.principal_id
                LIMIT 1
            """,
            "artifacts.run": """
                SELECT 1 FROM artifacts child
                JOIN runs parent ON parent.run_id = child.run_id
                WHERE child.run_id IS NOT NULL
                  AND (
                    child.principal_id != parent.principal_id
                    OR child.task_id != parent.task_id
                  )
                LIMIT 1
            """,
            "tasks.context-json": """
                SELECT 1
                FROM tasks child
                JOIN json_each(child.context_ids_json) reference
                LEFT JOIN contexts context ON context.context_id = reference.value
                WHERE json_array_length(child.context_ids_json) > 64
                   OR reference.type != 'text'
                   OR context.context_id IS NULL
                   OR context.principal_id != child.principal_id
                   OR context.access_scope != 'principal'
                LIMIT 1
            """,
            "tasks.context-json-duplicates": """
                SELECT 1
                FROM tasks child
                WHERE (
                  SELECT COUNT(*) FROM json_each(child.context_ids_json)
                ) != (
                  SELECT COUNT(DISTINCT value) FROM json_each(child.context_ids_json)
                )
                LIMIT 1
            """,
            "runs.context-json": """
                SELECT 1
                FROM runs child
                JOIN tasks task ON task.task_id = child.task_id
                JOIN json_each(child.manifest_json, '$.contextIds') reference
                LEFT JOIN contexts context ON context.context_id = reference.value
                WHERE json_array_length(child.manifest_json, '$.contextIds') > 64
                   OR reference.type != 'text'
                   OR context.context_id IS NULL
                   OR context.principal_id != child.principal_id
                   OR context.access_scope = 'session'
                   OR (
                     context.access_scope = 'task'
                     AND context.task_id != child.task_id
                   )
                   OR (
                     context.access_scope = 'principal'
                     AND NOT EXISTS (
                       SELECT 1 FROM json_each(task.context_ids_json) task_reference
                       WHERE task_reference.value = context.context_id
                     )
                   )
                LIMIT 1
            """,
            "runs.context-json-duplicates": """
                SELECT 1
                FROM runs child
                WHERE (
                  SELECT COUNT(*) FROM json_each(child.manifest_json, '$.contextIds')
                ) != (
                  SELECT COUNT(DISTINCT value) FROM json_each(child.manifest_json, '$.contextIds')
                )
                LIMIT 1
            """,
            "operations.task-run": """
                SELECT 1
                FROM operation_links child
                LEFT JOIN tasks task ON task.task_id = child.task_id
                LEFT JOIN runs run ON run.run_id = child.run_id
                WHERE (child.task_id IS NULL AND child.run_id IS NOT NULL)
                   OR (child.task_id IS NOT NULL AND (
                     task.task_id IS NULL OR task.principal_id != child.principal_id
                   ))
                   OR (child.run_id IS NOT NULL AND (
                     run.run_id IS NULL
                     OR run.principal_id != child.principal_id
                     OR run.task_id != child.task_id
                   ))
                LIMIT 1
            """,
            "operations.artifact-json": """
                SELECT 1
                FROM operation_links child
                JOIN json_each(child.payload_json, '$.artifactIds') reference
                LEFT JOIN artifacts artifact ON artifact.artifact_id = reference.value
                WHERE json_array_length(child.payload_json, '$.artifactIds') > 128
                   OR reference.type != 'text'
                   OR artifact.artifact_id IS NULL
                   OR artifact.principal_id != child.principal_id
                LIMIT 1
            """,
            "operations.artifact-json-duplicates": """
                SELECT 1
                FROM operation_links child
                WHERE (
                  SELECT COUNT(*) FROM json_each(child.payload_json, '$.artifactIds')
                ) != (
                  SELECT COUNT(DISTINCT value) FROM json_each(child.payload_json, '$.artifactIds')
                )
                LIMIT 1
            """,
            "usage.task-run": """
                SELECT 1
                FROM usage_records child
                LEFT JOIN tasks task ON task.task_id = child.task_id
                LEFT JOIN runs run ON run.run_id = child.run_id
                WHERE (child.task_id IS NULL AND child.run_id IS NOT NULL)
                   OR (child.task_id IS NOT NULL AND (
                     task.task_id IS NULL OR task.principal_id != child.principal_id
                   ))
                   OR (child.run_id IS NOT NULL AND (
                     run.run_id IS NULL
                     OR run.principal_id != child.principal_id
                     OR run.task_id != child.task_id
                   ))
                LIMIT 1
            """,
            "approvals.operation-owner": """
                SELECT 1
                FROM approval_projections child
                JOIN operation_links operation ON operation.operation_id = child.operation_id
                WHERE operation.principal_id != child.principal_id
                  AND NOT EXISTS (
                    SELECT 1 FROM operation_links owned
                    WHERE owned.operation_id = child.operation_id
                      AND owned.principal_id = child.principal_id
                  )
                LIMIT 1
            """,
        }
        for label, statement in checks.items():
            if connection.execute(statement).fetchone() is not None:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused a cross-owner durable relationship.",
                    detail=label,
                    recovery_actions=("managed-work.restore-database",),
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

    def _migrate(
        self,
        connection: sqlite3.Connection,
        current: int,
        *,
        sidecars: Sequence[str],
    ) -> None:
        for target in range(current + 1, CURRENT_SCHEMA + 1):
            statements = MIGRATIONS.get(target)
            if statements is None:
                raise ManagedWorkError("managed-work.migration-missing", f"Migration {target} is unavailable.")
            connection.execute("BEGIN IMMEDIATE")
            try:
                for statement in statements:
                    connection.execute(statement)
                    self._verify_open_sidecars(
                        sidecars,
                        require_open=True,
                    )
                if target == 4:
                    for table in ("provider_projections", "operation_links"):
                        for row in connection.execute(
                            f"SELECT row_id, payload_json FROM {table}"
                        ).fetchall():
                            canonical = json.dumps(
                                json.loads(row["payload_json"]),
                                ensure_ascii=False,
                                allow_nan=False,
                                separators=(",", ":"),
                                sort_keys=True,
                            )
                            connection.execute(
                                f"UPDATE {table} SET payload_json = ? WHERE row_id = ?",
                                (canonical, row["row_id"]),
                            )
                connection.execute(
                    "INSERT OR REPLACE INTO managed_metadata(key, value) VALUES ('schema_version', ?)",
                    (str(target),),
                )
                connection.execute(f"PRAGMA user_version = {target}")
                connection.execute("COMMIT")
            except Exception:
                connection.execute("ROLLBACK")
                raise

    def recover_interrupted(self) -> int:
        now = time.time()
        with self.transaction() as connection:
            attached_session_context = connection.execute(
                """
                SELECT 1
                FROM contexts context
                JOIN tasks task ON task.principal_id = context.principal_id
                JOIN json_each(task.context_ids_json) reference
                  ON reference.value = context.context_id
                WHERE context.access_scope = 'session'
                LIMIT 1
                """
            ).fetchone()
            if attached_session_context is not None:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused a durable task bound to expired session context.",
                    recovery_actions=("managed-work.restore-database",),
                )
            connection.execute(
                """
                DELETE FROM idempotency
                WHERE action = 'context.capture'
                  AND json_extract(result_json, '$.contextId') IN (
                    SELECT context_id FROM contexts WHERE access_scope = 'session'
                  )
                """
            )
            session_contexts = connection.execute(
                "DELETE FROM contexts WHERE access_scope = 'session'"
            ).rowcount
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
            total = int(session_contexts + runs + tasks + claims)
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
            failure: ManagedWorkError | None = None
            try:
                connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            except (sqlite3.DatabaseError, OSError) as error:
                failure = self._database_error(error, context="close")
            finally:
                try:
                    connection.close()
                except (sqlite3.DatabaseError, OSError) as error:
                    if failure is None:
                        failure = self._database_error(error, context="close")
                self._release_sidecar_holds()
            if failure is not None:
                raise failure

    def require_connection(self) -> sqlite3.Connection:
        if self.connection is None:
            raise RuntimeError("managed-work store is not open")
        return self.connection

    @contextmanager
    def transaction(self) -> Iterator[sqlite3.Connection]:
        with self._lock:
            connection = self.require_connection()
            nested = connection.in_transaction
            savepoint = ""
            try:
                if nested:
                    self._savepoint_sequence += 1
                    savepoint = f"managed_work_{self._savepoint_sequence}"
                    connection.execute(f"SAVEPOINT {savepoint}")
                else:
                    connection.execute("BEGIN IMMEDIATE")
                yield connection
                if nested:
                    connection.execute(f"RELEASE SAVEPOINT {savepoint}")
                else:
                    connection.execute("COMMIT")
            except ManagedWorkError:
                if nested:
                    try:
                        connection.execute(f"ROLLBACK TO SAVEPOINT {savepoint}")
                        connection.execute(f"RELEASE SAVEPOINT {savepoint}")
                    except sqlite3.DatabaseError:
                        pass
                else:
                    self._rollback_preserving(connection)
                raise
            except (sqlite3.DatabaseError, OSError) as error:
                if nested:
                    try:
                        connection.execute(f"ROLLBACK TO SAVEPOINT {savepoint}")
                        connection.execute(f"RELEASE SAVEPOINT {savepoint}")
                    except sqlite3.DatabaseError:
                        pass
                else:
                    self._rollback_preserving(connection)
                raise self._database_error(error, context="transaction") from error
            except Exception:
                if nested:
                    try:
                        connection.execute(f"ROLLBACK TO SAVEPOINT {savepoint}")
                        connection.execute(f"RELEASE SAVEPOINT {savepoint}")
                    except sqlite3.DatabaseError:
                        pass
                else:
                    self._rollback_preserving(connection)
                raise

    @contextmanager
    def read(self) -> Iterator[sqlite3.Connection]:
        """Serialize reads with writes on the shared SQLite connection."""

        with self._lock:
            try:
                yield self.require_connection()
            except ManagedWorkError:
                raise
            except (sqlite3.DatabaseError, OSError) as error:
                raise self._database_error(error, context="read") from error

    def execute(self, sql: str, parameters: Sequence[Any] = ()) -> sqlite3.Cursor:
        with self._lock:
            try:
                return self.require_connection().execute(sql, parameters)
            except (sqlite3.DatabaseError, OSError) as error:
                raise self._database_error(error, context="read") from error

    def quick_check(self) -> str:
        row = self.execute("PRAGMA quick_check").fetchone()
        return "missing" if row is None else str(row[0])

    def foreign_key_violations(self) -> int:
        return len(self.execute("PRAGMA foreign_key_check").fetchall())

    def schema_version(self) -> int:
        return int(self.execute("PRAGMA user_version").fetchone()[0])
