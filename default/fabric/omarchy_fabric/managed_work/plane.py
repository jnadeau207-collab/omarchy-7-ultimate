from __future__ import annotations

import json
import re
import time
import uuid
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .errors import ManagedWorkError
from .scheduler import first_due, normalize_policy, normalize_trigger, reconcile_due
from .store import CURRENT_SCHEMA, ManagedWorkStore
from .types import Actor, CapacityLimits
from .validation import (
    bounded_text,
    canonical_json,
    closed_object,
    decode_cursor,
    decode_ordered_cursor,
    encode_cursor,
    encode_ordered_cursor,
    enum_value,
    fingerprint,
    finite_number,
    integer,
    normalize_json,
    opaque_id,
    redact_context,
    reject_secret_fields,
    require_context_source,
    sha256_id,
    stable_id,
    timestamp,
)


@dataclass(frozen=True, slots=True)
class NormalizedQuery:
    view: str
    limit: int
    cursor: str | None
    entity_type: str | None
    entity_id: str | None

TASK_TRANSITIONS: dict[str, frozenset[str]] = {
    "draft": frozenset({"awaiting-approval", "queued", "cancelled"}),
    "awaiting-approval": frozenset({"queued", "cancelled"}),
    "queued": frozenset({"cancelled", "failed", "running"}),
    "running": frozenset({"waiting", "retrying", "succeeded", "failed", "cancelled", "interrupted"}),
    "waiting": frozenset({"queued", "cancelled", "interrupted"}),
    "retrying": frozenset({"queued", "failed", "cancelled", "interrupted"}),
    "succeeded": frozenset(),
    "failed": frozenset({"retrying"}),
    "cancelled": frozenset(),
    "interrupted": frozenset({"retrying", "failed", "cancelled"}),
}
TERMINAL_TASK_STATES = frozenset({"succeeded", "failed", "cancelled"})
ACTIVE_TASK_STATES = frozenset(TASK_TRANSITIONS) - TERMINAL_TASK_STATES
SANDBOX_CAPABILITIES = frozenset({"system.info.read"})
EXECUTION_AVAILABLE_CODE = "managed-execution.bubblewrap"
EXECUTION_UNAVAILABLE_CODE = "sandbox.unavailable"
RUN_TRANSITIONS: dict[str, frozenset[str]] = {
    "queued": frozenset({"failed", "cancelled", "running"}),
    "running": frozenset({"waiting", "retrying", "succeeded", "failed", "cancelled", "interrupted"}),
    "waiting": frozenset({"running", "cancelled", "interrupted"}),
    "retrying": frozenset({"queued", "failed", "cancelled", "interrupted"}),
    "succeeded": frozenset(),
    "failed": frozenset({"retrying"}),
    "cancelled": frozenset(),
    "interrupted": frozenset({"retrying", "failed", "cancelled"}),
}
OPERATION_STATES = frozenset(
    {
        "proposed",
        "awaiting-consent",
        "awaiting-authentication",
        "queued",
        "running",
        "validating",
        "awaiting-keep",
        "waiting-restart",
        "waiting-reboot",
        "rolling-back",
        "rolled-back",
        "rollback-failed",
        "succeeded",
        "failed",
        "cancelled",
        "interrupted",
        "reconciling",
        "needs-attention",
        "undoing",
        "undone",
        "undo-failed",
        "recovering",
        "recovered",
        "recovery-failed",
    }
)
MAX_QUERY_RESPONSE_BYTES = 56 * 1024
MAX_DURABLE_OWNERS = 16
_MEDIA_TYPE_RE = re.compile(
    r"^[a-z0-9][a-z0-9!#$&^_.+-]{0,126}/[a-z0-9][a-z0-9!#$&^_.+-]{0,126}$"
)
_PROVIDER_VERSION_RE = re.compile(r"^v[0-9]+(?:\.[0-9]+){0,2}$")


def _new_id(prefix: str) -> str:
    return f"{prefix}.{uuid.uuid4()}"


