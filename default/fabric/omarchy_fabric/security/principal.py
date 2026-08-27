"""Endpoint-bound principals and opaque server-issued session credentials."""

from __future__ import annotations

import hashlib
import hmac
import re
import secrets
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from enum import Enum
from typing import Callable

from .errors import SecurityValidationError

_STABLE_RE = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$")


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _validate_time(value: datetime, name: str) -> None:
    try:
        aware = isinstance(value, datetime) and value.tzinfo is not None and value.utcoffset() is not None
    except (TypeError, ValueError, OverflowError):
        aware = False
    if not aware:
        raise SecurityValidationError("principal.time", f"{name} must be timezone-aware.")


class PrincipalKind(str, Enum):
    SHELL = "shell"
    PROVIDER = "provider"
    TASK = "task"


@dataclass(frozen=True)
class EndpointAdmission:
    """A role admitted by daemon-owned configuration, never an RPC actor field."""

    endpoint_id: str
    kind: PrincipalKind
    provider_id: str | None = None
    task_id: str | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.kind, PrincipalKind):
            raise SecurityValidationError("principal.kind", "Endpoint kind is invalid.")
        if not _STABLE_RE.fullmatch(self.endpoint_id):
            raise SecurityValidationError("principal.endpoint", "Endpoint ID must be a stable identifier.")
        if self.kind is PrincipalKind.PROVIDER:
            if self.provider_id is None or not _STABLE_RE.fullmatch(self.provider_id):
                raise SecurityValidationError("principal.provider", "Provider endpoints require a provider ID.")
        elif self.provider_id is not None:
            raise SecurityValidationError("principal.provider", "Only provider endpoints carry a provider ID.")
        if self.kind is PrincipalKind.TASK:
            if self.task_id is None or not _STABLE_RE.fullmatch(self.task_id):
                raise SecurityValidationError("principal.task", "Task endpoints require a task ID.")
        elif self.task_id is not None:
            raise SecurityValidationError("principal.task", "Only task endpoints carry a task ID.")


@dataclass(frozen=True)
class EndpointPrincipal:
    principal_id: str
    session_id: str
    uid: int
    endpoint_id: str
    kind: PrincipalKind
    issued_at: datetime
    expires_at: datetime
    provider_id: str | None = None
    task_id: str | None = None


@dataclass(frozen=True)
class SessionCredential:
    session_id: str
    token: str


@dataclass
class _StoredBinding:
    principal: EndpointPrincipal
    token_digest: bytes
    revoked: bool = False


class SessionBindingStore:
    """Binds an admitted endpoint to peer UID and an opaque session token.

    The peer UID proves only the Unix account. Endpoint kind comes exclusively
    from ``EndpointAdmission`` supplied by daemon authority, never from a caller's
    actor/provider/task claim.
    """

    def __init__(self, *, clock: Callable[[], datetime] = _utc_now) -> None:
        self._clock = clock
        self._bindings: dict[str, _StoredBinding] = {}

    def issue(
        self,
        peer_uid: int,
        admission: EndpointAdmission,
        *,
        lifetime: timedelta = timedelta(hours=8),
    ) -> tuple[EndpointPrincipal, SessionCredential]:
        if not isinstance(peer_uid, int) or isinstance(peer_uid, bool) or peer_uid < 0:
            raise SecurityValidationError("principal.uid", "Peer UID must be a non-negative integer.")
        if lifetime <= timedelta(0) or lifetime > timedelta(days=1):
            raise SecurityValidationError("principal.lifetime", "Session lifetime must be within one day.")
        now = self._clock()
        _validate_time(now, "Current time")
        session_id = f"session.{uuid.uuid4().hex}"
        principal_id = f"principal.{uuid.uuid4().hex}"
        token = secrets.token_urlsafe(32)
        principal = EndpointPrincipal(
            principal_id=principal_id,
            session_id=session_id,
            uid=peer_uid,
            endpoint_id=admission.endpoint_id,
            kind=admission.kind,
            issued_at=now,
            expires_at=now + lifetime,
            provider_id=admission.provider_id,
            task_id=admission.task_id,
        )
        self._bindings[session_id] = _StoredBinding(
            principal=principal,
            token_digest=hashlib.sha256(token.encode("utf-8")).digest(),
        )
        return principal, SessionCredential(session_id=session_id, token=token)

    def resolve(self, peer_uid: int, credential: SessionCredential) -> EndpointPrincipal:
        if (
            not isinstance(credential, SessionCredential)
            or not isinstance(credential.session_id, str)
            or not isinstance(credential.token, str)
        ):
            raise SecurityValidationError("principal.credential", "Session credential is invalid.")
        binding = self._bindings.get(credential.session_id)
        supplied_digest = hashlib.sha256(credential.token.encode("utf-8")).digest()
        if binding is None or not hmac.compare_digest(
            binding.token_digest if binding is not None else bytes(32), supplied_digest
        ):
            raise SecurityValidationError("principal.credential", "Session credential is invalid.")
        if binding.revoked:
            raise SecurityValidationError("principal.revoked", "Session has been revoked.")
        if peer_uid != binding.principal.uid:
            raise SecurityValidationError("principal.peer-uid", "Session is bound to a different peer UID.")
        now = self._clock()
        _validate_time(now, "Current time")
        if now >= binding.principal.expires_at:
            raise SecurityValidationError("principal.expired", "Session has expired.")
        return binding.principal

    def revoke(self, session_id: str) -> None:
        binding = self._bindings.get(session_id)
        if binding is None:
            raise SecurityValidationError("principal.unknown", "Session does not exist.")
        binding.revoked = True
