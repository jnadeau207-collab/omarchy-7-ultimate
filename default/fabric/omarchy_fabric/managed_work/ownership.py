"""Daemon-owned stable account identity and ephemeral endpoint sessions.

Account ownership is derived only from the authenticated Unix peer UID after it
has been matched to the daemon UID.  Client hello labels and request fields are
deliberately absent from this module's API.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Callable

from ..security import (
    EndpointAdmission,
    EndpointPrincipal,
    SessionCredential,
)
from ..security.errors import SecurityValidationError

MAX_ACTIVE_ENDPOINT_SESSIONS = 1024


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _require_aware_time(value: datetime, label: str) -> datetime:
    if not isinstance(value, datetime) or value.tzinfo is None or value.utcoffset() is None:
        raise SecurityValidationError("principal.time", f"{label} must be timezone-aware.")
    return value


def _require_uid(value: int, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0 or value > 2**32 - 1:
        raise SecurityValidationError("principal.uid", f"{label} must be a non-negative Unix UID.")
    return value


@dataclass(frozen=True)
class AccountOwner:
    """Stable authorization owner for exactly one daemon Unix account."""

    owner_id: str
    uid: int


@dataclass
class _Binding:
    principal: EndpointPrincipal
    token_digest: bytes
    revoked: bool = False


class StableOwnerSessionStore:
    """Bind stable account ownership to separately expiring endpoint sessions."""

    def __init__(
        self,
        daemon_uid: int,
        *,
        clock: Callable[[], datetime] = _utc_now,
        maximum_active_sessions: int = MAX_ACTIVE_ENDPOINT_SESSIONS,
    ) -> None:
        self._daemon_uid = _require_uid(daemon_uid, "Daemon UID")
        if (
            isinstance(maximum_active_sessions, bool)
            or not isinstance(maximum_active_sessions, int)
            or not 1 <= maximum_active_sessions <= MAX_ACTIVE_ENDPOINT_SESSIONS
        ):
            raise SecurityValidationError(
                "principal.capacity",
                f"Active endpoint session capacity must be between 1 and {MAX_ACTIVE_ENDPOINT_SESSIONS}.",
            )
        self._clock = clock
        self._maximum_active_sessions = maximum_active_sessions
        self._bindings: dict[str, _Binding] = {}

    @property
    def daemon_owner(self) -> AccountOwner:
        return AccountOwner(owner_id=f"account.uid.{self._daemon_uid}", uid=self._daemon_uid)

    def owner_for_peer(self, peer_uid: int) -> AccountOwner:
        peer = _require_uid(peer_uid, "Peer UID")
        if peer != self._daemon_uid:
            raise SecurityValidationError(
                "principal.peer-owner",
                "The authenticated Unix peer is not owned by this user daemon.",
            )
        return self.daemon_owner

    def _purge_inactive(self, now: datetime) -> None:
        expired = [
            session_id
            for session_id, binding in self._bindings.items()
            if binding.revoked or now >= binding.principal.expires_at
        ]
        for session_id in expired:
            self._bindings.pop(session_id, None)

    def issue(
        self,
        peer_uid: int,
        admission: EndpointAdmission,
        *,
        lifetime: timedelta = timedelta(hours=8),
    ) -> tuple[EndpointPrincipal, SessionCredential]:
        owner = self.owner_for_peer(peer_uid)
        if not isinstance(admission, EndpointAdmission):
            raise SecurityValidationError("principal.admission", "Endpoint admission is invalid.")
        if lifetime <= timedelta(0) or lifetime > timedelta(days=1):
            raise SecurityValidationError(
                "principal.lifetime",
                "Session lifetime must be positive and no longer than one day.",
            )
        now = _require_aware_time(self._clock(), "Current time")
        self._purge_inactive(now)
        if len(self._bindings) >= self._maximum_active_sessions:
            raise SecurityValidationError(
                "principal.capacity",
                "Active endpoint session capacity is exhausted.",
            )
        session_id = f"session.{uuid.uuid4().hex}"
        token = secrets.token_urlsafe(32)
        principal = EndpointPrincipal(
            principal_id=owner.owner_id,
            session_id=session_id,
            uid=owner.uid,
            endpoint_id=admission.endpoint_id,
            kind=admission.kind,
            issued_at=now,
            expires_at=now + lifetime,
            provider_id=admission.provider_id,
            task_id=admission.task_id,
        )
        self._bindings[session_id] = _Binding(
            principal=principal,
            token_digest=hashlib.sha256(token.encode("utf-8")).digest(),
        )
        return principal, SessionCredential(session_id=session_id, token=token)

    def resolve(self, peer_uid: int, credential: SessionCredential) -> EndpointPrincipal:
        self.owner_for_peer(peer_uid)
        if (
            not isinstance(credential, SessionCredential)
            or not isinstance(credential.session_id, str)
            or not isinstance(credential.token, str)
        ):
            raise SecurityValidationError("principal.credential", "Session credential is invalid.")
        binding = self._bindings.get(credential.session_id)
        supplied = hashlib.sha256(credential.token.encode("utf-8")).digest()
        expected = binding.token_digest if binding is not None else bytes(32)
        if binding is None or not hmac.compare_digest(expected, supplied):
            raise SecurityValidationError("principal.credential", "Session credential is invalid.")
        return self.require_active(binding.principal)

    def require_active(self, principal: EndpointPrincipal) -> EndpointPrincipal:
        if not isinstance(principal, EndpointPrincipal):
            raise SecurityValidationError("principal.unknown", "Session principal is invalid.")
        binding = self._bindings.get(principal.session_id)
        if binding is None or binding.principal != principal:
            raise SecurityValidationError("principal.unknown", "Session does not exist.")
        if binding.revoked:
            raise SecurityValidationError("principal.revoked", "Session has been revoked.")
        now = _require_aware_time(self._clock(), "Current time")
        if now >= principal.expires_at:
            raise SecurityValidationError("principal.expired", "Session has expired.")
        return principal

    def is_active(self, session_id: str) -> bool:
        binding = self._bindings.get(session_id)
        if binding is None or binding.revoked:
            return False
        now = _require_aware_time(self._clock(), "Current time")
        return now < binding.principal.expires_at

    def revoke(self, session_id: str) -> None:
        binding = self._bindings.get(session_id)
        if binding is None:
            raise SecurityValidationError("principal.unknown", "Session does not exist.")
        binding.revoked = True

    def release(self, session_id: str) -> bool:
        return self._bindings.pop(session_id, None) is not None