class ManagedWorkPlane:
    """A hermetic storage/query authority with no execution authority."""

    QUERY_VIEWS = frozenset(
        {
            "agent.overview",
            "agent.tasks",
            "agent.approvals",
            "agent.automations",
            "agent.activity",
            "agent.history",
            "agent.context",
            "agent.permissions",
            "agent.usage",
            "agent.providers",
            "agent.artifacts",
            "agent.troubleshooting",
        }
    )

    def __init__(
        self,
        database_path: Path,
        *,
        capacities: CapacityLimits | None = None,
        maximum_database_bytes: int | None = None,
    ) -> None:
        self.store = (
            ManagedWorkStore(database_path)
            if maximum_database_bytes is None
            else ManagedWorkStore(database_path, maximum_database_bytes=maximum_database_bytes)
        )
        self.capacities = capacities or CapacityLimits()

    def open(self, *, database_lease_descriptor: int | None = None) -> "ManagedWorkPlane":
        self.store.open(database_lease_descriptor=database_lease_descriptor)
        previous_recoveries = self.store.restart_recoveries
        try:
            self._validate_startup_query_liveness()
            with self.store.transaction():
                recovery_count = self.store.recover_interrupted()
                self._validate_startup_query_liveness()
            self.store.restart_recoveries = recovery_count
        except ManagedWorkError as error:
            self.store.restart_recoveries = previous_recoveries
            self.store.close()
            if error.code.startswith("managed-work.database"):
                raise
            raise ManagedWorkError(
                "managed-work.database-corrupt",
                "Managed work refused durable state that cannot produce bounded closed query items.",
                detail=error.code,
                recovery_actions=("managed-work.restore-database",),
            ) from error
        except (json.JSONDecodeError, KeyError, TypeError, ValueError, OverflowError) as error:
            self.store.restart_recoveries = previous_recoveries
            self.store.close()
            raise ManagedWorkError(
                "managed-work.database-corrupt",
                "Managed work refused durable state that cannot produce bounded closed query items.",
                detail=type(error).__name__,
                recovery_actions=("managed-work.restore-database",),
            ) from error
        return self

    def _validate_startup_query_liveness(self) -> None:
        connection = self.store.require_connection()
        principal_ids: set[str] = set()
        owner_sessions: dict[str, str] = {}

        def rows(table: str, maximum: int) -> list[Any]:
            total_limit = maximum * MAX_DURABLE_OWNERS
            result = connection.execute(
                f"SELECT * FROM {table} ORDER BY row_id LIMIT ?",
                (total_limit + 1,),
            ).fetchall()
            if len(result) > total_limit:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused a table that exceeds its declared durable capacity.",
                    detail=table,
                    recovery_actions=("managed-work.restore-database",),
                )
            counts: dict[str, int] = {}
            for row in result:
                principal_id = str(row["principal_id"])
                principal_ids.add(principal_id)
                counts[principal_id] = counts.get(principal_id, 0) + 1
                if counts[principal_id] > maximum:
                    raise ManagedWorkError(
                        "managed-work.database-corrupt",
                        "Managed work refused an owner table that exceeds its declared durable capacity.",
                        detail=table,
                        recovery_actions=("managed-work.restore-database",),
                    )
                if "owner_session_id" in row.keys():
                    owner_sessions.setdefault(principal_id, str(row["owner_session_id"]))
            return result

        contexts = rows("contexts", self.capacities.total_contexts)
        tasks = rows("tasks", self.capacities.total_tasks)
        runs = rows("runs", self.capacities.total_runs)
        automations = rows("automations", self.capacities.total_automations)
        rows("automation_firings", self.capacities.event_firings)
        approvals = rows("approval_projections", self.capacities.approval_projections)
        operations = rows("operation_links", self.capacities.operation_links)
        permissions = rows("permission_projections", self.capacities.permission_projections)
        usage = rows("usage_records", self.capacities.usage_records)
        artifacts = rows("artifacts", self.capacities.artifacts)
        events = rows("managed_events", self.capacities.history_events)
        providers = rows("provider_projections", self.capacities.provider_projections)

        def require_subset_capacity(
            table: str,
            values: Sequence[Any],
            maximum: int,
            predicate: Any,
        ) -> None:
            counts: dict[str, int] = {}
            for row in values:
                if not predicate(row):
                    continue
                principal_id = str(row["principal_id"])
                counts[principal_id] = counts.get(principal_id, 0) + 1
                if counts[principal_id] > maximum:
                    raise ManagedWorkError(
                        "managed-work.database-corrupt",
                        "Managed work refused an owner table whose active rows exceed declared capacity.",
                        detail=table,
                        recovery_actions=("managed-work.restore-database",),
                    )

        validation_time = time.time()
        require_subset_capacity(
            "contexts.live",
            contexts,
            self.capacities.live_contexts,
            lambda row: row["revoked_at"] is None and float(row["expires_at"]) > validation_time,
        )
        require_subset_capacity(
            "tasks.active",
            tasks,
            self.capacities.active_tasks,
            lambda row: row["state"] not in TERMINAL_TASK_STATES,
        )
        require_subset_capacity(
            "automations.active",
            automations,
            self.capacities.active_automations,
            lambda row: row["state"] != "disabled",
        )
        idempotency_limit = self.capacities.idempotency_records * MAX_DURABLE_OWNERS
        idempotency_rows = connection.execute(
            """
            SELECT principal_id, result_json
            FROM idempotency
            ORDER BY principal_id, action, idempotency_key
            LIMIT ?
            """,
            (idempotency_limit + 1,),
        ).fetchall()
        if len(idempotency_rows) > idempotency_limit:
            raise ManagedWorkError(
                "managed-work.database-corrupt",
                "Managed work refused an idempotency table beyond its declared capacity.",
                recovery_actions=("managed-work.restore-database",),
            )
        idempotency_counts: dict[str, int] = {}
        for row in idempotency_rows:
            principal_id = str(row["principal_id"])
            principal_ids.add(principal_id)
            idempotency_counts[principal_id] = idempotency_counts.get(principal_id, 0) + 1
            if idempotency_counts[principal_id] > self.capacities.idempotency_records:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused an owner idempotency table beyond its declared capacity.",
                    recovery_actions=("managed-work.restore-database",),
                )

        step_limit = self.capacities.total_runs * MAX_DURABLE_OWNERS * 64
        step_counts: dict[str, int] = {}
        step_total = 0
        for row in connection.execute(
            "SELECT run_id, principal_id FROM steps ORDER BY row_id LIMIT ?",
            (step_limit + 1,),
        ):
            step_total += 1
            if step_total > step_limit:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused a step table beyond its declared durable capacity.",
                    recovery_actions=("managed-work.restore-database",),
                )
            run_id = str(row["run_id"])
            principal_ids.add(str(row["principal_id"]))
            step_counts[run_id] = step_counts.get(run_id, 0) + 1
            if step_counts[run_id] > 64:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused a run with more than 64 durable steps.",
                    recovery_actions=("managed-work.restore-database",),
                )

        if len(principal_ids) > MAX_DURABLE_OWNERS:
            raise ManagedWorkError(
                "managed-work.database-corrupt",
                "Managed work refused an owner-only database with too many durable owners.",
                recovery_actions=("managed-work.restore-database",),
            )

        for row in contexts:
            self._require_query_item_capacity("agent.context", self._context_result(row))
        for row in runs:
            run = self._run_result(
                row,
                self._steps_for_run(connection, row["run_id"], row["principal_id"]),
            )
            self._require_query_item_capacity(
                "agent.tasks",
                {"entityType": "run", "task": None, "run": run},
            )
        for row in tasks:
            latest = connection.execute(
                "SELECT * FROM runs WHERE task_id = ? AND principal_id = ? ORDER BY row_id DESC LIMIT 1",
                (row["task_id"], row["principal_id"]),
            ).fetchone()
            run = None
            if latest is not None:
                run = self._run_result(
                    latest,
                    self._steps_for_run(connection, latest["run_id"], row["principal_id"]),
                )
            self._require_query_item_capacity(
                "agent.tasks",
                {"entityType": "task", "task": self._task_result(row), "run": run},
            )
        for row in automations:
            self._require_query_item_capacity(
                "agent.automations",
                self._automation_result(
                    row,
                    self._firings_for_automation(
                        connection,
                        row["automation_id"],
                        row["principal_id"],
                        limit=5,
                    ),
                ),
            )
        for row in approvals:
            self._require_query_item_capacity("agent.approvals", self._approval_result(row))
        for row in operations:
            self._require_query_item_capacity("agent.activity", self._operation_result(row))
        for row in permissions:
            self._require_query_item_capacity("agent.permissions", self._permission_result(row))
        usage_summaries: dict[str, dict[str, int]] = {}
        for row in usage:
            summary = usage_summaries.setdefault(
                str(row["principal_id"]),
                {"costMicrounits": 0, "recordCount": 0},
            )
            summary["costMicrounits"] += int(row["cost_microunits"])
            summary["recordCount"] += 1
        for row in usage:
            self._require_query_item_capacity(
                "agent.usage",
                self._usage_result(row),
                summary=usage_summaries[str(row["principal_id"])],
            )
        for row in artifacts:
            self._require_query_item_capacity("agent.artifacts", self._artifact_result(row))
        pruned_values = connection.execute(
            "SELECT value FROM managed_metadata WHERE key LIKE 'history_pruned_through.%'"
        ).fetchall()
        pruned_through = max((int(row[0]) for row in pruned_values), default=0)
        for row in events:
            self._require_query_item_capacity(
                "agent.history",
                self._event_result(row),
                summary={"prunedThrough": pruned_through},
            )
        for row in providers:
            self._require_query_item_capacity("agent.providers", self._provider_result(row))

        for row in idempotency_rows:
            if row["result_json"] is None:
                continue
            result = json.loads(row["result_json"])
            if len(canonical_json(result).encode("utf-8")) > MAX_QUERY_RESPONSE_BYTES:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused an oversized durable idempotency result.",
                    recovery_actions=("managed-work.restore-database",),
                )

        if not principal_ids:
            principal_ids.add("account.uid.0")
        for principal_id in sorted(principal_ids):
            actor = Actor(principal_id, owner_sessions.get(principal_id, "session.validation"))
            diagnostics = self._query_troubleshooting(actor)["items"][0]
            self._require_query_item_capacity("agent.troubleshooting", diagnostics)

    def close(self) -> None:
        self.store.close()

    def __enter__(self) -> "ManagedWorkPlane":
        return self.open()

    def __exit__(self, *_: object) -> None:
        self.close()

    @staticmethod
    def execution_status() -> dict[str, Any]:
        from sandbox.builder import SandboxUnavailable, require_bwrap
        from sandbox.runner import packaged_runner_source

        try:
            require_bwrap()
            packaged_runner_source()
        except SandboxUnavailable:
            return {
                "schemaVersion": "v0",
                "kind": "managed-execution-status",
                "available": False,
                "code": EXECUTION_UNAVAILABLE_CODE,
                "explanation": "Managed execution fails closed without packaged bubblewrap and the packaged runner.",
                "legacyInteractiveIncluded": False,
                "networkDefault": "denied",
            }
        return {
            "schemaVersion": "v0",
            "kind": "managed-execution-status",
            "available": True,
            "code": EXECUTION_AVAILABLE_CODE,
            "explanation": "Managed tasks execute inside packaged bubblewrap with the packaged runner.",
            "legacyInteractiveIncluded": False,
            "networkDefault": "denied",
        }

    @staticmethod
    def _require_idempotency_key(value: Any) -> str:
        key = bounded_text(value, field="idempotency key", maximum=256)
        reject_secret_fields({"value": key}, field="idempotency key")
        return key

    def _claim_idempotency(
        self,
        connection: Any,
        actor: Actor,
        *,
        action: str,
        key: str,
        request: Mapping[str, Any],
        now: float,
    ) -> dict[str, Any] | None:
        request_hash = fingerprint(request)
        row = connection.execute(
            "SELECT request_hash, state, result_json FROM idempotency WHERE principal_id = ? AND action = ? AND idempotency_key = ?",
            (actor.principal_id, action, key),
        ).fetchone()
        if row is None:
            self._require_capacity(
                connection,
                table="idempotency",
                principal_id=actor.principal_id,
                limit=self.capacities.idempotency_records,
            )
            connection.execute(
                "INSERT INTO idempotency(principal_id, action, idempotency_key, request_hash, result_json, state, created_at, updated_at) VALUES (?, ?, ?, ?, NULL, 'pending', ?, ?)",
                (actor.principal_id, action, key, request_hash, now, now),
            )
            return None
        if row["request_hash"] != request_hash:
            raise ManagedWorkError(
                "idempotency.conflict",
                "The idempotency key was already used for a different request.",
            )
        if row["state"] == "complete" and row["result_json"]:
            return json.loads(row["result_json"])
        raise ManagedWorkError(
            "idempotency.incomplete",
            "The prior request did not complete and must be reconciled before retry.",
            recovery_actions=("managed-work.reconcile",),
        )

    @staticmethod
    def _finish_idempotency(
        connection: Any,
        actor: Actor,
        *,
        action: str,
        key: str,
        result: Mapping[str, Any],
        now: float,
    ) -> None:
        updated = connection.execute(
            "UPDATE idempotency SET result_json = ?, state = 'complete', updated_at = ? WHERE principal_id = ? AND action = ? AND idempotency_key = ? AND state = 'pending'",
            (canonical_json(result), now, actor.principal_id, action, key),
        ).rowcount
        if updated != 1:
            raise ManagedWorkError("idempotency.state", "The idempotency record changed unexpectedly.")

    def _append_event(
        self,
        connection: Any,
        actor: Actor,
        *,
        topic: str,
        entity_id: str | None,
        payload: Mapping[str, Any],
        now: float,
    ) -> None:
        count = int(
            connection.execute(
                "SELECT COUNT(*) FROM managed_events WHERE principal_id = ?",
                (actor.principal_id,),
            ).fetchone()[0]
        )
        if count >= self.capacities.history_events:
            remove_count = count - self.capacities.history_events + 1
            cutoff = connection.execute(
                "SELECT row_id FROM managed_events WHERE principal_id = ? ORDER BY row_id LIMIT 1 OFFSET ?",
                (actor.principal_id, remove_count - 1),
            ).fetchone()
            if cutoff is None:
                raise ManagedWorkError("history.capacity", "Managed-work history could not enforce retention.")
            cutoff_row = int(cutoff["row_id"])
            connection.execute(
                "DELETE FROM managed_events WHERE principal_id = ? AND row_id <= ?",
                (actor.principal_id, cutoff_row),
            )
            connection.execute(
                "INSERT OR REPLACE INTO managed_metadata(key, value) VALUES (?, ?)",
                (f"history_pruned_through.{actor.principal_id}", str(cutoff_row)),
            )
        event_id = _new_id("event")
        payload_value = normalize_json(payload, field="managed event payload")
        reject_secret_fields(payload_value, field="managed event payload")
        self._require_query_item_capacity(
            "agent.history",
            {
                "schemaVersion": "v0",
                "kind": "managed-work-event",
                "eventId": event_id,
                "topic": topic,
                "entityId": entity_id,
                "payload": payload_value,
                "createdAt": now,
            },
            summary={"prunedThrough": 9_223_372_036_854_775_807},
        )
        connection.execute(
            "INSERT INTO managed_events(event_id, principal_id, owner_session_id, topic, entity_id, payload_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (event_id, actor.principal_id, actor.session_id, topic, entity_id, canonical_json(payload_value), now),
        )

    @staticmethod
    def _require_capacity(
        connection: Any,
        *,
        table: str,
        principal_id: str,
        limit: int,
        where: str = "1 = 1",
        parameters: Sequence[Any] = (),
    ) -> None:
        allowed = {
            "contexts",
            "tasks",
            "runs",
            "automations",
            "artifacts",
            "usage_records",
            "operation_links",
            "approval_projections",
            "permission_projections",
            "automation_firings",
            "idempotency",
        }
        if table not in allowed:
            raise RuntimeError("unapproved capacity table")
        count = int(
            connection.execute(
                f"SELECT COUNT(*) FROM {table} WHERE principal_id = ? AND {where}",
                (principal_id, *parameters),
            ).fetchone()[0]
        )
        if count >= limit:
            raise ManagedWorkError(
                "capacity.exceeded",
                f"The {table.replace('_', ' ')} capacity is exhausted.",
                recovery_actions=("managed-work.review-retention",),
            )

    @staticmethod
    def _task_row(connection: Any, actor: Actor, task_id: str) -> Any:
        stable_id(task_id, field="task ID")
        row = connection.execute("SELECT * FROM tasks WHERE task_id = ?", (task_id,)).fetchone()
        if row is None or row["principal_id"] != actor.principal_id:
            raise ManagedWorkError("access.denied", "The task is unavailable to this principal.")
        return row

    @staticmethod
    def _run_row(connection: Any, actor: Actor, run_id: str) -> Any:
        stable_id(run_id, field="run ID")
        row = connection.execute("SELECT * FROM runs WHERE run_id = ?", (run_id,)).fetchone()
        if row is None or row["principal_id"] != actor.principal_id:
            raise ManagedWorkError("access.denied", "The run is unavailable to this principal.")
        return row

    @staticmethod
    def _context_row(connection: Any, actor: Actor, context_id: str, *, now: float) -> Any:
        stable_id(context_id, field="context ID")
        row = connection.execute("SELECT * FROM contexts WHERE context_id = ?", (context_id,)).fetchone()
        if row is None or row["principal_id"] != actor.principal_id:
            raise ManagedWorkError("access.denied", "The context snapshot is unavailable to this principal.")
        if row["access_scope"] == "session" and row["owner_session_id"] != actor.session_id:
            raise ManagedWorkError("access.session-denied", "This context snapshot belongs to another endpoint session.")
        if row["revoked_at"] is not None:
            raise ManagedWorkError("context.revoked", "The context snapshot has been revoked.")
        if float(row["expires_at"]) <= now:
            raise ManagedWorkError("context.expired", "The context snapshot has expired.")
        return row

    @staticmethod
    def _context_result(row: Any, *, include_content: bool = True) -> dict[str, Any]:
        result = {
            "schemaVersion": "v0",
            "kind": "context-snapshot",
            "contextId": row["context_id"],
            "owner": {"principalId": row["principal_id"], "sessionId": row["owner_session_id"]},
            "source": row["source"],
            "access": {"scope": row["access_scope"], "taskId": row["task_id"]},
            "capturedAt": float(row["captured_at"]),
            "expiresAt": float(row["expires_at"]),
            "sensitivity": row["sensitivity"],
            "contentHash": row["content_hash"],
            "revision": int(row["revision"]),
            "revokedAt": None if row["revoked_at"] is None else float(row["revoked_at"]),
            "redaction": {
                "applied": bool(json.loads(row["redacted_paths_json"])),
                "paths": json.loads(row["redacted_paths_json"]),
            },
            "content": json.loads(row["content_json"]) if include_content else None,
        }
        return result

    def capture_context(
        self,
        actor: Actor,
        *,
        source: str,
        access_scope: str,
        content: Any,
        sensitivity: str,
        ttl_seconds: int,
        idempotency_key: str,
        task_id: str | None = None,
        redact_keys: Sequence[str] = (),
        now: float | None = None,
    ) -> dict[str, Any]:
        captured_at = time.time() if now is None else timestamp(now, field="capture time")
        source_value = require_context_source(source)
        scope_value = enum_value(access_scope, field="context access scope", choices={"session", "task", "principal"})
        sensitivity_value = enum_value(
            sensitivity,
            field="context sensitivity",
            choices={"public", "personal", "private", "restricted"},
        )
        ttl_value = integer(ttl_seconds, field="context TTL", minimum=1, maximum=604_800)
        if scope_value == "task" and task_id is None:
            raise ManagedWorkError("context.task-required", "Task-scoped context requires a task ID.")
        if scope_value != "task" and task_id is not None:
            raise ManagedWorkError("context.task-forbidden", "Only task-scoped context may carry a task ID.")
        if task_id is not None:
            stable_id(task_id, field="task ID")
        normalized_redact_keys = sorted(
            {
                bounded_text(value, field="redaction key", maximum=256).casefold()
                for value in redact_keys
            }
        )
        redacted, paths = redact_context(content, extra_keys=normalized_redact_keys)
        content_json = canonical_json(redacted, field="context content")
        content_hash = fingerprint(redacted)
        key = self._require_idempotency_key(idempotency_key)
        request = {
            "source": source_value,
            "accessScope": scope_value,
            "taskId": task_id,
            "contentHash": content_hash,
            "sensitivity": sensitivity_value,
            "ttlSeconds": ttl_value,
            "redactKeys": normalized_redact_keys,
        }
        with self.store.transaction() as connection:
            existing = self._claim_idempotency(connection, actor, action="context.capture", key=key, request=request, now=captured_at)
            if existing is not None:
                return existing
            self._require_capacity(
                connection,
                table="contexts",
                principal_id=actor.principal_id,
                limit=self.capacities.total_contexts,
            )
            self._require_capacity(
                connection,
                table="contexts",
                principal_id=actor.principal_id,
                limit=self.capacities.live_contexts,
                where="revoked_at IS NULL AND expires_at > ?",
                parameters=(captured_at,),
            )
            if task_id is not None:
                self._task_row(connection, actor, task_id)
            context_id = _new_id("context")
            connection.execute(
                """
                INSERT INTO contexts(
                  context_id, principal_id, owner_session_id, source, access_scope, task_id,
                  captured_at, expires_at, sensitivity, content_json, redacted_paths_json,
                  content_hash, revision, revoked_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, NULL)
                """,
                (
                    context_id,
                    actor.principal_id,
                    actor.session_id,
                    source_value,
                    scope_value,
                    task_id,
                    captured_at,
                    captured_at + ttl_value,
                    sensitivity_value,
                    content_json,
                    canonical_json(paths),
                    content_hash,
                ),
            )
            row = connection.execute("SELECT * FROM contexts WHERE context_id = ?", (context_id,)).fetchone()
            result = self._context_result(row)
            self._require_query_item_capacity("agent.context", result)
            self._append_event(connection, actor, topic="context.captured", entity_id=context_id, payload={"contextId": context_id}, now=captured_at)
            self._finish_idempotency(connection, actor, action="context.capture", key=key, result=result, now=captured_at)
            return result

    def get_context(self, actor: Actor, context_id: str, *, now: float | None = None) -> dict[str, Any]:
        current = time.time() if now is None else timestamp(now, field="current time")
        with self.store.read() as connection:
            return self._context_result(self._context_row(connection, actor, context_id, now=current))

    def revoke_context(
        self,
        actor: Actor,
        context_id: str,
        *,
        expected_revision: int,
        now: float | None = None,
    ) -> dict[str, Any]:
        current = time.time() if now is None else timestamp(now, field="revocation time")
        revision = integer(expected_revision, field="expected revision", minimum=1)
        with self.store.transaction() as connection:
            stable_id(context_id, field="context ID")
            row = connection.execute("SELECT * FROM contexts WHERE context_id = ?", (context_id,)).fetchone()
            if row is None or row["principal_id"] != actor.principal_id:
                raise ManagedWorkError("access.denied", "The context snapshot is unavailable to this principal.")
            if int(row["revision"]) != revision:
                raise ManagedWorkError("revision.stale", "The context snapshot revision is stale.")
            if row["revoked_at"] is not None:
                return self._context_result(row)
            connection.execute(
                "UPDATE contexts SET revoked_at = ?, revision = revision + 1 WHERE context_id = ? AND revision = ?",
                (current, context_id, revision),
            )
            updated = connection.execute("SELECT * FROM contexts WHERE context_id = ?", (context_id,)).fetchone()
            self._append_event(connection, actor, topic="context.revoked", entity_id=context_id, payload={"contextId": context_id}, now=current)
            return self._context_result(updated)

    @staticmethod
    def _normalize_budget(value: Any) -> dict[str, Any]:
        data = closed_object(
            value,
            field="task budget",
            required={"timeSeconds", "outputBytes", "costMicrounits", "network"},
        )
        if not isinstance(data["network"], bool):
            raise ManagedWorkError("task.network", "The task network budget must be a boolean.")
        return {
            "timeSeconds": integer(data["timeSeconds"], field="task time budget", minimum=1, maximum=604_800),
            "outputBytes": integer(data["outputBytes"], field="task output budget", minimum=0, maximum=10 * 1024**3),
            "costMicrounits": integer(data["costMicrounits"], field="task cost budget", minimum=0, maximum=10**15),
            "network": data["network"],
        }

    @staticmethod
    def _task_result(row: Any) -> dict[str, Any]:
        return {
            "schemaVersion": "v0",
            "kind": "managed-task",
            "taskId": row["task_id"],
            "owner": {"principalId": row["principal_id"], "sessionId": row["owner_session_id"]},
            "title": row["title"],
            "intent": json.loads(row["intent_json"]),
            "contextIds": json.loads(row["context_ids_json"]),
            "budget": json.loads(row["budget_json"]),
            "state": row["state"],
            "revision": int(row["revision"]),
            "retryCount": int(row["retry_count"]),
            "createdAt": float(row["created_at"]),
            "updatedAt": float(row["updated_at"]),
            "execution": ManagedWorkPlane.execution_status(),
        }

    def create_task(
        self,
        actor: Actor,
        *,
        title: str,
        intent: Mapping[str, Any],
        context_ids: Sequence[str],
        budget: Mapping[str, Any],
        idempotency_key: str,
        now: float | None = None,
    ) -> dict[str, Any]:
        current = time.time() if now is None else timestamp(now, field="task creation time")
        title_value = bounded_text(title, field="task title", maximum=512)
        reject_secret_fields({"value": title_value}, field="task title")
        intent_value = normalize_json(intent, field="task intent")
        if not isinstance(intent_value, dict):
            raise ManagedWorkError("task.intent", "Task intent must be an object.")
        reject_secret_fields(intent_value, field="task intent")
        capability = intent_value.get("capability")
        if capability not in SANDBOX_CAPABILITIES:
            raise ManagedWorkError(
                "task.capability",
                "Task create requires a catalog capability from the Phase 2 sandbox allowlist.",
                detail="missing" if capability is None else str(capability),
            )
        if not isinstance(context_ids, Sequence) or isinstance(context_ids, (str, bytes)) or len(context_ids) > 64:
            raise ManagedWorkError("task.context", "Task context IDs must be a bounded array.")
        context_values = [stable_id(value, field="context ID") for value in context_ids]
        if len(set(context_values)) != len(context_values):
            raise ManagedWorkError("task.context", "Task context IDs must be unique.")
        budget_value = self._normalize_budget(budget)
        key = self._require_idempotency_key(idempotency_key)
        request = {
            "title": title_value,
            "intent": intent_value,
            "contextIds": context_values,
            "budget": budget_value,
        }
        with self.store.transaction() as connection:
            existing = self._claim_idempotency(connection, actor, action="task.create", key=key, request=request, now=current)
            if existing is not None:
                return existing
            self._require_capacity(
                connection,
                table="tasks",
                principal_id=actor.principal_id,
                limit=self.capacities.total_tasks,
            )
            self._require_capacity(
                connection,
                table="tasks",
                principal_id=actor.principal_id,
                limit=self.capacities.active_tasks,
                where="state NOT IN ('succeeded', 'failed', 'cancelled')",
            )
            for context_id in context_values:
                context = self._context_row(connection, actor, context_id, now=current)
                if context["access_scope"] in {"session", "task"}:
                    raise ManagedWorkError(
                        "task.context-scope",
                        "A durable task accepts only principal-scoped context; session and task context cannot be rebound.",
                    )
            task_id = _new_id("task")
            connection.execute(
                """
                INSERT INTO tasks(
                  task_id, principal_id, owner_session_id, title, intent_json, context_ids_json,
                  budget_json, state, revision, retry_count, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 'draft', 1, 0, ?, ?)
                """,
                (
                    task_id,
                    actor.principal_id,
                    actor.session_id,
                    title_value,
                    canonical_json(intent_value),
                    canonical_json(context_values),
                    canonical_json(budget_value),
                    current,
                    current,
                ),
            )
            row = connection.execute("SELECT * FROM tasks WHERE task_id = ?", (task_id,)).fetchone()
            result = self._task_result(row)
            self._require_query_item_capacity(
                "agent.tasks",
                {"entityType": "task", "task": result, "run": None},
            )
            self._append_event(connection, actor, topic="task.created", entity_id=task_id, payload={"taskId": task_id}, now=current)
            self._finish_idempotency(connection, actor, action="task.create", key=key, result=result, now=current)
            return result

    def release_session_contexts(self, actor: Actor) -> int:
        """Atomically remove context that cannot outlive its authenticated session."""

        with self.store.transaction() as connection:
            attached = connection.execute(
                """
                SELECT 1
                FROM contexts context
                JOIN tasks task ON task.principal_id = context.principal_id
                JOIN json_each(task.context_ids_json) reference
                  ON reference.value = context.context_id
                WHERE context.principal_id = ?
                  AND context.owner_session_id = ?
                  AND context.access_scope = 'session'
                LIMIT 1
                """,
                (actor.principal_id, actor.session_id),
            ).fetchone()
            if attached is not None:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "A durable task illegally references session-scoped context.",
                    recovery_actions=("managed-work.restore-database",),
                )
            connection.execute(
                """
                DELETE FROM idempotency
                WHERE principal_id = ?
                  AND action = 'context.capture'
                  AND json_extract(result_json, '$.contextId') IN (
                    SELECT context_id FROM contexts
                    WHERE principal_id = ? AND owner_session_id = ? AND access_scope = 'session'
                  )
                """,
                (actor.principal_id, actor.principal_id, actor.session_id),
            )
            removed = connection.execute(
                "DELETE FROM contexts WHERE principal_id = ? AND owner_session_id = ? AND access_scope = 'session'",
                (actor.principal_id, actor.session_id),
            ).rowcount
            return int(removed)

    def get_task(self, actor: Actor, task_id: str) -> dict[str, Any]:
        with self.store.read() as connection:
            return self._task_result(self._task_row(connection, actor, task_id))

    def transition_task(
        self,
        actor: Actor,
        task_id: str,
        *,
        expected_revision: int,
        target: str,
        reason: str = "",
        now: float | None = None,
        executor_attested: bool = False,
    ) -> dict[str, Any]:
        current = time.time() if now is None else timestamp(now, field="transition time")
        revision = integer(expected_revision, field="expected revision", minimum=1)
        target_value = enum_value(target, field="task state", choices=set(TASK_TRANSITIONS))
        reason_value = bounded_text(reason, field="transition reason", maximum=2048, allow_empty=True)
        reject_secret_fields({"value": reason_value}, field="transition reason")
        if target_value in {"running", "waiting", "succeeded"} and not executor_attested:
            raise ManagedWorkError(
                "managed-execution.unavailable",
                "A task cannot enter an executor-owned state until the executor attests the run.",
            )
        with self.store.transaction() as connection:
            row = self._task_row(connection, actor, task_id)
            if int(row["revision"]) != revision:
                raise ManagedWorkError("revision.stale", "The task revision is stale.")
            if target_value not in TASK_TRANSITIONS[row["state"]]:
                raise ManagedWorkError(
                    "task.transition",
                    f"Task state {row['state']} cannot transition to {target_value}.",
                )
            connection.execute(
                "UPDATE tasks SET state = ?, revision = revision + 1, updated_at = ? WHERE task_id = ? AND revision = ?",
                (target_value, current, task_id, revision),
            )
            updated = connection.execute("SELECT * FROM tasks WHERE task_id = ?", (task_id,)).fetchone()
            self._append_event(
                connection,
                actor,
                topic="task.transitioned",
                entity_id=task_id,
                payload={"taskId": task_id, "from": row["state"], "to": target_value, "reason": reason_value},
                now=current,
            )
            return self._task_result(updated)

    @staticmethod
    def _normalize_run_manifest(value: Any) -> dict[str, Any]:
        data = closed_object(
            value,
            field="run manifest",
            required={
                "provider",
                "model",
                "capabilities",
                "contextIds",
                "workspaceHandles",
                "artifactHandle",
                "budgets",
                "networkGranted",
                "sandboxRequired",
                "steps",
            },
        )
        if data["sandboxRequired"] is not True:
            raise ManagedWorkError("run.sandbox-required", "Managed run manifests must require a sandbox.")
        if not isinstance(data["networkGranted"], bool):
            raise ManagedWorkError("run.network", "Run network grant must be a boolean.")
        capabilities = data["capabilities"]
        contexts = data["contextIds"]
        workspaces = data["workspaceHandles"]
        steps = data["steps"]
        for field, collection, maximum in (
            ("capabilities", capabilities, 64),
            ("context IDs", contexts, 64),
            ("workspace handles", workspaces, 16),
            ("steps", steps, 64),
        ):
            if not isinstance(collection, list) or len(collection) > maximum:
                raise ManagedWorkError("run.manifest-array", f"Run {field} must be a bounded array.")
        capability_values = [stable_id(item, field="capability") for item in capabilities]
        context_values = [stable_id(item, field="context ID") for item in contexts]
        workspace_values = [stable_id(item, field="workspace handle") for item in workspaces]
        if any(len(set(values)) != len(values) for values in (capability_values, context_values, workspace_values)):
            raise ManagedWorkError("run.manifest-duplicate", "Run manifest arrays must not contain duplicate identities.")
        step_values: list[dict[str, Any]] = []
        for step in steps:
            step_data = closed_object(step, field="run step", required={"label"}, optional={"capability"})
            step_values.append(
                {
                    "label": bounded_text(step_data["label"], field="step label", maximum=512),
                    "capability": None
                    if step_data.get("capability") is None
                    else stable_id(step_data["capability"], field="step capability"),
                }
            )
        reject_secret_fields(step_values, field="run manifest steps")
        return {
            "provider": stable_id(data["provider"], field="run provider"),
            "model": stable_id(data["model"], field="run model"),
            "capabilities": capability_values,
            "contextIds": context_values,
            "workspaceHandles": workspace_values,
            "artifactHandle": stable_id(data["artifactHandle"], field="artifact handle"),
            "budgets": ManagedWorkPlane._normalize_budget(data["budgets"]),
            "networkGranted": data["networkGranted"],
            "sandboxRequired": True,
            "steps": step_values,
        }

    @staticmethod
    def _run_result(row: Any, steps: list[dict[str, Any]]) -> dict[str, Any]:
        return {
            "schemaVersion": "v0",
            "kind": "managed-run",
            "runId": row["run_id"],
            "taskId": row["task_id"],
            "parentRunId": row["parent_run_id"],
            "owner": {"principalId": row["principal_id"], "sessionId": row["owner_session_id"]},
            "manifest": json.loads(row["manifest_json"]),
            "manifestHash": row["manifest_hash"],
            "state": row["state"],
            "revision": int(row["revision"]),
            "createdAt": float(row["created_at"]),
            "updatedAt": float(row["updated_at"]),
            "interruptedAt": None if row["interrupted_at"] is None else float(row["interrupted_at"]),
            "steps": steps,
            "execution": ManagedWorkPlane.execution_status(),
        }

    @staticmethod
    def _steps_for_run(connection: Any, run_id: str, principal_id: str) -> list[dict[str, Any]]:
        rows = connection.execute(
            "SELECT * FROM steps WHERE run_id = ? AND principal_id = ? ORDER BY sequence",
            (run_id, principal_id),
        ).fetchall()
        return [
            {
                "schemaVersion": "v0",
                "kind": "managed-step",
                "stepId": row["step_id"],
                "runId": row["run_id"],
                "sequence": int(row["sequence"]),
                "label": row["label"],
                "capability": row["capability"],
                "state": row["state"],
                "detail": json.loads(row["detail_json"]),
                "createdAt": float(row["created_at"]),
            }
            for row in rows
        ]

    def create_run_plan(
        self,
        actor: Actor,
        task_id: str,
        *,
        manifest: Mapping[str, Any],
        idempotency_key: str,
        parent_run_id: str | None = None,
        now: float | None = None,
    ) -> dict[str, Any]:
        current = time.time() if now is None else timestamp(now, field="run creation time")
        manifest_value = self._normalize_run_manifest(manifest)
        key = self._require_idempotency_key(idempotency_key)
        stable_id(task_id, field="task ID")
        if parent_run_id is not None:
            stable_id(parent_run_id, field="parent run ID")
        request = {"taskId": task_id, "parentRunId": parent_run_id, "manifest": manifest_value}
        with self.store.transaction() as connection:
            existing = self._claim_idempotency(connection, actor, action="run.plan", key=key, request=request, now=current)
            if existing is not None:
                return existing
            self._require_capacity(
                connection,
                table="runs",
                principal_id=actor.principal_id,
                limit=self.capacities.total_runs,
            )
            task = self._task_row(connection, actor, task_id)
            if task["state"] not in {"queued", "retrying"}:
                raise ManagedWorkError("run.task-state", "A run may be planned only for a queued or retrying task.")
            task_contexts = set(json.loads(task["context_ids_json"]))
            for context_id in manifest_value["contextIds"]:
                context = self._context_row(connection, actor, context_id, now=current)
                if context["access_scope"] == "task" and context["task_id"] != task_id:
                    raise ManagedWorkError("run.context-scope", "The run manifest references context outside its task.")
                if context_id not in task_contexts and context["access_scope"] != "task":
                    raise ManagedWorkError("run.context-scope", "The run manifest references context outside its task.")
            if manifest_value["networkGranted"]:
                grant = connection.execute(
                    "SELECT 1 FROM permission_projections WHERE principal_id = ? AND capability = 'managed.network' AND resource = 'network.internet' AND state = 'active' AND (expires_at IS NULL OR expires_at > ?) LIMIT 1",
                    (actor.principal_id, current),
                ).fetchone()
                if grant is None:
                    raise ManagedWorkError("run.network-denied", "The run has no active managed.network grant.")
            if parent_run_id is not None:
                parent = self._run_row(connection, actor, parent_run_id)
                if parent["task_id"] != task_id:
                    raise ManagedWorkError("run.parent", "The parent run belongs to another task.")
            run_id = _new_id("run")
            manifest_json = canonical_json(manifest_value)
            connection.execute(
                """
                INSERT INTO runs(
                  run_id, task_id, principal_id, owner_session_id, parent_run_id, manifest_json,
                  manifest_hash, state, revision, created_at, updated_at, interrupted_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 'queued', 1, ?, ?, NULL)
                """,
                (
                    run_id,
                    task_id,
                    actor.principal_id,
                    actor.session_id,
                    parent_run_id,
                    manifest_json,
                    fingerprint(manifest_value),
                    current,
                    current,
                ),
            )
            step_state, step_detail = ManagedWorkPlane._run_step_record()
            for sequence, step in enumerate(manifest_value["steps"]):
                connection.execute(
                    "INSERT INTO steps(step_id, run_id, principal_id, sequence, label, capability, state, detail_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        _new_id("step"),
                        run_id,
                        actor.principal_id,
                        sequence,
                        step["label"],
                        step["capability"],
                        step_state,
                        canonical_json(step_detail),
                        current,
                    ),
                )
            row = connection.execute("SELECT * FROM runs WHERE run_id = ?", (run_id,)).fetchone()
            result = self._run_result(row, self._steps_for_run(connection, run_id, actor.principal_id))
            self._require_query_item_capacity(
                "agent.tasks",
                {"entityType": "run", "task": None, "run": result},
            )
            self._require_query_item_capacity(
                "agent.tasks",
                {"entityType": "task", "task": self._task_result(task), "run": result},
            )
            self._append_event(connection, actor, topic="run.planned", entity_id=run_id, payload={"runId": run_id, "taskId": task_id}, now=current)
            self._finish_idempotency(connection, actor, action="run.plan", key=key, result=result, now=current)
            return result

    def get_run(self, actor: Actor, run_id: str) -> dict[str, Any]:
        with self.store.read() as connection:
            row = self._run_row(connection, actor, run_id)
            return self._run_result(row, self._steps_for_run(connection, run_id, actor.principal_id))

    def transition_run(
        self,
        actor: Actor,
        run_id: str,
        *,
        expected_revision: int,
        target: str,
        detail: Mapping[str, Any],
        now: float | None = None,
        executor_attested: bool = False,
    ) -> dict[str, Any]:
        current = time.time() if now is None else timestamp(now, field="run transition time")
        revision = integer(expected_revision, field="expected revision", minimum=1)
        target_value = enum_value(target, field="run state", choices=set(RUN_TRANSITIONS))
        detail_value = normalize_json(detail, field="run transition detail")
        if not isinstance(detail_value, dict):
            raise ManagedWorkError("run.detail", "Run transition detail must be an object.")
        reject_secret_fields(detail_value, field="run transition detail")
        if target_value in {"running", "waiting", "retrying", "succeeded"} and not executor_attested:
            raise ManagedWorkError(
                "managed-execution.unavailable",
                "The managed-work plane cannot report executor-owned progress without an integrated executor.",
            )
        with self.store.transaction() as connection:
            row = self._run_row(connection, actor, run_id)
            if int(row["revision"]) != revision:
                raise ManagedWorkError("revision.stale", "The run revision is stale.")
            if target_value not in RUN_TRANSITIONS[row["state"]]:
                raise ManagedWorkError("run.transition", f"Run state {row['state']} cannot transition to {target_value}.")
            connection.execute(
                "UPDATE runs SET state = ?, revision = revision + 1, updated_at = ? WHERE run_id = ? AND revision = ?",
                (target_value, current, run_id, revision),
            )
            if target_value in {"cancelled", "failed"}:
                task_target = "cancelled" if target_value == "cancelled" else "failed"
                connection.execute(
                    "UPDATE tasks SET state = ?, revision = revision + 1, updated_at = ? WHERE task_id = ? AND state IN ('queued', 'retrying', 'running')",
                    (task_target, current, row["task_id"]),
                )
            elif target_value == "running" and executor_attested:
                connection.execute(
                    "UPDATE tasks SET state = 'running', revision = revision + 1, updated_at = ? WHERE task_id = ? AND state IN ('queued', 'retrying')",
                    (current, row["task_id"]),
                )
            elif target_value == "succeeded" and executor_attested:
                connection.execute(
                    "UPDATE tasks SET state = 'succeeded', revision = revision + 1, updated_at = ? WHERE task_id = ? AND state IN ('running', 'queued', 'retrying')",
                    (current, row["task_id"]),
                )
            updated = connection.execute("SELECT * FROM runs WHERE run_id = ?", (run_id,)).fetchone()
            self._append_event(
                connection,
                actor,
                topic="run.transitioned",
                entity_id=run_id,
                payload={"runId": run_id, "from": row["state"], "to": target_value, "detail": detail_value},
                now=current,
            )
            return self._run_result(updated, self._steps_for_run(connection, run_id, actor.principal_id))

    def retry_run(
        self,
        actor: Actor,
        run_id: str,
        *,
        expected_revision: int,
        idempotency_key: str,
        now: float | None = None,
    ) -> dict[str, Any]:
        current = time.time() if now is None else timestamp(now, field="retry time")
        revision = integer(expected_revision, field="expected revision", minimum=1)
        key = self._require_idempotency_key(idempotency_key)
        stable_id(run_id, field="run ID")
        request = {"runId": run_id, "expectedRevision": revision}
        with self.store.transaction() as connection:
            existing = self._claim_idempotency(connection, actor, action="run.retry", key=key, request=request, now=current)
            if existing is not None:
                return existing
            self._require_capacity(
                connection,
                table="runs",
                principal_id=actor.principal_id,
                limit=self.capacities.total_runs,
            )
            parent = self._run_row(connection, actor, run_id)
            if int(parent["revision"]) != revision:
                raise ManagedWorkError("revision.stale", "The run revision is stale.")
            if parent["state"] not in {"failed", "interrupted"}:
                raise ManagedWorkError("run.retry-state", "Only a failed or interrupted run can be retried.")
            task = self._task_row(connection, actor, parent["task_id"])
            if int(task["retry_count"]) >= 10:
                raise ManagedWorkError("run.retry-limit", "The task retry limit is exhausted.")
            new_run_id = _new_id("run")
            connection.execute(
                """
                INSERT INTO runs(
                  run_id, task_id, principal_id, owner_session_id, parent_run_id, manifest_json,
                  manifest_hash, state, revision, created_at, updated_at, interrupted_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 'queued', 1, ?, ?, NULL)
                """,
                (
                    new_run_id,
                    parent["task_id"],
                    actor.principal_id,
                    actor.session_id,
                    run_id,
                    parent["manifest_json"],
                    parent["manifest_hash"],
                    current,
                    current,
                ),
            )
            parent_steps = connection.execute("SELECT * FROM steps WHERE run_id = ? ORDER BY sequence", (run_id,)).fetchall()
            step_state, step_detail = ManagedWorkPlane._run_step_record()
            retry_detail = dict(step_detail)
            retry_detail["retryOf"] = run_id
            for step in parent_steps:
                connection.execute(
                    "INSERT INTO steps(step_id, run_id, principal_id, sequence, label, capability, state, detail_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        _new_id("step"),
                        new_run_id,
                        actor.principal_id,
                        step["sequence"],
                        step["label"],
                        step["capability"],
                        step_state,
                        canonical_json(retry_detail),
                        current,
                    ),
                )
            connection.execute(
                "UPDATE tasks SET state = 'queued', revision = revision + 1, retry_count = retry_count + 1, updated_at = ? WHERE task_id = ?",
                (current, parent["task_id"]),
            )
            new_run = connection.execute("SELECT * FROM runs WHERE run_id = ?", (new_run_id,)).fetchone()
            result = self._run_result(new_run, self._steps_for_run(connection, new_run_id, actor.principal_id))
            updated_task = connection.execute(
                "SELECT * FROM tasks WHERE task_id = ?",
                (parent["task_id"],),
            ).fetchone()
            self._require_query_item_capacity(
                "agent.tasks",
                {"entityType": "run", "task": None, "run": result},
            )
            self._require_query_item_capacity(
                "agent.tasks",
                {"entityType": "task", "task": self._task_result(updated_task), "run": result},
            )
            self._append_event(connection, actor, topic="run.retried", entity_id=new_run_id, payload={"runId": new_run_id, "parentRunId": run_id}, now=current)
            self._finish_idempotency(connection, actor, action="run.retry", key=key, result=result, now=current)
            return result

    @staticmethod
    def _normalize_task_template(value: Any) -> dict[str, Any]:
        data = closed_object(
            value,
            field="automation task template",
            required={"title", "intent", "contextIds", "budget"},
        )
        intent = normalize_json(data["intent"], field="automation task intent")
        if not isinstance(intent, dict):
            raise ManagedWorkError("automation.intent", "Automation task intent must be an object.")
        reject_secret_fields(intent, field="automation task intent")
        context_ids = data["contextIds"]
        if not isinstance(context_ids, list) or len(context_ids) > 64:
            raise ManagedWorkError("automation.context", "Automation context IDs must be a bounded array.")
        normalized_contexts = [stable_id(item, field="context ID") for item in context_ids]
        if len(set(normalized_contexts)) != len(normalized_contexts):
            raise ManagedWorkError("automation.context", "Automation context IDs must be unique.")
        return {
            "title": bounded_text(data["title"], field="automation task title", maximum=512),
            "intent": intent,
            "contextIds": normalized_contexts,
            "budget": ManagedWorkPlane._normalize_budget(data["budget"]),
        }

    @staticmethod
    def _automation_result(row: Any, firings: list[dict[str, Any]] | None = None) -> dict[str, Any]:
        return {
            "schemaVersion": "v0",
            "kind": "managed-automation",
            "automationId": row["automation_id"],
            "owner": {"principalId": row["principal_id"], "sessionId": row["owner_session_id"]},
            "name": row["name"],
            "taskTemplate": json.loads(row["task_template_json"]),
            "trigger": json.loads(row["trigger_json"]),
            "policy": json.loads(row["policy_json"]),
            "state": row["state"],
            "revision": int(row["revision"]),
            "nextDueAt": None if row["next_due_at"] is None else float(row["next_due_at"]),
            "lastReconciledAt": None
            if row["last_reconciled_at"] is None
            else float(row["last_reconciled_at"]),
            "createdAt": float(row["created_at"]),
            "updatedAt": float(row["updated_at"]),
            "firings": firings or [],
            "execution": ManagedWorkPlane.execution_status(),
        }

    @staticmethod
    def _firing_result(row: Any) -> dict[str, Any]:
        return {
            "schemaVersion": "v0",
            "kind": "automation-firing",
            "firingId": row["firing_id"],
            "automationId": row["automation_id"],
            "triggerKind": row["trigger_kind"],
            "triggerId": row["trigger_id"],
            "dueAt": float(row["due_at"]),
            "state": row["state"],
            "detail": json.loads(row["detail_json"]),
            "createdAt": float(row["created_at"]),
        }

    @classmethod
    def _firings_for_automation(
        cls,
        connection: Any,
        automation_id: str,
        principal_id: str,
        *,
        limit: int = 20,
    ) -> list[dict[str, Any]]:
        rows = connection.execute(
            "SELECT * FROM automation_firings WHERE automation_id = ? AND principal_id = ? ORDER BY row_id DESC LIMIT ?",
            (automation_id, principal_id, limit),
        ).fetchall()
        return [cls._firing_result(row) for row in rows]

    @staticmethod
    def _automation_row(connection: Any, actor: Actor, automation_id: str) -> Any:
        stable_id(automation_id, field="automation ID")
        row = connection.execute("SELECT * FROM automations WHERE automation_id = ?", (automation_id,)).fetchone()
        if row is None or row["principal_id"] != actor.principal_id:
            raise ManagedWorkError("access.denied", "The automation is unavailable to this principal.")
        return row

    def create_automation(
        self,
        actor: Actor,
        *,
        name: str,
        task_template: Mapping[str, Any],
        trigger: Mapping[str, Any],
        policy: Mapping[str, Any],
        idempotency_key: str,
        now: float | None = None,
    ) -> dict[str, Any]:
        current = time.time() if now is None else timestamp(now, field="automation creation time")
        name_value = bounded_text(name, field="automation name", maximum=512)
        reject_secret_fields({"value": name_value}, field="automation name")
        template_value = self._normalize_task_template(task_template)
        reject_secret_fields(template_value, field="automation task template")
        trigger_value = normalize_trigger(trigger)
        policy_value = normalize_policy(policy)
        key = self._require_idempotency_key(idempotency_key)
        request = {
            "name": name_value,
            "taskTemplate": template_value,
            "trigger": trigger_value,
            "policy": policy_value,
        }
        with self.store.transaction() as connection:
            existing = self._claim_idempotency(connection, actor, action="automation.create", key=key, request=request, now=current)
            if existing is not None:
                return existing
            self._require_capacity(
                connection,
                table="automations",
                principal_id=actor.principal_id,
                limit=self.capacities.total_automations,
            )
            self._require_capacity(
                connection,
                table="automations",
                principal_id=actor.principal_id,
                limit=self.capacities.active_automations,
                where="state != 'disabled'",
            )
            for context_id in template_value["contextIds"]:
                context = self._context_row(connection, actor, context_id, now=current)
                if context["access_scope"] != "principal":
                    raise ManagedWorkError(
                        "automation.context-scope",
                        "Automations may retain only principal-scoped context.",
                    )
            automation_id = _new_id("automation")
            next_due_at = first_due(trigger_value, created_at=current)
            connection.execute(
                """
                INSERT INTO automations(
                  automation_id, principal_id, owner_session_id, name, task_template_json,
                  trigger_json, policy_json, state, revision, next_due_at,
                  last_reconciled_at, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 'enabled', 1, ?, NULL, ?, ?)
                """,
                (
                    automation_id,
                    actor.principal_id,
                    actor.session_id,
                    name_value,
                    canonical_json(template_value),
                    canonical_json(trigger_value),
                    canonical_json(policy_value),
                    next_due_at,
                    current,
                    current,
                ),
            )
            row = connection.execute("SELECT * FROM automations WHERE automation_id = ?", (automation_id,)).fetchone()
            result = self._automation_result(row)
            self._require_query_item_capacity("agent.automations", result)
            self._append_event(connection, actor, topic="automation.created", entity_id=automation_id, payload={"automationId": automation_id}, now=current)
            self._finish_idempotency(connection, actor, action="automation.create", key=key, result=result, now=current)
            return result

    def get_automation(self, actor: Actor, automation_id: str) -> dict[str, Any]:
        with self.store.read() as connection:
            row = self._automation_row(connection, actor, automation_id)
            return self._automation_result(
                row,
                self._firings_for_automation(connection, automation_id, actor.principal_id),
            )

    def set_automation_state(
        self,
        actor: Actor,
        automation_id: str,
        *,
        expected_revision: int,
        state: str,
        now: float | None = None,
    ) -> dict[str, Any]:
        current = time.time() if now is None else timestamp(now, field="automation update time")
        revision = integer(expected_revision, field="expected revision", minimum=1)
        state_value = enum_value(state, field="automation state", choices={"enabled", "paused", "disabled"})
        with self.store.transaction() as connection:
            row = self._automation_row(connection, actor, automation_id)
            if int(row["revision"]) != revision:
                raise ManagedWorkError("revision.stale", "The automation revision is stale.")
            if row["state"] == "disabled" and state_value != "disabled":
                raise ManagedWorkError("automation.disabled", "A disabled automation cannot be re-enabled.")
            connection.execute(
                "UPDATE automations SET state = ?, revision = revision + 1, updated_at = ? WHERE automation_id = ? AND revision = ?",
                (state_value, current, automation_id, revision),
            )
            if state_value == "disabled":
                pending_rows = connection.execute(
                    "SELECT firing_id, detail_json FROM automation_firings WHERE automation_id = ? AND state = 'pending-unavailable'",
                    (automation_id,),
                ).fetchall()
                for pending in pending_rows:
                    detail = json.loads(pending["detail_json"])
                    detail["cancelled"] = {"reason": "automation-disabled", "at": current}
                    connection.execute(
                        "UPDATE automation_firings SET state = 'cancelled', detail_json = ? WHERE firing_id = ?",
                        (canonical_json(detail), pending["firing_id"]),
                    )
            updated = connection.execute("SELECT * FROM automations WHERE automation_id = ?", (automation_id,)).fetchone()
            self._append_event(
                connection,
                actor,
                topic="automation.state-changed",
                entity_id=automation_id,
                payload={"automationId": automation_id, "from": row["state"], "to": state_value},
                now=current,
            )
            result = self._automation_result(
                updated,
                self._firings_for_automation(connection, automation_id, actor.principal_id),
            )
            self._require_query_item_capacity("agent.automations", result)
            return result

    def reconcile_schedules(
        self,
        actor: Actor,
        *,
        now: float | None = None,
        signed_in: bool = True,
    ) -> dict[str, Any]:
        current = time.time() if now is None else timestamp(now, field="schedule reconciliation time")
        if not isinstance(signed_in, bool):
            raise ManagedWorkError("schedule.signed-in", "Signed-in state must be a boolean.")
        created: list[dict[str, Any]] = []
        skipped = 0
        missed = 0
        rollbacks = 0
        with self.store.transaction() as connection:
            rows = connection.execute(
                "SELECT * FROM automations WHERE principal_id = ? AND state = 'enabled' ORDER BY row_id",
                (actor.principal_id,),
            ).fetchall()
            for row in rows:
                trigger = json.loads(row["trigger_json"])
                if trigger["kind"] == "event":
                    continue
                last = row["last_reconciled_at"]
                if last is not None and current < float(last):
                    rollbacks += 1
                    continue
                if not signed_in:
                    connection.execute(
                        "UPDATE automations SET last_reconciled_at = ?, updated_at = ? WHERE automation_id = ?",
                        (current, current, row["automation_id"]),
                    )
                    continue
                policy = json.loads(row["policy_json"])
                selected, future, count = reconcile_due(
                    trigger,
                    policy,
                    due_at=None if row["next_due_at"] is None else float(row["next_due_at"]),
                    now=current,
                )
                missed += count
                required_records = len(selected) + (1 if count and not selected else 0)
                if required_records:
                    existing_count = int(
                        connection.execute(
                            "SELECT COUNT(*) FROM automation_firings WHERE principal_id = ?",
                            (actor.principal_id,),
                        ).fetchone()[0]
                    )
                    if existing_count + required_records > self.capacities.event_firings:
                        raise ManagedWorkError(
                            "capacity.exceeded",
                            "Automation firing history is at capacity; no due cursor was advanced.",
                        )
                if count and not selected:
                    firing_id = _new_id("firing")
                    trigger_id = f"schedule.skip.{int(float(row['next_due_at']) * 1_000_000)}.{count}"
                    detail = {
                        "missedCount": count,
                        "policy": policy,
                        "executionCode": "managed-execution.not-integrated",
                    }
                    connection.execute(
                        "INSERT OR IGNORE INTO automation_firings(firing_id, automation_id, principal_id, trigger_kind, trigger_id, due_at, state, detail_json, created_at) VALUES (?, ?, ?, 'schedule', ?, ?, 'skipped', ?, ?)",
                        (
                            firing_id,
                            row["automation_id"],
                            actor.principal_id,
                            trigger_id,
                            row["next_due_at"],
                            canonical_json(detail),
                            current,
                        ),
                    )
                    skipped += count
                for due_at in selected:
                    firing_id = _new_id("firing")
                    trigger_id = f"schedule.{int(due_at * 1_000_000)}"
                    detail = {
                        "missedCount": count,
                        "policy": policy,
                        "executionCode": "managed-execution.not-integrated",
                    }
                    cursor = connection.execute(
                        "INSERT OR IGNORE INTO automation_firings(firing_id, automation_id, principal_id, trigger_kind, trigger_id, due_at, state, detail_json, created_at) VALUES (?, ?, ?, 'schedule', ?, ?, 'pending-unavailable', ?, ?)",
                        (
                            firing_id,
                            row["automation_id"],
                            actor.principal_id,
                            trigger_id,
                            due_at,
                            canonical_json(detail),
                            current,
                        ),
                    )
                    if cursor.rowcount:
                        firing = connection.execute("SELECT * FROM automation_firings WHERE firing_id = ?", (firing_id,)).fetchone()
                        created.append(self._firing_result(firing))
                connection.execute(
                    "UPDATE automations SET next_due_at = ?, last_reconciled_at = ?, updated_at = ? WHERE automation_id = ?",
                    (future, current, current, row["automation_id"]),
                )
                projected = connection.execute(
                    "SELECT * FROM automations WHERE automation_id = ?",
                    (row["automation_id"],),
                ).fetchone()
                self._require_query_item_capacity(
                    "agent.automations",
                    self._automation_result(
                        projected,
                        self._firings_for_automation(
                            connection,
                            row["automation_id"],
                            actor.principal_id,
                            limit=5,
                        ),
                    ),
                )
            if created or skipped or rollbacks:
                self._append_event(
                    connection,
                    actor,
                    topic="automation.reconciled",
                    entity_id=None,
                    payload={
                        "created": len(created),
                        "skipped": skipped,
                        "missed": missed,
                        "clockRollbacks": rollbacks,
                    },
                    now=current,
                )
        return {
            "schemaVersion": "v0",
            "kind": "schedule-reconciliation",
            "reconciledAt": current,
            "signedIn": signed_in,
            "missedCount": missed,
            "createdCount": len(created),
            "skippedCount": skipped,
            "clockRollbackCount": rollbacks,
            "firings": created,
            "execution": self.execution_status(),
        }

    def ingest_event(
        self,
        actor: Actor,
        *,
        topic: str,
        event_id: str,
        payload: Mapping[str, Any],
        occurred_at: float,
        now: float | None = None,
    ) -> dict[str, Any]:
        current = time.time() if now is None else timestamp(now, field="event ingestion time")
        topic_value = stable_id(topic, field="event topic")
        event_value = opaque_id(event_id, field="event ID")
        occurred = timestamp(occurred_at, field="event occurrence time")
        if occurred > current + 300:
            raise ManagedWorkError("event.future", "An automation event cannot be more than five minutes in the future.")
        payload_value = normalize_json(payload, field="event payload")
        if not isinstance(payload_value, dict):
            raise ManagedWorkError("event.payload", "Automation event payload must be an object.")
        reject_secret_fields(payload_value, field="automation event payload")
        firings: list[dict[str, Any]] = []
        with self.store.transaction() as connection:
            rows = connection.execute(
                "SELECT * FROM automations WHERE principal_id = ? AND state = 'enabled' ORDER BY row_id",
                (actor.principal_id,),
            ).fetchall()
            matching = [row for row in rows if json.loads(row["trigger_json"]) == {"kind": "event", "topic": topic_value}]
            event_projection = {
                "id": event_value,
                "topic": topic_value,
                "payload": payload_value,
                "occurredAt": occurred,
            }
            novel: list[Any] = []
            for row in matching:
                existing = connection.execute(
                    "SELECT detail_json FROM automation_firings WHERE automation_id = ? AND trigger_kind = 'event' AND trigger_id = ?",
                    (row["automation_id"], event_value),
                ).fetchone()
                if existing is None:
                    novel.append(row)
                    continue
                prior = json.loads(existing["detail_json"])["event"]
                if prior != event_projection:
                    raise ManagedWorkError(
                        "event.conflict",
                        "The event identity was already bound to different event data.",
                    )
            existing_count = int(
                connection.execute(
                    "SELECT COUNT(*) FROM automation_firings WHERE principal_id = ?",
                    (actor.principal_id,),
                ).fetchone()[0]
            )
            if existing_count + len(novel) > self.capacities.event_firings:
                raise ManagedWorkError("capacity.exceeded", "Automation firing history is at capacity.")
            for row in novel:
                firing_id = _new_id("firing")
                automation_policy = json.loads(row["policy_json"])
                detail = {
                    "event": event_projection,
                    "policy": automation_policy,
                    "executionCode": "managed-execution.not-integrated",
                }
                firing_state = "pending-unavailable"
                pending = connection.execute(
                    "SELECT * FROM automation_firings WHERE automation_id = ? AND state = 'pending-unavailable' ORDER BY row_id DESC LIMIT 1",
                    (row["automation_id"],),
                ).fetchone()
                if pending is not None and automation_policy["coalescing"] == "earliest":
                    firing_state = "skipped"
                    detail["coalesced"] = {
                        "policy": "earliest",
                        "keptFiringId": pending["firing_id"],
                    }
                elif pending is not None and automation_policy["coalescing"] == "latest":
                    prior_detail = json.loads(pending["detail_json"])
                    prior_detail["coalesced"] = {
                        "policy": "latest",
                        "replacedByEventId": event_value,
                    }
                    connection.execute(
                        "UPDATE automation_firings SET state = 'cancelled', detail_json = ? WHERE firing_id = ?",
                        (canonical_json(prior_detail), pending["firing_id"]),
                    )
                cursor = connection.execute(
                    "INSERT OR IGNORE INTO automation_firings(firing_id, automation_id, principal_id, trigger_kind, trigger_id, due_at, state, detail_json, created_at) VALUES (?, ?, ?, 'event', ?, ?, ?, ?, ?)",
                    (
                        firing_id,
                        row["automation_id"],
                        actor.principal_id,
                        event_value,
                        occurred,
                        firing_state,
                        canonical_json(detail),
                        current,
                    ),
                )
                if cursor.rowcount:
                    firing = connection.execute("SELECT * FROM automation_firings WHERE firing_id = ?", (firing_id,)).fetchone()
                    firings.append(self._firing_result(firing))
            for automation_id in {str(row["automation_id"]) for row in novel}:
                projected = connection.execute(
                    "SELECT * FROM automations WHERE automation_id = ?",
                    (automation_id,),
                ).fetchone()
                self._require_query_item_capacity(
                    "agent.automations",
                    self._automation_result(
                        projected,
                        self._firings_for_automation(
                            connection,
                            automation_id,
                            actor.principal_id,
                            limit=5,
                        ),
                    ),
                )
            if firings:
                self._append_event(
                    connection,
                    actor,
                    topic="automation.event-ingested",
                    entity_id=None,
                    payload={"eventId": event_value, "topic": topic_value, "firingCount": len(firings)},
                    now=current,
                )
        return {
            "schemaVersion": "v0",
            "kind": "automation-event-result",
            "eventId": event_value,
            "topic": topic_value,
            "matchedCount": len(firings),
            "firings": firings,
            "execution": self.execution_status(),
        }

    @staticmethod
    def _projection_decision(existing: Any, *, source_revision: int, payload_json: str) -> str:
        if existing is None:
            return "insert"
        existing_revision = int(existing["source_revision"])
        if source_revision < existing_revision:
            raise ManagedWorkError("projection.stale", "The projection source revision is stale.")
        if source_revision == existing_revision:
            if existing["payload_json"] != payload_json:
                raise ManagedWorkError(
                    "projection.conflict",
                    "The same projection revision contains different data.",
                )
            return "unchanged"
        return "update"

    @staticmethod
    def _approval_result(row: Any) -> dict[str, Any]:
        return {
            "schemaVersion": "v0",
            "kind": "approval-projection",
            "approvalId": row["approval_id"],
            "operationId": row["operation_id"],
            "owner": {"principalId": row["principal_id"], "sessionId": row["owner_session_id"]},
            "sourceRevision": int(row["source_revision"]),
            "capability": row["capability"],
            "state": row["state"],
            "risk": row["risk"],
            "summary": row["summary"],
            "requestedAt": float(row["requested_at"]),
            "expiresAt": float(row["expires_at"]),
            "projectedAt": float(row["projected_at"]),
        }

    def project_approval(self, actor: Actor, projection: Mapping[str, Any], *, now: float | None = None) -> dict[str, Any]:
        current = time.time() if now is None else timestamp(now, field="approval projection time")
        data = closed_object(
            projection,
            field="approval projection",
            required={
                "sourceRevision",
                "approvalId",
                "operationId",
                "capability",
                "state",
                "risk",
                "summary",
                "requestedAt",
                "expiresAt",
            },
        )
        value = {
            "sourceRevision": integer(data["sourceRevision"], field="source revision", minimum=1),
            "approvalId": opaque_id(data["approvalId"], field="approval ID"),
            "operationId": opaque_id(data["operationId"], field="operation ID"),
            "capability": stable_id(data["capability"], field="capability"),
            "state": enum_value(
                data["state"],
                field="approval state",
                choices={"pending", "approved", "denied", "expired", "cancelled"},
            ),
            "risk": enum_value(data["risk"], field="approval risk", choices={"low", "consequential", "high"}),
            "summary": bounded_text(data["summary"], field="approval summary", maximum=2048),
            "requestedAt": timestamp(data["requestedAt"], field="approval request time"),
            "expiresAt": timestamp(data["expiresAt"], field="approval expiry"),
        }
        if value["expiresAt"] <= value["requestedAt"]:
            raise ManagedWorkError("approval.expiry", "Approval expiry must follow its request time.")
        reject_secret_fields({"value": value["summary"]}, field="approval summary")
        payload_json = canonical_json(value)
        with self.store.transaction() as connection:
            existing = connection.execute(
                "SELECT * FROM approval_projections WHERE principal_id = ? AND approval_id = ?",
                (actor.principal_id, value["approvalId"]),
            ).fetchone()
            decision = self._projection_decision(
                existing,
                source_revision=value["sourceRevision"],
                payload_json=payload_json,
            )
            if decision == "insert":
                self._require_capacity(
                    connection,
                    table="approval_projections",
                    principal_id=actor.principal_id,
                    limit=self.capacities.approval_projections,
                )
                connection.execute(
                    """
                    INSERT INTO approval_projections(
                      approval_id, principal_id, owner_session_id, source_revision, operation_id,
                      capability, state, risk, summary, requested_at, expires_at, projected_at, payload_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        value["approvalId"],
                        actor.principal_id,
                        actor.session_id,
                        str(value["sourceRevision"]),
                        value["operationId"],
                        value["capability"],
                        value["state"],
                        value["risk"],
                        value["summary"],
                        value["requestedAt"],
                        value["expiresAt"],
                        current,
                        payload_json,
                    ),
                )
            elif decision == "update":
                connection.execute(
                    """
                    UPDATE approval_projections SET
                      owner_session_id = ?, source_revision = ?, operation_id = ?, capability = ?,
                      state = ?, risk = ?, summary = ?, requested_at = ?, expires_at = ?,
                      projected_at = ?, payload_json = ?
                    WHERE principal_id = ? AND approval_id = ?
                    """,
                    (
                        actor.session_id,
                        str(value["sourceRevision"]),
                        value["operationId"],
                        value["capability"],
                        value["state"],
                        value["risk"],
                        value["summary"],
                        value["requestedAt"],
                        value["expiresAt"],
                        current,
                        payload_json,
                        actor.principal_id,
                        value["approvalId"],
                    ),
                )
            row = connection.execute(
                "SELECT * FROM approval_projections WHERE principal_id = ? AND approval_id = ?",
                (actor.principal_id, value["approvalId"]),
            ).fetchone()
            result = self._approval_result(row)
            self._require_query_item_capacity("agent.approvals", result)
            if decision != "unchanged":
                self._append_event(connection, actor, topic="approval.projected", entity_id=value["approvalId"], payload={"approvalId": value["approvalId"], "state": value["state"]}, now=current)
            return result

    @staticmethod
    def _operation_result(row: Any) -> dict[str, Any]:
        payload = json.loads(row["payload_json"])
        return {
            "schemaVersion": "v0",
            "kind": "operation-link",
            "operationId": row["operation_id"],
            "owner": {"principalId": row["principal_id"], "sessionId": row["owner_session_id"]},
            "sourceRevision": int(row["source_revision"]),
            "legacyOwner": bool(payload.get("legacyOwner", False)),
            "taskId": row["task_id"],
            "runId": row["run_id"],
            "capability": row["capability"],
            "status": row["status"],
            "changeState": row["change_state"],
            "summary": row["summary"],
            "recoveryEligible": bool(row["recovery_eligible"]),
            "artifactIds": payload["artifactIds"],
            "createdAt": float(row["created_at"]),
            "updatedAt": float(row["updated_at"]),
            "projectedAt": float(row["projected_at"]),
        }

    def link_operation(self, actor: Actor, projection: Mapping[str, Any], *, now: float | None = None) -> dict[str, Any]:
        current = time.time() if now is None else timestamp(now, field="operation projection time")
        data = closed_object(
            projection,
            field="operation projection",
            required={
                "sourceRevision",
                "operationId",
                "taskId",
                "runId",
                "capability",
                "status",
                "changeState",
                "summary",
                "recoveryEligible",
                "artifactIds",
                "createdAt",
                "updatedAt",
            },
            optional={"legacyOwner"},
        )
        task_id = None if data["taskId"] is None else stable_id(data["taskId"], field="task ID")
        run_id = None if data["runId"] is None else stable_id(data["runId"], field="run ID")
        if task_id is None and run_id is not None:
            raise ManagedWorkError("operation.task", "A run-linked operation must also name its task.")
        artifacts = data["artifactIds"]
        if not isinstance(artifacts, list) or len(artifacts) > 128:
            raise ManagedWorkError("operation.artifacts", "Operation artifact IDs must be a bounded array.")
        artifact_ids = [stable_id(item, field="artifact ID") for item in artifacts]
        if len(set(artifact_ids)) != len(artifact_ids):
            raise ManagedWorkError("operation.artifacts", "Operation artifact IDs must be unique.")
        if not isinstance(data["recoveryEligible"], bool):
            raise ManagedWorkError("operation.recovery", "Operation recovery eligibility must be a boolean.")
        if not isinstance(data.get("legacyOwner", False), bool):
            raise ManagedWorkError("operation.legacy-owner", "Legacy owner provenance must be a boolean.")
        created = timestamp(data["createdAt"], field="operation creation time")
        updated = timestamp(data["updatedAt"], field="operation update time")
        if updated < created:
            raise ManagedWorkError("operation.time", "Operation update time precedes creation time.")
        value = {
            "sourceRevision": integer(data["sourceRevision"], field="source revision", minimum=1),
            "legacyOwner": data.get("legacyOwner", False),
            "operationId": opaque_id(data["operationId"], field="operation ID"),
            "taskId": task_id,
            "runId": run_id,
            "capability": stable_id(data["capability"], field="capability"),
            "status": enum_value(
                data["status"],
                field="operation status",
                choices=set(OPERATION_STATES),
            ),
            "changeState": enum_value(
                data["changeState"],
                field="operation change state",
                choices={"none", "partial", "complete", "unknown"},
            ),
            "summary": bounded_text(data["summary"], field="operation summary", maximum=2048),
            "recoveryEligible": data["recoveryEligible"],
            "artifactIds": artifact_ids,
            "createdAt": created,
            "updatedAt": updated,
        }
        reject_secret_fields({"value": value["summary"]}, field="operation summary")
        payload_json = canonical_json(value)
        with self.store.transaction() as connection:
            if task_id is not None:
                self._task_row(connection, actor, task_id)
            if run_id is not None:
                run = self._run_row(connection, actor, run_id)
                if run["task_id"] != task_id:
                    raise ManagedWorkError("operation.run-task", "Operation task and run links disagree.")
            for artifact_id in artifact_ids:
                artifact = connection.execute("SELECT principal_id FROM artifacts WHERE artifact_id = ?", (artifact_id,)).fetchone()
                if artifact is None or artifact["principal_id"] != actor.principal_id:
                    raise ManagedWorkError("access.denied", "An operation artifact is unavailable to this principal.")
            existing = connection.execute(
                "SELECT * FROM operation_links WHERE principal_id = ? AND operation_id = ?",
                (actor.principal_id, value["operationId"]),
            ).fetchone()
            decision = self._projection_decision(existing, source_revision=value["sourceRevision"], payload_json=payload_json)
            if decision == "insert":
                self._require_capacity(
                    connection,
                    table="operation_links",
                    principal_id=actor.principal_id,
                    limit=self.capacities.operation_links,
                )
                connection.execute(
                    """
                    INSERT INTO operation_links(
                      operation_id, principal_id, owner_session_id, source_revision, task_id, run_id,
                      capability, status, change_state, summary, recovery_eligible, created_at,
                      updated_at, projected_at, payload_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        value["operationId"],
                        actor.principal_id,
                        actor.session_id,
                        str(value["sourceRevision"]),
                        task_id,
                        run_id,
                        value["capability"],
                        value["status"],
                        value["changeState"],
                        value["summary"],
                        int(value["recoveryEligible"]),
                        created,
                        updated,
                        current,
                        payload_json,
                    ),
                )
            elif decision == "update":
                connection.execute(
                    """
                    UPDATE operation_links SET
                      owner_session_id = ?, source_revision = ?, task_id = ?, run_id = ?, capability = ?,
                      status = ?, change_state = ?, summary = ?, recovery_eligible = ?, created_at = ?,
                      updated_at = ?, projected_at = ?, payload_json = ?
                    WHERE principal_id = ? AND operation_id = ?
                    """,
                    (
                        actor.session_id,
                        str(value["sourceRevision"]),
                        task_id,
                        run_id,
                        value["capability"],
                        value["status"],
                        value["changeState"],
                        value["summary"],
                        int(value["recoveryEligible"]),
                        created,
                        updated,
                        current,
                        payload_json,
                        actor.principal_id,
                        value["operationId"],
                    ),
                )
            row = connection.execute(
                "SELECT * FROM operation_links WHERE principal_id = ? AND operation_id = ?",
                (actor.principal_id, value["operationId"]),
            ).fetchone()
            result = self._operation_result(row)
            self._require_query_item_capacity("agent.activity", result)
            if decision != "unchanged":
                self._append_event(connection, actor, topic="operation.projected", entity_id=value["operationId"], payload={"operationId": value["operationId"], "status": value["status"]}, now=current)
            return result

    def project_operation_inventory(
        self,
        actor: Actor,
        inventory: Sequence[tuple[Actor, Mapping[str, Any]]],
        *,
        source_capability: str,
        now: float | None = None,
    ) -> list[dict[str, Any]]:
        """Atomically project one bounded authoritative operation snapshot."""

        current = time.time() if now is None else timestamp(now, field="operation inventory time")
        if not isinstance(actor, Actor):
            raise ManagedWorkError("operation.inventory", "Operation inventory owner is invalid.")
        capability = stable_id(source_capability, field="operation inventory capability")
        if isinstance(inventory, (str, bytes, bytearray)) or not isinstance(inventory, Sequence):
            raise ManagedWorkError("operation.inventory", "Operation inventory must be a bounded array.")
        if len(inventory) > self.capacities.operation_links:
            raise ManagedWorkError("capacity.operation-links", "Operation inventory exceeds durable capacity.")
        identities: list[tuple[Actor, Mapping[str, Any], str]] = []
        seen: set[tuple[str, str]] = set()
        for index, item in enumerate(inventory):
            if not isinstance(item, tuple) or len(item) != 2:
                raise ManagedWorkError("operation.inventory", f"Operation inventory item {index} is malformed.")
            source_actor, projection = item
            if not isinstance(source_actor, Actor) or not isinstance(projection, Mapping):
                raise ManagedWorkError("operation.inventory", f"Operation inventory item {index} is malformed.")
            if source_actor.principal_id != actor.principal_id:
                raise ManagedWorkError(
                    "operation.inventory-owner",
                    "Operation inventory cannot cross its explicit stable owner boundary.",
                )
            if projection.get("capability") != capability:
                raise ManagedWorkError(
                    "operation.inventory-source",
                    "Operation inventory contains an item from another projection source family.",
                )
            operation_id = opaque_id(projection.get("operationId"), field="operation ID")
            identity = (source_actor.principal_id, operation_id)
            if identity in seen:
                raise ManagedWorkError("operation.inventory", "Operation inventory contains a duplicate identity.")
            seen.add(identity)
            identities.append((source_actor, projection, operation_id))
        results: list[dict[str, Any]] = []
        with self.store.transaction() as connection:
            existing_capabilities = {
                str(row["operation_id"]): str(row["capability"])
                for row in connection.execute(
                    "SELECT operation_id, capability FROM operation_links WHERE principal_id = ? LIMIT ?",
                    (actor.principal_id, self.capacities.operation_links + 1),
                ).fetchall()
            }
            all_existing = set(existing_capabilities)
            source_existing = {
                str(row["operation_id"])
                for row in connection.execute(
                    "SELECT operation_id FROM operation_links WHERE principal_id = ? AND capability = ? LIMIT ?",
                    (actor.principal_id, capability, self.capacities.operation_links + 1),
                ).fetchall()
            }
            incoming = {operation_id for _source_actor, _projection, operation_id in identities}
            if any(
                operation_id in existing_capabilities
                and existing_capabilities[operation_id] != capability
                for operation_id in incoming
            ):
                raise ManagedWorkError(
                    "operation.inventory-source-conflict",
                    "Operation inventory cannot replace an identity owned by another projection source family.",
                )
            prospective = (all_existing - source_existing) | incoming
            if (
                len(all_existing) > self.capacities.operation_links
                or len(source_existing) > self.capacities.operation_links
                or len(prospective) > self.capacities.operation_links
            ):
                raise ManagedWorkError(
                    "capacity.operation-links",
                    "Operation inventory and existing durable links exceed capacity.",
                )
            for source_actor, projection, _operation_id in identities:
                results.append(self.link_operation(source_actor, projection, now=current))
            missing = source_existing - incoming
            if missing:
                placeholders = ",".join("?" for _ in missing)
                connection.execute(
                    f"DELETE FROM operation_links WHERE principal_id = ? AND capability = ? AND operation_id IN ({placeholders})",
                    (actor.principal_id, capability, *sorted(missing)),
                )
        return results

    @staticmethod
    def _provider_result(row: Any) -> dict[str, Any]:
        return {
            "schemaVersion": "v0",
            "kind": "managed-provider-readiness",
            "providerId": row["provider_id"],
            "providerVersion": row["provider_version"],
            "sourceRevision": int(row["source_revision"]),
            "registryGeneration": int(row["registry_generation"]),
            "registrationOrder": int(row["registration_order"]),
            "installed": bool(row["installed"]),
            "available": bool(row["available"]),
            "state": row["state"],
            "code": row["code"],
            "explanation": row["explanation"],
            "registeredAt": float(row["registered_at"]),
            "changedAt": float(row["changed_at"]),
            "projectedAt": float(row["projected_at"]),
        }

    def project_provider_inventory(
        self,
        actor: Actor,
        catalog: Sequence[Mapping[str, Any]],
        *,
        now: float | None = None,
    ) -> list[dict[str, Any]]:
        """Persist one closed, monotonic projection of daemon registry truth.

        The caller is the daemon integration, not RPC.  The registry catalog is
        reduced to non-secret readiness fields before it reaches durable state.
        Revisions are owned by this projection and never trust registry counters
        that may restart from one after a daemon restart.
        """

        current = time.time() if now is None else timestamp(now, field="provider projection time")
        if isinstance(catalog, (str, bytes, bytearray)) or not isinstance(catalog, Sequence):
            raise ManagedWorkError("provider.catalog", "Provider inventory must be an array.")
        if len(catalog) > self.capacities.provider_projections:
            raise ManagedWorkError("capacity.provider-projections", "Provider inventory exceeds its durable capacity.")
        normalized: dict[str, dict[str, Any]] = {}
        for index, raw in enumerate(catalog):
            record = closed_object(
                raw,
                field=f"provider catalog item {index}",
                required={
                    "manifest",
                    "fingerprint",
                    "generation",
                    "registrationOrder",
                    "state",
                    "detail",
                    "registeredAt",
                    "changedAt",
                },
            )
            manifest = record["manifest"]
            if not isinstance(manifest, Mapping):
                raise ManagedWorkError("provider.manifest", "Provider manifest must be an object.")
            provider_id = stable_id(manifest.get("provider"), field="provider ID")
            provider_version = bounded_text(
                manifest.get("providerVersion"),
                field="provider version",
                maximum=64,
            )
            if _PROVIDER_VERSION_RE.fullmatch(provider_version) is None:
                raise ManagedWorkError("provider.version", "Provider version is malformed.")
            if provider_id in normalized:
                raise ManagedWorkError("provider.duplicate", "Provider inventory contains a duplicate provider ID.")
            registry_fingerprint = sha256_id(record["fingerprint"], field="provider fingerprint")
            generation = integer(record["generation"], field="registry generation", minimum=1)
            registration_order = integer(
                record["registrationOrder"],
                field="provider registration order",
                minimum=0,
                maximum=self.capacities.provider_projections - 1,
            )
            state = enum_value(
                record["state"],
                field="provider state",
                choices={"available", "degraded", "unavailable", "incompatible"},
            )
            detail = bounded_text(record["detail"], field="provider detail", maximum=4096, allow_empty=True)
            registered_at = timestamp(record["registeredAt"], field="provider registration time")
            changed_at = timestamp(record["changedAt"], field="provider change time")
            if changed_at < registered_at:
                raise ManagedWorkError("provider.time", "Provider change time precedes registration.")
            available = state in {"available", "degraded"}
            normalized[provider_id] = {
                "providerId": provider_id,
                "providerVersion": provider_version,
                "registryFingerprint": registry_fingerprint,
                "detailDigest": fingerprint(detail),
                "registryGeneration": generation,
                "registrationOrder": registration_order,
                "installed": True,
                "available": available,
                "state": state,
                "code": (
                    "provider.available"
                    if state == "available"
                    else "provider.degraded"
                    if state == "degraded"
                    else "provider.incompatible-version"
                    if state == "incompatible"
                    else "provider.unavailable"
                ),
                "explanation": (
                    "The provider is registered and its read capabilities are available."
                    if state == "available"
                    else "The provider is registered and usable, but reports degraded readiness."
                    if state == "degraded"
                    else "The provider is registered but currently unavailable."
                ),
                "registeredAt": registered_at,
                "changedAt": changed_at,
            }

        with self.store.transaction() as connection:
            existing_rows = {
                row["provider_id"]: row
                for row in connection.execute(
                    "SELECT * FROM provider_projections WHERE principal_id = ? ORDER BY provider_id",
                    (actor.principal_id,),
                ).fetchall()
            }
            if len(set(existing_rows) | set(normalized)) > self.capacities.provider_projections:
                raise ManagedWorkError("capacity.provider-projections", "Provider projections reached durable capacity.")
            for provider_id, value in normalized.items():
                payload_json = canonical_json(value)
                existing = existing_rows.get(provider_id)
                if existing is not None and existing["payload_json"] == payload_json:
                    continue
                source_revision = 1 if existing is None else int(existing["source_revision"]) + 1
                if existing is None:
                    connection.execute(
                        """
                        INSERT INTO provider_projections(
                          provider_id, principal_id, owner_session_id, source_revision,
                          provider_version, registry_generation, registration_order, installed, available, state,
                          code, explanation, registered_at, changed_at, projected_at, payload_json
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            provider_id,
                            actor.principal_id,
                            actor.session_id,
                            source_revision,
                            value["providerVersion"],
                            value["registryGeneration"],
                            value["registrationOrder"],
                            1,
                            int(value["available"]),
                            value["state"],
                            value["code"],
                            value["explanation"],
                            value["registeredAt"],
                            value["changedAt"],
                            current,
                            payload_json,
                        ),
                    )
                else:
                    connection.execute(
                        """
                        UPDATE provider_projections SET
                          owner_session_id = ?, source_revision = ?, provider_version = ?,
                          registry_generation = ?, registration_order = ?, installed = 1, available = ?, state = ?,
                          code = ?, explanation = ?, registered_at = ?, changed_at = ?,
                          projected_at = ?, payload_json = ?
                        WHERE principal_id = ? AND provider_id = ?
                        """,
                        (
                            actor.session_id,
                            source_revision,
                            value["providerVersion"],
                            value["registryGeneration"],
                            value["registrationOrder"],
                            int(value["available"]),
                            value["state"],
                            value["code"],
                            value["explanation"],
                            value["registeredAt"],
                            value["changedAt"],
                            current,
                            payload_json,
                            actor.principal_id,
                            provider_id,
                        ),
                    )

            missing = sorted(set(existing_rows) - set(normalized))
            for provider_id in missing:
                existing = existing_rows[provider_id]
                if existing["state"] == "not-registered":
                    continue
                try:
                    previous = json.loads(existing["payload_json"])
                except (json.JSONDecodeError, TypeError) as error:
                    raise ManagedWorkError(
                        "managed-work.database-corrupt",
                        "A durable provider projection contains malformed JSON.",
                        recovery_actions=("managed-work.restore-database",),
                    ) from error
                value = {
                    "providerId": provider_id,
                    "providerVersion": existing["provider_version"],
                    "registryFingerprint": previous["registryFingerprint"],
                    "detailDigest": previous["detailDigest"],
                    "registryGeneration": int(existing["registry_generation"]),
                    "registrationOrder": previous["registrationOrder"],
                    "installed": False,
                    "available": False,
                    "state": "not-registered",
                    "code": "provider.not-registered",
                    "explanation": "The provider is no longer registered with this daemon.",
                    "registeredAt": float(existing["registered_at"]),
                    "changedAt": current,
                }
                connection.execute(
                    """
                    UPDATE provider_projections SET
                      owner_session_id = ?, source_revision = source_revision + 1,
                      installed = 0, available = 0, state = 'not-registered',
                      code = ?, explanation = ?, changed_at = ?, projected_at = ?, payload_json = ?
                    WHERE principal_id = ? AND provider_id = ?
                    """,
                    (
                        actor.session_id,
                        value["code"],
                        value["explanation"],
                        current,
                        current,
                        canonical_json(value),
                        actor.principal_id,
                        provider_id,
                    ),
                )
            results = [
                self._provider_result(row)
                for row in connection.execute(
                    "SELECT * FROM provider_projections WHERE principal_id = ? ORDER BY provider_id",
                    (actor.principal_id,),
                ).fetchall()
            ]
            for result in results:
                self._require_query_item_capacity("agent.providers", result)
            return results

    @staticmethod
    def _permission_result(row: Any) -> dict[str, Any]:
        return {
            "schemaVersion": "v0",
            "kind": "permission-projection",
            "grantId": row["grant_id"],
            "owner": {"principalId": row["principal_id"], "sessionId": row["owner_session_id"]},
            "sourceRevision": int(row["source_revision"]),
            "capability": row["capability"],
            "resource": row["resource"],
            "state": row["state"],
            "riskCeiling": row["risk_ceiling"],
            "issuedAt": float(row["issued_at"]),
            "expiresAt": None if row["expires_at"] is None else float(row["expires_at"]),
            "projectedAt": float(row["projected_at"]),
        }

    def project_permission(self, actor: Actor, projection: Mapping[str, Any], *, now: float | None = None) -> dict[str, Any]:
        current = time.time() if now is None else timestamp(now, field="permission projection time")
        data = closed_object(
            projection,
            field="permission projection",
            required={
                "sourceRevision",
                "grantId",
                "capability",
                "resource",
                "state",
                "riskCeiling",
                "issuedAt",
                "expiresAt",
            },
        )
        expires = None if data["expiresAt"] is None else timestamp(data["expiresAt"], field="permission expiry")
        issued = timestamp(data["issuedAt"], field="permission issue time")
        if expires is not None and expires <= issued:
            raise ManagedWorkError("permission.expiry", "Permission expiry must follow its issue time.")
        value = {
            "sourceRevision": integer(data["sourceRevision"], field="source revision", minimum=1),
            "grantId": opaque_id(data["grantId"], field="grant ID"),
            "capability": stable_id(data["capability"], field="capability"),
            "resource": stable_id(data["resource"], field="resource"),
            "state": enum_value(data["state"], field="permission state", choices={"active", "revoked", "expired", "denied"}),
            "riskCeiling": enum_value(data["riskCeiling"], field="risk ceiling", choices={"low", "consequential"}),
            "issuedAt": issued,
            "expiresAt": expires,
        }
        if value["riskCeiling"] == "consequential" and value["capability"] == "managed.high-risk":
            raise ManagedWorkError("permission.high-risk", "Persistent high-risk automation grants are forbidden.")
        payload_json = canonical_json(value)
        with self.store.transaction() as connection:
            existing = connection.execute(
                "SELECT * FROM permission_projections WHERE principal_id = ? AND grant_id = ?",
                (actor.principal_id, value["grantId"]),
            ).fetchone()
            decision = self._projection_decision(existing, source_revision=value["sourceRevision"], payload_json=payload_json)
            if decision == "insert":
                self._require_capacity(
                    connection,
                    table="permission_projections",
                    principal_id=actor.principal_id,
                    limit=self.capacities.permission_projections,
                )
                connection.execute(
                    """
                    INSERT INTO permission_projections(
                      grant_id, principal_id, owner_session_id, source_revision, capability, resource,
                      state, risk_ceiling, issued_at, expires_at, projected_at, payload_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        value["grantId"],
                        actor.principal_id,
                        actor.session_id,
                        str(value["sourceRevision"]),
                        value["capability"],
                        value["resource"],
                        value["state"],
                        value["riskCeiling"],
                        issued,
                        expires,
                        current,
                        payload_json,
                    ),
                )
            elif decision == "update":
                connection.execute(
                    """
                    UPDATE permission_projections SET
                      owner_session_id = ?, source_revision = ?, capability = ?, resource = ?, state = ?,
                      risk_ceiling = ?, issued_at = ?, expires_at = ?, projected_at = ?, payload_json = ?
                    WHERE principal_id = ? AND grant_id = ?
                    """,
                    (
                        actor.session_id,
                        str(value["sourceRevision"]),
                        value["capability"],
                        value["resource"],
                        value["state"],
                        value["riskCeiling"],
                        issued,
                        expires,
                        current,
                        payload_json,
                        actor.principal_id,
                        value["grantId"],
                    ),
                )
            row = connection.execute(
                "SELECT * FROM permission_projections WHERE principal_id = ? AND grant_id = ?",
                (actor.principal_id, value["grantId"]),
            ).fetchone()
            result = self._permission_result(row)
            self._require_query_item_capacity("agent.permissions", result)
            if decision != "unchanged":
                self._append_event(connection, actor, topic="permission.projected", entity_id=value["grantId"], payload={"grantId": value["grantId"], "state": value["state"]}, now=current)
            return result

    @staticmethod
    def _usage_result(row: Any) -> dict[str, Any]:
        return {
            "schemaVersion": "v0",
            "kind": "usage-record",
            "usageId": row["usage_id"],
            "owner": {"principalId": row["principal_id"], "sessionId": row["owner_session_id"]},
            "taskId": row["task_id"],
            "runId": row["run_id"],
            "provider": row["provider"],
            "metric": row["metric"],
            "quantity": float(row["quantity"]),
            "unit": row["unit"],
            "costMicrounits": int(row["cost_microunits"]),
            "recordedAt": float(row["recorded_at"]),
        }

    def record_usage(self, actor: Actor, record: Mapping[str, Any]) -> dict[str, Any]:
        data = closed_object(
            record,
            field="usage record",
            required={
                "usageId",
                "taskId",
                "runId",
                "provider",
                "metric",
                "quantity",
                "unit",
                "costMicrounits",
                "recordedAt",
            },
        )
        task_id = None if data["taskId"] is None else stable_id(data["taskId"], field="task ID")
        run_id = None if data["runId"] is None else stable_id(data["runId"], field="run ID")
        if run_id is not None and task_id is None:
            raise ManagedWorkError("usage.task", "Run usage must also name its task.")
        value = {
            "usageId": opaque_id(data["usageId"], field="usage ID"),
            "taskId": task_id,
            "runId": run_id,
            "provider": stable_id(data["provider"], field="usage provider"),
            "metric": stable_id(data["metric"], field="usage metric"),
            "quantity": finite_number(data["quantity"], field="usage quantity", minimum=0, maximum=1e18),
            "unit": stable_id(data["unit"], field="usage unit"),
            "costMicrounits": integer(data["costMicrounits"], field="usage cost", minimum=0, maximum=10**15),
            "recordedAt": timestamp(data["recordedAt"], field="usage time"),
        }
        payload_json = canonical_json(value)
        with self.store.transaction() as connection:
            if task_id is not None:
                self._task_row(connection, actor, task_id)
            if run_id is not None:
                run = self._run_row(connection, actor, run_id)
                if run["task_id"] != task_id:
                    raise ManagedWorkError("usage.run-task", "Usage task and run links disagree.")
            existing = connection.execute(
                "SELECT * FROM usage_records WHERE principal_id = ? AND usage_id = ?",
                (actor.principal_id, value["usageId"]),
            ).fetchone()
            if existing is not None:
                if existing["payload_json"] != payload_json:
                    raise ManagedWorkError("usage.conflict", "The usage ID already records different usage.")
                return self._usage_result(existing)
            self._require_capacity(
                connection,
                table="usage_records",
                principal_id=actor.principal_id,
                limit=self.capacities.usage_records,
            )
            connection.execute(
                """
                INSERT INTO usage_records(
                  usage_id, principal_id, owner_session_id, task_id, run_id, provider, metric,
                  quantity, unit, cost_microunits, recorded_at, payload_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    value["usageId"],
                    actor.principal_id,
                    actor.session_id,
                    task_id,
                    run_id,
                    value["provider"],
                    value["metric"],
                    value["quantity"],
                    value["unit"],
                    value["costMicrounits"],
                    value["recordedAt"],
                    payload_json,
                ),
            )
            row = connection.execute(
                "SELECT * FROM usage_records WHERE principal_id = ? AND usage_id = ?",
                (actor.principal_id, value["usageId"]),
            ).fetchone()
            result = self._usage_result(row)
            self._require_query_item_capacity("agent.usage", result)
            return result

    @staticmethod
    def _artifact_result(row: Any) -> dict[str, Any]:
        return {
            "schemaVersion": "v0",
            "kind": "managed-artifact",
            "artifactId": row["artifact_id"],
            "owner": {"principalId": row["principal_id"], "sessionId": row["owner_session_id"]},
            "taskId": row["task_id"],
            "runId": row["run_id"],
            "handle": row["handle"],
            "label": row["label"],
            "mediaType": row["media_type"],
            "byteLength": int(row["byte_length"]),
            "contentHash": row["content_hash"],
            "scope": row["scope"],
            "createdAt": float(row["created_at"]),
        }

    def register_artifact(
        self,
        actor: Actor,
        *,
        task_id: str,
        run_id: str | None,
        handle: str,
        label: str,
        media_type: str,
        byte_length: int,
        content_hash: str,
        scope: str,
        idempotency_key: str,
        now: float | None = None,
    ) -> dict[str, Any]:
        current = time.time() if now is None else timestamp(now, field="artifact creation time")
        stable_id(task_id, field="task ID")
        if run_id is not None:
            stable_id(run_id, field="run ID")
        handle_value = stable_id(handle, field="artifact handle")
        label_value = bounded_text(label, field="artifact label", maximum=512)
        reject_secret_fields({"value": label_value}, field="artifact label")
        media_value = bounded_text(media_type, field="artifact media type", maximum=256)
        if not _MEDIA_TYPE_RE.fullmatch(media_value):
            raise ManagedWorkError("artifact.media-type", "Artifact media type must be a MIME type.")
        length_value = integer(byte_length, field="artifact byte length", minimum=0, maximum=10 * 1024**3)
        hash_value = sha256_id(content_hash, field="artifact content hash")
        scope_value = enum_value(scope, field="artifact scope", choices={"task", "principal"})
        key = self._require_idempotency_key(idempotency_key)
        request = {
            "taskId": task_id,
            "runId": run_id,
            "handle": handle_value,
            "label": label_value,
            "mediaType": media_value,
            "byteLength": length_value,
            "contentHash": hash_value,
            "scope": scope_value,
        }
        with self.store.transaction() as connection:
            existing_result = self._claim_idempotency(connection, actor, action="artifact.register", key=key, request=request, now=current)
            if existing_result is not None:
                return existing_result
            self._require_capacity(
                connection,
                table="artifacts",
                principal_id=actor.principal_id,
                limit=self.capacities.artifacts,
            )
            self._task_row(connection, actor, task_id)
            if run_id is not None:
                run = self._run_row(connection, actor, run_id)
                if run["task_id"] != task_id:
                    raise ManagedWorkError("artifact.run-task", "Artifact task and run links disagree.")
            artifact_id = _new_id("artifact")
            connection.execute(
                """
                INSERT INTO artifacts(
                  artifact_id, principal_id, owner_session_id, task_id, run_id, handle, label,
                  media_type, byte_length, content_hash, scope, created_at, payload_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    artifact_id,
                    actor.principal_id,
                    actor.session_id,
                    task_id,
                    run_id,
                    handle_value,
                    label_value,
                    media_value,
                    length_value,
                    hash_value,
                    scope_value,
                    current,
                    canonical_json(request),
                ),
            )
            row = connection.execute("SELECT * FROM artifacts WHERE artifact_id = ?", (artifact_id,)).fetchone()
            result = self._artifact_result(row)
            self._require_query_item_capacity("agent.artifacts", result)
            self._append_event(connection, actor, topic="artifact.registered", entity_id=artifact_id, payload={"artifactId": artifact_id, "taskId": task_id}, now=current)
            self._finish_idempotency(connection, actor, action="artifact.register", key=key, result=result, now=current)
            return result

    @staticmethod
    def _event_result(row: Any) -> dict[str, Any]:
        return {
            "schemaVersion": "v0",
            "kind": "managed-work-event",
            "eventId": row["event_id"],
            "topic": row["topic"],
            "entityId": row["entity_id"],
            "payload": json.loads(row["payload_json"]),
            "createdAt": float(row["created_at"]),
        }

    @staticmethod
    def _run_step_record() -> tuple[str, dict[str, Any]]:
        status = ManagedWorkPlane.execution_status()
        if status["available"]:
            return "planned", {"code": status["code"]}
        return "blocked-unavailable", {"code": status["code"]}

    @staticmethod
    def _query_availability(*, available: bool = True, code: str = "managed-work.query-ready") -> dict[str, Any]:
        return {
            "available": available,
            "code": code,
            "executionAvailable": bool(ManagedWorkPlane.execution_status()["available"]),
        }

    @staticmethod
    def _capacity_cursor(view: str) -> str | None:
        if view in {"agent.overview", "agent.troubleshooting"}:
            return None
        maximum_identity = "p" * 160
        maximum_integer = 2**53 - 1
        if view == "agent.providers":
            return encode_ordered_cursor(
                view=view,
                principal_id=maximum_identity,
                row_id=maximum_integer,
                order=maximum_integer,
                entity_id=maximum_identity,
            )
        return encode_cursor(
            view=view,
            principal_id=maximum_identity,
            row_id=maximum_integer,
        )

    @staticmethod
    def _require_query_item_capacity(
        view: str,
        item: Mapping[str, Any],
        *,
        summary: Mapping[str, Any] | None = None,
    ) -> None:
        try:
            ManagedWorkPlane._finish_query(
                view=view,
                items=[dict(item)],
                next_cursor=ManagedWorkPlane._capacity_cursor(view),
                summary=summary,
            )
        except ManagedWorkError as error:
            if error.code != "query.result-capacity":
                raise
            raise ManagedWorkError(
                "validation.query-item-capacity",
                "The record cannot be persisted because one closed query item would exceed the Fabric frame budget.",
            ) from error

    @staticmethod
    def _finish_query(
        *,
        view: str,
        items: list[dict[str, Any]],
        next_cursor: str | None,
        available: bool = True,
        code: str = "managed-work.query-ready",
        summary: Mapping[str, Any] | None = None,
    ) -> dict[str, Any]:
        result = {
            "schemaVersion": "v0",
            "kind": "agent-center-query",
            "view": view,
            "items": items,
            "nextCursor": next_cursor,
            "partial": False,
            "availability": ManagedWorkPlane._query_availability(available=available, code=code),
            "summary": dict(summary or {}),
        }
        try:
            encoded = json.dumps(
                result,
                ensure_ascii=False,
                allow_nan=False,
                separators=(",", ":"),
                sort_keys=True,
            ).encode("utf-8")
        except (TypeError, ValueError) as error:
            raise ManagedWorkError("query.result", "The query produced invalid JSON.") from error
        if len(encoded) > MAX_QUERY_RESPONSE_BYTES:
            raise ManagedWorkError(
                "query.result-capacity",
                "The bounded query response does not fit one Fabric RPC frame; request a smaller page.",
                retryable=True,
            )
        return result

    @staticmethod
    def _page(
        connection: Any,
        *,
        table: str,
        principal_id: str,
        view: str,
        limit: int,
        cursor: str | None,
        where: str = "1 = 1",
        parameters: Sequence[Any] = (),
    ) -> tuple[list[Any], str | None]:
        allowed = {
            "tasks",
            "approval_projections",
            "automations",
            "operation_links",
            "managed_events",
            "contexts",
            "permission_projections",
            "usage_records",
            "artifacts",
            "provider_projections",
        }
        if table not in allowed:
            raise RuntimeError("unapproved query table")
        clauses = ["principal_id = ?", where]
        values: list[Any] = [principal_id, *parameters]
        if cursor is not None:
            row_id = decode_cursor(cursor, view=view, principal_id=principal_id)
            clauses.append("row_id < ?")
            values.append(row_id)
        values.append(limit + 1)
        rows = connection.execute(
            f"SELECT * FROM {table} WHERE {' AND '.join(clauses)} ORDER BY row_id DESC LIMIT ?",
            values,
        ).fetchall()
        has_more = len(rows) > limit
        selected = list(rows[:limit])
        next_cursor = None
        if has_more and selected:
            next_cursor = encode_cursor(view=view, principal_id=principal_id, row_id=int(selected[-1]["row_id"]))
        return selected, next_cursor

    @staticmethod
    def _provider_page(
        connection: Any,
        *,
        principal_id: str,
        view: str,
        limit: int,
        cursor: str | None,
    ) -> tuple[list[Any], str | None]:
        parameters: list[Any] = [principal_id]
        continuation = ""
        if cursor is not None:
            try:
                _row_id, order, provider_id = decode_ordered_cursor(
                    cursor,
                    view=view,
                    principal_id=principal_id,
                )
            except ManagedWorkError:
                legacy_row_id = decode_cursor(cursor, view=view, principal_id=principal_id)
                legacy = connection.execute(
                    "SELECT registration_order, provider_id FROM provider_projections WHERE principal_id = ? AND row_id = ?",
                    (principal_id, legacy_row_id),
                ).fetchone()
                if legacy is None:
                    raise ManagedWorkError("query.cursor", "The provider cursor no longer identifies an owned row.")
                order = int(legacy["registration_order"])
                provider_id = str(legacy["provider_id"])
            continuation = "AND (registration_order > ? OR (registration_order = ? AND provider_id > ?))"
            parameters.extend((order, order, provider_id))
        parameters.append(limit + 1)
        rows = connection.execute(
            f"""
            SELECT * FROM provider_projections
            WHERE principal_id = ? {continuation}
            ORDER BY registration_order, provider_id
            LIMIT ?
            """,
            parameters,
        ).fetchall()
        has_more = len(rows) > limit
        selected = list(rows[:limit])
        next_cursor = None
        if has_more and selected:
            final = selected[-1]
            next_cursor = encode_ordered_cursor(
                view=view,
                principal_id=principal_id,
                row_id=int(final["row_id"]),
                order=int(final["registration_order"]),
                entity_id=str(final["provider_id"]),
            )
        return selected, next_cursor

    def _query_overview(self, actor: Actor, *, now: float) -> dict[str, Any]:
        connection = self.store.require_connection()
        active_tasks = int(
            connection.execute(
                "SELECT COUNT(*) FROM tasks WHERE principal_id = ? AND state NOT IN ('succeeded', 'failed', 'cancelled')",
                (actor.principal_id,),
            ).fetchone()[0]
        )
        pending_approvals = int(
            connection.execute(
                "SELECT COUNT(*) FROM approval_projections WHERE principal_id = ? AND state = 'pending' AND expires_at > ?",
                (actor.principal_id, now),
            ).fetchone()[0]
        )
        enabled_automations = int(
            connection.execute(
                "SELECT COUNT(*) FROM automations WHERE principal_id = ? AND state = 'enabled'",
                (actor.principal_id,),
            ).fetchone()[0]
        )
        pending_firings = int(
            connection.execute(
                "SELECT COUNT(*) FROM automation_firings WHERE principal_id = ? AND state = 'pending-unavailable'",
                (actor.principal_id,),
            ).fetchone()[0]
        )
        live_contexts = int(
            connection.execute(
                "SELECT COUNT(*) FROM contexts WHERE principal_id = ? AND revoked_at IS NULL AND expires_at > ?",
                (actor.principal_id, now),
            ).fetchone()[0]
        )
        summary = {
            "activeTasks": active_tasks,
            "pendingApprovals": pending_approvals,
            "enabledAutomations": enabled_automations,
            "pendingUnavailableFirings": pending_firings,
            "liveContexts": live_contexts,
            "execution": self.execution_status(),
        }
        return self._finish_query(view="agent.overview", items=[], next_cursor=None, summary=summary)

    def _query_troubleshooting(self, actor: Actor) -> dict[str, Any]:
        connection = self.store.require_connection()
        tables = (
            "contexts",
            "tasks",
            "runs",
            "automations",
            "automation_firings",
            "approval_projections",
            "operation_links",
            "permission_projections",
            "usage_records",
            "artifacts",
            "idempotency",
            "managed_events",
            "provider_projections",
        )
        counts = {
            table: int(connection.execute(f"SELECT COUNT(*) FROM {table} WHERE principal_id = ?", (actor.principal_id,)).fetchone()[0])
            for table in tables
        }
        history_pruned = connection.execute(
            "SELECT value FROM managed_metadata WHERE key = ?",
            (f"history_pruned_through.{actor.principal_id}",),
        ).fetchone()
        item = {
            "schemaVersion": "v0",
            "kind": "managed-work-diagnostics",
            "databaseSchema": self.store.schema_version(),
            "databaseIntegrity": self.store.quick_check(),
            "foreignKeyViolations": self.store.foreign_key_violations(),
            "restartRecoveries": self.store.restart_recoveries,
            "historyPrunedThrough": 0 if history_pruned is None else int(history_pruned["value"]),
            "ownerCounts": counts,
            "capacities": dict(self.capacities.__dict__),
            "execution": self.execution_status(),
            "recoveryActions": ["managed-work.reconcile", "managed-work.export-diagnostics"],
        }
        return self._finish_query(view="agent.troubleshooting", items=[item], next_cursor=None)

    def query(
        self,
        actor: Actor,
        view: str,
        *,
        limit: int = 50,
        cursor: str | None = None,
        entity_type: str | None = None,
        entity_id: str | None = None,
        now: float | None = None,
    ) -> dict[str, Any]:
        normalized = self.normalize_query_arguments(
            actor,
            view,
            limit=limit,
            cursor=cursor,
            entity_type=entity_type,
            entity_id=entity_id,
        )
        return self.query_normalized(actor, normalized, now=now)

    def query_normalized(
        self,
        actor: Actor,
        normalized: NormalizedQuery,
        *,
        now: float | None = None,
    ) -> dict[str, Any]:
        if not isinstance(actor, Actor) or not isinstance(normalized, NormalizedQuery):
            raise ManagedWorkError("query.arguments", "The normalized query contract is invalid.")
        with self.store.read():
            try:
                return self._query_normalized_locked(
                    actor,
                    normalized,
                    now=now,
                )
            except ManagedWorkError:
                raise
            except (json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
                raise ManagedWorkError(
                    "managed-work.database-corrupt",
                    "Managed work refused malformed durable query state.",
                    detail=type(error).__name__,
                    recovery_actions=("managed-work.restore-database",),
                ) from error

    def normalize_query_arguments(
        self,
        actor: Actor,
        view: Any,
        *,
        limit: Any = 50,
        cursor: Any = None,
        entity_type: Any = None,
        entity_id: Any = None,
        present_fields: frozenset[str] | None = None,
    ) -> NormalizedQuery:
        """Purely validate and normalize one closed Agent Center read request."""

        if not isinstance(actor, Actor):
            raise ManagedWorkError("query.actor", "The query actor is invalid.")
        if present_fields is not None:
            if not isinstance(present_fields, frozenset) or not all(
                isinstance(field, str) for field in present_fields
            ):
                raise ManagedWorkError("query.arguments", "The query field set is invalid.")
            for field, value in (
                ("cursor", cursor),
                ("entityType", entity_type),
                ("entityId", entity_id),
            ):
                if field in present_fields and value is None:
                    raise ManagedWorkError(
                        "query.arguments",
                        f"{field} cannot be explicitly null.",
                    )
        view_value = enum_value(view, field="Agent Center view", choices=set(self.QUERY_VIEWS))
        limit_value = integer(limit, field="page size", minimum=1, maximum=self.capacities.page_size)
        if (entity_type is None) != (entity_id is None):
            raise ManagedWorkError("query.entity", "Entity type and ID must be supplied together.")
        entity_type_value = entity_type
        entity_id_value = entity_id
        if entity_type_value is not None:
            entity_type_value = enum_value(
                entity_type_value,
                field="entity type",
                choices={"task", "run", "operation", "provider"},
            )
            entity_id_value = opaque_id(entity_id_value, field="entity ID")
            if cursor is not None:
                raise ManagedWorkError("query.cursor", "Entity queries do not accept pagination cursors.")
        if view_value in {"agent.overview", "agent.troubleshooting"}:
            if cursor is not None or entity_type_value is not None:
                raise ManagedWorkError("query.arguments", f"{view_value} does not accept a cursor or entity selector.")
        elif view_value == "agent.providers":
            if entity_type_value is not None and entity_type_value != "provider":
                raise ManagedWorkError("query.entity", "The provider route accepts only provider entities.")
            if entity_id_value is not None:
                stable_id(entity_id_value, field="provider ID")
        elif view_value == "agent.tasks":
            if entity_type_value is not None and entity_type_value not in {"task", "run"}:
                raise ManagedWorkError("query.entity", "The tasks route accepts only task or run entities.")
        elif view_value == "agent.activity":
            if entity_type_value is not None and entity_type_value != "operation":
                raise ManagedWorkError("query.entity", "The activity route accepts only operation entities.")
        elif entity_type_value is not None:
            raise ManagedWorkError("query.entity", "This Agent Center route has no entity selector.")
        if cursor is not None:
            if view_value == "agent.providers":
                try:
                    decode_ordered_cursor(cursor, view=view_value, principal_id=actor.principal_id)
                except ManagedWorkError as ordered_error:
                    try:
                        decode_cursor(cursor, view=view_value, principal_id=actor.principal_id)
                    except ManagedWorkError as legacy_error:
                        raise ManagedWorkError(
                            "query.cursor",
                            "The pagination cursor is malformed or belongs to another view.",
                        ) from legacy_error
            else:
                decode_cursor(cursor, view=view_value, principal_id=actor.principal_id)
        return NormalizedQuery(
            view=view_value,
            limit=limit_value,
            cursor=cursor,
            entity_type=entity_type_value,
            entity_id=entity_id_value,
        )

    def _query_normalized_locked(
        self,
        actor: Actor,
        normalized: NormalizedQuery,
        *,
        now: float | None = None,
    ) -> dict[str, Any]:
        current = time.time() if now is None else timestamp(now, field="query time")
        view_value = normalized.view
        limit_value = normalized.limit
        cursor = normalized.cursor
        entity_type = normalized.entity_type
        entity_id = normalized.entity_id
        if view_value == "agent.overview":
            if cursor is not None or entity_type is not None:
                raise ManagedWorkError("query.arguments", "Overview does not accept a cursor or entity selector.")
            return self._query_overview(actor, now=current)
        if view_value == "agent.troubleshooting":
            if cursor is not None or entity_type is not None:
                raise ManagedWorkError("query.arguments", "Troubleshooting does not accept a cursor or entity selector.")
            return self._query_troubleshooting(actor)
        connection = self.store.require_connection()
        if view_value == "agent.providers":
            if entity_type is not None and entity_type != "provider":
                raise ManagedWorkError("query.entity", "The provider route accepts only provider entities.")
            if entity_id is not None:
                stable_id(entity_id, field="provider ID")
                if cursor is not None:
                    raise ManagedWorkError("query.cursor", "Provider entity queries do not accept a cursor.")
                row = connection.execute(
                    "SELECT * FROM provider_projections WHERE principal_id = ? AND provider_id = ?",
                    (actor.principal_id, entity_id),
                ).fetchone()
                return self._finish_query(
                    view=view_value,
                    items=[] if row is None else [self._provider_result(row)],
                    next_cursor=None,
                    available=row is not None,
                    code="provider.unavailable" if row is None else "managed-work.query-ready",
                )
            rows, next_cursor = self._provider_page(
                connection,
                principal_id=actor.principal_id,
                view=view_value,
                limit=limit_value,
                cursor=cursor,
            )
            return self._finish_query(
                view=view_value,
                items=[self._provider_result(row) for row in rows],
                next_cursor=next_cursor,
            )
        if view_value == "agent.tasks" and entity_type is not None:
            if entity_type == "task":
                stable_id(entity_id, field="task ID")
                task = self._task_row(connection, actor, entity_id)
                latest = connection.execute(
                    "SELECT * FROM runs WHERE task_id = ? AND principal_id = ? ORDER BY row_id DESC LIMIT 1",
                    (entity_id, actor.principal_id),
                ).fetchone()
                item = {
                    "entityType": "task",
                    "task": self._task_result(task),
                    "run": None
                    if latest is None
                    else self._run_result(
                        latest,
                        self._steps_for_run(connection, latest["run_id"], actor.principal_id),
                    ),
                }
            elif entity_type == "run":
                stable_id(entity_id, field="run ID")
                item = {"entityType": "run", "task": None, "run": self.get_run(actor, entity_id)}
            else:
                raise ManagedWorkError("query.entity", "The tasks route accepts only task or run entities.")
            return self._finish_query(view=view_value, items=[item], next_cursor=None)
        if view_value == "agent.activity" and entity_type is not None:
            if entity_type != "operation":
                raise ManagedWorkError("query.entity", "The activity route accepts only operation entities.")
            row = connection.execute(
                "SELECT * FROM operation_links WHERE principal_id = ? AND operation_id = ?",
                (actor.principal_id, entity_id),
            ).fetchone()
            if row is None:
                raise ManagedWorkError("access.denied", "The operation is unavailable to this principal.")
            return self._finish_query(view=view_value, items=[self._operation_result(row)], next_cursor=None)
        if entity_type is not None:
            raise ManagedWorkError("query.entity", "This Agent Center route has no entity selector.")

        if view_value == "agent.tasks":
            rows, next_cursor = self._page(
                connection,
                table="tasks",
                principal_id=actor.principal_id,
                view=view_value,
                limit=limit_value,
                cursor=cursor,
            )
            items: list[dict[str, Any]] = []
            for row in rows:
                latest = connection.execute(
                    "SELECT * FROM runs WHERE task_id = ? AND principal_id = ? ORDER BY row_id DESC LIMIT 1",
                    (row["task_id"], actor.principal_id),
                ).fetchone()
                items.append(
                    {
                        "entityType": "task",
                        "task": self._task_result(row),
                        "run": None
                        if latest is None
                        else self._run_result(
                            latest,
                            self._steps_for_run(connection, latest["run_id"], actor.principal_id),
                        ),
                    }
                )
            return self._finish_query(view=view_value, items=items, next_cursor=next_cursor)
        if view_value == "agent.approvals":
            rows, next_cursor = self._page(
                connection,
                table="approval_projections",
                principal_id=actor.principal_id,
                view=view_value,
                limit=limit_value,
                cursor=cursor,
                where="state = 'pending' AND expires_at > ?",
                parameters=(current,),
            )
            return self._finish_query(
                view=view_value,
                items=[self._approval_result(row) for row in rows],
                next_cursor=next_cursor,
            )
        if view_value == "agent.automations":
            rows, next_cursor = self._page(
                connection,
                table="automations",
                principal_id=actor.principal_id,
                view=view_value,
                limit=limit_value,
                cursor=cursor,
            )
            return self._finish_query(
                view=view_value,
                items=[
                    self._automation_result(
                        row,
                        self._firings_for_automation(
                            connection,
                            row["automation_id"],
                            actor.principal_id,
                            limit=5,
                        ),
                    )
                    for row in rows
                ],
                next_cursor=next_cursor,
            )
        if view_value == "agent.activity":
            rows, next_cursor = self._page(
                connection,
                table="operation_links",
                principal_id=actor.principal_id,
                view=view_value,
                limit=limit_value,
                cursor=cursor,
            )
            return self._finish_query(view=view_value, items=[self._operation_result(row) for row in rows], next_cursor=next_cursor)
        if view_value == "agent.history":
            history_pruned = connection.execute(
                "SELECT value FROM managed_metadata WHERE key = ?",
                (f"history_pruned_through.{actor.principal_id}",),
            ).fetchone()
            pruned_through = 0 if history_pruned is None else int(history_pruned["value"])
            if cursor is not None and decode_cursor(
                cursor,
                view=view_value,
                principal_id=actor.principal_id,
            ) <= pruned_through:
                raise ManagedWorkError(
                    "query.cursor-expired",
                    "The managed-work history cursor was pruned; refresh the view.",
                )
            rows, next_cursor = self._page(
                connection,
                table="managed_events",
                principal_id=actor.principal_id,
                view=view_value,
                limit=limit_value,
                cursor=cursor,
            )
            return self._finish_query(
                view=view_value,
                items=[self._event_result(row) for row in rows],
                next_cursor=next_cursor,
                summary={"prunedThrough": pruned_through},
            )
        if view_value == "agent.context":
            rows, next_cursor = self._page(
                connection,
                table="contexts",
                principal_id=actor.principal_id,
                view=view_value,
                limit=limit_value,
                cursor=cursor,
                where="(access_scope != 'session' OR owner_session_id = ?)",
                parameters=(actor.session_id,),
            )
            return self._finish_query(view=view_value, items=[self._context_result(row) for row in rows], next_cursor=next_cursor)
        if view_value == "agent.permissions":
            rows, next_cursor = self._page(
                connection,
                table="permission_projections",
                principal_id=actor.principal_id,
                view=view_value,
                limit=limit_value,
                cursor=cursor,
            )
            return self._finish_query(view=view_value, items=[self._permission_result(row) for row in rows], next_cursor=next_cursor)
        if view_value == "agent.usage":
            rows, next_cursor = self._page(
                connection,
                table="usage_records",
                principal_id=actor.principal_id,
                view=view_value,
                limit=limit_value,
                cursor=cursor,
            )
            aggregate = connection.execute(
                "SELECT COALESCE(SUM(cost_microunits), 0), COUNT(*) FROM usage_records WHERE principal_id = ?",
                (actor.principal_id,),
            ).fetchone()
            return self._finish_query(
                view=view_value,
                items=[self._usage_result(row) for row in rows],
                next_cursor=next_cursor,
                summary={"costMicrounits": int(aggregate[0]), "recordCount": int(aggregate[1])},
            )
        if view_value == "agent.artifacts":
            rows, next_cursor = self._page(
                connection,
                table="artifacts",
                principal_id=actor.principal_id,
                view=view_value,
                limit=limit_value,
                cursor=cursor,
            )
            return self._finish_query(view=view_value, items=[self._artifact_result(row) for row in rows], next_cursor=next_cursor)
        raise AssertionError("unhandled Agent Center view")
