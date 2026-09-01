"""Private append-only SQLite journal for durable Fabric operations."""

from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import stat
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Mapping

from ..models import FabricError
from ..security.normalize import binding_digest, canonical_json, normalize_json
from ..security.redaction import redact, scan_for_secrets
from .contracts import (
    MAX_EVENT_PAYLOAD_BYTES,
    MAX_LEDGER_PAGE,
    MAX_PLAN_BYTES,
    ZERO_HASH,
    OperationCheckpoint,
    OperationPlan,
    OperationState,
    OperationStatus,
    operation_error,
)

STORE_SCHEMA_VERSION = 1

_EXPECTED_TABLE_COLUMNS = {
    "operations": (
        "ordinal", "operation_id", "owner_id", "owner_uid", "principal_id", "session_id",
        "provider_id", "action", "resource_kind", "resource_id", "idempotency_digest",
        "request_fingerprint", "plan_digest", "plan_json", "created_at",
    ),
    "operation_events": (
        "ordinal", "event_id", "operation_id", "sequence", "event_type", "checkpoint",
        "status", "payload_json", "previous_hash", "event_hash", "created_at",
    ),
    "consumed_operation_approvals": (
        "approval_id", "operation_id", "binding_digest", "consumed_at",
    ),
}
_EXPECTED_COLUMN_TYPES = {
    "operations": (
        "INTEGER", "TEXT", "TEXT", "INTEGER", "TEXT", "TEXT", "TEXT", "TEXT", "TEXT",
        "TEXT", "TEXT", "TEXT", "TEXT", "TEXT", "TEXT",
    ),
    "operation_events": (
        "INTEGER", "TEXT", "TEXT", "INTEGER", "TEXT", "TEXT", "TEXT", "TEXT", "TEXT", "TEXT", "TEXT",
    ),
    "consumed_operation_approvals": ("TEXT", "TEXT", "TEXT", "TEXT"),
}
_EXPECTED_INDEXES = {
    "operations_resource_idx": ("owner_id", "resource_kind", "resource_id", "ordinal"),
    "operation_events_operation_idx": ("operation_id", "sequence"),
}
_EXPECTED_UNIQUE_SETS = {
    "operations": {("operation_id",), ("owner_id", "idempotency_digest")},
    "operation_events": {("event_id",), ("event_hash",), ("operation_id", "sequence")},
    "consumed_operation_approvals": {("approval_id",), ("operation_id",)},
}
_EXPECTED_TRIGGERS = {
    "operations_no_update": ("operations", "update", "append-only operations"),
    "operations_no_delete": ("operations", "delete", "append-only operations"),
    "operation_events_no_update": ("operation_events", "update", "append-only events"),
    "operation_events_no_delete": ("operation_events", "delete", "append-only events"),
    "approvals_no_update": ("consumed_operation_approvals", "update", "append-only approvals"),
    "approvals_no_delete": ("consumed_operation_approvals", "delete", "append-only approvals"),
}
_APPROVAL_ID = re.compile(r"^approval\.[0-9a-f]{32}$")

class _TransactionContext:
    def __init__(self, store: "OperationStore", label: str) -> None:
        self.store = store
        self.label = label
        self.connection: sqlite3.Connection | None = None

    def __enter__(self) -> sqlite3.Connection:
        self.connection = self.store._connection()
        try:
            self.connection.execute("BEGIN IMMEDIATE")
            self.store._verify_use_boundary(self.connection)
        except BaseException as error:
            cleanup_error = self._rollback_and_verify()
            if cleanup_error is not None:
                if isinstance(cleanup_error, FabricError):
                    raise cleanup_error from error
                raise self.store._storage_error(cleanup_error) from error
            if isinstance(error, FabricError):
                raise
            if isinstance(error, (OSError, sqlite3.Error)):
                raise self.store._storage_error(error) from error
            raise
        return self.connection

    def _rollback_and_verify(self) -> BaseException | None:
        assert self.connection is not None
        try:
            if self.connection.in_transaction:
                self.connection.execute("ROLLBACK")
        except BaseException as error:
            try:
                self.store.close()
            except BaseException:
                pass
            return error
        if self.connection.in_transaction:
            error = sqlite3.OperationalError("rollback left operation transaction open")
            try:
                self.store.close()
            except BaseException:
                pass
            return error
        try:
            self.store._verify_use_boundary(self.connection)
        except BaseException as error:
            try:
                self.store.close()
            except BaseException:
                pass
            return error
        return None

    def __exit__(self, exception_type, exception, traceback) -> bool:
        assert self.connection is not None
        if exception is not None:
            cleanup_error = self._rollback_and_verify()
            if cleanup_error is not None:
                if isinstance(cleanup_error, FabricError):
                    raise cleanup_error from exception
                raise self.store._storage_error(cleanup_error) from exception
            if isinstance(exception, FabricError):
                return False
            if isinstance(exception, (OSError, sqlite3.Error)):
                raise self.store._storage_error(exception) from exception
            return False
        try:
            self.store._verify_use_boundary(self.connection)
            if self.store.durability_probe is not None:
                self.store.durability_probe(self.label)
            self.connection.execute("COMMIT")
            self.store._verify_use_boundary(self.connection)
        except BaseException as error:
            cleanup_error = self._rollback_and_verify()
            if cleanup_error is not None:
                if isinstance(cleanup_error, FabricError):
                    raise cleanup_error from error
                raise self.store._storage_error(cleanup_error) from error
            if isinstance(error, FabricError):
                raise
            if isinstance(error, (OSError, sqlite3.Error)):
                raise self.store._storage_error(error) from error
            raise
        return False

def _utc_now() -> datetime:
    return datetime.now(timezone.utc)

