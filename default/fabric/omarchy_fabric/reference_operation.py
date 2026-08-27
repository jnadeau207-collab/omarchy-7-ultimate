"""Hermetic consequential reference operation for the provisional Fabric.

This module joins the existing owner-scoped daemon, Trust Plane, durable event
stream, and SQLite state through one deliberately fake provider.  It is a
production-shaped contract exerciser, not a host settings implementation.
"""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import re
import sqlite3
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Mapping

from .db import FabricDatabase, canonical_json, request_fingerprint
from .events import EventBroker
from .models import FabricError
from .security import (
    ApprovalAuthority,
    EndpointPrincipal,
    OperationRequest,
    PolicyEngine,
    ResourceRef,
    RiskLevel,
)
from .security.errors import SecurityValidationError

REFERENCE_PROVIDER_ID = "fake.reference-settings"
REFERENCE_PROVIDER_VERSION = "v0"
REFERENCE_CAPABILITY = "reference.setting.apply"
REFERENCE_RESOURCE_KIND = "reference-setting"

_UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_STABLE_RE = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$")
_IDEMPOTENCY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$")
_RECOVERY_TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{43}$")
_TERMINAL_STATUSES = frozenset({"succeeded", "recovered", "failed", "cancelled"})
_ACTIVE_STATUSES = frozenset({"queued", "running", "reconciling"})
_MAX_LEDGER_ENTRIES = 128
_MAX_LEDGER_PAGE_ENTRIES = 8
_MAX_PROJECTION_SOURCES = 256
_MAX_APPROVAL_ISSUES = 4
_ZERO_HASH = "0" * 64
_EVIDENCE_FAILURE_CODES = frozenset({"ledger.capacity-exhausted", "ledger.integrity-failed"})
_UPDATE_FIELDS = frozenset(
    {
        "status",
        "checkpoint",
        "progress",
        "cancellation_requested",
        "approval_id",
        "approval_binding_digest",
        "correlation_nonce",
        "authorization_code",
        "error_json",
        "result_json",
        "ledger_entry_count",
        "ledger_head_hash",
        "updated_at",
    }
)


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _operation_id(value: Any) -> str:
    if not isinstance(value, str) or _UUID_RE.fullmatch(value) is None:
        raise FabricError(
            "rpc.invalid-params",
            "Reference operation parameters are invalid",
            "operationId must be a lowercase UUID.",
        )
    return value


def _stable_resource_id(value: Any) -> str:
    if (
        not isinstance(value, str)
        or len(value) > 160
        or _STABLE_RE.fullmatch(value) is None
    ):
        raise FabricError(
            "rpc.invalid-params",
            "Reference operation parameters are invalid",
            "resourceId must be a stable lowercase identifier, never a path.",
        )
    return value


def _idempotency_key(value: Any) -> str:
    if not isinstance(value, str) or _IDEMPOTENCY_RE.fullmatch(value) is None:
        raise FabricError(
            "rpc.invalid-params",
            "Reference operation parameters are invalid",
            "idempotencyKey must contain 1 through 256 bounded identifier characters.",
        )
    return value


def _exact_fields(
    value: Mapping[str, Any],
    *,
    required: tuple[str, ...],
    optional: tuple[str, ...] = (),
    context: str,
) -> None:
    missing = sorted(set(required) - set(value))
    extras = sorted(set(value) - set(required) - set(optional))
    if missing or extras:
        details: list[str] = []
        if missing:
            details.append(f"missing: {', '.join(missing)}")
        if extras:
            details.append(f"unknown: {', '.join(extras)}")
        raise FabricError(
            "rpc.invalid-params",
            "Reference operation parameters are invalid",
            f"The {context} object does not match its closed typed contract.",
            detail="; ".join(details),
        )


def _recovery_token(value: Any, *, required: bool) -> str | None:
    if value is None and not required:
        return None
    if not isinstance(value, str) or _RECOVERY_TOKEN_RE.fullmatch(value) is None:
        raise FabricError(
            "rpc.invalid-params",
            "Reference recovery credential is invalid",
            "recoveryToken must be an unpadded 32-byte base64url value.",
            change_state="none",
        )
    return value


