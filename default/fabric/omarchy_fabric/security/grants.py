"""Capability/resource/constraint/duration/task-scoped grant contracts."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from types import MappingProxyType
from typing import Any, Mapping

from .errors import SecurityValidationError
from .normalize import normalize_json
from .principal import PrincipalKind
from .types import OperationRequest, ResourceRef, RiskLevel

_STABLE_RE = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$")
_CAPABILITY_RE = re.compile(r"^[a-z][a-z0-9-]*(?:\.[a-z][a-z0-9-]*)+$")


def _is_aware(value: Any) -> bool:
    if not isinstance(value, datetime) or value.tzinfo is None:
        return False
    try:
        return value.utcoffset() is not None
    except (TypeError, ValueError, OverflowError):
        return False


class GrantPersistence(str, Enum):
    SESSION = "session"
    DURATION = "duration"
    PERSISTENT = "persistent"


def _lookup_dotted(request: OperationRequest, path: str) -> Any:
    if path.startswith("arguments."):
        value: Any = request.arguments
        parts = path.split(".")[1:]
    elif path.startswith("context."):
        value = request.context
        parts = path.split(".")[1:]
    else:
        raise SecurityValidationError(
            "grant.constraint-path",
            "Constraint paths must start with arguments. or context..",
        )
    if not parts:
        raise SecurityValidationError("grant.constraint-path", "Constraint path is incomplete.")
    for part in parts:
        if not _STABLE_RE.fullmatch(part):
            raise SecurityValidationError("grant.constraint-path", "Constraint path is invalid.")
        if not isinstance(value, Mapping) or part not in value:
            return _MISSING
        value = value[part]
    return value


_MISSING = object()


@dataclass(frozen=True)
class CapabilityGrant:
    grant_id: str
    principal_id: str
    principal_kind: PrincipalKind
    capability: str
    resource: ResourceRef
    issued_at: datetime
    expires_at: datetime
    maximum_risk: RiskLevel
    persistence: GrantPersistence
    constraints: Mapping[str, tuple[Any, ...]] = field(default_factory=dict)
    task_id: str | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.principal_kind, PrincipalKind):
            raise SecurityValidationError("grant.principal-kind", "Grant principal kind is invalid.")
        if not isinstance(self.maximum_risk, RiskLevel):
            raise SecurityValidationError("grant.risk", "Grant maximum risk is invalid.")
        if not isinstance(self.persistence, GrantPersistence):
            raise SecurityValidationError("grant.persistence", "Grant persistence is invalid.")
        if not _CAPABILITY_RE.fullmatch(self.capability):
            raise SecurityValidationError("grant.capability", "Grant capability ID is invalid.")
        for name, value in (("grant", self.grant_id), ("principal", self.principal_id)):
            if not isinstance(value, str) or not _STABLE_RE.fullmatch(value):
                raise SecurityValidationError(f"grant.{name}", f"{name.title()} ID must be stable.")
        if not _is_aware(self.issued_at) or not _is_aware(self.expires_at):
            raise SecurityValidationError("grant.time", "Grant timestamps must be timezone-aware.")
        if self.expires_at <= self.issued_at:
            raise SecurityValidationError("grant.expiry", "Grant expiry must be after issuance.")
        if self.expires_at - self.issued_at > timedelta(days=365):
            raise SecurityValidationError("grant.duration", "Grant duration cannot exceed one year.")
        if self.persistence is GrantPersistence.PERSISTENT and self.maximum_risk is RiskLevel.HIGH:
            raise SecurityValidationError(
                "grant.high-risk-persistent",
                "High-risk capability grants can never be persistent.",
            )
        if self.principal_kind is PrincipalKind.SHELL and self.maximum_risk.rank >= RiskLevel.CONSEQUENTIAL.rank:
            raise SecurityValidationError(
                "grant.shell-consequential",
                "The shell principal cannot hold a standing consequential or high-risk grant.",
            )
        if self.principal_kind is PrincipalKind.TASK:
            if self.task_id is None or not _STABLE_RE.fullmatch(self.task_id):
                raise SecurityValidationError("grant.task", "Task grants require a stable task ID.")
        elif self.task_id is not None:
            raise SecurityValidationError("grant.task", "Only task principals can receive task-scoped grants.")
        if not isinstance(self.constraints, Mapping):
            raise SecurityValidationError("grant.constraints", "Grant constraints must be an object.")
        normalized: dict[str, tuple[Any, ...]] = {}
        for path, allowed in self.constraints.items():
            if not isinstance(path, str):
                raise SecurityValidationError("grant.constraint-path", "Constraint paths must be strings.")
            if not isinstance(allowed, (tuple, list)) or not allowed:
                raise SecurityValidationError(
                    "grant.constraint-values",
                    "Every constraint requires at least one explicit allowed value.",
                )
            normalized_values = tuple(normalize_json(item) for item in allowed)
            if any(not (item is None or isinstance(item, (bool, int, str))) for item in normalized_values):
                raise SecurityValidationError(
                    "grant.constraint-values",
                    "Constraint values must be explicit JSON scalars.",
                )
            normalized[path] = normalized_values
            # Validate path syntax at grant issuance, not first authorization.
            dummy = object.__new__(OperationRequest)
            object.__setattr__(dummy, "arguments", {})
            object.__setattr__(dummy, "context", {})
            _lookup_dotted(dummy, path)
        object.__setattr__(self, "constraints", MappingProxyType(normalized))

    def matches(self, request: OperationRequest, *, now: datetime) -> tuple[bool, str]:
        if not _is_aware(now):
            raise SecurityValidationError("grant.time", "Authorization time must be timezone-aware.")
        if now < self.issued_at:
            return False, "grant.not-yet-valid"
        if now >= self.expires_at:
            return False, "grant.expired"
        if request.principal_id != self.principal_id:
            return False, "grant.principal"
        if request.capability != self.capability:
            return False, "grant.capability"
        if request.resource != self.resource:
            return False, "grant.resource"
        if request.risk.rank > self.maximum_risk.rank:
            return False, "grant.risk"
        if self.principal_kind is PrincipalKind.TASK and request.task_id != self.task_id:
            return False, "grant.task"
        for path, allowed in self.constraints.items():
            actual = _lookup_dotted(request, path)
            if actual is _MISSING or normalize_json(actual) not in allowed:
                return False, "grant.constraint"
        return True, "grant.matched"