def _iso_time(value: datetime) -> str:
    if not isinstance(value, datetime) or value.tzinfo is None or value.utcoffset() is None:
        raise operation_error("operation.clock-invalid", "Operation storage clock must be timezone-aware.")
    return value.astimezone(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")

def _canonical_time(value: Any, label: str) -> datetime:
    if not isinstance(value, str) or len(value) != 27 or not value.endswith("Z"):
        raise operation_error("operation.ledger-corrupt", f"{label} is not canonical UTC time.")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise operation_error("operation.ledger-corrupt", f"{label} is invalid.") from error
    if parsed.tzinfo is None or parsed.utcoffset() is None or _iso_time(parsed) != value:
        raise operation_error("operation.ledger-corrupt", f"{label} is not canonical UTC time.")
    return parsed

def _bounded_json(value: Any, maximum: int, label: str) -> tuple[Any, str]:
    try:
        normalized = normalize_json(value)
        encoded = canonical_json(normalized)
    except Exception as error:
        if isinstance(error, FabricError):
            raise
        raise operation_error("operation.invalid-json", f"{label} is not deterministic JSON.") from error
    if len(encoded.encode("utf-8")) > maximum:
        raise operation_error("operation.evidence-too-large", f"{label} exceeds its durable size bound.")
    return normalized, encoded

class OperationStore:
    """Append-only plans, approval consumption, and hash-chained evidence.

    The immediate state directory is a mode-0700 same-owner trust boundary. A
    same-UID attacker with arbitrary access to that directory is outside this
    storage boundary, just as it is for the per-user Fabric database. Symlinks,
    non-regular files, inode swaps during open, and hard-linked databases are
    rejected before journal use.
    """

    def __init__(
        self,
        path: Path,
        *,
        clock: Callable[[], datetime] = _utc_now,
        max_operations: int = 4096,
        max_events_per_operation: int = 128,
        busy_timeout_ms: int = 1000,
        durability_probe: Callable[[str], None] | None = None,
    ) -> None:
        self.path = Path(path)
        if not self.path.is_absolute():
            raise operation_error("operation.store-unsafe-path", "Operation database path must be absolute.")
        if isinstance(max_operations, bool) or not 16 <= max_operations <= 65_536:
            raise operation_error("operation.store-capacity", "Operation capacity must be between 16 and 65536.")
        if isinstance(max_events_per_operation, bool) or not 16 <= max_events_per_operation <= 1024:
            raise operation_error("operation.store-capacity", "Per-operation event capacity must be between 16 and 1024.")
        if isinstance(busy_timeout_ms, bool) or not 1 <= busy_timeout_ms <= 30_000:
            raise operation_error("operation.store-timeout", "Storage busy timeout is invalid.")
        self.clock = clock
        self.max_operations = max_operations
        self.max_events_per_operation = max_events_per_operation
        self.busy_timeout_ms = busy_timeout_ms
        self.durability_probe = durability_probe
        self.connection: sqlite3.Connection | None = None
        self._held_descriptor: int | None = None
        self._held_identity: tuple[int, int] | None = None
        self._held_directory_descriptor: int | None = None
        self._directory_identity: tuple[int, int] | None = None
        self._sqlite_descriptor: int | None = None
        self._lock = threading.RLock()

    @staticmethod
    def _matching_descriptors(
        identity: tuple[int, int],
        *,
        exclude: frozenset[int] = frozenset(),
    ) -> frozenset[int]:
        if os.name == "nt":
            return frozenset()
        descriptor_directory = Path("/proc/self/fd")
        if not descriptor_directory.is_dir():
            raise operation_error(
                "operation.store-unsafe-path",
                "Linux descriptor evidence is unavailable for the operation database.",
            )
        try:
            descriptors = tuple(
                int(entry.name)
                for entry in descriptor_directory.iterdir()
                if entry.name.isdigit()
            )
        except OSError as error:
            raise operation_error(
                "operation.store-unsafe-path",
                "Linux descriptors could not be enumerated for the operation database.",
            ) from error
        matches: set[int] = set()
        for descriptor in descriptors:
            if descriptor in exclude:
                continue
            try:
                metadata = os.fstat(descriptor)
            except OSError:
                continue
            if stat.S_ISREG(metadata.st_mode) and (metadata.st_dev, metadata.st_ino) == identity:
                matches.add(descriptor)
        return frozenset(matches)

    def _hold_directory(self, parent: Path) -> tuple[int, tuple[int, int]]:
        try:
            expected = parent.lstat()
        except OSError as error:
            raise operation_error("operation.store-unsafe-path", "Operation state directory cannot be inspected.") from error
        if stat.S_ISLNK(expected.st_mode) or not stat.S_ISDIR(expected.st_mode):
            raise operation_error("operation.store-unsafe-path", "Operation state directory must be a real directory.")
        if hasattr(os, "getuid") and expected.st_uid != os.getuid():
            raise operation_error("operation.store-wrong-owner", "Operation state directory has the wrong owner.")
        identity = (expected.st_dev, expected.st_ino)
        if os.name == "nt":
            return -1, identity
        flags = os.O_RDONLY
        flags |= getattr(os, "O_CLOEXEC", 0)
        flags |= getattr(os, "O_DIRECTORY", 0)
        flags |= getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(parent, flags)
        try:
            held = os.fstat(descriptor)
            if (
                not stat.S_ISDIR(held.st_mode)
                or (held.st_dev, held.st_ino) != identity
                or (hasattr(os, "getuid") and held.st_uid != os.getuid())
            ):
                raise operation_error("operation.store-unsafe-path", "Operation state directory identity changed during open.")
            os.fchmod(descriptor, 0o700)
            return descriptor, identity
        except Exception:
            os.close(descriptor)
            raise

    def _open_held_database(
        self,
        expected: os.stat_result | None,
        directory_descriptor: int,
    ) -> tuple[int, tuple[int, int]]:
        flags = os.O_RDWR | os.O_CREAT
        flags |= getattr(os, "O_CLOEXEC", 0)
        flags |= getattr(os, "O_NOFOLLOW", 0)
        if os.name == "nt":
            descriptor = os.open(self.path, flags, 0o600)
        else:
            descriptor = os.open(self.path.name, flags, 0o600, dir_fd=directory_descriptor)
        try:
            held = os.fstat(descriptor)
            identity = (held.st_dev, held.st_ino)
            if not stat.S_ISREG(held.st_mode) or held.st_nlink != 1:
                raise operation_error("operation.store-unsafe-path", "Held operation database is not one regular inode.")
            if hasattr(os, "getuid") and held.st_uid != os.getuid():
                raise operation_error("operation.store-wrong-owner", "Operation database has the wrong owner.")
            if expected is not None and identity != (expected.st_dev, expected.st_ino):
                raise operation_error("operation.store-unsafe-path", "Operation database identity changed during open.")
            if os.name != "nt":
                os.fchmod(descriptor, 0o600)
            return descriptor, identity
        except Exception:
            os.close(descriptor)
            raise

    def _prove_connected_identity(
        self,
        connection: sqlite3.Connection,
        *,
        held_descriptor: int,
        identity: tuple[int, int],
        existing_matches: frozenset[int],
    ) -> int | None:
        try:
            path = self.path.lstat()
        except OSError as error:
            raise operation_error("operation.store-unsafe-path", "SQLite database path disappeared during open.") from error
        if (
            not stat.S_ISREG(path.st_mode)
            or path.st_nlink != 1
            or (path.st_dev, path.st_ino) != identity
            or (hasattr(os, "getuid") and path.st_uid != os.getuid())
        ):
            raise operation_error("operation.store-unsafe-path", "SQLite opened a changed operation database path.")
        if os.name == "nt":
            sqlite_descriptor = None
        else:
            matches = self._matching_descriptors(identity, exclude=frozenset({held_descriptor}))
            new_matches = matches - existing_matches
            if not existing_matches.issubset(matches) or len(new_matches) != 1:
                raise operation_error(
                    "operation.store-unsafe-path",
                    "SQLite did not open exactly one new descriptor for the held operation database inode.",
                    detail=f"matching={len(matches)} new={len(new_matches)}",
                )
            sqlite_descriptor = next(iter(new_matches))
        rows = list(connection.execute("PRAGMA database_list"))
        if len(rows) != 1 or rows[0]["name"] != "main" or rows[0]["seq"] != 0:
            raise operation_error("operation.store-unsafe-path", "SQLite operation database attachment set is not exact.")
        try:
            connected = Path(rows[0]["file"]).resolve(strict=True)
            expected = self.path.resolve(strict=True)
        except (OSError, RuntimeError) as error:
            raise operation_error("operation.store-unsafe-path", "SQLite database path cannot be resolved.") from error
        if connected != expected:
            raise operation_error("operation.store-unsafe-path", "SQLite opened an unexpected operation database.")
        return sqlite_descriptor

    def open(self) -> None:
        with self._lock:
            if self.connection is not None:
                return
            parent = self.path.parent
            parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            directory_descriptor = -1
            descriptor = -1
            connection: sqlite3.Connection | None = None
            try:
                directory_descriptor, directory_identity = self._hold_directory(parent)
                if os.name != "nt":
                    try:
                        before = os.stat(self.path.name, dir_fd=directory_descriptor, follow_symlinks=False)
                    except FileNotFoundError:
                        before = None
                else:
                    try:
                        before = self.path.lstat()
                    except FileNotFoundError:
                        before = None
                if before is not None and (
                    stat.S_ISLNK(before.st_mode)
                    or not stat.S_ISREG(before.st_mode)
                    or before.st_nlink != 1
                    or (hasattr(os, "getuid") and before.st_uid != os.getuid())
                ):
                    raise operation_error("operation.store-unsafe-path", "Operation database path is unsafe.")
                self._validate_sidecars()
                descriptor, held_identity = self._open_held_database(before, directory_descriptor)
                existing_matches = self._matching_descriptors(
                    held_identity,
                    exclude=frozenset({descriptor}),
                )
                connection = sqlite3.connect(
                    self.path,
                    timeout=self.busy_timeout_ms / 1000,
                    isolation_level=None,
                    check_same_thread=False,
                )
                connection.row_factory = sqlite3.Row
                sqlite_descriptor = self._prove_connected_identity(
                    connection,
                    held_descriptor=descriptor,
                    identity=held_identity,
                    existing_matches=existing_matches,
                )
                version = int(connection.execute("PRAGMA user_version").fetchone()[0])
                tables = {
                    row[0]
                    for row in connection.execute(
                        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
                    )
                }
                if version == 0 and tables:
                    raise operation_error("operation.store-unversioned", "Operation database schema is unversioned.")
                if version not in {0, STORE_SCHEMA_VERSION}:
                    raise operation_error("operation.store-version", "Operation database schema version is unsupported.")
                existing_database = version == STORE_SCHEMA_VERSION
                if existing_database:
                    self._verify_schema(connection)
                check = connection.execute("PRAGMA quick_check").fetchone()
                if check is None or check[0] != "ok":
                    raise operation_error("operation.store-corrupt", "Operation database failed SQLite integrity checks.")
                self.connection = connection
                self._held_descriptor = descriptor
                self._held_identity = held_identity
                self._held_directory_descriptor = None if directory_descriptor < 0 else directory_descriptor
                self._directory_identity = directory_identity
                self._sqlite_descriptor = sqlite_descriptor
                connection = None
                descriptor = -1
                directory_descriptor = -1
                try:
                    if existing_database:
                        self.verify_all()
                    active = self._connection()
                    mode = str(active.execute("PRAGMA journal_mode").fetchone()[0]).lower()
                    if mode != "delete":
                        raise operation_error("operation.store-journal", "Operation database requires DELETE journaling.")
                    active.execute(f"PRAGMA busy_timeout = {self.busy_timeout_ms}")
                    active.execute("PRAGMA trusted_schema = OFF")
                    active.execute("PRAGMA synchronous = FULL")
                    active.execute("PRAGMA foreign_keys = ON")
                    if not existing_database:
                        assigned_mode = str(active.execute("PRAGMA journal_mode = DELETE").fetchone()[0]).lower()
                        if assigned_mode != "delete":
                            raise operation_error("operation.store-journal", "Operation database requires DELETE journaling.")
                        self._create_schema(active)
                        self._verify_schema(active)
                        self.verify_all()
                    self._verify_use_boundary(active)
                except Exception:
                    self.close()
                    raise
            except FabricError:
                if connection is not None:
                    connection.close()
                elif self.connection is not None:
                    self.close()
                raise
            except (OSError, sqlite3.Error) as error:
                if connection is not None:
                    connection.close()
                elif self.connection is not None:
                    self.close()
                raise self._storage_error(error) from error
            finally:
                if descriptor >= 0:
                    os.close(descriptor)
                if directory_descriptor >= 0:
                    os.close(directory_descriptor)

    @staticmethod
    def _initialize(connection: sqlite3.Connection) -> None:
        version = int(connection.execute("PRAGMA user_version").fetchone()[0])
        tables = {
            row[0]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
            )
        }
        if version == 0 and tables:
            raise operation_error("operation.store-unversioned", "Operation database schema is unversioned.")
        if version not in {0, STORE_SCHEMA_VERSION}:
            raise operation_error("operation.store-version", "Operation database schema version is unsupported.")
        if version == STORE_SCHEMA_VERSION:
            OperationStore._verify_schema(connection)
            return
        OperationStore._create_schema(connection)
        OperationStore._verify_schema(connection)

    @staticmethod
    def _create_schema(connection: sqlite3.Connection) -> None:
        connection.executescript(
            """
            BEGIN IMMEDIATE;
            CREATE TABLE operations (
              ordinal INTEGER PRIMARY KEY AUTOINCREMENT,
              operation_id TEXT NOT NULL UNIQUE,
              owner_id TEXT NOT NULL,
              owner_uid INTEGER NOT NULL,
              principal_id TEXT NOT NULL,
              session_id TEXT NOT NULL,
              provider_id TEXT NOT NULL,
              action TEXT NOT NULL,
              resource_kind TEXT NOT NULL,
              resource_id TEXT NOT NULL,
              idempotency_digest TEXT NOT NULL,
              request_fingerprint TEXT NOT NULL,
              plan_digest TEXT NOT NULL,
              plan_json TEXT NOT NULL,
              created_at TEXT NOT NULL,
              UNIQUE(owner_id, idempotency_digest)
            );
            CREATE INDEX operations_resource_idx
              ON operations(owner_id, resource_kind, resource_id, ordinal);
            CREATE TABLE operation_events (
              ordinal INTEGER PRIMARY KEY AUTOINCREMENT,
              event_id TEXT NOT NULL UNIQUE,
              operation_id TEXT NOT NULL REFERENCES operations(operation_id),
              sequence INTEGER NOT NULL,
              event_type TEXT NOT NULL,
              checkpoint TEXT NOT NULL,
              status TEXT NOT NULL,
              payload_json TEXT NOT NULL,
              previous_hash TEXT NOT NULL,
              event_hash TEXT NOT NULL UNIQUE,
              created_at TEXT NOT NULL,
              UNIQUE(operation_id, sequence)
            );
            CREATE INDEX operation_events_operation_idx
              ON operation_events(operation_id, sequence);
            CREATE TABLE consumed_operation_approvals (
              approval_id TEXT PRIMARY KEY,
              operation_id TEXT NOT NULL UNIQUE REFERENCES operations(operation_id),
              binding_digest TEXT NOT NULL,
              consumed_at TEXT NOT NULL
            );
            CREATE TRIGGER operations_no_update BEFORE UPDATE ON operations
              BEGIN SELECT RAISE(ABORT, 'append-only operations'); END;
            CREATE TRIGGER operations_no_delete BEFORE DELETE ON operations
              BEGIN SELECT RAISE(ABORT, 'append-only operations'); END;
            CREATE TRIGGER operation_events_no_update BEFORE UPDATE ON operation_events
              BEGIN SELECT RAISE(ABORT, 'append-only events'); END;
            CREATE TRIGGER operation_events_no_delete BEFORE DELETE ON operation_events
              BEGIN SELECT RAISE(ABORT, 'append-only events'); END;
            CREATE TRIGGER approvals_no_update BEFORE UPDATE ON consumed_operation_approvals
              BEGIN SELECT RAISE(ABORT, 'append-only approvals'); END;
            CREATE TRIGGER approvals_no_delete BEFORE DELETE ON consumed_operation_approvals
              BEGIN SELECT RAISE(ABORT, 'append-only approvals'); END;
            PRAGMA user_version = 1;
            COMMIT;
            """
        )

    @staticmethod
    def _normalize_sql(value: Any) -> str:
        return re.sub(r"\s+", " ", str(value or "").strip().lower()).rstrip(";")

    @staticmethod
    def _golden_connection() -> sqlite3.Connection:
        golden = sqlite3.connect(":memory:", isolation_level=None)
        golden.row_factory = sqlite3.Row
        golden.execute("PRAGMA foreign_keys = ON")
        OperationStore._create_schema(golden)
        return golden

    @staticmethod
    def _verify_schema(connection: sqlite3.Connection) -> None:
        objects = list(
            connection.execute(
                """
                SELECT type, name, tbl_name, sql FROM sqlite_master
                 WHERE name NOT LIKE 'sqlite_%'
                 ORDER BY type, name
                """
            )
        )
        actual_tables = {row["name"] for row in objects if row["type"] == "table"}
        actual_indexes = {row["name"] for row in objects if row["type"] == "index"}
        actual_triggers = {row["name"] for row in objects if row["type"] == "trigger"}
        actual_other = {row["name"] for row in objects if row["type"] not in {"table", "index", "trigger"}}
        if (
            actual_tables != set(_EXPECTED_TABLE_COLUMNS)
            or actual_indexes != set(_EXPECTED_INDEXES)
            or actual_triggers != set(_EXPECTED_TRIGGERS)
            or actual_other
        ):
            raise operation_error("operation.store-schema", "Operation database schema objects are not exact.")
        golden = OperationStore._golden_connection()
        try:
            golden_objects = {
                (row["type"], row["name"]): (
                    row["tbl_name"],
                    OperationStore._normalize_sql(row["sql"]),
                )
                for row in golden.execute(
                    """
                    SELECT type, name, tbl_name, sql FROM sqlite_master
                     WHERE name NOT LIKE 'sqlite_%'
                    """
                )
            }
            actual_object_definitions = {
                (row["type"], row["name"]): (
                    row["tbl_name"],
                    OperationStore._normalize_sql(row["sql"]),
                )
                for row in objects
            }
            if actual_object_definitions != golden_objects:
                raise operation_error("operation.store-schema", "Operation database object SQL differs from the golden schema.")
            actual_table_list = {
                (row["name"], row["type"], row["ncol"], row["wr"], row["strict"])
                for row in connection.execute("PRAGMA table_list")
                if row["name"] in _EXPECTED_TABLE_COLUMNS
            }
            golden_table_list = {
                (row["name"], row["type"], row["ncol"], row["wr"], row["strict"])
                for row in golden.execute("PRAGMA table_list")
                if row["name"] in _EXPECTED_TABLE_COLUMNS
            }
            if actual_table_list != golden_table_list:
                raise operation_error("operation.store-schema", "Operation table flags differ from the golden schema.")
            for table in _EXPECTED_TABLE_COLUMNS:
                actual_xinfo = tuple(
                    (
                        row["cid"], row["name"], row["type"], row["notnull"],
                        row["dflt_value"], row["pk"], row["hidden"],
                    )
                    for row in connection.execute(f'PRAGMA table_xinfo("{table}")')
                )
                golden_xinfo = tuple(
                    (
                        row["cid"], row["name"], row["type"], row["notnull"],
                        row["dflt_value"], row["pk"], row["hidden"],
                    )
                    for row in golden.execute(f'PRAGMA table_xinfo("{table}")')
                )
                if actual_xinfo != golden_xinfo:
                    raise operation_error("operation.store-schema", "Operation hidden/generated columns differ from the golden schema.")
        finally:
            golden.close()
        for table, expected_names in _EXPECTED_TABLE_COLUMNS.items():
            columns = list(connection.execute(f'PRAGMA table_info("{table}")'))
            names = tuple(row["name"] for row in columns)
            types = tuple(str(row["type"]).upper() for row in columns)
            primary = tuple(row["name"] for row in columns if row["pk"])
            expected_primary = ("approval_id",) if table == "consumed_operation_approvals" else ("ordinal",)
            expected_not_null = tuple(
                0 if name in expected_primary else 1
                for name in expected_names
            )
            not_null = tuple(row["notnull"] for row in columns)
            defaults = tuple(row["dflt_value"] for row in columns)
            if (
                names != expected_names
                or types != _EXPECTED_COLUMN_TYPES[table]
                or primary != expected_primary
                or not_null != expected_not_null
                or any(value is not None for value in defaults)
            ):
                raise operation_error("operation.store-schema", "Operation database columns are not exact.")
            unique_sets: set[tuple[str, ...]] = set()
            for index in connection.execute(f'PRAGMA index_list("{table}")'):
                if index["unique"]:
                    unique_sets.add(
                        tuple(
                            column["name"]
                            for column in connection.execute(f'PRAGMA index_info("{index["name"]}")')
                        )
                    )
            if unique_sets != _EXPECTED_UNIQUE_SETS[table]:
                raise operation_error("operation.store-schema", "Operation database uniqueness is not exact.")
        object_rows = {row["name"]: row for row in objects}
        for name, expected_columns in _EXPECTED_INDEXES.items():
            columns = tuple(
                row["name"]
                for row in connection.execute(f'PRAGMA index_info("{name}")')
            )
            table = object_rows[name]["tbl_name"]
            index_row = next(
                (
                    row
                    for row in connection.execute(f'PRAGMA index_list("{table}")')
                    if row["name"] == name
                ),
                None,
            )
            if columns != expected_columns or index_row is None or index_row["unique"] or index_row["partial"]:
                raise operation_error("operation.store-schema", "Operation database indexes are not exact.")
        expected_foreign_keys = {
            "operations": set(),
            "operation_events": {("operations", "operation_id", "operation_id", "NO ACTION", "NO ACTION")},
            "consumed_operation_approvals": {("operations", "operation_id", "operation_id", "NO ACTION", "NO ACTION")},
        }
        for table, expected in expected_foreign_keys.items():
            actual = {
                (row["table"], row["from"], row["to"], row["on_update"], row["on_delete"])
                for row in connection.execute(f'PRAGMA foreign_key_list("{table}")')
            }
            if actual != expected:
                raise operation_error("operation.store-schema", "Operation database foreign keys are not exact.")
        trigger_rows = {row["name"]: row for row in objects if row["type"] == "trigger"}
        for name, (table, action, message) in _EXPECTED_TRIGGERS.items():
            sql = str(trigger_rows[name]["sql"] or "")
            normalized = re.sub(r"\s+", " ", sql.strip().lower()).rstrip(";")
            expected = (
                f"create trigger {name} before {action} on {table} "
                f"begin select raise(abort, '{message}'); end"
            )
            if normalized != expected:
                raise operation_error("operation.store-schema", "Operation append-only triggers are not exact.")
        if list(connection.execute("PRAGMA foreign_key_check")):
            raise operation_error("operation.store-corrupt", "Operation database has broken foreign keys.")

    def _validate_sidecars(self, connection: sqlite3.Connection | None = None) -> None:
        for suffix in ("-journal", "-wal", "-shm"):
            sidecar = Path(f"{self.path}{suffix}")
            try:
                expected = sidecar.lstat()
            except FileNotFoundError:
                continue
            if stat.S_ISLNK(expected.st_mode) or not stat.S_ISREG(expected.st_mode):
                raise operation_error("operation.store-unsafe-path", "Operation database sidecar path is unsafe.")
            flags = os.O_RDONLY
            flags |= getattr(os, "O_CLOEXEC", 0)
            flags |= getattr(os, "O_NOFOLLOW", 0)
            descriptor = -1
            try:
                try:
                    descriptor = os.open(sidecar, flags)
                except FileNotFoundError:
                    continue
                held = os.fstat(descriptor)
                identity = (held.st_dev, held.st_ino)
                if (
                    not stat.S_ISREG(held.st_mode)
                    or held.st_nlink != 1
                    or identity != (expected.st_dev, expected.st_ino)
                    or (hasattr(os, "getuid") and held.st_uid != os.getuid())
                ):
                    raise operation_error("operation.store-unsafe-path", "Operation database sidecar identity is unsafe.")
                if os.name != "nt":
                    os.fchmod(descriptor, 0o600)
                if suffix in {"-wal", "-shm"}:
                    raise operation_error("operation.store-journal", "Unexpected WAL sidecar violates DELETE journaling.")
                if connection is not None and os.name != "nt":
                    matches = self._matching_descriptors(identity, exclude=frozenset({descriptor}))
                    if not matches:
                        raise operation_error(
                            "operation.store-unsafe-path",
                            "SQLite does not hold the verified rollback-journal inode at the transaction boundary.",
                        )
            except FabricError:
                raise
            except OSError as error:
                raise operation_error("operation.store-unsafe-path", "Operation database sidecar could not be held safely.") from error
            finally:
                if descriptor >= 0:
                    os.close(descriptor)

    def _verify_use_boundary(self, connection: sqlite3.Connection) -> None:
        if self._held_descriptor is None or self._held_identity is None or self._directory_identity is None:
            raise operation_error("operation.store-unsafe-path", "Operation database inode lease is missing.")
        try:
            held = os.fstat(self._held_descriptor)
            path = self.path.lstat()
            directory_path = self.path.parent.lstat()
            if os.name == "nt":
                directory_held = directory_path
            else:
                if self._held_directory_descriptor is None:
                    raise operation_error("operation.store-unsafe-path", "Operation directory inode lease is missing.")
                directory_held = os.fstat(self._held_directory_descriptor)
        except FabricError:
            raise
        except OSError as error:
            raise operation_error("operation.store-unsafe-path", "Operation database inode lease cannot be verified.") from error
        identity = (held.st_dev, held.st_ino)
        directory_identity = (directory_held.st_dev, directory_held.st_ino)
        if (
            identity != self._held_identity
            or not stat.S_ISREG(held.st_mode)
            or held.st_nlink != 1
            or not stat.S_ISREG(path.st_mode)
            or path.st_nlink != 1
            or (path.st_dev, path.st_ino) != identity
            or (hasattr(os, "getuid") and (held.st_uid != os.getuid() or path.st_uid != os.getuid()))
        ):
            raise operation_error("operation.store-unsafe-path", "Operation database inode changed during use.")
        if (
            directory_identity != self._directory_identity
            or not stat.S_ISDIR(directory_held.st_mode)
            or not stat.S_ISDIR(directory_path.st_mode)
            or (directory_path.st_dev, directory_path.st_ino) != directory_identity
            or (hasattr(os, "getuid") and (
                directory_held.st_uid != os.getuid()
                or directory_path.st_uid != os.getuid()
            ))
        ):
            raise operation_error("operation.store-unsafe-path", "Operation state directory inode changed during use.")
        if os.name != "nt":
            if self._sqlite_descriptor is None:
                raise operation_error("operation.store-unsafe-path", "SQLite main database descriptor proof is missing.")
            try:
                sqlite_metadata = os.fstat(self._sqlite_descriptor)
            except OSError as error:
                raise operation_error("operation.store-unsafe-path", "SQLite main database descriptor was closed.") from error
            if (
                not stat.S_ISREG(sqlite_metadata.st_mode)
                or (sqlite_metadata.st_dev, sqlite_metadata.st_ino) != identity
            ):
                raise operation_error("operation.store-unsafe-path", "SQLite main database descriptor identity changed.")
        database_rows = list(connection.execute("PRAGMA database_list"))
        main_rows = [row for row in database_rows if row["name"] == "main"]
        temp_rows = [row for row in database_rows if row["name"] == "temp"]
        if (
            len(main_rows) != 1
            or main_rows[0]["seq"] != 0
            or len(temp_rows) > 1
            or any(row["name"] not in {"main", "temp"} for row in database_rows)
            or any(row["file"] for row in temp_rows)
            or connection.execute(
                "SELECT 1 FROM temp.sqlite_master WHERE name NOT LIKE 'sqlite_%' LIMIT 1"
            ).fetchone() is not None
        ):
            raise operation_error("operation.store-unsafe-path", "SQLite operation database attachment set is not exact.")
        try:
            connected = Path(main_rows[0]["file"]).resolve(strict=True)
            expected = self.path.resolve(strict=True)
        except (OSError, RuntimeError) as error:
            raise operation_error("operation.store-unsafe-path", "SQLite database path cannot be resolved.") from error
        if connected != expected:
            raise operation_error("operation.store-unsafe-path", "SQLite opened an unexpected operation database.")
        self._validate_sidecars(connection)

    def close(self) -> None:
        with self._lock:
            connection = self.connection
            database_descriptor = self._held_descriptor
            directory_descriptor = self._held_directory_descriptor
            self.connection = None
            self._held_descriptor = None
            self._held_directory_descriptor = None
            self._held_identity = None
            self._directory_identity = None
            self._sqlite_descriptor = None
            first_error: BaseException | None = None
            if connection is not None:
                try:
                    connection.close()
                except BaseException as error:
                    first_error = error
                    try:
                        connection.close()
                    except BaseException:
                        pass
            retry_descriptors: list[int] = []
            for descriptor in (database_descriptor, directory_descriptor):
                if descriptor is None:
                    continue
                try:
                    os.close(descriptor)
                except BaseException as error:
                    retry_descriptors.append(descriptor)
                    if first_error is None:
                        first_error = error
            for descriptor in retry_descriptors:
                try:
                    os.close(descriptor)
                except BaseException:
                    pass
            if first_error is not None:
                raise first_error

    def _connection(self) -> sqlite3.Connection:
        if self.connection is None:
            raise operation_error("operation.store-closed", "Operation database is not open.")
        self._verify_use_boundary(self.connection)
        return self.connection

    @staticmethod
    def _storage_error(error: BaseException) -> FabricError:
        return operation_error(
            "operation.storage-unavailable",
            "Durable operation storage did not commit; no success is reported.",
            detail=type(error).__name__,
            retryable=True,
            change_state="unknown" if isinstance(error, OSError) else "none",
            recovery_actions=("storage.free-space", "operation.reconcile"),
        )

    def _transaction(self, label: str) -> _TransactionContext:
        return _TransactionContext(self, label)

    @staticmethod
    def _row_plan(row: sqlite3.Row) -> OperationPlan:
        raw = row["plan_json"]
        if not isinstance(raw, str) or len(raw.encode("utf-8")) > MAX_PLAN_BYTES:
            raise operation_error("operation.plan-corrupt", "Durable operation plan size is corrupt.")
        try:
            document = json.loads(raw)
        except (TypeError, ValueError) as error:
            raise operation_error("operation.plan-corrupt", "Durable operation plan JSON is corrupt.") from error
        try:
            normalized = normalize_json(document)
        except Exception as error:
            raise operation_error("operation.plan-corrupt", "Durable operation plan JSON is ambiguous.") from error
        if (
            not isinstance(normalized, Mapping)
            or canonical_json(normalized) != raw
            or scan_for_secrets(normalized)
            or binding_digest(normalized) != row["plan_digest"]
        ):
            raise operation_error("operation.plan-corrupt", "Durable operation plan hash is corrupt.")
        try:
            plan = OperationPlan.from_dict(normalized)
        except Exception as error:
            if isinstance(error, FabricError) and error.code == "operation.plan-corrupt":
                raise
            raise operation_error("operation.plan-corrupt", "Durable operation plan fields are corrupt.") from error
        scalar_values = {
            "operation_id": plan.operation_id,
            "owner_id": plan.owner_id,
            "owner_uid": plan.owner_uid,
            "principal_id": plan.principal_id,
            "session_id": plan.session_id,
            "provider_id": plan.provider.provider_id,
            "action": plan.action,
            "resource_kind": plan.resource.kind,
            "resource_id": plan.resource.resource_id,
            "idempotency_digest": plan.idempotency_digest,
            "request_fingerprint": plan.request_fingerprint,
            "created_at": plan.created_at,
        }
        if any(row[name] != expected for name, expected in scalar_values.items()):
            raise operation_error("operation.plan-corrupt", "Operation scalar index columns disagree with the immutable plan.")
        return plan

    @staticmethod
    def _event_hash(
        operation_id: str,
        sequence: int,
        event_type: str,
        checkpoint: str,
        status: str,
        payload: Any,
        previous_hash: str,
        created_at: str,
    ) -> str:
        return hashlib.sha256(
            canonical_json(
                {
                    "operationId": operation_id,
                    "sequence": sequence,
                    "eventType": event_type,
                    "checkpoint": checkpoint,
                    "status": status,
                    "payload": payload,
                    "previousHash": previous_hash,
                    "createdAt": created_at,
                }
            ).encode("utf-8")
        ).hexdigest()

    @staticmethod
    def _validate_transition(
        previous: sqlite3.Row | None,
        event_type: str,
        checkpoint: str,
        status: str,
    ) -> None:
        current_status = OperationStatus(status)
        current_checkpoint = OperationCheckpoint(checkpoint)
        if previous is None:
            if (
                event_type != "preflight-frozen"
                or current_status is not OperationStatus.AWAITING_APPROVAL
                or current_checkpoint is not OperationCheckpoint.PREFLIGHT
            ):
                raise operation_error("operation.ledger-corrupt", "Operation ledger does not start at preflight.")
            return
        previous_status = OperationStatus(previous["status"])
        previous_checkpoint = OperationCheckpoint(previous["checkpoint"])
        if previous_status.terminal:
            raise operation_error("operation.ledger-corrupt", "Terminal operation state was reopened.")
        if event_type in {"cancellation-requested", "checkpoint-observed"}:
            allowed = current_status is previous_status and current_checkpoint is previous_checkpoint
        elif event_type == "approval-checked":
            allowed = (
                previous_status is OperationStatus.AWAITING_APPROVAL
                and previous["event_type"] in {"preflight-frozen", "approval-checked", "checkpoint-observed"}
                and current_status is OperationStatus.AWAITING_APPROVAL
                and current_checkpoint is OperationCheckpoint.APPROVAL
            )
        elif event_type == "authorized":
            allowed = (
                previous["event_type"] == "approval-checked"
                and current_status is OperationStatus.AUTHORIZED
                and current_checkpoint is OperationCheckpoint.AUTHORIZED
            )
        elif event_type == "apply-started":
            allowed = (
                previous_status is OperationStatus.AUTHORIZED
                and current_status is OperationStatus.RUNNING
                and current_checkpoint is OperationCheckpoint.APPLYING
            )
        elif event_type == "apply-finished":
            allowed = (
                previous_status is OperationStatus.RUNNING
                and previous_checkpoint is OperationCheckpoint.APPLYING
                and current_status is OperationStatus.RUNNING
                and current_checkpoint is OperationCheckpoint.APPLIED
            )
        elif event_type == "validation-started":
            allowed = (
                previous_status is OperationStatus.RUNNING
                and previous_checkpoint is OperationCheckpoint.APPLIED
                and current_status is OperationStatus.RUNNING
                and current_checkpoint is OperationCheckpoint.VALIDATING
            )
        elif event_type == "postcondition-validated":
            allowed = (
                previous_status is OperationStatus.RUNNING
                and previous_checkpoint is OperationCheckpoint.VALIDATING
                and current_status is OperationStatus.SUCCEEDED
                and current_checkpoint is OperationCheckpoint.FINISHED
            )
        elif event_type == "apply-failed":
            allowed = (
                previous_status is OperationStatus.RUNNING
                and previous_checkpoint is OperationCheckpoint.APPLYING
                and current_status is OperationStatus.FAILED
                and current_checkpoint is OperationCheckpoint.FINISHED
            )
        elif event_type == "reconciliation-started":
            allowed = (
                previous_status in {OperationStatus.RUNNING, OperationStatus.INTERRUPTED}
                and current_status is OperationStatus.RECONCILING
                and current_checkpoint is OperationCheckpoint.RECONCILING
            )
        elif event_type in {"reconciliation-failed", "reconciled-diverged"}:
            allowed = (
                previous_status is OperationStatus.RECONCILING
                and current_status is OperationStatus.FAILED
                and current_checkpoint is OperationCheckpoint.FINISHED
            )
        elif event_type == "reconciled-before-state":
            allowed = (
                previous_status is OperationStatus.RECONCILING
                and current_status in {OperationStatus.FAILED, OperationStatus.CANCELLED}
                and current_checkpoint is OperationCheckpoint.FINISHED
            )
        elif event_type == "reconciled-desired-state":
            allowed = (
                previous_status is OperationStatus.RECONCILING
                and current_status is OperationStatus.SUCCEEDED
                and current_checkpoint is OperationCheckpoint.FINISHED
            )
        elif event_type == "rollback-started":
            allowed = (
                previous_status in {OperationStatus.RUNNING, OperationStatus.RECONCILING}
                and current_status is OperationStatus.ROLLING_BACK
                and current_checkpoint is OperationCheckpoint.ROLLING_BACK
            )
        elif event_type == "rollback-failed":
            allowed = (
                previous_status is OperationStatus.ROLLING_BACK
                and current_status is OperationStatus.FAILED
                and current_checkpoint is OperationCheckpoint.FINISHED
            )
        elif event_type == "rollback-validated":
            allowed = (
                previous_status is OperationStatus.ROLLING_BACK
                and current_status in {OperationStatus.FAILED, OperationStatus.CANCELLED}
                and current_checkpoint is OperationCheckpoint.FINISHED
            )
        elif event_type in {"rollback-superseded", "reconciliation-superseded"}:
            allowed = (
                previous_status in {
                    OperationStatus.RUNNING,
                    OperationStatus.INTERRUPTED,
                    OperationStatus.RECONCILING,
                }
                and current_status is OperationStatus.SUPERSEDED
                and current_checkpoint is OperationCheckpoint.FINISHED
            )
        elif event_type in {"startup-interrupted", "runtime-interrupted"}:
            allowed = (
                previous_status in {
                    OperationStatus.AUTHORIZED,
                    OperationStatus.RUNNING,
                    OperationStatus.RECONCILING,
                    OperationStatus.ROLLING_BACK,
                }
                and current_status is OperationStatus.INTERRUPTED
                and current_checkpoint is previous_checkpoint
            )
        elif event_type in {
            "cancelled-before-authorization",
            "cancelled-before-apply",
            "cancelled-during-apply",
        }:
            allowed = (
                previous_status in {
                    OperationStatus.AWAITING_APPROVAL,
                    OperationStatus.AUTHORIZED,
                    OperationStatus.RUNNING,
                }
                and current_status is OperationStatus.CANCELLED
                and current_checkpoint is OperationCheckpoint.FINISHED
            )
        else:
            allowed = False
        if not allowed:
            raise operation_error(
                "operation.ledger-corrupt",
                "Operation event violates the closed lifecycle transition table.",
                detail=event_type[:160],
            )

    def _verified_events(self, connection: sqlite3.Connection, operation_id: str) -> list[sqlite3.Row]:
        rows = list(
            connection.execute(
                "SELECT * FROM operation_events WHERE operation_id=? ORDER BY sequence LIMIT ?",
                (operation_id, self.max_events_per_operation + 1),
            )
        )
        if not rows:
            raise operation_error("operation.ledger-corrupt", "Operation has no durable preflight event.")
        if len(rows) > self.max_events_per_operation:
            raise operation_error("operation.ledger-corrupt", "Operation event count exceeds the configured bound.")
        previous = ZERO_HASH
        previous_row: sqlite3.Row | None = None
        for expected_sequence, row in enumerate(rows, 1):
            raw_payload = row["payload_json"]
            if not isinstance(raw_payload, str) or len(raw_payload.encode("utf-8")) > MAX_EVENT_PAYLOAD_BYTES:
                raise operation_error("operation.ledger-corrupt", "Operation evidence size is corrupt.")
            try:
                payload = json.loads(raw_payload)
                OperationStatus(row["status"])
                OperationCheckpoint(row["checkpoint"])
            except (TypeError, ValueError) as error:
                raise operation_error("operation.ledger-corrupt", "Operation evidence values are corrupt.") from error
            try:
                normalized_payload = normalize_json(payload)
            except Exception as error:
                raise operation_error("operation.ledger-corrupt", "Operation evidence JSON is ambiguous.") from error
            if (
                not isinstance(normalized_payload, Mapping)
                or canonical_json(normalized_payload) != raw_payload
                or redact(normalized_payload) != normalized_payload
            ):
                raise operation_error("operation.ledger-corrupt", "Operation evidence JSON is not canonical redacted data.")
            payload = normalized_payload
            _canonical_time(row["created_at"], "Operation event time")
            try:
                canonical_event_id = str(uuid.UUID(row["event_id"]))
            except (AttributeError, TypeError, ValueError) as error:
                raise operation_error("operation.ledger-corrupt", "Operation event identity is invalid.") from error
            if canonical_event_id != row["event_id"]:
                raise operation_error("operation.ledger-corrupt", "Operation event identity is non-canonical.")
            self._validate_transition(
                previous_row,
                row["event_type"],
                row["checkpoint"],
                row["status"],
            )
            expected_hash = self._event_hash(
                operation_id,
                expected_sequence,
                row["event_type"],
                row["checkpoint"],
                row["status"],
                payload,
                previous,
                row["created_at"],
            )
            if (
                row["sequence"] != expected_sequence
                or row["previous_hash"] != previous
                or row["event_hash"] != expected_hash
            ):
                raise operation_error("operation.ledger-corrupt", "Operation evidence hash chain is corrupt.")
            previous = expected_hash
            previous_row = row
        return rows

    def verify_all(self) -> int:
        with self._lock:
            connection = self._connection()
            operation_count = int(connection.execute("SELECT COUNT(*) FROM operations").fetchone()[0])
            event_count = int(connection.execute("SELECT COUNT(*) FROM operation_events").fetchone()[0])
            approval_count = int(connection.execute("SELECT COUNT(*) FROM consumed_operation_approvals").fetchone()[0])
            if (
                operation_count > self.max_operations
                or event_count > self.max_operations * self.max_events_per_operation
                or approval_count > operation_count
            ):
                raise operation_error("operation.store-corrupt", "Operation database row counts exceed configured bounds.")
            rows = list(
                connection.execute(
                    "SELECT * FROM operations ORDER BY ordinal LIMIT ?",
                    (self.max_operations + 1,),
                )
            )
            approvals = {
                row["operation_id"]: row
                for row in connection.execute(
                    "SELECT * FROM consumed_operation_approvals ORDER BY rowid LIMIT ?",
                    (self.max_operations + 1,),
                )
            }
            if len(approvals) != approval_count:
                raise operation_error("operation.store-corrupt", "Consumed approval identities are duplicated or unbounded.")
            for row in rows:
                plan = self._row_plan(row)
                events = self._verified_events(connection, row["operation_id"])
                authorized = [event for event in events if event["event_type"] == "authorized"]
                checked = [event for event in events if event["event_type"] == "approval-checked"]
                consumed = approvals.get(plan.operation_id)
                if consumed is None:
                    if authorized:
                        raise operation_error("operation.ledger-corrupt", "Authorized event lacks consumed approval evidence.")
                    continue
                if (
                    not isinstance(consumed["approval_id"], str)
                    or not _APPROVAL_ID.fullmatch(consumed["approval_id"])
                    or consumed["binding_digest"] != plan.binding_digest
                    or len(authorized) != 1
                    or len(checked) < 1
                ):
                    raise operation_error("operation.ledger-corrupt", "Consumed approval binding is corrupt.")
                try:
                    authorized_payload = json.loads(authorized[0]["payload_json"])
                    checked_payload = json.loads(checked[-1]["payload_json"])
                except (AttributeError, TypeError, ValueError) as error:
                    raise operation_error("operation.ledger-corrupt", "Consumed approval evidence is malformed.") from error
                consumed_at = _canonical_time(consumed["consumed_at"], "Approval consumption time")
                checked_at = _canonical_time(checked[-1]["created_at"], "Approval check event time")
                authorized_at = _canonical_time(authorized[0]["created_at"], "Authorization event time")
                if (
                    not isinstance(authorized_payload, Mapping)
                    or not isinstance(checked_payload, Mapping)
                    or set(authorized_payload) != {"approvalId"}
                    or set(checked_payload) != {"approvalId"}
                    or authorized[0]["checkpoint"] != OperationCheckpoint.AUTHORIZED.value
                    or authorized[0]["status"] != OperationStatus.AUTHORIZED.value
                    or authorized_payload.get("approvalId") != consumed["approval_id"]
                    or checked_payload.get("approvalId") != consumed["approval_id"]
                    or checked[-1]["sequence"] >= authorized[0]["sequence"]
                    or not checked_at <= consumed_at <= authorized_at
                ):
                    raise operation_error("operation.ledger-corrupt", "Consumed approval event relation is corrupt.")
            return len(rows)

    def _append_in_transaction(
        self,
        connection: sqlite3.Connection,
        operation_id: str,
        event_type: str,
        checkpoint: OperationCheckpoint,
        status: OperationStatus,
        payload: Mapping[str, Any],
    ) -> None:
        safe_payload, payload_json = _bounded_json(
            redact(dict(payload)),
            MAX_EVENT_PAYLOAD_BYTES,
            "Operation evidence",
        )
        rows = self._verified_events(connection, operation_id) if connection.execute(
            "SELECT 1 FROM operation_events WHERE operation_id=? LIMIT 1", (operation_id,)
        ).fetchone() else []
        if len(rows) >= self.max_events_per_operation:
            raise operation_error(
                "operation.ledger-capacity",
                "Operation evidence capacity is exhausted; mutation is stopped.",
                recovery_actions=("operation.export-ledger",),
            )
        sequence = len(rows) + 1
        previous = rows[-1]["event_hash"] if rows else ZERO_HASH
        self._validate_transition(
            rows[-1] if rows else None,
            event_type,
            checkpoint.value,
            status.value,
        )
        created_at = _iso_time(self.clock())
        event_hash = self._event_hash(
            operation_id,
            sequence,
            event_type,
            checkpoint.value,
            status.value,
            safe_payload,
            previous,
            created_at,
        )
        connection.execute(
            """
            INSERT INTO operation_events(
              event_id, operation_id, sequence, event_type, checkpoint, status,
              payload_json, previous_hash, event_hash, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                str(uuid.uuid4()), operation_id, sequence, event_type,
                checkpoint.value, status.value, payload_json, previous, event_hash, created_at,
            ),
        )

    def create_plan(self, plan: OperationPlan, request_fingerprint: str) -> tuple[OperationState, bool]:
        document, plan_json = _bounded_json(plan.as_dict(), MAX_PLAN_BYTES, "Operation plan")
        plan_digest = binding_digest(document)
        with self._lock:
            with self._transaction("create-plan") as connection:
                existing = connection.execute(
                    "SELECT * FROM operations WHERE owner_id=? AND idempotency_digest=?",
                    (plan.owner_id, plan.idempotency_digest),
                ).fetchone()
                if existing is not None:
                    if existing["request_fingerprint"] != request_fingerprint:
                        raise operation_error(
                            "operation.idempotency-conflict",
                            "Idempotency key was already bound to a different exact request.",
                        )
                    operation_id = existing["operation_id"]
                    replay = True
                else:
                    count = int(connection.execute("SELECT COUNT(*) FROM operations").fetchone()[0])
                    if count >= self.max_operations:
                        raise operation_error(
                            "operation.store-capacity",
                            "Durable operation capacity is exhausted; no plan was admitted.",
                            recovery_actions=("operation.export-ledger",),
                        )
                    latest = connection.execute(
                        """
                        SELECT e.status
                          FROM operations o
                          JOIN operation_events e ON e.operation_id=o.operation_id
                         WHERE o.owner_id=? AND o.resource_kind=? AND o.resource_id=?
                           AND e.sequence=(
                             SELECT MAX(e2.sequence) FROM operation_events e2
                              WHERE e2.operation_id=o.operation_id
                           )
                         ORDER BY o.ordinal DESC LIMIT 1
                        """,
                        (plan.owner_id, plan.resource.kind, plan.resource.resource_id),
                    ).fetchone()
                    if latest is not None and not OperationStatus(latest["status"]).terminal:
                        raise operation_error(
                            "operation.resource-busy",
                            "Another durable operation already owns this exact resource.",
                            retryable=True,
                        )
                    connection.execute(
                        """
                        INSERT INTO operations(
                          operation_id, owner_id, owner_uid, principal_id, session_id,
                          provider_id, action, resource_kind, resource_id, idempotency_digest,
                          request_fingerprint, plan_digest, plan_json, created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            plan.operation_id, plan.owner_id, plan.owner_uid, plan.principal_id,
                            plan.session_id, plan.provider.provider_id, plan.action,
                            plan.resource.kind, plan.resource.resource_id, plan.idempotency_digest,
                            request_fingerprint, plan_digest, plan_json, plan.created_at,
                        ),
                    )
                    self._append_in_transaction(
                        connection,
                        plan.operation_id,
                        "preflight-frozen",
                        OperationCheckpoint.PREFLIGHT,
                        OperationStatus.AWAITING_APPROVAL,
                        {"bindingDigest": plan.binding_digest},
                    )
                    operation_id = plan.operation_id
                    replay = False
            return self.get(operation_id), replay

    def append(
        self,
        operation_id: str,
        event_type: str,
        checkpoint: OperationCheckpoint,
        status: OperationStatus,
        payload: Mapping[str, Any] | None = None,
        *,
        consume_approval_id: str | None = None,
        approval_binding: str | None = None,
    ) -> OperationState:
        with self._lock:
            with self._transaction(f"append-{event_type}") as connection:
                if connection.execute("SELECT 1 FROM operations WHERE operation_id=?", (operation_id,)).fetchone() is None:
                    raise operation_error("operation.unknown", "Durable operation does not exist.")
                existing_events = self._verified_events(connection, operation_id)
                if OperationStatus(existing_events[-1]["status"]).terminal:
                    raise operation_error(
                        "operation.terminal",
                        "Append-only terminal operation state cannot be reopened or overwritten.",
                    )
                if consume_approval_id is not None:
                    if approval_binding is None:
                        raise operation_error("operation.approval-invalid", "Approval binding is missing.")
                    try:
                        connection.execute(
                            "INSERT INTO consumed_operation_approvals VALUES (?, ?, ?, ?)",
                            (consume_approval_id, operation_id, approval_binding, _iso_time(self.clock())),
                        )
                    except sqlite3.IntegrityError as error:
                        raise operation_error("operation.approval-replayed", "Approval was already durably consumed.") from error
                self._append_in_transaction(
                    connection,
                    operation_id,
                    event_type,
                    checkpoint,
                    status,
                    payload or {},
                )
            return self.get(operation_id)

    def get(self, operation_id: str) -> OperationState:
        with self._lock:
            connection = self._connection()
            row = connection.execute("SELECT * FROM operations WHERE operation_id=?", (operation_id,)).fetchone()
            if row is None:
                raise operation_error("operation.unknown", "Durable operation does not exist.")
            plan = self._row_plan(row)
            events = self._verified_events(connection, operation_id)
            last = events[-1]
            try:
                payload = json.loads(last["payload_json"])
                status = OperationStatus(last["status"])
                checkpoint = OperationCheckpoint(last["checkpoint"])
            except (TypeError, ValueError) as error:
                raise operation_error("operation.ledger-corrupt", "Operation projection values are corrupt.") from error
            cancellation = any(event["event_type"] == "cancellation-requested" for event in events)
            return OperationState(
                plan=plan,
                status=status,
                checkpoint=checkpoint,
                cancellation_requested=cancellation,
                event_count=len(events),
                last_sequence=last["sequence"],
                result=payload.get("result") if isinstance(payload, Mapping) else None,
                error=payload.get("error") if isinstance(payload, Mapping) else None,
            )

    def is_latest_resource_intent(self, operation_id: str) -> bool:
        with self._lock:
            connection = self._connection()
            row = connection.execute("SELECT * FROM operations WHERE operation_id=?", (operation_id,)).fetchone()
            if row is None:
                raise operation_error("operation.unknown", "Durable operation does not exist.")
            latest = connection.execute(
                """
                SELECT operation_id FROM operations
                 WHERE owner_id=? AND resource_kind=? AND resource_id=?
                 ORDER BY ordinal DESC LIMIT 1
                """,
                (row["owner_id"], row["resource_kind"], row["resource_id"]),
            ).fetchone()
            return latest is not None and latest["operation_id"] == operation_id

    def request_cancel(self, operation_id: str) -> OperationState:
        with self._lock:
            with self._transaction("request-cancel") as connection:
                if connection.execute("SELECT 1 FROM operations WHERE operation_id=?", (operation_id,)).fetchone() is None:
                    raise operation_error("operation.unknown", "Durable operation does not exist.")
                events = self._verified_events(connection, operation_id)
                status = OperationStatus(events[-1]["status"])
                checkpoint = OperationCheckpoint(events[-1]["checkpoint"])
                already_requested = any(event["event_type"] == "cancellation-requested" for event in events)
                if not status.terminal and not already_requested:
                    self._append_in_transaction(
                        connection,
                        operation_id,
                        "cancellation-requested",
                        checkpoint,
                        status,
                        {"requested": True},
                    )
            return self.get(operation_id)

    def recover_startup(self) -> list[str]:
        interrupted: list[str] = []
        with self._lock:
            rows = list(
                self._connection().execute(
                    "SELECT operation_id FROM operations ORDER BY ordinal LIMIT ?",
                    (self.max_operations + 1,),
                )
            )
            if len(rows) > self.max_operations:
                raise operation_error("operation.store-corrupt", "Operation database row count exceeds the configured bound.")
        for row in rows:
            state = self.get(row["operation_id"])
            if state.status in {
                OperationStatus.AUTHORIZED,
                OperationStatus.RUNNING,
                OperationStatus.RECONCILING,
                OperationStatus.ROLLING_BACK,
            }:
                self.append(
                    state.plan.operation_id,
                    "startup-interrupted",
                    state.checkpoint,
                    OperationStatus.INTERRUPTED,
                    {"requiresReconciliation": True},
                )
                interrupted.append(state.plan.operation_id)
        return interrupted

    def ledger(self, operation_id: str, *, after_sequence: int = 0, limit: int = 32) -> dict[str, Any]:
        if isinstance(after_sequence, bool) or not isinstance(after_sequence, int) or after_sequence < 0:
            raise operation_error("operation.ledger-query", "Ledger sequence is invalid.")
        if isinstance(limit, bool) or not isinstance(limit, int) or not 1 <= limit <= MAX_LEDGER_PAGE:
            raise operation_error("operation.ledger-query", "Ledger page limit is invalid.")
        with self._lock:
            events = self._verified_events(self._connection(), operation_id)
            selected = [event for event in events if event["sequence"] > after_sequence][:limit]
            entries = []
            for event in selected:
                entries.append(
                    {
                        "sequence": event["sequence"],
                        "eventType": event["event_type"],
                        "checkpoint": event["checkpoint"],
                        "status": event["status"],
                        "payload": json.loads(event["payload_json"]),
                        "previousHash": event["previous_hash"],
                        "eventHash": event["event_hash"],
                        "createdAt": event["created_at"],
                    }
                )
            return {
                "schemaVersion": "v0",
                "operationId": operation_id,
                "entries": entries,
                "nextSequence": entries[-1]["sequence"] if entries else after_sequence,
                "hasMore": any(event["sequence"] > (entries[-1]["sequence"] if entries else after_sequence) for event in events),
                "headHash": events[-1]["event_hash"],
                "totalEntries": len(events),
            }
