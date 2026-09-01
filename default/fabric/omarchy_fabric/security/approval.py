"""Exact, expiring, one-operation consent bindings."""

from __future__ import annotations

import re
import uuid
from dataclasses import dataclass, replace
from datetime import datetime, timedelta, timezone
from typing import Callable

from .errors import SecurityValidationError
from .normalize import binding_digest
from .principal import EndpointPrincipal
from .types import OperationRequest

_UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_DEFAULT_MAX_RECORDS = 1024

def _utc_now() -> datetime:
    return datetime.now(timezone.utc)

def _is_aware(value: object) -> bool:
    if not isinstance(value, datetime) or value.tzinfo is None:
        return False
    try:
        return value.utcoffset() is not None
    except (TypeError, ValueError, OverflowError):
        return False

@dataclass(frozen=True)
class ApprovalRecord:
    approval_id: str
    correlation_nonce: str
    operation_id: str
    principal_id: str
    session_id: str
    capability: str
    resource_kind: str
    resource_id: str
    provider_version: str
    state_revision: str
    risk: str
    task_id: str | None
    argument_digest: str
    binding_digest: str
    issued_at: datetime
    expires_at: datetime
    consumed_at: datetime | None = None

@dataclass(frozen=True)
class ApprovalCheck:
    valid: bool
    code: str
    explanation: str
    approval_id: str | None = None

class ApprovalAuthority:
    """Keeps approval records in the authority, never as caller-owned claims."""

    def __init__(
        self,
        *,
        clock: Callable[[], datetime] = _utc_now,
        max_records: int = _DEFAULT_MAX_RECORDS,
    ) -> None:
        if isinstance(max_records, bool) or not isinstance(max_records, int) or not 1 <= max_records <= 65_536:
            raise SecurityValidationError(
                "approval.capacity",
                "Approval record capacity must be between 1 and 65536.",
            )
        self._clock = clock
        self._max_records = max_records
        self._records: dict[str, ApprovalRecord] = {}

    def _prune(self, now: datetime) -> int:
        removable = [
            approval_id
            for approval_id, record in self._records.items()
            if record.consumed_at is not None or now >= record.expires_at
        ]
        for approval_id in removable:
            del self._records[approval_id]
        return len(removable)

    def prune(self) -> int:
        """Remove expired and consumed authority records using the bounded authority clock."""

        now = self._clock()
        if not _is_aware(now):
            raise SecurityValidationError("approval.time", "Current time must be timezone-aware.")
        return self._prune(now)

    def discard(self, approval_id: str) -> bool:
        """Forget an unbound approval when durable binding fails."""

        return self._records.pop(approval_id, None) is not None

    @property
    def record_count(self) -> int:
        return len(self._records)

    def issue(
        self,
        principal: EndpointPrincipal,
        request: OperationRequest,
        *,
        expires_at: datetime,
        correlation_nonce: str | None = None,
    ) -> ApprovalRecord:
        now = self._clock()
        if not _is_aware(now) or not _is_aware(expires_at):
            raise SecurityValidationError("approval.time", "Approval timestamps must be timezone-aware.")
        self._prune(now)
        if len(self._records) >= self._max_records:
            raise SecurityValidationError(
                "approval.capacity",
                "Approval authority record capacity is exhausted.",
            )
        if expires_at <= now or expires_at - now > timedelta(minutes=15):
            raise SecurityValidationError("approval.expiry", "Approval lifetime must be within 15 minutes.")
        if request.principal_id != principal.principal_id or request.session_id != principal.session_id:
            raise SecurityValidationError("approval.principal", "Request is not bound to this endpoint session.")
        nonce = correlation_nonce or str(uuid.uuid4())
        if not _UUID_RE.fullmatch(nonce):
            raise SecurityValidationError("approval.nonce", "Correlation nonce must be a lowercase UUID.")
        approval_id = f"approval.{uuid.uuid4().hex}"
        payload = request.approval_payload()
        record = ApprovalRecord(
            approval_id=approval_id,
            correlation_nonce=nonce,
            operation_id=request.operation_id,
            principal_id=request.principal_id,
            session_id=request.session_id,
            capability=request.capability,
            resource_kind=request.resource.kind,
            resource_id=request.resource.resource_id,
            provider_version=request.provider_version,
            state_revision=request.state_revision,
            risk=request.risk.value,
            task_id=request.task_id,
            argument_digest=binding_digest(dict(request.arguments)),
            binding_digest=binding_digest(payload),
            issued_at=now,
            expires_at=expires_at,
        )
        self._records[approval_id] = record
        return record

    def check(
        self,
        approval_id: str,
        principal: EndpointPrincipal,
        request: OperationRequest,
        *,
        consume: bool = False,
    ) -> ApprovalCheck:
        record = self._records.get(approval_id)
        if record is None:
            return ApprovalCheck(False, "approval.unknown", "Approval does not exist.")
        now = self._clock()
        if not _is_aware(now):
            raise SecurityValidationError("approval.time", "Current time must be timezone-aware.")
        if record.consumed_at is not None:
            return ApprovalCheck(False, "approval.consumed", "Approval was already consumed.", approval_id)
        if now >= record.expires_at:
            return ApprovalCheck(False, "approval.expired", "Approval has expired.", approval_id)
        if principal.principal_id != record.principal_id or principal.session_id != record.session_id:
            return ApprovalCheck(False, "approval.principal-drift", "Approval belongs to another endpoint session.", approval_id)
        if request.operation_id != record.operation_id:
            return ApprovalCheck(False, "approval.operation-drift", "Operation identity changed after approval.", approval_id)
        if request.provider_version != record.provider_version:
            return ApprovalCheck(False, "approval.provider-drift", "Provider version changed after approval.", approval_id)
        if request.state_revision != record.state_revision:
            return ApprovalCheck(False, "approval.state-drift", "Target state changed after approval.", approval_id)
        if request.risk.value != record.risk:
            return ApprovalCheck(False, "approval.risk-drift", "Operation risk changed after approval.", approval_id)
        if request.task_id != record.task_id:
            return ApprovalCheck(False, "approval.task-drift", "Task scope changed after approval.", approval_id)
        if request.capability != record.capability:
            return ApprovalCheck(False, "approval.capability-drift", "Capability changed after approval.", approval_id)
        if request.resource.kind != record.resource_kind or request.resource.resource_id != record.resource_id:
            return ApprovalCheck(False, "approval.resource-drift", "Target identity changed after approval.", approval_id)
        if binding_digest(dict(request.arguments)) != record.argument_digest:
            return ApprovalCheck(False, "approval.argument-drift", "Normalized arguments changed after approval.", approval_id)
        if binding_digest(request.approval_payload()) != record.binding_digest:
            return ApprovalCheck(False, "approval.binding-drift", "Approval binding no longer matches the request.", approval_id)
        if consume:
            self._records[approval_id] = replace(record, consumed_at=now)
        return ApprovalCheck(True, "approval.valid", "Approval exactly matches the operation.", approval_id)

    def get(self, approval_id: str) -> ApprovalRecord | None:
        return self._records.get(approval_id)
