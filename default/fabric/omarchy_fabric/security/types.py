"""Shared immutable security-domain value objects."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import Enum
from types import MappingProxyType
from typing import Any, Mapping

from .errors import SecurityValidationError
from .normalize import normalize_json

_CAPABILITY_RE = re.compile(r"^[a-z][a-z0-9-]*(?:\.[a-z][a-z0-9-]*)+$")
_STABLE_RE = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$")
_UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

class RiskLevel(str, Enum):
    LOW = "low"
    CONSEQUENTIAL = "consequential"
    HIGH = "high"

    @property
    def rank(self) -> int:
        return {self.LOW: 0, self.CONSEQUENTIAL: 1, self.HIGH: 2}[self]

class DecisionKind(str, Enum):
    ALLOW = "allow"
    DENY = "deny"
    CONSENT_REQUIRED = "consent-required"

@dataclass(frozen=True)
class ResourceRef:
    kind: str
    resource_id: str

    def __post_init__(self) -> None:
        if not isinstance(self.kind, str) or not _STABLE_RE.fullmatch(self.kind):
            raise SecurityValidationError("resource.kind", "Resource kind must be a stable identifier.")
        if (
            not isinstance(self.resource_id, str)
            or not self.resource_id
            or len(self.resource_id) > 256
            or "\x00" in self.resource_id
        ):
            raise SecurityValidationError("resource.id", "Resource identity is missing or invalid.")
        if "/" in self.resource_id or "\\" in self.resource_id or self.resource_id in {".", ".."}:
            raise SecurityValidationError("resource.path", "Resources use stable identities, never paths.")

    def as_dict(self) -> dict[str, str]:
        return {"kind": self.kind, "id": self.resource_id}

@dataclass(frozen=True)
class OperationRequest:
    operation_id: str
    principal_id: str
    session_id: str
    capability: str
    resource: ResourceRef
    provider_version: str
    state_revision: str
    risk: RiskLevel
    arguments: Mapping[str, Any] = field(default_factory=dict)
    context: Mapping[str, Any] = field(default_factory=dict)
    task_id: str | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.risk, RiskLevel):
            raise SecurityValidationError("operation.risk", "Operation risk is invalid.")
        if not isinstance(self.operation_id, str) or not _UUID_RE.fullmatch(self.operation_id):
            raise SecurityValidationError("operation.id", "Operation ID must be a lowercase UUID.")
        if not isinstance(self.principal_id, str) or not _STABLE_RE.fullmatch(self.principal_id):
            raise SecurityValidationError("operation.principal", "Principal ID must be a stable identifier.")
        if not isinstance(self.session_id, str) or not _STABLE_RE.fullmatch(self.session_id):
            raise SecurityValidationError("operation.session", "Session ID must be a stable identifier.")
        if not isinstance(self.capability, str) or not _CAPABILITY_RE.fullmatch(self.capability):
            raise SecurityValidationError("operation.capability", "Capability ID is invalid.")
        if (
            not isinstance(self.provider_version, str)
            or not self.provider_version
            or len(self.provider_version) > 160
            or "\x00" in self.provider_version
        ):
            raise SecurityValidationError("operation.provider-version", "Provider version is required.")
        if (
            not isinstance(self.state_revision, str)
            or not self.state_revision
            or len(self.state_revision) > 256
            or "\x00" in self.state_revision
        ):
            raise SecurityValidationError("operation.state-revision", "State revision is required.")
        if self.task_id is not None and (
            not isinstance(self.task_id, str) or not _STABLE_RE.fullmatch(self.task_id)
        ):
            raise SecurityValidationError("operation.task", "Task ID must be a stable identifier.")
        if not isinstance(self.resource, ResourceRef):
            raise SecurityValidationError("operation.resource", "Operation resource must be a ResourceRef.")
        if not isinstance(self.arguments, Mapping) or not isinstance(self.context, Mapping):
            raise SecurityValidationError("operation.json", "Operation arguments and context must be objects.")
        object.__setattr__(self, "arguments", MappingProxyType(normalize_json(self.arguments)))
        object.__setattr__(self, "context", MappingProxyType(normalize_json(self.context)))

    def approval_payload(self) -> dict[str, Any]:
        return {
            "operationId": self.operation_id,
            "principalId": self.principal_id,
            "sessionId": self.session_id,
            "capability": self.capability,
            "resource": self.resource.as_dict(),
            "providerVersion": self.provider_version,
            "stateRevision": self.state_revision,
            "risk": self.risk.value,
            "arguments": dict(self.arguments),
            "taskId": self.task_id,
        }

@dataclass(frozen=True)
class PolicyDecision:
    decision: DecisionKind
    code: str
    explanation: str
    operation_id: str
    principal_id: str
    grant_id: str | None = None
    approval_id: str | None = None

    @property
    def allowed(self) -> bool:
        return self.decision is DecisionKind.ALLOW

    def as_dict(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "schemaVersion": "v0",
            "decision": self.decision.value,
            "code": self.code,
            "explanation": self.explanation,
            "operationId": self.operation_id,
            "principalId": self.principal_id,
        }
        if self.grant_id is not None:
            result["grantId"] = self.grant_id
        if self.approval_id is not None:
            result["approvalId"] = self.approval_id
        return result
