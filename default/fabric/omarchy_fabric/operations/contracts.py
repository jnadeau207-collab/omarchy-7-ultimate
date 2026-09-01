"""Closed immutable values shared by the operation coordinator and executor."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from types import MappingProxyType
from typing import Any, Callable, Mapping

from ..models import FabricError
from ..security.normalize import binding_digest, normalize_json
from ..security.principal import EndpointPrincipal
from ..security.redaction import scan_for_secrets
from ..security.types import OperationRequest, ResourceRef, RiskLevel

_UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_STABLE = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$")
_CAPABILITY = re.compile(r"^[a-z][a-z0-9-]*(?:\.[a-z][a-z0-9-]*)+$")
_DIGEST = re.compile(r"^[0-9a-f]{64}$")
_REVISION = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,255}$")

MAX_PLAN_BYTES = 256 * 1024
MAX_EVENT_PAYLOAD_BYTES = 16 * 1024
MAX_LEDGER_PAGE = 64
ZERO_HASH = "0" * 64

def operation_error(
    code: str,
    explanation: str,
    *,
    detail: str = "",
    retryable: bool = False,
    change_state: str = "none",
    recovery_actions: tuple[str, ...] = (),
) -> FabricError:
    return FabricError(
        code,
        "Fabric operation could not continue",
        explanation,
        detail=detail,
        retryable=retryable,
        change_state=change_state,
        recovery_actions=recovery_actions,
    )

def _stable(value: Any, label: str) -> str:
    if not isinstance(value, str) or len(value) > 256 or not _STABLE.fullmatch(value):
        raise operation_error("operation.invalid-contract", f"{label} must be a stable identifier.")
    return value

def _revision(value: Any, label: str) -> str:
    if not isinstance(value, str) or not _REVISION.fullmatch(value):
        raise operation_error("operation.invalid-contract", f"{label} must be a bounded revision token.")
    return value

def _digest(value: Any, label: str) -> str:
    if not isinstance(value, str) or not _DIGEST.fullmatch(value):
        raise operation_error("operation.invalid-contract", f"{label} must be a SHA-256 digest.")
    return value

def _json_object(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise operation_error("operation.invalid-contract", f"{label} must be a JSON object.")
    try:
        normalized = normalize_json(value)
    except Exception as error:
        raise operation_error(
            "operation.invalid-contract",
            f"{label} must be unambiguous bounded JSON.",
            detail=type(error).__name__,
        ) from error
    if scan_for_secrets(normalized):
        raise operation_error(
            "operation.secret-rejected",
            f"{label} contains credential-shaped data and cannot enter an operation record.",
        )
    return _freeze_json(normalized)

def _projection_object(value: Any, label: str) -> Mapping[str, Any]:
    """Freeze already-redacted durable evidence without rejecting the marker."""

    if not isinstance(value, Mapping):
        raise operation_error("operation.invalid-contract", f"{label} must be a JSON object.")
    try:
        return _freeze_json(normalize_json(value))
    except Exception as error:
        raise operation_error(
            "operation.invalid-contract",
            f"{label} must be unambiguous bounded JSON.",
            detail=type(error).__name__,
        ) from error

def _freeze_json(value: Any) -> Any:
    """Recursively freeze an already-normalized JSON value."""

    if isinstance(value, dict):
        return MappingProxyType({key: _freeze_json(item) for key, item in value.items()})
    if isinstance(value, list):
        return tuple(_freeze_json(item) for item in value)
    return value

def _plain_json(value: Any) -> Any:
    """Return an independent plain JSON copy of a frozen contract value."""

    return normalize_json(value)

def owner_id_for(principal: EndpointPrincipal) -> str:
    """Derive the stable account owner from daemon-verified peer identity."""

    if not isinstance(principal, EndpointPrincipal) or isinstance(principal.uid, bool) or principal.uid < 0:
        raise operation_error("operation.principal-invalid", "An active daemon-issued endpoint principal is required.")
    return f"account.uid.{principal.uid}"

class OperationStatus(str, Enum):
    AWAITING_APPROVAL = "awaiting-approval"
    AUTHORIZED = "authorized"
    RUNNING = "running"
    INTERRUPTED = "interrupted"
    RECONCILING = "reconciling"
    ROLLING_BACK = "rolling-back"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    CANCELLED = "cancelled"
    SUPERSEDED = "superseded"

    @property
    def terminal(self) -> bool:
        return self in {
            self.SUCCEEDED,
            self.FAILED,
            self.CANCELLED,
            self.SUPERSEDED,
        }

class OperationCheckpoint(str, Enum):
    PREFLIGHT = "preflight"
    APPROVAL = "approval"
    AUTHORIZED = "authorized"
    APPLYING = "applying"
    APPLIED = "applied"
    VALIDATING = "validating"
    ROLLING_BACK = "rolling-back"
    RECONCILING = "reconciling"
    FINISHED = "finished"

@dataclass(frozen=True)
class ProviderBinding:
    provider_id: str
    version: str
    fingerprint: str
    generation: int

    def __post_init__(self) -> None:
        _stable(self.provider_id, "Provider ID")
        _revision(self.version, "Provider version")
        _digest(self.fingerprint, "Provider fingerprint")
        if isinstance(self.generation, bool) or not isinstance(self.generation, int) or self.generation < 1:
            raise operation_error("operation.invalid-contract", "Provider generation must be a positive integer.")

    def as_dict(self) -> dict[str, Any]:
        return {
            "id": self.provider_id,
            "version": self.version,
            "fingerprint": self.fingerprint,
            "generation": self.generation,
        }

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "ProviderBinding":
        if not isinstance(value, Mapping) or set(value) != {"id", "version", "fingerprint", "generation"}:
            raise operation_error("operation.invalid-contract", "Provider binding fields are not exact.")
        return cls(value["id"], value["version"], value["fingerprint"], value["generation"])

@dataclass(frozen=True)
class ResourceBinding:
    kind: str
    resource_id: str
    revision: str

    def __post_init__(self) -> None:
        _stable(self.kind, "Resource kind")
        try:
            ResourceRef(self.kind, self.resource_id)
        except Exception as error:
            raise operation_error("operation.invalid-contract", "Resource binding is invalid.") from error
        _revision(self.revision, "Resource revision")

    def as_dict(self) -> dict[str, str]:
        return {"kind": self.kind, "id": self.resource_id, "revision": self.revision}

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "ResourceBinding":
        if not isinstance(value, Mapping) or set(value) != {"kind", "id", "revision"}:
            raise operation_error("operation.invalid-contract", "Resource binding fields are not exact.")
        return cls(value["kind"], value["id"], value["revision"])

@dataclass(frozen=True)
class ExecutorIntent:
    intent_id: str
    template_fingerprint: str
    payload: Mapping[str, Any]

    def __post_init__(self) -> None:
        _stable(self.intent_id, "Executor intent ID")
        _digest(self.template_fingerprint, "Executor template fingerprint")
        object.__setattr__(self, "payload", _json_object(self.payload, "Executor payload"))

    @property
    def digest(self) -> str:
        return binding_digest(self.as_dict())

    def as_dict(self) -> dict[str, Any]:
        return {
            "intentId": self.intent_id,
            "templateFingerprint": self.template_fingerprint,
            "payload": _plain_json(self.payload),
        }

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "ExecutorIntent":
        if not isinstance(value, Mapping) or set(value) != {"intentId", "templateFingerprint", "payload"}:
            raise operation_error("operation.invalid-contract", "Executor intent fields are not exact.")
        return cls(value["intentId"], value["templateFingerprint"], value["payload"])

@dataclass(frozen=True)
class OperationDefinition:
    """Code-owned provider/action to executor-intent mapping."""

    provider_id: str
    action: str
    intent_id: str
    payload_builder: Callable[[Mapping[str, Any]], Mapping[str, Any]]

    def __post_init__(self) -> None:
        _stable(self.provider_id, "Definition provider")
        _stable(self.action, "Definition action")
        _stable(self.intent_id, "Definition intent")
        if not callable(self.payload_builder):
            raise operation_error("operation.invalid-definition", "Intent payload builder must be code-owned callable.")

@dataclass(frozen=True)
class OperationPlan:
    operation_id: str
    owner_id: str
    owner_uid: int
    principal_id: str
    session_id: str
    endpoint_id: str
    task_id: str | None
    provider: ProviderBinding
    action: str
    capability: str
    risk: RiskLevel
    resource: ResourceBinding
    policy_revision: str
    idempotency_digest: str
    normalized_arguments: Mapping[str, Any]
    preflight: Mapping[str, Any]
    intent: ExecutorIntent
    created_at: str

    def __post_init__(self) -> None:
        if not isinstance(self.operation_id, str) or not _UUID.fullmatch(self.operation_id):
            raise operation_error("operation.invalid-contract", "Operation ID must be a lowercase UUID.")
        for label, value in (
            ("Owner ID", self.owner_id),
            ("Principal ID", self.principal_id),
            ("Session ID", self.session_id),
            ("Endpoint ID", self.endpoint_id),
            ("Action", self.action),
        ):
            _stable(value, label)
        if self.task_id is not None:
            _stable(self.task_id, "Task ID")
        if isinstance(self.owner_uid, bool) or not isinstance(self.owner_uid, int) or self.owner_uid < 0:
            raise operation_error("operation.invalid-contract", "Owner UID must be non-negative.")
        if self.owner_id != f"account.uid.{self.owner_uid}":
            raise operation_error("operation.owner-spoof", "Owner identity must be derived from the peer UID.")
        if not isinstance(self.provider, ProviderBinding) or not isinstance(self.resource, ResourceBinding):
            raise operation_error("operation.invalid-contract", "Provider and resource bindings are required.")
        if not isinstance(self.intent, ExecutorIntent):
            raise operation_error("operation.invalid-contract", "A typed executor intent is required.")
        if not isinstance(self.risk, RiskLevel):
            raise operation_error("operation.invalid-contract", "Operation risk must be typed.")
        if not isinstance(self.capability, str) or len(self.capability) > 256 or not _CAPABILITY.fullmatch(self.capability):
            raise operation_error("operation.invalid-contract", "Capability is invalid.")
        _revision(self.policy_revision, "Policy revision")
        _digest(self.idempotency_digest, "Idempotency digest")
        try:
            created_at = datetime.fromisoformat(self.created_at.replace("Z", "+00:00"))
        except (AttributeError, TypeError, ValueError) as error:
            raise operation_error("operation.invalid-contract", "Creation time must be ISO 8601.") from error
        canonical_created_at = created_at.astimezone(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")
        if (
            created_at.tzinfo is None
            or created_at.utcoffset() is None
            or self.created_at != canonical_created_at
        ):
            raise operation_error("operation.invalid-contract", "Creation time must be canonical UTC.")
        object.__setattr__(self, "normalized_arguments", _json_object(self.normalized_arguments, "Normalized arguments"))
        object.__setattr__(self, "preflight", _json_object(self.preflight, "Provider preflight"))
        self._verify_preflight_coherence()

    def _verify_preflight_coherence(self) -> None:
        required = {
            "schemaVersion", "provider", "providerVersion", "action", "capability", "resource",
            "normalizedArguments", "stateRevision", "currentState", "proposedState",
            "changed", "summary", "risk", "effects", "recovery",
        }
        optional = {"guards"}
        preflight = self.preflight
        if not required <= set(preflight) <= required | optional:
            raise operation_error("operation.plan-corrupt", "Durable provider preflight fields are not exact.")
        if (
            preflight["provider"] != self.provider.provider_id
            or preflight["providerVersion"] != self.provider.version
            or preflight["action"] != self.action
            or preflight["capability"] != self.capability
            or preflight["risk"] != self.risk.value
            or preflight["stateRevision"] != self.resource.revision
            or _plain_json(preflight["normalizedArguments"]) != _plain_json(self.normalized_arguments)
        ):
            raise operation_error("operation.plan-corrupt", "Durable provider preflight disagrees with the operation plan.")
        resource = preflight["resource"]
        current = preflight["currentState"]
        proposed = preflight["proposedState"]
        if (
            not isinstance(resource, Mapping)
            or set(resource) != {"kind", "id"}
            or resource["kind"] != self.resource.kind
            or resource["id"] != self.resource.resource_id
            or not isinstance(current, Mapping)
            or not isinstance(proposed, Mapping)
            or current.get("resourceId") != self.resource.resource_id
            or proposed.get("resourceId") != self.resource.resource_id
            or current.get("revision") != self.resource.revision
        ):
            raise operation_error("operation.plan-corrupt", "Durable resource state bindings are inconsistent.")

    @property
    def arguments_digest(self) -> str:
        return binding_digest(dict(self.normalized_arguments))

    @property
    def preflight_digest(self) -> str:
        return binding_digest(dict(self.preflight))

    @property
    def binding_digest(self) -> str:
        return binding_digest(self.security_request().approval_payload())

    @property
    def request_fingerprint(self) -> str:
        """Immutable idempotency fingerprint, excluding generated operation ID/time."""

        return binding_digest(
            {
                "ownerId": self.owner_id,
                "ownerUid": self.owner_uid,
                "principalId": self.principal_id,
                "sessionId": self.session_id,
                "endpointId": self.endpoint_id,
                "taskId": self.task_id,
                "provider": self.provider.as_dict(),
                "action": self.action,
                "capability": self.capability,
                "risk": self.risk.value,
                "resource": self.resource.as_dict(),
                "policyRevision": self.policy_revision,
                "idempotencyDigest": self.idempotency_digest,
                "normalizedArguments": _plain_json(self.normalized_arguments),
                "preflightDigest": self.preflight_digest,
                "intentDigest": self.intent.digest,
            }
        )

    def approval_arguments(self) -> dict[str, Any]:
        """Everything beyond OperationRequest's native exact binding."""

        return {
            "ownerId": self.owner_id,
            "ownerUid": self.owner_uid,
            "endpointId": self.endpoint_id,
            "providerId": self.provider.provider_id,
            "providerFingerprint": self.provider.fingerprint,
            "providerGeneration": self.provider.generation,
            "policyRevision": self.policy_revision,
            "idempotencyDigest": self.idempotency_digest,
            "argumentsDigest": self.arguments_digest,
            "preflightDigest": self.preflight_digest,
            "intentDigest": self.intent.digest,
        }

    def security_request(self) -> OperationRequest:
        return OperationRequest(
            operation_id=self.operation_id,
            principal_id=self.principal_id,
            session_id=self.session_id,
            capability=self.capability,
            resource=ResourceRef(self.resource.kind, self.resource.resource_id),
            provider_version=self.provider.version,
            state_revision=self.resource.revision,
            risk=self.risk,
            arguments=self.approval_arguments(),
            context={},
            task_id=self.task_id,
        )

    def as_dict(self) -> dict[str, Any]:
        return {
            "schemaVersion": "v0",
            "operationId": self.operation_id,
            "owner": {"id": self.owner_id, "uid": self.owner_uid},
            "origin": {
                "principalId": self.principal_id,
                "sessionId": self.session_id,
                "endpointId": self.endpoint_id,
                "taskId": self.task_id,
            },
            "provider": self.provider.as_dict(),
            "action": self.action,
            "capability": self.capability,
            "risk": self.risk.value,
            "resource": self.resource.as_dict(),
            "policyRevision": self.policy_revision,
            "idempotencyDigest": self.idempotency_digest,
            "normalizedArguments": _plain_json(self.normalized_arguments),
            "preflight": _plain_json(self.preflight),
            "intent": self.intent.as_dict(),
            "bindingDigest": self.binding_digest,
            "createdAt": self.created_at,
        }

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "OperationPlan":
        required = {
            "schemaVersion", "operationId", "owner", "origin", "provider", "action",
            "capability", "risk", "resource", "policyRevision", "idempotencyDigest",
            "normalizedArguments", "preflight", "intent", "bindingDigest", "createdAt",
        }
        if not isinstance(value, Mapping) or set(value) != required or value.get("schemaVersion") != "v0":
            raise operation_error("operation.invalid-contract", "Operation plan fields are not exact.")
        owner = value["owner"]
        origin = value["origin"]
        if not isinstance(owner, Mapping) or set(owner) != {"id", "uid"}:
            raise operation_error("operation.invalid-contract", "Owner binding fields are not exact.")
        if not isinstance(origin, Mapping) or set(origin) != {"principalId", "sessionId", "endpointId", "taskId"}:
            raise operation_error("operation.invalid-contract", "Origin binding fields are not exact.")
        try:
            risk = RiskLevel(value["risk"])
        except (TypeError, ValueError) as error:
            raise operation_error("operation.invalid-contract", "Operation risk is invalid.") from error
        plan = cls(
            operation_id=value["operationId"],
            owner_id=owner["id"],
            owner_uid=owner["uid"],
            principal_id=origin["principalId"],
            session_id=origin["sessionId"],
            endpoint_id=origin["endpointId"],
            task_id=origin["taskId"],
            provider=ProviderBinding.from_dict(value["provider"]),
            action=value["action"],
            capability=value["capability"],
            risk=risk,
            resource=ResourceBinding.from_dict(value["resource"]),
            policy_revision=value["policyRevision"],
            idempotency_digest=value["idempotencyDigest"],
            normalized_arguments=value["normalizedArguments"],
            preflight=value["preflight"],
            intent=ExecutorIntent.from_dict(value["intent"]),
            created_at=value["createdAt"],
        )
        if value["bindingDigest"] != plan.binding_digest:
            raise operation_error("operation.plan-corrupt", "The durable operation binding digest does not match its plan.")
        return plan