def _ledger_after_sequence(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= 9_223_372_036_854_775_807:
        raise FabricError(
            "rpc.invalid-params",
            "Reference ledger cursor is invalid",
            "afterSequence must be a non-negative signed 64-bit integer.",
            change_state="none",
        )
    return value


def _ledger_limit(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= _MAX_LEDGER_PAGE_ENTRIES:
        raise FabricError(
            "rpc.invalid-params",
            "Reference ledger page limit is invalid",
            f"limit must be between 1 and {_MAX_LEDGER_PAGE_ENTRIES}.",
            change_state="none",
        )
    return value


def _revision_number(value: str) -> int:
    prefix = "revision."
    if not value.startswith(prefix) or not value[len(prefix) :].isdigit():
        raise FabricError(
            "operation.invalid-record",
            "Reference operation record is invalid",
            "The durable preflight state revision is malformed.",
            change_state="unknown",
            recovery_actions=("fabric.restore-database",),
        )
    return int(value[len(prefix) :])


class ReferenceOperationStore:
    """Transactional state, event, and tamper-evident ledger persistence."""

    def __init__(self, database: FabricDatabase, *, event_retention: int) -> None:
        self.database = database
        self.event_retention = event_retention

    @staticmethod
    def _rollback_preserving(connection: Any) -> None:
        try:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
        except sqlite3.DatabaseError:
            pass

    @staticmethod
    def _operation_from_row(row: Any) -> dict[str, Any]:
        return {
            "operationId": row["operation_id"],
            "provider": REFERENCE_PROVIDER_ID,
            "providerVersion": row["provider_version"],
            "capability": REFERENCE_CAPABILITY,
            "risk": RiskLevel.CONSEQUENTIAL.value,
            "resource": {"kind": REFERENCE_RESOURCE_KIND, "id": row["resource_id"]},
            "stateRevision": row["state_revision"],
            "arguments": {
                "desiredState": row["desired_state"],
                "outcome": row["outcome"],
                "pace": row["pace"],
            },
            "beforeState": row["before_state"],
            "status": row["status"],
            "checkpoint": row["checkpoint"],
            "progress": int(row["progress"]),
            "cancellationRequested": bool(row["cancellation_requested"]),
            "approvalId": row["approval_id"],
            "authorizationCode": row["authorization_code"],
            "error": json.loads(row["error_json"]) if row["error_json"] else None,
            "result": json.loads(row["result_json"]) if row["result_json"] else None,
            "idempotency": {"key": row["idempotency_key"], "replayed": False},
            "createdAt": row["created_at"],
            "updatedAt": row["updated_at"],
        }

    def _row(self, operation_id: str) -> Any:
        row = self.database._require_connection().execute(
            "SELECT * FROM reference_operations WHERE operation_id = ?",
            (operation_id,),
        ).fetchone()
        if row is None:
            raise FabricError(
                "operation.unknown",
                "Reference operation is unknown",
                "No reference operation exists with this operationId.",
            )
        return row

    def get(self, operation_id: str) -> dict[str, Any]:
        row = self._row(operation_id)
        return self._operation_from_row(row)

    def projection_sources(
        self,
        principal_id: str,
        *,
        limit: int,
    ) -> tuple[dict[str, Any], ...]:
        """Return one bounded, verified, secret-free owner snapshot.

        This is the public read seam into durable Agent Center projection. It
        returns plain copies rather than SQLite rows, recovery credentials,
        arguments, authorization material, provider errors, or store handles.
        """

        if (
            not isinstance(principal_id, str)
            or len(principal_id.encode("utf-8")) > 160
            or _STABLE_RE.fullmatch(principal_id) is None
        ):
            raise FabricError(
                "projection.invalid-owner",
                "Reference projection owner is invalid",
                "The projection owner must be a bounded stable principal ID.",
                change_state="none",
            )
        if (
            isinstance(limit, bool)
            or not isinstance(limit, int)
            or not 1 <= limit <= _MAX_PROJECTION_SOURCES
        ):
            raise FabricError(
                "projection.invalid-limit",
                "Reference projection limit is invalid",
                f"The projection limit must be between 1 and {_MAX_PROJECTION_SOURCES}.",
                change_state="none",
            )
        connection = self.database._require_connection()
        if connection.in_transaction:
            raise FabricError(
                "projection.busy",
                "Reference projection snapshot is temporarily unavailable",
                "The authoritative store is completing another serialized operation.",
                retryable=True,
                change_state="none",
            )
        try:
            connection.execute("BEGIN")
            stable_account = principal_id.startswith("account.uid.") and principal_id[12:].isdigit()
            owner_clause = (
                "(principal_id = ? OR principal_id GLOB 'principal.*')"
                if stable_account
                else "principal_id = ?"
            )
            rows = connection.execute(
                f"""
                SELECT * FROM reference_operations
                WHERE {owner_clause}
                ORDER BY created_at, operation_id
                LIMIT ?
                """,
                (principal_id, limit + 1),
            ).fetchall()
            if len(rows) > limit:
                raise FabricError(
                    "projection.capacity-exceeded",
                    "Reference projection capacity is exhausted",
                    "The owner has more durable operations than this bounded projection can represent.",
                    change_state="none",
                    recovery_actions=("managed-work.review-retention",),
                )
            snapshot: list[dict[str, Any]] = []
            for row in rows:
                session_id = row["session_id"]
                if (
                    not isinstance(session_id, str)
                    or len(session_id.encode("utf-8")) > 160
                    or _STABLE_RE.fullmatch(session_id) is None
                ):
                    raise FabricError(
                        "operation.invalid-record",
                        "Reference operation record is invalid",
                        "The durable operation session identity is malformed.",
                        change_state="unknown",
                        recovery_actions=("fabric.restore-database",),
                    )
                verified = self._verified_ledger_rows(
                    connection,
                    str(row["operation_id"]),
                    row,
                )
                source_revision = len(verified)
                if source_revision < 1:
                    raise FabricError(
                        "ledger.integrity-failed",
                        "Reference operation ledger integrity failed",
                        "A projection requires verified non-empty operation evidence.",
                        change_state="unknown",
                        recovery_actions=("fabric.restore-database",),
                    )
                origin_row, origin_payload = verified[0]
                if (
                    str(origin_row["event_type"]) != "preflight.completed"
                    or origin_payload.get("operationId") != str(row["operation_id"])
                    or origin_payload.get("principalId") != str(row["principal_id"])
                    or origin_payload.get("sessionId") != session_id
                ):
                    raise FabricError(
                        "ledger.state-mismatch",
                        "Reference operation origin disagrees with its ledger",
                        "The first verified evidence does not attest the durable principal and session provenance.",
                        detail="origin",
                        change_state="unknown",
                        recovery_actions=("fabric.restore-database",),
                    )
                latest_row, latest_payload = verified[-1]
                comparisons = {
                    "operationId": str(row["operation_id"]),
                    "status": str(row["status"]),
                    "checkpoint": str(row["checkpoint"]),
                    "progress": int(row["progress"]),
                }
                for key, expected in comparisons.items():
                    if latest_payload.get(key) != expected:
                        raise FabricError(
                            "ledger.state-mismatch",
                            "Reference operation state disagrees with its ledger",
                            "The latest verified evidence does not attest the projected operation state.",
                            detail=key,
                            change_state="unknown",
                            recovery_actions=("fabric.restore-database",),
                        )
                if not 0 <= float(latest_row["created_at"]) - float(row["updated_at"]) <= 5:
                    raise FabricError(
                        "ledger.state-mismatch",
                        "Reference operation time disagrees with its ledger",
                        "The latest verified evidence does not bound the projected update time.",
                        detail="updatedAt",
                        change_state="unknown",
                        recovery_actions=("fabric.restore-database",),
                    )
                try:
                    error = json.loads(row["error_json"]) if row["error_json"] else None
                    result = json.loads(row["result_json"]) if row["result_json"] else None
                except (json.JSONDecodeError, TypeError) as decode_error:
                    raise FabricError(
                        "operation.invalid-record",
                        "Reference operation record is invalid",
                        "The durable operation result metadata is malformed.",
                        change_state="unknown",
                        recovery_actions=("fabric.restore-database",),
                    ) from decode_error
                error_change_state = None
                if isinstance(error, Mapping) and error.get("changeState") in {
                    "none",
                    "partial",
                    "complete",
                    "unknown",
                }:
                    error_change_state = str(error["changeState"])
                result_validated = (
                    bool(result["validated"])
                    if isinstance(result, Mapping) and isinstance(result.get("validated"), bool)
                    else None
                )
                error_evidence = "errorCode" in latest_payload or "changeState" in latest_payload
                if (
                    ("errorCode" in latest_payload) != ("changeState" in latest_payload)
                    or (
                        error_evidence
                        and (
                            not isinstance(error, Mapping)
                            or latest_payload.get("errorCode") != error.get("code")
                            or latest_payload.get("changeState") != error.get("changeState")
                        )
                    )
                    or (not error_evidence and error is not None)
                ):
                    raise FabricError(
                        "ledger.state-mismatch",
                        "Reference operation error disagrees with its ledger",
                        "The latest verified evidence does not attest the projected error metadata.",
                        detail="error",
                        change_state="unknown",
                        recovery_actions=("fabric.restore-database",),
                    )
                if "result" in latest_payload:
                    if latest_payload["result"] != result:
                        raise FabricError(
                            "ledger.state-mismatch",
                            "Reference operation result disagrees with its ledger",
                            "The latest verified evidence does not attest the projected result metadata.",
                            detail="result",
                            change_state="unknown",
                            recovery_actions=("fabric.restore-database",),
                        )
                elif result is not None:
                    raise FabricError(
                        "ledger.state-mismatch",
                        "Reference operation result disagrees with its ledger",
                        "The latest verified evidence does not attest the projected result metadata.",
                        detail="result",
                        change_state="unknown",
                        recovery_actions=("fabric.restore-database",),
                    )
                snapshot.append(
                    {
                        "operationId": str(row["operation_id"]),
                        "sessionId": session_id,
                        "legacyOwner": str(row["principal_id"]) != principal_id,
                        "sourceRevision": source_revision,
                        "capability": REFERENCE_CAPABILITY,
                        "status": str(row["status"]),
                        "checkpoint": str(row["checkpoint"]),
                        "errorChangeState": error_change_state,
                        "resultValidated": result_validated,
                        "createdAt": float(row["created_at"]),
                        "updatedAt": float(row["updated_at"]),
                    }
                )
            connection.execute("COMMIT")
            return tuple(snapshot)
        except FabricError:
            self._rollback_preserving(connection)
            raise
        except (KeyError, TypeError, ValueError, OverflowError) as error:
            self._rollback_preserving(connection)
            raise FabricError(
                "operation.invalid-record",
                "Reference operation record is invalid",
                "The bounded projection source contains malformed durable values.",
                detail=type(error).__name__,
                change_state="unknown",
                recovery_actions=("fabric.restore-database",),
            ) from error
        except sqlite3.DatabaseError as error:
            self._rollback_preserving(connection)
            raise FabricError(
                "projection.read-failed",
                "Reference projection snapshot could not be read",
                "The authoritative operation store refused the bounded snapshot.",
                detail=type(error).__name__,
                retryable=True,
                change_state="none",
                recovery_actions=("fabric.reconnect",),
            ) from error

    @staticmethod
    def _origin_matches(row: Any, principal: EndpointPrincipal) -> bool:
        return (
            row["principal_id"] == principal.principal_id
            and row["session_id"] == principal.session_id
        )

    def require_origin(
        self,
        operation_id: str,
        principal: EndpointPrincipal,
    ) -> dict[str, Any]:
        row = self._row(operation_id)
        if not self._origin_matches(row, principal):
            raise FabricError(
                "principal.request-spoof",
                "Reference operation belongs to another endpoint session",
                "The operation principal and session do not match this connection.",
                change_state="none",
            )
        return self._operation_from_row(row)

    def origin_matches(self, operation_id: str, principal: EndpointPrincipal) -> bool:
        return self._origin_matches(self._row(operation_id), principal)

    def origin_session_id(self, operation_id: str) -> str:
        return str(self._row(operation_id)["session_id"])

    def require_access(
        self,
        operation_id: str,
        principal: EndpointPrincipal,
        *,
        recovery_token: str | None,
        allow_recovery: bool,
        recovery_statuses: frozenset[str] | None = None,
    ) -> dict[str, Any]:
        row = self._row(operation_id)
        if self._origin_matches(row, principal):
            return self._operation_from_row(row)
        if not allow_recovery or (
            recovery_statuses is not None and row["status"] not in recovery_statuses
        ):
            raise FabricError(
                "principal.request-spoof",
                "Reference operation belongs to another endpoint session",
                "The operation principal and session do not match this connection.",
                change_state="none",
            )
        if recovery_token is None:
            raise FabricError(
                "principal.request-spoof",
                "Reference operation recovery requires its credential",
                "A different endpoint session must present the operation-specific recovery token.",
                change_state="none",
            )
        supplied_digest = hashlib.sha256(recovery_token.encode("ascii")).hexdigest()
        if not hmac.compare_digest(row["recovery_token_digest"], supplied_digest):
            raise FabricError(
                "operation.recovery-credential",
                "Reference operation recovery credential was rejected",
                "The supplied recovery token does not belong to this operation.",
                change_state="none",
            )
        return self._operation_from_row(row)

    def resource(self, resource_id: str) -> dict[str, Any]:
        row = self.database._require_connection().execute(
            "SELECT state, revision, updated_at FROM reference_resources WHERE resource_id = ?",
            (resource_id,),
        ).fetchone()
        if row is None:
            return {"id": resource_id, "state": "disabled", "revision": "revision.0"}
        return {
            "id": resource_id,
            "state": row["state"],
            "revision": f"revision.{int(row['revision'])}",
            "updatedAt": row["updated_at"],
        }

    @staticmethod
    def _ledger_hash(
        *,
        entry_id: str,
        operation_id: str,
        event_type: str,
        payload: Mapping[str, Any],
        previous_hash: str,
        created_at: float,
    ) -> str:
        material = {
            "entryId": entry_id,
            "operationId": operation_id,
            "eventType": event_type,
            "payload": dict(payload),
            "previousHash": previous_hash,
            "createdAt": created_at,
        }
        return hashlib.sha256(canonical_json(material).encode("utf-8")).hexdigest()

    def _verified_ledger_rows(
        self,
        connection: Any,
        operation_id: str,
        operation_row: Any,
    ) -> list[tuple[Any, dict[str, Any]]]:
        rows = connection.execute(
            """
            SELECT sequence, entry_id, event_type, payload_json, previous_hash, entry_hash, created_at
            FROM reference_operation_ledger WHERE operation_id = ? ORDER BY sequence
            """,
            (operation_id,),
        ).fetchall()
        verified: list[tuple[Any, dict[str, Any]]] = []
        expected_previous = _ZERO_HASH
        for row in rows:
            try:
                payload = json.loads(row["payload_json"])
                if not isinstance(payload, dict):
                    raise TypeError("ledger payload is not an object")
                computed = self._ledger_hash(
                    entry_id=row["entry_id"],
                    operation_id=operation_id,
                    event_type=row["event_type"],
                    payload=payload,
                    previous_hash=row["previous_hash"],
                    created_at=row["created_at"],
                )
            except (json.JSONDecodeError, TypeError, ValueError, UnicodeError) as error:
                raise FabricError(
                    "ledger.integrity-failed",
                    "Reference operation ledger failed verification",
                    "An evidence entry cannot be decoded and hashed as its typed object.",
                    detail=f"entry {row['entry_id']}",
                    change_state="unknown",
                    recovery_actions=("fabric.restore-database",),
                ) from error
            if row["previous_hash"] != expected_previous or row["entry_hash"] != computed:
                raise FabricError(
                    "ledger.integrity-failed",
                    "Reference operation ledger failed verification",
                    "The append-only evidence chain does not match its durable hashes.",
                    detail=f"entry {row['entry_id']}",
                    change_state="unknown",
                    recovery_actions=("fabric.restore-database",),
                )
            verified.append((row, payload))
            expected_previous = row["entry_hash"]
        if (
            len(verified) != int(operation_row["ledger_entry_count"])
            or expected_previous != operation_row["ledger_head_hash"]
        ):
            raise FabricError(
                "ledger.integrity-failed",
                "Reference operation ledger failed verification",
                "The verified evidence chain does not match its durable count and head anchor.",
                change_state="unknown",
                recovery_actions=("fabric.restore-database",),
            )
        return verified

    def _append_ledger(
        self,
        connection: Any,
        operation_id: str,
        event_type: str,
        payload: Mapping[str, Any],
    ) -> dict[str, Any]:
        anchor = connection.execute(
            """
            SELECT ledger_entry_count, ledger_head_hash
            FROM reference_operations WHERE operation_id = ?
            """,
            (operation_id,),
        ).fetchone()
        if anchor is None:
            raise FabricError(
                "operation.unknown",
                "Reference operation is unknown",
                "Evidence cannot be appended without its operation record.",
                change_state="none",
            )
        verified = self._verified_ledger_rows(connection, operation_id, anchor)
        ledger_count = len(verified)
        previous_hash = _ZERO_HASH if not verified else str(verified[-1][0]["entry_hash"])
        if ledger_count >= _MAX_LEDGER_ENTRIES:
            raise FabricError(
                "ledger.capacity-exhausted",
                "Reference operation evidence capacity is exhausted",
                f"A reference operation may contain at most {_MAX_LEDGER_ENTRIES} anchored evidence entries.",
                change_state="unknown",
                recovery_actions=("operation.inspect",),
            )
        entry_id = str(uuid.uuid4())
        created_at = time.time()
        entry_hash = self._ledger_hash(
            entry_id=entry_id,
            operation_id=operation_id,
            event_type=event_type,
            payload=payload,
            previous_hash=previous_hash,
            created_at=created_at,
        )
        cursor = connection.execute(
            """
            INSERT INTO reference_operation_ledger(
              entry_id, operation_id, event_type, payload_json,
              previous_hash, entry_hash, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                entry_id,
                operation_id,
                event_type,
                canonical_json(payload),
                previous_hash,
                entry_hash,
                created_at,
            ),
        )
        self._update(
            connection,
            operation_id,
            {
                "ledger_entry_count": ledger_count + 1,
                "ledger_head_hash": entry_hash,
            },
        )
        return {
            "sequence": int(cursor.lastrowid),
            "entryId": entry_id,
            "operationId": operation_id,
            "eventType": event_type,
            "payload": dict(payload),
            "previousHash": previous_hash,
            "entryHash": entry_hash,
            "createdAt": created_at,
        }

    def _append_evidence(
        self,
        connection: Any,
        operation_id: str,
        event_type: str,
        payload: Mapping[str, Any],
        *,
        topic: str = "reference.operation-progress",
    ) -> dict[str, Any]:
        self._append_ledger(connection, operation_id, event_type, payload)
        return FabricDatabase._append_event_in_transaction(
            connection,
            topic,
            payload,
            retention=self.event_retention,
        )

    def _update(
        self,
        connection: Any,
        operation_id: str,
        updates: Mapping[str, Any],
    ) -> None:
        if not updates or not set(updates) <= _UPDATE_FIELDS:
            raise RuntimeError("reference operation attempted an unsupported durable field update")
        assignments = ", ".join(f"{field} = ?" for field in updates)
        connection.execute(
            f"UPDATE reference_operations SET {assignments} WHERE operation_id = ?",
            (*updates.values(), operation_id),
        )

    def preflight(
        self,
        *,
        operation_id: str,
        idempotency_key: str,
        recovery_token: str,
        principal: EndpointPrincipal,
        resource_id: str,
        desired_state: str,
        outcome: str,
        pace: str,
    ) -> tuple[dict[str, Any], bool, dict[str, Any] | None]:
        recovery_token_digest = hashlib.sha256(recovery_token.encode("ascii")).hexdigest()
        fingerprint = request_fingerprint(
            {
                "provider": REFERENCE_PROVIDER_ID,
                "providerVersion": REFERENCE_PROVIDER_VERSION,
                "operationId": operation_id,
                "recoveryTokenDigest": recovery_token_digest,
                "resource": {"kind": REFERENCE_RESOURCE_KIND, "id": resource_id},
                "arguments": {
                    "desiredState": desired_state,
                    "outcome": outcome,
                    "pace": pace,
                },
            }
        )
        connection = self.database._require_connection()
        connection.execute("BEGIN IMMEDIATE")
        try:
            matches = connection.execute(
                """
                SELECT * FROM reference_operations
                WHERE operation_id = ? OR idempotency_key = ?
                ORDER BY operation_id
                """,
                (operation_id, idempotency_key),
            ).fetchall()
            if matches:
                if (
                    len(matches) == 1
                    and matches[0]["operation_id"] == operation_id
                    and matches[0]["idempotency_key"] == idempotency_key
                    and matches[0]["request_hash"] == fingerprint
                ):
                    if not self._origin_matches(matches[0], principal):
                        raise FabricError(
                            "principal.request-spoof",
                            "Reference operation belongs to another endpoint session",
                            "A preflight replay cannot cross its frozen principal and session boundary.",
                            change_state="none",
                        )
                    connection.execute("COMMIT")
                    operation = self._operation_from_row(matches[0])
                    operation["idempotency"]["replayed"] = True
                    return operation, True, None
                raise FabricError(
                    "operation.idempotency-conflict",
                    "Reference operation identity conflicts",
                    "operationId or idempotencyKey is already bound to another normalized request.",
                    change_state="none",
                    recovery_actions=("operation.inspect",),
                )
            now = time.time()
            connection.execute(
                """
                INSERT OR IGNORE INTO reference_resources(resource_id, state, revision, updated_at)
                VALUES (?, 'disabled', 0, ?)
                """,
                (resource_id, now),
            )
            resource = connection.execute(
                "SELECT state, revision FROM reference_resources WHERE resource_id = ?",
                (resource_id,),
            ).fetchone()
            assert resource is not None
            state_revision = f"revision.{int(resource['revision'])}"
            connection.execute(
                """
                INSERT INTO reference_operations(
                  operation_id, idempotency_key, request_hash, recovery_token_digest, principal_id, session_id,
                  resource_id, provider_version, state_revision, before_state, desired_state,
                  outcome, pace, status, checkpoint, progress, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'awaiting-consent', 'preflight', 0, ?, ?)
                """,
                (
                    operation_id,
                    idempotency_key,
                    fingerprint,
                    recovery_token_digest,
                    principal.principal_id,
                    principal.session_id,
                    resource_id,
                    REFERENCE_PROVIDER_VERSION,
                    state_revision,
                    resource["state"],
                    desired_state,
                    outcome,
                    pace,
                    now,
                    now,
                ),
            )
            payload = {
                "operationId": operation_id,
                "phase": "preflight-complete",
                "status": "awaiting-consent",
                "checkpoint": "preflight",
                "progress": 0,
                "provider": REFERENCE_PROVIDER_ID,
                "providerVersion": REFERENCE_PROVIDER_VERSION,
                "capability": REFERENCE_CAPABILITY,
                "risk": RiskLevel.CONSEQUENTIAL.value,
                "resource": {"kind": REFERENCE_RESOURCE_KIND, "id": resource_id},
                "stateRevision": state_revision,
                "arguments": {
                    "desiredState": desired_state,
                    "outcome": outcome,
                    "pace": pace,
                },
                "principalId": principal.principal_id,
                "sessionId": principal.session_id,
            }
            event = self._append_evidence(connection, operation_id, "preflight.completed", payload)
            row = connection.execute(
                "SELECT * FROM reference_operations WHERE operation_id = ?",
                (operation_id,),
            ).fetchone()
            connection.execute("COMMIT")
            assert row is not None
            return self._operation_from_row(row), False, event
        except Exception:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            raise

    def bind_approval(
        self,
        operation_id: str,
        principal: EndpointPrincipal,
        *,
        approval_id: str,
        binding_digest: str,
        correlation_nonce: str,
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        connection = self.database._require_connection()
        connection.execute("BEGIN IMMEDIATE")
        try:
            row = connection.execute(
                "SELECT * FROM reference_operations WHERE operation_id = ?",
                (operation_id,),
            ).fetchone()
            if row is None:
                raise FabricError("operation.unknown", "Reference operation is unknown", "No operation exists with this ID.")
            if row["status"] != "awaiting-consent":
                raise FabricError(
                    "operation.state-conflict",
                    "Reference operation cannot be approved",
                    "Only an operation awaiting consent can receive approval.",
                    change_state="none",
                )
            if not self._origin_matches(row, principal):
                raise FabricError(
                    "principal.request-spoof",
                    "Reference operation belongs to another endpoint session",
                    "Approval cannot change the principal or session frozen at preflight.",
                    change_state="none",
                )
            approval_count = int(
                connection.execute(
                    """
                    SELECT COUNT(*) FROM reference_operation_ledger
                    WHERE operation_id = ? AND event_type = 'consent.issued'
                    """,
                    (operation_id,),
                ).fetchone()[0]
            )
            if approval_count >= _MAX_APPROVAL_ISSUES:
                raise FabricError(
                    "approval.issue-limit",
                    "Reference operation approval limit reached",
                    f"A reference operation may receive at most {_MAX_APPROVAL_ISSUES} exact approvals.",
                    change_state="none",
                    recovery_actions=("operation.preflight",),
                )
            resource = connection.execute(
                "SELECT state, revision FROM reference_resources WHERE resource_id = ?",
                (row["resource_id"],),
            ).fetchone()
            if resource is None or f"revision.{int(resource['revision'])}" != row["state_revision"]:
                raise FabricError(
                    "operation.state-drift",
                    "Reference preflight is stale",
                    "The fake resource changed after preflight; create a new operation and approve its current state.",
                    change_state="none",
                    recovery_actions=("operation.preflight",),
                )
            now = time.time()
            self._update(
                connection,
                operation_id,
                {
                    "approval_id": approval_id,
                    "approval_binding_digest": binding_digest,
                    "correlation_nonce": correlation_nonce,
                    "updated_at": now,
                },
            )
            payload = {
                "operationId": operation_id,
                "phase": "consent-recorded",
                "status": "awaiting-consent",
                "checkpoint": "preflight",
                "progress": int(row["progress"]),
                "approvalId": approval_id,
                "correlationNonce": correlation_nonce,
                "bindingDigest": binding_digest,
                "principalId": principal.principal_id,
                "sessionId": principal.session_id,
            }
            event = self._append_evidence(connection, operation_id, "consent.issued", payload)
            rebound = connection.execute(
                "SELECT * FROM reference_operations WHERE operation_id = ?",
                (operation_id,),
            ).fetchone()
            connection.execute("COMMIT")
            assert rebound is not None
            return self._operation_from_row(rebound), event
        except Exception:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            raise

    def authorize(
        self,
        operation_id: str,
        *,
        approval_id: str,
        authorization_code: str,
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        connection = self.database._require_connection()
        connection.execute("BEGIN IMMEDIATE")
        try:
            row = connection.execute(
                "SELECT * FROM reference_operations WHERE operation_id = ?",
                (operation_id,),
            ).fetchone()
            if row is None:
                raise FabricError("operation.unknown", "Reference operation is unknown", "No operation exists with this ID.")
            if row["status"] != "awaiting-consent" or row["approval_id"] != approval_id:
                raise FabricError(
                    "operation.state-conflict",
                    "Reference operation authorization changed",
                    "The durable operation no longer matches this approval.",
                    change_state="none",
                )
            self._validate_start_state(connection, row, operation_id)
            now = time.time()
            self._update(
                connection,
                operation_id,
                {
                    "status": "queued",
                    "checkpoint": "authorized",
                    "progress": 5,
                    "authorization_code": authorization_code,
                    "updated_at": now,
                },
            )
            payload = {
                "operationId": operation_id,
                "phase": "authorization-complete",
                "status": "queued",
                "checkpoint": "authorized",
                "progress": 5,
                "approvalId": approval_id,
                "authorizationCode": authorization_code,
            }
            event = self._append_evidence(connection, operation_id, "authorization.allowed", payload)
            authorized = connection.execute(
                "SELECT * FROM reference_operations WHERE operation_id = ?",
                (operation_id,),
            ).fetchone()
            connection.execute("COMMIT")
            assert authorized is not None
            return self._operation_from_row(authorized), event
        except Exception:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            raise

    @staticmethod
    def _validate_start_state(connection: Any, row: Any, operation_id: str) -> None:
        resource = connection.execute(
            "SELECT state, revision FROM reference_resources WHERE resource_id = ?",
            (row["resource_id"],),
        ).fetchone()
        if (
            resource is None
            or resource["state"] != row["before_state"]
            or f"revision.{int(resource['revision'])}" != row["state_revision"]
        ):
            raise FabricError(
                "operation.state-drift",
                "Reference preflight is stale",
                "The fake resource changed after approval; create a new operation against its current revision.",
                change_state="none",
                recovery_actions=("operation.preflight",),
            )
        competing = connection.execute(
            """
            SELECT operation_id FROM reference_operations
            WHERE resource_id = ? AND operation_id != ?
              AND status IN ('queued', 'running', 'interrupted', 'reconciling')
            ORDER BY created_at LIMIT 1
            """,
            (row["resource_id"], operation_id),
        ).fetchone()
        if competing is not None:
            raise FabricError(
                "operation.resource-busy",
                "Reference resource already has an active operation",
                "Only one consequential reference operation may own a fake resource at a time.",
                detail=competing["operation_id"],
                retryable=True,
                change_state="none",
                recovery_actions=("operation.inspect",),
            )

    def validate_start(
        self,
        operation_id: str,
        approval_id: str,
        principal: EndpointPrincipal,
    ) -> None:
        connection = self.database._require_connection()
        row = connection.execute(
            "SELECT * FROM reference_operations WHERE operation_id = ?",
            (operation_id,),
        ).fetchone()
        if row is None:
            raise FabricError("operation.unknown", "Reference operation is unknown", "No operation exists with this ID.")
        if not self._origin_matches(row, principal):
            raise FabricError(
                "principal.request-spoof",
                "Reference operation belongs to another endpoint session",
                "Starting an operation cannot change the principal or session frozen at preflight.",
                change_state="none",
            )
        if row["status"] == "awaiting-consent" and row["approval_id"] is None:
            raise FabricError(
                "approval.required",
                "Exact reference operation consent is required",
                "Approve the normalized preflight operation before starting it.",
                change_state="none",
            )
        if row["status"] != "awaiting-consent" or row["approval_id"] != approval_id:
            raise FabricError(
                "operation.state-conflict",
                "Reference operation authorization changed",
                "The durable operation no longer matches this approval.",
                change_state="none",
            )
        self._validate_start_state(connection, row, operation_id)

    def transition(
        self,
        operation_id: str,
        *,
        allowed_statuses: frozenset[str],
        allowed_checkpoints: frozenset[str] | None,
        status: str,
        checkpoint: str,
        progress: int,
        phase: str,
        event_type: str,
        topic: str = "reference.operation-progress",
        error: Mapping[str, Any] | None = None,
        result: Mapping[str, Any] | None = None,
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        connection = self.database._require_connection()
        connection.execute("BEGIN IMMEDIATE")
        try:
            row = connection.execute(
                "SELECT * FROM reference_operations WHERE operation_id = ?",
                (operation_id,),
            ).fetchone()
            if row is None:
                raise FabricError("operation.unknown", "Reference operation is unknown", "No operation exists with this ID.")
            if row["status"] not in allowed_statuses or (
                allowed_checkpoints is not None and row["checkpoint"] not in allowed_checkpoints
            ):
                raise FabricError(
                    "operation.state-conflict",
                    "Reference operation state changed unexpectedly",
                    "The durable status or checkpoint did not match the requested transition.",
                    change_state="unknown",
                    recovery_actions=("operation.inspect",),
                )
            updates: dict[str, Any] = {
                "status": status,
                "checkpoint": checkpoint,
                "progress": progress,
                "updated_at": time.time(),
            }
            if error is not None:
                updates["error_json"] = canonical_json(error)
            if result is not None:
                updates["result_json"] = canonical_json(result)
            self._update(connection, operation_id, updates)
            payload: dict[str, Any] = {
                "operationId": operation_id,
                "phase": phase,
                "status": status,
                "checkpoint": checkpoint,
                "progress": progress,
            }
            if error is not None:
                payload["errorCode"] = error["code"]
                payload["changeState"] = error["changeState"]
            if result is not None:
                payload["result"] = dict(result)
            event = self._append_evidence(connection, operation_id, event_type, payload, topic=topic)
            changed = connection.execute(
                "SELECT * FROM reference_operations WHERE operation_id = ?",
                (operation_id,),
            ).fetchone()
            connection.execute("COMMIT")
            assert changed is not None
            return self._operation_from_row(changed), event
        except Exception:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            raise

    def apply(self, operation_id: str) -> tuple[dict[str, Any], dict[str, Any]]:
        connection = self.database._require_connection()
        connection.execute("BEGIN IMMEDIATE")
        try:
            row = connection.execute(
                "SELECT * FROM reference_operations WHERE operation_id = ?",
                (operation_id,),
            ).fetchone()
            if row is None or row["status"] != "running" or row["checkpoint"] != "validated":
                raise FabricError(
                    "operation.state-conflict",
                    "Reference operation cannot apply",
                    "The operation is not at its validated checkpoint.",
                    change_state="unknown",
                    recovery_actions=("operation.inspect",),
                )
            revision = _revision_number(row["state_revision"])
            cursor = connection.execute(
                """
                UPDATE reference_resources
                SET state = ?, revision = revision + 1, updated_at = ?
                WHERE resource_id = ? AND state = ? AND revision = ?
                """,
                (
                    row["desired_state"],
                    time.time(),
                    row["resource_id"],
                    row["before_state"],
                    revision,
                ),
            )
            if cursor.rowcount != 1:
                raise FabricError(
                    "operation.state-drift",
                    "Reference resource changed after preflight",
                    "The fake provider refused to apply against a stale state revision.",
                    change_state="none",
                    recovery_actions=("operation.preflight",),
                )
            self._update(
                connection,
                operation_id,
                {"checkpoint": "applied", "progress": 60, "updated_at": time.time()},
            )
            payload = {
                "operationId": operation_id,
                "phase": "fake-state-applied",
                "status": "running",
                "checkpoint": "applied",
                "progress": 60,
                "resourceRevision": f"revision.{revision + 1}",
            }
            event = self._append_evidence(connection, operation_id, "provider.applied", payload)
            changed = connection.execute(
                "SELECT * FROM reference_operations WHERE operation_id = ?",
                (operation_id,),
            ).fetchone()
            connection.execute("COMMIT")
            assert changed is not None
            return self._operation_from_row(changed), event
        except Exception:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            raise

    def finish_after_apply(
        self,
        operation_id: str,
        *,
        status: str,
        phase: str,
        event_type: str,
        rollback: bool,
        recovered: bool = False,
        error: Mapping[str, Any] | None = None,
        allowed_statuses: frozenset[str] = frozenset({"running", "reconciling"}),
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        connection = self.database._require_connection()
        connection.execute("BEGIN IMMEDIATE")
        try:
            row = connection.execute(
                "SELECT * FROM reference_operations WHERE operation_id = ?",
                (operation_id,),
            ).fetchone()
            if row is None or row["status"] not in allowed_statuses or row["checkpoint"] != "applied":
                raise FabricError(
                    "operation.state-conflict",
                    "Reference operation cannot finish",
                    "The operation is not at its applied checkpoint.",
                    change_state="unknown",
                    recovery_actions=("operation.inspect",),
                )
            base_revision = _revision_number(row["state_revision"])
            resource = connection.execute(
                "SELECT state, revision FROM reference_resources WHERE resource_id = ?",
                (row["resource_id"],),
            ).fetchone()
            if (
                resource is None
                or resource["state"] != row["desired_state"]
                or int(resource["revision"]) != base_revision + 1
            ):
                raise FabricError(
                    "operation.reconciliation-conflict",
                    "Reference resource state cannot be reconciled",
                    "Durable fake-provider state does not match the applied checkpoint.",
                    change_state="unknown",
                    recovery_actions=("operation.inspect",),
                )
            final_revision = base_revision + 1
            final_state = row["desired_state"]
            checkpoint = "finished"
            if rollback:
                final_revision = base_revision + 2
                final_state = row["before_state"]
                checkpoint = "reconciled"
                connection.execute(
                    """
                    UPDATE reference_resources
                    SET state = ?, revision = ?, updated_at = ? WHERE resource_id = ?
                    """,
                    (final_state, final_revision, time.time(), row["resource_id"]),
                )
            result = {
                "provider": REFERENCE_PROVIDER_ID,
                "resource": {"kind": REFERENCE_RESOURCE_KIND, "id": row["resource_id"]},
                "state": final_state,
                "revision": f"revision.{final_revision}",
                "validated": error is None,
                "reconciled": rollback or recovered,
            }
            updates: dict[str, Any] = {
                "status": status,
                "checkpoint": checkpoint,
                "progress": 100,
                "error_json": canonical_json(error) if error is not None else None,
                "result_json": canonical_json(result),
                "updated_at": time.time(),
            }
            self._update(connection, operation_id, updates)
            payload: dict[str, Any] = {
                "operationId": operation_id,
                "phase": phase,
                "status": status,
                "checkpoint": checkpoint,
                "progress": 100,
                "result": result,
            }
            if error is not None:
                payload["errorCode"] = error["code"]
                payload["changeState"] = error["changeState"]
            event = self._append_evidence(
                connection,
                operation_id,
                event_type,
                payload,
                topic="reference.operation-finished",
            )
            changed = connection.execute(
                "SELECT * FROM reference_operations WHERE operation_id = ?",
                (operation_id,),
            ).fetchone()
            connection.execute("COMMIT")
            assert changed is not None
            return self._operation_from_row(changed), event
        except Exception:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            raise

    def request_cancel(self, operation_id: str) -> tuple[dict[str, Any], bool, dict[str, Any] | None]:
        connection = self.database._require_connection()
        connection.execute("BEGIN IMMEDIATE")
        try:
            row = connection.execute(
                "SELECT * FROM reference_operations WHERE operation_id = ?",
                (operation_id,),
            ).fetchone()
            if row is None:
                raise FabricError("operation.unknown", "Reference operation is unknown", "No operation exists with this ID.")
            if row["status"] in _TERMINAL_STATUSES or bool(row["cancellation_requested"]):
                connection.execute("COMMIT")
                return self._operation_from_row(row), True, None
            if row["status"] == "awaiting-consent":
                resource = connection.execute(
                    "SELECT state, revision FROM reference_resources WHERE resource_id = ?",
                    (row["resource_id"],),
                ).fetchone()
                if resource is None:
                    raise FabricError(
                        "operation.invalid-record",
                        "Reference resource record is missing",
                        "The preflight resource disappeared before cancellation.",
                        change_state="unknown",
                        recovery_actions=("fabric.restore-database",),
                    )
                result = {
                    "provider": REFERENCE_PROVIDER_ID,
                    "resource": {"kind": REFERENCE_RESOURCE_KIND, "id": row["resource_id"]},
                    "state": resource["state"],
                    "revision": f"revision.{int(resource['revision'])}",
                    "validated": True,
                    "reconciled": False,
                }
                self._update(
                    connection,
                    operation_id,
                    {
                        "status": "cancelled",
                        "checkpoint": "finished",
                        "progress": 100,
                        "cancellation_requested": 1,
                        "result_json": canonical_json(result),
                        "updated_at": time.time(),
                    },
                )
                payload = {
                    "operationId": operation_id,
                    "phase": "cancelled-before-start",
                    "status": "cancelled",
                    "checkpoint": "finished",
                    "progress": 100,
                    "result": result,
                }
                event = self._append_evidence(
                    connection,
                    operation_id,
                    "cancellation.completed",
                    payload,
                    topic="reference.operation-finished",
                )
                changed = connection.execute(
                    "SELECT * FROM reference_operations WHERE operation_id = ?",
                    (operation_id,),
                ).fetchone()
                connection.execute("COMMIT")
                assert changed is not None
                return self._operation_from_row(changed), False, event
            self._update(
                connection,
                operation_id,
                {"cancellation_requested": 1, "updated_at": time.time()},
            )
            payload = {
                "operationId": operation_id,
                "phase": "cancellation-requested",
                "status": row["status"],
                "checkpoint": row["checkpoint"],
                "progress": int(row["progress"]),
            }
            event = self._append_evidence(connection, operation_id, "cancellation.requested", payload)
            changed = connection.execute(
                "SELECT * FROM reference_operations WHERE operation_id = ?",
                (operation_id,),
            ).fetchone()
            connection.execute("COMMIT")
            assert changed is not None
            return self._operation_from_row(changed), False, event
        except Exception:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            raise

    def fail_evidence(self, operation_id: str, error: FabricError) -> dict[str, Any]:
        """Contain an evidence failure to one operation without appending to a broken/full chain."""

        connection = self.database._require_connection()
        connection.execute("BEGIN IMMEDIATE")
        try:
            row = connection.execute(
                "SELECT * FROM reference_operations WHERE operation_id = ?",
                (operation_id,),
            ).fetchone()
            if row is None:
                raise FabricError(
                    "operation.unknown",
                    "Reference operation is unknown",
                    "No operation exists with this ID.",
                    change_state="none",
                )
            if row["status"] in _TERMINAL_STATUSES:
                connection.execute("COMMIT")
                return self._operation_from_row(row)
            resource = connection.execute(
                "SELECT state, revision FROM reference_resources WHERE resource_id = ?",
                (row["resource_id"],),
            ).fetchone()
            if resource is None:
                result = None
            else:
                result = {
                    "provider": REFERENCE_PROVIDER_ID,
                    "resource": {"kind": REFERENCE_RESOURCE_KIND, "id": row["resource_id"]},
                    "state": resource["state"],
                    "revision": f"revision.{int(resource['revision'])}",
                    "validated": False,
                    "reconciled": False,
                }
            self._update(
                connection,
                operation_id,
                {
                    "status": "failed",
                    "checkpoint": "applied" if row["checkpoint"] == "applied" else "finished",
                    "progress": 100,
                    "error_json": canonical_json(error.to_dict()),
                    "result_json": canonical_json(result) if result is not None else None,
                    "updated_at": time.time(),
                },
            )
            changed = connection.execute(
                "SELECT * FROM reference_operations WHERE operation_id = ?",
                (operation_id,),
            ).fetchone()
            connection.execute("COMMIT")
            assert changed is not None
            return self._operation_from_row(changed)
        except Exception:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            raise

    def mark_interrupted_on_start(self) -> list[dict[str, Any]]:
        connection = self.database._require_connection()
        rows = connection.execute(
            "SELECT * FROM reference_operations WHERE status IN ('queued', 'running', 'reconciling') ORDER BY created_at",
        ).fetchall()
        events: list[dict[str, Any]] = []
        for row in rows:
            connection.execute("BEGIN IMMEDIATE")
            try:
                self._update(
                    connection,
                    row["operation_id"],
                    {"status": "interrupted", "updated_at": time.time()},
                )
                payload = {
                    "operationId": row["operation_id"],
                    "phase": "daemon-recovery-required",
                    "status": "interrupted",
                    "checkpoint": row["checkpoint"],
                    "progress": int(row["progress"]),
                    "previousStatus": row["status"],
                    "recoveryAction": "reference.operation.reconcile",
                }
                events.append(
                    self._append_evidence(
                        connection,
                        row["operation_id"],
                        "daemon.recovery-required",
                        payload,
                    )
                )
                connection.execute("COMMIT")
            except FabricError as error:
                if connection.in_transaction:
                    connection.execute("ROLLBACK")
                if error.code in _EVIDENCE_FAILURE_CODES:
                    self.fail_evidence(row["operation_id"], error)
                    continue
                raise
            except Exception:
                if connection.in_transaction:
                    connection.execute("ROLLBACK")
                raise
        return events

    def ledger(
        self,
        operation_id: str,
        *,
        after_sequence: int,
        limit: int,
    ) -> dict[str, Any]:
        operation_row = self._row(operation_id)
        entries: list[dict[str, Any]] = []
        verified = self._verified_ledger_rows(
            self.database._require_connection(),
            operation_id,
            operation_row,
        )
        for row, payload in verified:
            entry = {
                "sequence": int(row["sequence"]),
                "entryId": row["entry_id"],
                "operationId": operation_id,
                "eventType": row["event_type"],
                "payload": payload,
                "previousHash": row["previous_hash"],
                "entryHash": row["entry_hash"],
                "createdAt": row["created_at"],
            }
            entries.append(entry)
        page_candidates = [entry for entry in entries if entry["sequence"] > after_sequence]
        page = page_candidates[:limit]
        next_after_sequence = None
        if len(page_candidates) > len(page):
            next_after_sequence = page[-1]["sequence"]
        return {
            "operationId": operation_id,
            "verified": True,
            "entryCount": len(page),
            "totalEntryCount": len(entries),
            "headHash": operation_row["ledger_head_hash"],
            "entries": page,
            "nextAfterSequence": next_after_sequence,
        }


class ReferenceOperationManager:
    """Executes the closed fake operation through Trust and durable checkpoints."""

    def __init__(
        self,
        database: FabricDatabase,
        events: EventBroker,
        *,
        session_is_active: Callable[[str], bool],
    ) -> None:
        self.events = events
        self.store = ReferenceOperationStore(database, event_retention=events.retention)
        self.approvals = ApprovalAuthority()
        self.policy = PolicyEngine()
        self._session_is_active = session_is_active
        self._tasks: dict[str, asyncio.Task[None]] = {}

    def recover_startup(self) -> int:
        events = self.store.mark_interrupted_on_start()
        for event in events:
            self.events.deliver(event)
        return len(events)

    def projection_sources(
        self,
        principal_id: str,
        *,
        limit: int,
    ) -> tuple[dict[str, Any], ...]:
        return self.store.projection_sources(principal_id, limit=limit)

    def _deliver(self, event: dict[str, Any] | None) -> None:
        if event is not None:
            self.events.deliver(event)

    def _contain_evidence_failure(
        self,
        operation_id: str,
        error: FabricError,
    ) -> Mapping[str, Any]:
        if error.code in _EVIDENCE_FAILURE_CODES:
            return self.store.fail_evidence(operation_id, error)
        raise error

    @staticmethod
    def _request(operation: Mapping[str, Any], principal: EndpointPrincipal) -> OperationRequest:
        try:
            return OperationRequest(
                operation_id=operation["operationId"],
                principal_id=principal.principal_id,
                session_id=principal.session_id,
                capability=REFERENCE_CAPABILITY,
                resource=ResourceRef(REFERENCE_RESOURCE_KIND, operation["resource"]["id"]),
                provider_version=operation["providerVersion"],
                state_revision=operation["stateRevision"],
                risk=RiskLevel.CONSEQUENTIAL,
                arguments=operation["arguments"],
            )
        except SecurityValidationError as error:
            raise FabricError(
                "operation.invalid-record",
                "Reference operation record is invalid",
                error.explanation,
                detail=error.code,
                change_state="unknown",
                recovery_actions=("fabric.restore-database",),
            ) from error

    def preflight(self, principal: EndpointPrincipal, params: Mapping[str, Any]) -> Mapping[str, Any]:
        _exact_fields(
            params,
            required=("operationId", "idempotencyKey", "recoveryToken", "resourceId", "arguments"),
            context="reference preflight",
        )
        arguments = params["arguments"]
        if not isinstance(arguments, dict):
            raise FabricError(
                "rpc.invalid-params",
                "Reference operation parameters are invalid",
                "arguments must be an object.",
            )
        _exact_fields(
            arguments,
            required=("desiredState", "outcome", "pace"),
            context="reference operation arguments",
        )
        desired_state = arguments["desiredState"]
        outcome = arguments["outcome"]
        pace = arguments["pace"]
        if desired_state not in {"enabled", "disabled"}:
            raise FabricError("rpc.invalid-params", "Reference operation parameters are invalid", "desiredState must be enabled or disabled.")
        if outcome not in {"succeed", "fail-after-apply"}:
            raise FabricError("rpc.invalid-params", "Reference operation parameters are invalid", "outcome must be succeed or fail-after-apply.")
        if pace not in {"immediate", "observable"}:
            raise FabricError("rpc.invalid-params", "Reference operation parameters are invalid", "pace must be immediate or observable.")
        operation, replayed, event = self.store.preflight(
            operation_id=_operation_id(params["operationId"]),
            idempotency_key=_idempotency_key(params["idempotencyKey"]),
            recovery_token=_recovery_token(params["recoveryToken"], required=True),
            principal=principal,
            resource_id=_stable_resource_id(params["resourceId"]),
            desired_state=desired_state,
            outcome=outcome,
            pace=pace,
        )
        self._deliver(event)
        operation["idempotency"]["replayed"] = replayed
        operation["preflight"] = {
            "eligible": True,
            "consequence": "Change one hermetic fake setting and validate its exact durable revision.",
            "requiresConsent": True,
            "hostMutation": False,
        }
        return operation

    def approve(self, principal: EndpointPrincipal, params: Mapping[str, Any]) -> Mapping[str, Any]:
        _exact_fields(
            params,
            required=("operationId", "confirmation"),
            context="reference approval",
        )
        operation_id = _operation_id(params["operationId"])
        if params["confirmation"] != "approve-exact-operation":
            raise FabricError(
                "approval.confirmation-required",
                "Exact reference operation consent is required",
                "confirmation must explicitly approve the normalized preflight operation.",
                change_state="none",
            )
        operation = self.store.require_origin(operation_id, principal)
        request = self._request(operation, principal)
        try:
            approval = self.approvals.issue(
                principal,
                request,
                expires_at=_utc_now() + timedelta(minutes=5),
            )
        except SecurityValidationError as error:
            raise FabricError(
                error.code,
                "Reference approval could not be issued",
                error.explanation,
                change_state="none",
            ) from error
        try:
            operation, event = self.store.bind_approval(
                operation_id,
                principal,
                approval_id=approval.approval_id,
                binding_digest=approval.binding_digest,
                correlation_nonce=approval.correlation_nonce,
            )
        except Exception as error:
            self.approvals.discard(approval.approval_id)
            if isinstance(error, FabricError) and error.code in _EVIDENCE_FAILURE_CODES:
                self.store.fail_evidence(operation_id, error)
            raise
        self._deliver(event)
        return {
            "operation": operation,
            "approval": {
                "approvalId": approval.approval_id,
                "correlationNonce": approval.correlation_nonce,
                "bindingDigest": approval.binding_digest,
                "expiresAt": approval.expires_at.timestamp(),
                "oneUse": True,
            },
        }

    def start(self, principal: EndpointPrincipal, params: Mapping[str, Any]) -> Mapping[str, Any]:
        _exact_fields(
            params,
            required=("operationId", "approvalId"),
            context="reference start",
        )
        operation_id = _operation_id(params["operationId"])
        approval_id = params["approvalId"]
        if not isinstance(approval_id, str) or not approval_id.startswith("approval.") or len(approval_id) > 160:
            raise FabricError("rpc.invalid-params", "Reference operation parameters are invalid", "approvalId is invalid.")
        operation = self.store.require_origin(operation_id, principal)
        if operation["approvalId"] == approval_id and operation["status"] in _ACTIVE_STATUSES | _TERMINAL_STATUSES | {"interrupted"}:
            operation["idempotency"]["replayed"] = True
            return operation
        self.store.validate_start(operation_id, approval_id, principal)
        request = self._request(operation, principal)
        decision = self.policy.decide(
            principal,
            request,
            (),
            approval_authority=self.approvals,
            approval_id=approval_id,
            consume_approval=True,
        )
        if not decision.allowed:
            raise FabricError(
                decision.code,
                "Reference operation authorization denied",
                decision.explanation,
                change_state="none",
            )
        try:
            operation, event = self.store.authorize(
                operation_id,
                approval_id=approval_id,
                authorization_code=decision.code,
            )
        except FabricError as error:
            return self._contain_evidence_failure(operation_id, error)
        self._deliver(event)
        self._schedule(operation_id)
        return operation

    def get(self, principal: EndpointPrincipal, params: Mapping[str, Any]) -> Mapping[str, Any]:
        _exact_fields(
            params,
            required=("operationId",),
            optional=("recoveryToken",),
            context="reference inspection",
        )
        operation = self.store.require_access(
            _operation_id(params["operationId"]),
            principal,
            recovery_token=_recovery_token(params.get("recoveryToken"), required=False),
            allow_recovery=True,
        )
        operation["resourceState"] = self.store.resource(operation["resource"]["id"])
        return operation

    def ledger(self, principal: EndpointPrincipal, params: Mapping[str, Any]) -> Mapping[str, Any]:
        _exact_fields(
            params,
            required=("operationId",),
            optional=("recoveryToken", "afterSequence", "limit"),
            context="reference ledger inspection",
        )
        operation_id = _operation_id(params["operationId"])
        self.store.require_access(
            operation_id,
            principal,
            recovery_token=_recovery_token(params.get("recoveryToken"), required=False),
            allow_recovery=True,
        )
        try:
            return self.store.ledger(
                operation_id,
                after_sequence=_ledger_after_sequence(params.get("afterSequence", 0)),
                limit=_ledger_limit(params.get("limit", _MAX_LEDGER_PAGE_ENTRIES)),
            )
        except FabricError as error:
            if error.code in _EVIDENCE_FAILURE_CODES:
                self.store.fail_evidence(operation_id, error)
            raise

    def cancel(self, principal: EndpointPrincipal, params: Mapping[str, Any]) -> Mapping[str, Any]:
        _exact_fields(
            params,
            required=("operationId",),
            optional=("recoveryToken",),
            context="reference cancellation",
        )
        operation_id = _operation_id(params["operationId"])
        origin_matches = self.store.origin_matches(operation_id, principal)
        operation = self.store.require_access(
            operation_id,
            principal,
            recovery_token=_recovery_token(params.get("recoveryToken"), required=False),
            allow_recovery=True,
            recovery_statuses=frozenset({"awaiting-consent", "interrupted"}),
        )
        if (
            not origin_matches
            and operation["status"] == "awaiting-consent"
            and self._session_is_active(self.store.origin_session_id(operation_id))
        ):
            raise FabricError(
                "principal.request-spoof",
                "Reference operation still belongs to its active endpoint session",
                "A recovery token cannot cancel awaiting-consent work while its origin session remains active.",
                change_state="none",
            )
        try:
            operation, replayed, event = self.store.request_cancel(operation_id)
        except FabricError as error:
            return self._contain_evidence_failure(operation_id, error)
        self._deliver(event)
        operation["idempotency"]["replayed"] = replayed
        return operation

    def reconcile(self, principal: EndpointPrincipal, params: Mapping[str, Any]) -> Mapping[str, Any]:
        _exact_fields(
            params,
            required=("operationId",),
            optional=("recoveryToken",),
            context="reference reconciliation",
        )
        operation_id = _operation_id(params["operationId"])
        operation = self.store.require_access(
            operation_id,
            principal,
            recovery_token=_recovery_token(params.get("recoveryToken"), required=False),
            allow_recovery=True,
        )
        if operation["status"] in _TERMINAL_STATUSES:
            operation["idempotency"]["replayed"] = True
            return operation
        if operation["status"] != "interrupted":
            raise FabricError(
                "operation.reconciliation-not-required",
                "Reference operation does not require reconciliation",
                "Only an interrupted operation can enter the reconciliation path.",
                change_state="none",
            )
        try:
            if operation["checkpoint"] == "applied":
                if operation["cancellationRequested"]:
                    return self._rollback_cancel(
                        operation_id,
                        allowed_statuses=frozenset({"interrupted"}),
                    )
                if operation["arguments"]["outcome"] == "fail-after-apply":
                    return self._deterministic_failure(
                        operation_id,
                        allowed_statuses=frozenset({"interrupted"}),
                    )
                recovered, event = self.store.finish_after_apply(
                    operation_id,
                    status="recovered",
                    phase="reconciliation-complete",
                    event_type="reconciliation.recovered",
                    rollback=False,
                    recovered=True,
                    allowed_statuses=frozenset({"interrupted"}),
                )
                self._deliver(event)
                return recovered
            if operation["cancellationRequested"]:
                resource = self.store.resource(operation["resource"]["id"])
                cancelled, event = self.store.transition(
                    operation_id,
                    allowed_statuses=frozenset({"interrupted"}),
                    allowed_checkpoints=frozenset({"authorized", "validated", "preflight"}),
                    status="cancelled",
                    checkpoint="reconciled",
                    progress=100,
                    phase="reconciliation-cancelled",
                    event_type="reconciliation.cancelled",
                    topic="reference.operation-finished",
                    result={
                        "provider": REFERENCE_PROVIDER_ID,
                        "resource": operation["resource"],
                        "state": resource["state"],
                        "revision": resource["revision"],
                        "validated": True,
                        "reconciled": True,
                    },
                )
                self._deliver(event)
                return cancelled
            queued, event = self.store.transition(
                operation_id,
                allowed_statuses=frozenset({"interrupted"}),
                allowed_checkpoints=frozenset({"authorized", "validated", "preflight"}),
                status="queued",
                checkpoint="authorized",
                progress=5,
                phase="reconciliation-resume-queued",
                event_type="reconciliation.resumed",
            )
            self._deliver(event)
            self._schedule(operation_id)
            return queued
        except FabricError as error:
            return self._contain_evidence_failure(operation_id, error)

    def _schedule(self, operation_id: str) -> None:
        task = self._tasks.get(operation_id)
        if task is not None and not task.done():
            return
        task = asyncio.create_task(self._run(operation_id))
        self._tasks[operation_id] = task
        task.add_done_callback(lambda _task: self._tasks.pop(operation_id, None))

    async def _pace(self, operation: Mapping[str, Any]) -> None:
        if operation["arguments"]["pace"] == "observable":
            await asyncio.sleep(0.25)
        else:
            await asyncio.sleep(0)

    async def _run(self, operation_id: str) -> None:
        try:
            operation, event = self.store.transition(
                operation_id,
                allowed_statuses=frozenset({"queued"}),
                allowed_checkpoints=frozenset({"authorized"}),
                status="running",
                checkpoint="authorized",
                progress=10,
                phase="execution-started",
                event_type="execution.started",
            )
            self._deliver(event)
            await self._pace(operation)
            operation = self.store.get(operation_id)
            if operation["cancellationRequested"]:
                self._cancel_without_change(operation_id)
                return
            resource = self.store.resource(operation["resource"]["id"])
            if resource["revision"] != operation["stateRevision"] or resource["state"] != operation["beforeState"]:
                raise FabricError(
                    "operation.state-drift",
                    "Reference resource changed after preflight",
                    "Validation refused to apply against a stale fake resource revision.",
                    change_state="none",
                    recovery_actions=("operation.preflight",),
                )
            operation, event = self.store.transition(
                operation_id,
                allowed_statuses=frozenset({"running"}),
                allowed_checkpoints=frozenset({"authorized"}),
                status="running",
                checkpoint="validated",
                progress=30,
                phase="pre-apply-validation-complete",
                event_type="validation.pre-apply-passed",
            )
            self._deliver(event)
            await self._pace(operation)
            operation = self.store.get(operation_id)
            if operation["cancellationRequested"]:
                self._cancel_without_change(operation_id)
                return
            operation, event = self.store.apply(operation_id)
            self._deliver(event)
            await self._pace(operation)
            operation = self.store.get(operation_id)
            if operation["cancellationRequested"]:
                self._rollback_cancel(operation_id)
                return
            if operation["arguments"]["outcome"] == "fail-after-apply":
                self._deterministic_failure(operation_id)
                return
            resource = self.store.resource(operation["resource"]["id"])
            base_revision = _revision_number(operation["stateRevision"])
            if resource["state"] != operation["arguments"]["desiredState"] or resource["revision"] != f"revision.{base_revision + 1}":
                raise FabricError(
                    "reference.validation-failed",
                    "Reference operation validation failed",
                    "The fake provider did not expose the exact desired state and revision.",
                    change_state="unknown",
                    recovery_actions=("reference.operation.reconcile",),
                )
            finished, event = self.store.finish_after_apply(
                operation_id,
                status="succeeded",
                phase="post-apply-validation-complete",
                event_type="validation.succeeded",
                rollback=False,
            )
            self._deliver(event)
        except asyncio.CancelledError:
            try:
                current = self.store.get(operation_id)
                if current["status"] in _ACTIVE_STATUSES:
                    try:
                        _interrupted, event = self.store.transition(
                            operation_id,
                            allowed_statuses=_ACTIVE_STATUSES,
                            allowed_checkpoints=None,
                            status="interrupted",
                            checkpoint=current["checkpoint"],
                            progress=current["progress"],
                            phase="daemon-shutdown-recovery-required",
                            event_type="daemon.recovery-required",
                        )
                        self._deliver(event)
                    except FabricError as error:
                        self._contain_evidence_failure(operation_id, error)
            finally:
                raise
        except FabricError as error:
            if error.code in _EVIDENCE_FAILURE_CODES:
                self.store.fail_evidence(operation_id, error)
                return
            current = self.store.get(operation_id)
            if current["status"] in _TERMINAL_STATUSES | {"interrupted"}:
                return
            failure = error.to_dict()
            resource = self.store.resource(current["resource"]["id"])
            if (
                current["checkpoint"] == "applied"
                and error.change_state == "unknown"
                and "reference.operation.reconcile" in error.recovery_actions
            ):
                try:
                    _interrupted, event = self.store.transition(
                        operation_id,
                        allowed_statuses=_ACTIVE_STATUSES,
                        allowed_checkpoints=frozenset({"applied"}),
                        status="interrupted",
                        checkpoint="applied",
                        progress=current["progress"],
                        phase="post-apply-validation-recovery-required",
                        event_type="validation.recovery-required",
                        error=failure,
                        result={
                            "provider": REFERENCE_PROVIDER_ID,
                            "resource": current["resource"],
                            "state": resource["state"],
                            "revision": resource["revision"],
                            "validated": False,
                            "reconciled": False,
                        },
                    )
                except FabricError as transition_error:
                    self._contain_evidence_failure(operation_id, transition_error)
                    return
                self._deliver(event)
                return
            try:
                failed, event = self.store.transition(
                    operation_id,
                    allowed_statuses=_ACTIVE_STATUSES,
                    allowed_checkpoints=None,
                    status="failed",
                    checkpoint="finished" if current["checkpoint"] != "applied" else "applied",
                    progress=100,
                    phase="execution-failed",
                    event_type="execution.failed",
                    topic="reference.operation-finished",
                    error=failure,
                    result={
                        "provider": REFERENCE_PROVIDER_ID,
                        "resource": current["resource"],
                        "state": resource["state"],
                        "revision": resource["revision"],
                        "validated": False,
                        "reconciled": False,
                    },
                )
            except FabricError as transition_error:
                self._contain_evidence_failure(operation_id, transition_error)
                return
            self._deliver(event)

    def _cancel_without_change(self, operation_id: str) -> Mapping[str, Any]:
        current = self.store.get(operation_id)
        resource = self.store.resource(current["resource"]["id"])
        cancelled, event = self.store.transition(
            operation_id,
            allowed_statuses=frozenset({"running", "queued", "reconciling"}),
            allowed_checkpoints=frozenset({"authorized", "validated", "preflight"}),
            status="cancelled",
            checkpoint="reconciled",
            progress=100,
            phase="cancelled-before-apply",
            event_type="cancellation.completed",
            topic="reference.operation-finished",
            result={
                "provider": REFERENCE_PROVIDER_ID,
                "resource": current["resource"],
                "state": resource["state"],
                "revision": resource["revision"],
                "validated": True,
                "reconciled": False,
            },
        )
        self._deliver(event)
        return cancelled

    def _rollback_cancel(
        self,
        operation_id: str,
        *,
        allowed_statuses: frozenset[str] = frozenset({"running", "reconciling"}),
    ) -> Mapping[str, Any]:
        error = FabricError(
            "operation.cancelled",
            "Reference operation was cancelled",
            "Cancellation reconciled the fake resource to its preflight state.",
            change_state="none",
        ).to_dict()
        cancelled, event = self.store.finish_after_apply(
            operation_id,
            status="cancelled",
            phase="cancellation-reconciled",
            event_type="cancellation.reconciled",
            rollback=True,
            error=error,
            allowed_statuses=allowed_statuses,
        )
        self._deliver(event)
        return cancelled

    def _deterministic_failure(
        self,
        operation_id: str,
        *,
        allowed_statuses: frozenset[str] = frozenset({"running", "reconciling"}),
    ) -> Mapping[str, Any]:
        error = FabricError(
            "reference.validation-failed",
            "Reference operation validation failed",
            "The typed fake provider produced its requested deterministic validation failure.",
            change_state="none",
            recovery_actions=("operation.inspect",),
        ).to_dict()
        failed, event = self.store.finish_after_apply(
            operation_id,
            status="failed",
            phase="validation-failed-and-reconciled",
            event_type="validation.failed-reconciled",
            rollback=True,
            error=error,
            allowed_statuses=allowed_statuses,
        )
        self._deliver(event)
        return failed

    async def shutdown(self) -> None:
        tasks = [task for task in self._tasks.values() if not task.done()]
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        self._tasks.clear()