@dataclass(frozen=True)
class OperationState:
    plan: OperationPlan
    status: OperationStatus
    checkpoint: OperationCheckpoint
    cancellation_requested: bool
    event_count: int
    last_sequence: int
    result: Mapping[str, Any] | None = field(default=None)
    error: Mapping[str, Any] | None = field(default=None)

    def __post_init__(self) -> None:
        if not isinstance(self.plan, OperationPlan):
            raise operation_error("operation.invalid-contract", "Operation state requires an immutable plan.")
        if not isinstance(self.status, OperationStatus) or not isinstance(self.checkpoint, OperationCheckpoint):
            raise operation_error("operation.invalid-contract", "Operation state lifecycle values are invalid.")
        if not isinstance(self.cancellation_requested, bool):
            raise operation_error("operation.invalid-contract", "Operation cancellation state is invalid.")
        if (
            isinstance(self.event_count, bool)
            or isinstance(self.last_sequence, bool)
            or not isinstance(self.event_count, int)
            or not isinstance(self.last_sequence, int)
            or self.event_count < 1
            or self.last_sequence != self.event_count
        ):
            raise operation_error("operation.invalid-contract", "Operation event projection is invalid.")
        if self.result is not None:
            object.__setattr__(self, "result", _projection_object(self.result, "Operation result"))
        if self.error is not None:
            object.__setattr__(self, "error", _projection_object(self.error, "Operation error"))

    def as_dict(self) -> dict[str, Any]:
        document: dict[str, Any] = {
            "schemaVersion": "v0",
            "operationId": self.plan.operation_id,
            "ownerId": self.plan.owner_id,
            "provider": self.plan.provider.as_dict(),
            "action": self.plan.action,
            "capability": self.plan.capability,
            "resource": self.plan.resource.as_dict(),
            "policyRevision": self.plan.policy_revision,
            "bindingDigest": self.plan.binding_digest,
            "status": self.status.value,
            "checkpoint": self.checkpoint.value,
            "cancellationRequested": self.cancellation_requested,
            "eventCount": self.event_count,
            "lastSequence": self.last_sequence,
        }
        if self.result is not None:
            document["result"] = _plain_json(self.result)
        if self.error is not None:
            document["error"] = _plain_json(self.error)
        return document
