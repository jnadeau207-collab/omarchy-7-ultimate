"""Single durable mutation path for typed Fabric provider operations."""

from __future__ import annotations

import asyncio
import math
import re
import uuid
from datetime import datetime, timezone
from types import MappingProxyType
from typing import Any, Awaitable, Callable, Iterable, Mapping

from ..models import FabricError
from ..security.approval import ApprovalAuthority
from ..security.errors import SecurityValidationError
from ..security.grants import CapabilityGrant
from ..security.normalize import canonical_json, normalize_json
from ..security.policy import PolicyEngine
from ..security.principal import EndpointPrincipal
from ..security.redaction import redact, scan_for_secrets
from ..security.types import RiskLevel
from .contracts import (
    OperationCheckpoint,
    OperationDefinition,
    OperationPlan,
    OperationState,
    OperationStatus,
    ProviderBinding,
    ResourceBinding,
    operation_error,
    owner_id_for,
)
from .executor import (
    ExecutorApplyResult,
    ExecutorReconcileResult,
    IntentCatalog,
    OperationExecutor,
    normalize_executor_evidence,
)
from .registry_gateway import OperationPreflightGateway
from .store import OperationStore

_IDEMPOTENCY = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$")
_REVISION = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,255}$")
_ERROR_CODE = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$")
MAX_PREFLIGHT_STATE_BYTES = 8 * 1024
MAX_GRANTS_PER_OPERATION = 1024

CheckpointHook = Callable[[str, str], Awaitable[None] | None]


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class OperationCoordinator:
    """Coordinates preflight, exact approval, execution, and reconciliation.

    This class is intentionally not registered in RPC yet. It is the only
    mutation-capable protocol path, but the supplied production executor is
    explicitly unavailable until a root-owned service and Polkit policy exist.
    """

    def __init__(
        self,
        *,
        store: OperationStore,
        gateway: OperationPreflightGateway,
        definitions: tuple[OperationDefinition, ...],
        intents: IntentCatalog,
        executor: OperationExecutor,
        session_resolver: Callable[[EndpointPrincipal], EndpointPrincipal],
        policy_revision: Callable[[], str],
        policy: PolicyEngine | None = None,
        clock: Callable[[], datetime] = _utc_now,
        max_concurrent: int = 4,
        max_operation_locks: int = 256,
        queue_timeout_seconds: float = 1.0,
        execution_timeout_seconds: float = 30.0,
        checkpoint_hook: CheckpointHook | None = None,
    ) -> None:
        records: dict[tuple[str, str], OperationDefinition] = {}
        for definition in definitions:
            if not isinstance(definition, OperationDefinition):
                raise operation_error("operation.invalid-definition", "Operation definition catalog is invalid.")
            key = (definition.provider_id, definition.action)
            if key in records:
                raise operation_error("operation.invalid-definition", "Operation definition catalog is invalid.")
            records[key] = definition
        if not records:
            raise operation_error("operation.invalid-definition", "At least one code-owned operation definition is required.")
        if isinstance(max_concurrent, bool) or not 1 <= max_concurrent <= 64:
            raise operation_error("operation.invalid-capacity", "Coordinator concurrency is invalid.")
        if isinstance(max_operation_locks, bool) or not 1 <= max_operation_locks <= 4096:
            raise operation_error("operation.invalid-capacity", "Coordinator operation-lock capacity is invalid.")
        if not 0.01 <= queue_timeout_seconds <= 60 or not 0.05 <= execution_timeout_seconds <= 600:
            raise operation_error("operation.invalid-timeout", "Coordinator deadlines are invalid.")
        self.store = store
        self.gateway = gateway
        self.definitions = MappingProxyType(records)
        self.intents = intents
        self.executor = executor
        self.session_resolver = session_resolver
        self.policy_revision = policy_revision
        self.policy = policy or PolicyEngine()
        self.clock = clock
        self.queue_timeout_seconds = queue_timeout_seconds
        self.execution_timeout_seconds = execution_timeout_seconds
        self.checkpoint_hook = checkpoint_hook
        self._capacity = asyncio.Semaphore(max_concurrent)
        self._max_operation_locks = max_operation_locks
        self._operation_locks: dict[str, asyncio.Lock] = {}
        self._operation_lock_references: dict[str, int] = {}

    def _active(self, principal: EndpointPrincipal) -> EndpointPrincipal:
        try:
            active = self.session_resolver(principal)
        except FabricError:
            raise
        except SecurityValidationError as error:
            raise operation_error(error.code, error.explanation) from error
        except Exception as error:
            raise operation_error(
                "operation.principal-invalid",
                "Endpoint session could not be verified.",
                detail=type(error).__name__,
            ) from error
        if active != principal:
            raise operation_error("operation.principal-invalid", "Endpoint resolver returned another principal.")
        return active

    def _current_policy_revision(self) -> str:
        try:
            revision = self.policy_revision()
        except Exception as error:
            raise operation_error(
                "operation.policy-unavailable",
                "Current policy revision could not be read.",
                detail=type(error).__name__,
            ) from error
        if not isinstance(revision, str) or not _REVISION.fullmatch(revision):
            raise operation_error("operation.policy-invalid", "Current policy revision is invalid.")
        return revision

    @staticmethod
    def _idempotency_digest(value: Any) -> str:
        if not isinstance(value, str) or not _IDEMPOTENCY.fullmatch(value):
            raise operation_error("operation.idempotency-invalid", "Idempotency key is invalid.")
        import hashlib

        return hashlib.sha256(value.encode("utf-8")).hexdigest()

    async def _acquire_operation_lock(self, operation_id: str) -> asyncio.Lock:
        lock = self._operation_locks.get(operation_id)
        if lock is None:
            if len(self._operation_locks) >= self._max_operation_locks:
                raise operation_error(
                    "operation.lock-backpressure",
                    "Coordinator operation-lock capacity is busy.",
                    retryable=True,
                )
            lock = asyncio.Lock()
            self._operation_locks[operation_id] = lock
            self._operation_lock_references[operation_id] = 0
        self._operation_lock_references[operation_id] += 1
        try:
            await lock.acquire()
        except BaseException:
            self._release_operation_lock_reference(operation_id, lock, acquired=False)
            raise
        return lock

    async def _acquire_capacity(self) -> None:
        try:
            await asyncio.wait_for(self._capacity.acquire(), timeout=self.queue_timeout_seconds)
        except asyncio.TimeoutError as error:
            raise operation_error(
                "operation.backpressure",
                "Coordinator capacity is busy.",
                retryable=True,
            ) from error

    async def _acquire_bounded_operation_lock(self, operation_id: str) -> asyncio.Lock:
        try:
            return await asyncio.wait_for(
                self._acquire_operation_lock(operation_id),
                timeout=self.queue_timeout_seconds,
            )
        except asyncio.TimeoutError as error:
            raise operation_error(
                "operation.backpressure",
                "Coordinator operation is already busy.",
                retryable=True,
            ) from error

    def _release_operation_lock_reference(
        self,
        operation_id: str,
        lock: asyncio.Lock,
        *,
        acquired: bool,
    ) -> None:
        if acquired:
            lock.release()
        remaining = self._operation_lock_references.get(operation_id, 1) - 1
        if remaining <= 0 and not lock.locked():
            self._operation_lock_references.pop(operation_id, None)
            if self._operation_locks.get(operation_id) is lock:
                self._operation_locks.pop(operation_id, None)
        else:
            self._operation_lock_references[operation_id] = remaining

    @staticmethod
    def _exact_origin(principal: EndpointPrincipal, plan: OperationPlan) -> None:
        if (
            principal.principal_id != plan.principal_id
            or principal.session_id != plan.session_id
            or principal.endpoint_id != plan.endpoint_id
            or principal.uid != plan.owner_uid
            or principal.task_id != plan.task_id
        ):
            raise operation_error(
                "operation.origin-session-drift",
                "Approval and initial execution require the exact originating endpoint session.",
            )

    @staticmethod
    def _same_owner(principal: EndpointPrincipal, plan: OperationPlan) -> None:
        if owner_id_for(principal) != plan.owner_id or principal.uid != plan.owner_uid:
            raise operation_error("operation.owner-drift", "Operation belongs to another account owner.")

    def _require_executor_available(self) -> None:
        if not getattr(self.executor, "available", False):
            raise operation_error(
                "executor.production-unavailable",
                "No production executor is available; no new authority was consumed.",
                recovery_actions=("system.executor.install",),
            )

    @staticmethod
    def _bounded_grants(grants: Iterable[CapabilityGrant]) -> tuple[CapabilityGrant, ...]:
        records: list[CapabilityGrant] = []
        try:
            for grant in grants:
                if len(records) >= MAX_GRANTS_PER_OPERATION:
                    raise operation_error("operation.grant-capacity", "Operation grant input exceeds its bound.")
                if not isinstance(grant, CapabilityGrant):
                    raise operation_error("operation.grant-invalid", "Operation grant input is not typed.")
                records.append(grant)
        except FabricError:
            raise
        except Exception as error:
            raise operation_error(
                "operation.grant-invalid",
                "Operation grants could not be read safely.",
                detail=type(error).__name__,
            ) from error
        return tuple(records)

    def _check_authority(
        self,
        principal: EndpointPrincipal,
        plan: OperationPlan,
        approval_id: str,
        approvals: ApprovalAuthority,
        grants: tuple[CapabilityGrant, ...],
    ) -> EndpointPrincipal:
        principal = self._active(principal)
        self._exact_origin(principal, plan)
        self._require_executor_available()
        self.gateway.assert_current(plan.provider)
        if self._current_policy_revision() != plan.policy_revision:
            raise operation_error("operation.policy-stale", "Policy revision changed after preflight.")
        if not self.store.is_latest_resource_intent(plan.operation_id):
            raise operation_error("operation.superseded", "A newer operation owns this resource.")
        self.intents.resolve(plan.intent)
        request = plan.security_request()
        check = approvals.check(approval_id, principal, request, consume=False)
        if not check.valid:
            raise operation_error(check.code, check.explanation)
        decision = self.policy.decide(
            principal,
            request,
            grants,
            approval_authority=approvals,
            approval_id=approval_id,
            now=self.clock(),
            consume_approval=False,
        )
        if not decision.allowed:
            raise operation_error(decision.code, decision.explanation)
        return principal

    def _mark_runtime_interrupted(self, operation_id: str) -> OperationState:
        state = self.store.get(operation_id)
        if state.status.terminal or state.status is OperationStatus.INTERRUPTED:
            return state
        try:
            return self.store.append(
                operation_id,
                "runtime-interrupted",
                state.checkpoint,
                OperationStatus.INTERRUPTED,
                {"requiresReconciliation": True},
            )
        except FabricError as error:
            if error.code == "operation.terminal":
                return self.store.get(operation_id)
            raise

    @staticmethod
    def _validate_executor_state(
        plan: OperationPlan,
        state_revision: str,
        observed_state: Mapping[str, Any],
        target_state: Mapping[str, Any] | None,
        *,
        change_state: str,
    ) -> None:
        try:
            observed = normalize_json(observed_state)
            target = normalize_json(target_state) if target_state is not None else None
        except Exception as error:
            raise operation_error(
                "executor.invalid-result",
                "Executor state result is not bounded canonical JSON.",
                detail=type(error).__name__,
                change_state=change_state,
            ) from error
        if (
            not isinstance(observed, Mapping)
            or observed.get("resourceId") != plan.resource.resource_id
            or observed.get("revision") != state_revision
        ):
            raise operation_error(
                "executor.invalid-result",
                "Executor state result disagrees with its resource binding.",
                change_state=change_state,
            )
        if target is not None:
            if not isinstance(target, Mapping) or set(observed) != set(target):
                raise operation_error(
                    "executor.invalid-result",
                    "Executor state shape disagrees with the approved target.",
                    change_state=change_state,
                )
            observed_without_revision = {key: value for key, value in observed.items() if key != "revision"}
            target_without_revision = {key: value for key, value in target.items() if key != "revision"}
            if observed_without_revision != target_without_revision:
                raise operation_error(
                    "executor.invalid-result",
                    "Executor state disagrees with the approved target.",
                    change_state=change_state,
                )

    @classmethod
    def _validate_apply_result(
        cls,
        plan: OperationPlan,
        result: Any,
        target_state: Mapping[str, Any],
    ) -> ExecutorApplyResult:
        if not isinstance(result, ExecutorApplyResult):
            raise operation_error(
                "executor.invalid-result",
                "Executor apply returned no typed result.",
                change_state="unknown",
            )
        cls._validate_executor_state(
            plan,
            result.state_revision,
            result.expected_state,
            target_state,
            change_state="unknown",
        )
        return result

    @classmethod
    def _validate_reconcile_result(
        cls,
        plan: OperationPlan,
        result: Any,
    ) -> ExecutorReconcileResult:
        if not isinstance(result, ExecutorReconcileResult):
            raise operation_error("executor.invalid-result", "Executor reconcile returned no typed result.")
        target = None
        if result.disposition == "before":
            target = plan.preflight["currentState"]
        elif result.disposition == "desired":
            target = plan.preflight["proposedState"]
        cls._validate_executor_state(
            plan,
            result.state_revision,
            result.observed_state,
            target,
            change_state="none",
        )
        return result

    async def _hook(self, operation_id: str, checkpoint: str) -> None:
        if self.checkpoint_hook is None:
            return
        result = self.checkpoint_hook(operation_id, checkpoint)
        if asyncio.iscoroutine(result):
            await result

    @staticmethod
    def _risk(value: Any) -> RiskLevel:
        try:
            return RiskLevel(value)
        except (TypeError, ValueError) as error:
            raise operation_error("operation.preflight-invalid", "Provider preflight risk is invalid.") from error

    @staticmethod
    def _preflight_fields(value: Mapping[str, Any], outer: Mapping[str, Any]) -> tuple[ResourceBinding, Mapping[str, Any]]:
        required = {
            "provider", "providerVersion", "action", "capability", "resource",
            "normalizedArguments", "stateRevision", "currentState", "proposedState", "risk", "effects",
        }
        optional = {"changed", "summary", "recovery"}
        if not isinstance(value, Mapping) or set(value) != required | optional:
            raise operation_error("operation.preflight-invalid", "Provider preflight lacks required exact bindings.")
        if (
            value["provider"] != outer["provider"]
            or value["providerVersion"] != outer["providerVersion"]
            or value["action"] != outer["action"]
            or value["capability"] != outer["capability"]
            or value["risk"] != outer["risk"]
            or value["effects"] != outer["effects"]
        ):
            raise operation_error("operation.preflight-invalid", "Provider preflight duplicates disagree with registry bindings.")
        effects = outer["effects"]
        if (
            not isinstance(effects, list)
            or not 1 <= len(effects) <= 16
            or any(
                not isinstance(effect, str)
                or len(effect) > 256
                or not _ERROR_CODE.fullmatch(effect)
                for effect in effects
            )
            or len(set(effects)) != len(effects)
        ):
            raise operation_error("operation.preflight-invalid", "Provider effects must be a bounded unique list.")
        resource = value["resource"]
        if not isinstance(resource, Mapping) or set(resource) != {"kind", "id"}:
            raise operation_error("operation.preflight-invalid", "Provider resource binding is not exact.")
        current = value["currentState"]
        proposed = value["proposedState"]
        if not isinstance(current, Mapping) or not isinstance(proposed, Mapping):
            raise operation_error("operation.preflight-invalid", "Provider state bindings must be objects.")
        if current.get("resourceId") != resource["id"] or proposed.get("resourceId") != resource["id"]:
            raise operation_error("operation.preflight-invalid", "Provider states belong to another resource.")
        if current.get("revision") != value["stateRevision"]:
            raise operation_error("operation.preflight-invalid", "Provider current-state revision is inconsistent.")
        if (
            not isinstance(proposed.get("revision"), str)
            or not _REVISION.fullmatch(proposed["revision"])
            or not isinstance(value["changed"], bool)
            or not isinstance(value["summary"], str)
            or not 1 <= len(value["summary"]) <= 1024
            or not isinstance(value["recovery"], Mapping)
        ):
            raise operation_error("operation.preflight-invalid", "Provider state and recovery metadata are invalid.")
        if any(
            len(canonical_json(state).encode("utf-8")) > MAX_PREFLIGHT_STATE_BYTES
            for state in (current, proposed)
        ):
            raise operation_error(
                "operation.preflight-invalid",
                "Provider state exceeds the durable executor checkpoint bound.",
            )
        try:
            normalized = normalize_json(value["normalizedArguments"])
        except Exception as error:
            raise operation_error(
                "operation.preflight-invalid",
                "Provider normalized arguments are ambiguous or unbounded.",
                detail=type(error).__name__,
            ) from error
        if not isinstance(normalized, Mapping):
            raise operation_error("operation.preflight-invalid", "Provider normalized arguments must be an object.")
        return ResourceBinding(resource["kind"], resource["id"], value["stateRevision"]), normalized

    async def preflight(
        self,
        principal: EndpointPrincipal,
        *,
        provider_id: str,
        action: str,
        arguments: Mapping[str, Any],
        idempotency_key: str,
    ) -> dict[str, Any]:
        principal = self._active(principal)
        definition = self.definitions.get((provider_id, action))
        if definition is None:
            raise operation_error("operation.definition-unavailable", "Action has no code-owned operation definition.")
        idempotency_digest = self._idempotency_digest(idempotency_key)
        try:
            raw_outer = await self.gateway.preflight(provider_id, action, arguments, principal)
        except FabricError:
            raise
        except Exception as error:
            raise operation_error(
                "operation.preflight-failed",
                "Provider preflight failed without a structured bounded error.",
                detail=type(error).__name__,
            ) from error
        required_outer = {
            "provider", "providerVersion", "providerFingerprint", "generation", "action",
            "capability", "risk", "effects", "preflight", "observedAt",
        }
        if not isinstance(raw_outer, Mapping) or set(raw_outer) != required_outer:
            raise operation_error("operation.preflight-invalid", "Registry preflight envelope fields are not exact.")
        raw_snapshot = dict(raw_outer)
        observed_at = raw_snapshot.pop("observedAt")
        if (
            isinstance(observed_at, bool)
            or not isinstance(observed_at, (int, float))
            or observed_at < 0
            or observed_at > 1_000_000_000_000_000
            or not math.isfinite(observed_at)
        ):
            raise operation_error("operation.preflight-invalid", "Registry observation time is invalid.")
        try:
            outer = normalize_json(raw_snapshot)
        except Exception as error:
            raise operation_error(
                "operation.preflight-invalid",
                "Registry preflight envelope is not bounded canonical JSON.",
                detail=type(error).__name__,
            ) from error
        if scan_for_secrets(outer):
            raise operation_error(
                "operation.secret-rejected",
                "Registry preflight contains credential-shaped data and cannot be persisted.",
            )
        if outer["provider"] != provider_id or outer["action"] != action:
            raise operation_error("operation.preflight-invalid", "Registry preflight targets another provider action.")
        resource, normalized_arguments = self._preflight_fields(outer["preflight"], outer)
        provider = ProviderBinding(
            outer["provider"],
            outer["providerVersion"],
            outer["providerFingerprint"],
            outer["generation"],
        )
        policy_revision = self._current_policy_revision()
        try:
            intent_payload = definition.payload_builder(normalize_json(outer["preflight"]))
        except FabricError:
            raise
        except Exception as error:
            raise operation_error(
                "operation.intent-build-failed",
                "Code-owned executor intent could not be built from typed preflight.",
                detail=type(error).__name__,
            ) from error
        intent = self.intents.build(definition.intent_id, intent_payload)
        now = self.clock()
        if not isinstance(now, datetime) or now.tzinfo is None or now.utcoffset() is None:
            raise operation_error("operation.clock-invalid", "Coordinator clock must be timezone-aware.")
        plan = OperationPlan(
            operation_id=str(uuid.uuid4()),
            owner_id=owner_id_for(principal),
            owner_uid=principal.uid,
            principal_id=principal.principal_id,
            session_id=principal.session_id,
            endpoint_id=principal.endpoint_id,
            task_id=principal.task_id,
            provider=provider,
            action=action,
            capability=outer["capability"],
            risk=self._risk(outer["risk"]),
            resource=resource,
            policy_revision=policy_revision,
            idempotency_digest=idempotency_digest,
            normalized_arguments=normalized_arguments,
            preflight=outer["preflight"],
            intent=intent,
            created_at=now.astimezone(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z"),
        )
        state, replay = self.store.create_plan(plan, plan.request_fingerprint)
        if not replay:
            await self._hook(plan.operation_id, OperationCheckpoint.PREFLIGHT.value)
        return {**state.as_dict(), "replayed": replay}

    def approval_request(self, principal: EndpointPrincipal, operation_id: str):
        principal = self._active(principal)
        state = self.store.get(operation_id)
        self._exact_origin(principal, state.plan)
        if state.status is not OperationStatus.AWAITING_APPROVAL:
            raise operation_error("operation.approval-state", "Operation is not awaiting exact approval.")
        if state.cancellation_requested:
            raise operation_error("operation.cancelled", "Operation cancellation is already durable.")
        self.gateway.assert_current(state.plan.provider)
        if self._current_policy_revision() != state.plan.policy_revision:
            raise operation_error("operation.policy-stale", "Policy revision changed after preflight.")
        if not self.store.is_latest_resource_intent(operation_id):
            raise operation_error("operation.superseded", "A newer operation owns this resource.")
        self.intents.resolve(state.plan.intent)
        return state.plan.security_request()

    async def start(
        self,
        principal: EndpointPrincipal,
        operation_id: str,
        *,
        approval_id: str,
        approvals: ApprovalAuthority,
        grants: Iterable[CapabilityGrant] = (),
    ) -> dict[str, Any]:
        principal = self._active(principal)
        self._require_executor_available()
        grant_records = self._bounded_grants(grants)
        await self._acquire_capacity()
        try:
            lock = await self._acquire_bounded_operation_lock(operation_id)
            try:
                state = self.store.get(operation_id)
                self._exact_origin(principal, state.plan)
                if state.status is not OperationStatus.AWAITING_APPROVAL:
                    raise operation_error("operation.start-state", "Operation cannot be started from its durable state.")
                if state.cancellation_requested:
                    return self._finish_cancelled(state, "cancelled-before-authorization").as_dict()
                principal = self._check_authority(
                    principal,
                    state.plan,
                    approval_id,
                    approvals,
                    grant_records,
                )
                request = state.plan.security_request()
                state = self.store.append(
                    operation_id,
                    "approval-checked",
                    OperationCheckpoint.APPROVAL,
                    OperationStatus.AWAITING_APPROVAL,
                    {"approvalId": approval_id},
                )
                await self._hook(operation_id, OperationCheckpoint.APPROVAL.value)
                if self.store.get(operation_id).cancellation_requested:
                    return self._finish_cancelled(state, "cancelled-before-authorization").as_dict()
                principal = self._check_authority(
                    principal,
                    state.plan,
                    approval_id,
                    approvals,
                    grant_records,
                )
                request = state.plan.security_request()
                consumed = approvals.check(approval_id, principal, request, consume=True)
                if not consumed.valid:
                    raise operation_error(consumed.code, consumed.explanation)
                state = self.store.append(
                    operation_id,
                    "authorized",
                    OperationCheckpoint.AUTHORIZED,
                    OperationStatus.AUTHORIZED,
                    {"approvalId": approval_id},
                    consume_approval_id=approval_id,
                    approval_binding=state.plan.binding_digest,
                )
                try:
                    await self._hook(operation_id, OperationCheckpoint.AUTHORIZED.value)
                    if self.store.get(operation_id).cancellation_requested:
                        return self._finish_cancelled(state, "cancelled-before-apply").as_dict()
                    self._require_executor_available()
                    return (await self._drive(state.plan)).as_dict()
                except asyncio.CancelledError:
                    self._mark_runtime_interrupted(operation_id)
                    raise
                except FabricError as error:
                    if error.code == "executor.production-unavailable":
                        self._mark_runtime_interrupted(operation_id)
                    raise
            finally:
                self._release_operation_lock_reference(operation_id, lock, acquired=True)
        finally:
            self._capacity.release()

    def _cancelled(self, operation_id: str) -> bool:
        return self.store.get(operation_id).cancellation_requested

    @staticmethod
    def _safe_text(value: Any, fallback: str, maximum: int) -> str:
        if not isinstance(value, str) or not value or not value.isprintable():
            return fallback
        return value[:maximum]

    @classmethod
    def _safe_error(cls, error: BaseException) -> dict[str, Any]:
        if isinstance(error, FabricError):
            code = error.code
            if not isinstance(code, str) or len(code) > 256 or not _ERROR_CODE.fullmatch(code):
                code = "operation.executor-failed"
            change_state = error.change_state if error.change_state in {"none", "unknown"} else "unknown"
            recovery_actions: list[str] = []
            if isinstance(error.recovery_actions, (tuple, list)):
                for action in error.recovery_actions:
                    if (
                        isinstance(action, str)
                        and len(action) <= 256
                        and _ERROR_CODE.fullmatch(action)
                        and action not in recovery_actions
                        and len(recovery_actions) < 16
                    ):
                        recovery_actions.append(action)
            return redact(
                {
                    "code": code,
                    "title": cls._safe_text(error.title, "Fabric operation executor failed", 256),
                    "explanation": cls._safe_text(
                        error.explanation,
                        "Executor failed without a valid structured explanation.",
                        1024,
                    ),
                    "retryable": error.retryable if isinstance(error.retryable, bool) else False,
                    "changeState": change_state,
                    "recoveryActions": recovery_actions,
                }
            )
        failure_type = cls._safe_text(type(error).__name__, "Exception", 160)
        return {
            "code": "operation.executor-failed",
            "title": "Fabric operation executor failed",
            "explanation": "Executor failed without a structured bounded error.",
            "retryable": False,
            "changeState": "unknown",
            "failureType": failure_type,
        }

    def _finish_cancelled(self, state: OperationState, event_type: str) -> OperationState:
        current = self.store.get(state.plan.operation_id)
        if current.status.terminal:
            return current
        try:
            return self.store.append(
                state.plan.operation_id,
                event_type,
                OperationCheckpoint.FINISHED,
                OperationStatus.CANCELLED,
                {"result": {"cancelled": True, "mutationApplied": False}},
            )
        except FabricError as error:
            if error.code == "operation.terminal":
                return self.store.get(state.plan.operation_id)
            raise

    async def _drive(self, plan: OperationPlan) -> OperationState:
        operation_id = plan.operation_id
        state = self.store.append(
            operation_id,
            "apply-started",
            OperationCheckpoint.APPLYING,
            OperationStatus.RUNNING,
            {},
        )
        await self._hook(operation_id, OperationCheckpoint.APPLYING.value)
        if self._cancelled(operation_id):
            return self._finish_cancelled(state, "cancelled-before-apply")
        try:
            applied = self._validate_apply_result(
                plan,
                await asyncio.wait_for(
                self.executor.apply(plan, plan.intent, lambda: self._cancelled(operation_id)),
                timeout=self.execution_timeout_seconds,
                ),
                plan.preflight["proposedState"],
            )
        except asyncio.TimeoutError as error:
            return await self._reconcile_unknown(plan, error)
        except BaseException as error:
            if isinstance(error, asyncio.CancelledError):
                raise
            if isinstance(error, FabricError) and error.code == "executor.production-unavailable":
                self._mark_runtime_interrupted(operation_id)
                raise
            if self._cancelled(operation_id) and isinstance(error, FabricError) and error.change_state == "none":
                return self._finish_cancelled(self.store.get(operation_id), "cancelled-during-apply")
            if not isinstance(error, FabricError) or error.change_state != "none":
                return await self._reconcile_unknown(plan, error)
            return self.store.append(
                operation_id,
                "apply-failed",
                OperationCheckpoint.FINISHED,
                OperationStatus.FAILED,
                {"error": self._safe_error(error)},
            )
        state = self.store.append(
            operation_id,
            "apply-finished",
            OperationCheckpoint.APPLIED,
            OperationStatus.RUNNING,
            {
                "stateRevision": applied.state_revision,
                "expectedState": dict(applied.expected_state),
                "evidence": dict(applied.evidence),
            },
        )
        await self._hook(operation_id, OperationCheckpoint.APPLIED.value)
        if self._cancelled(operation_id):
            return await self._rollback(plan, applied, cancelled=True, cause=None)
        state = self.store.append(
            operation_id,
            "validation-started",
            OperationCheckpoint.VALIDATING,
            OperationStatus.RUNNING,
            {"expectedRevision": applied.state_revision},
        )
        await self._hook(operation_id, OperationCheckpoint.VALIDATING.value)
        if self._cancelled(operation_id):
            return await self._rollback(plan, applied, cancelled=True, cause=None)
        try:
            evidence = normalize_executor_evidence(
                await asyncio.wait_for(
                    self.executor.validate(
                        plan,
                        plan.intent,
                        applied.expected_state,
                        lambda: self._cancelled(operation_id),
                    ),
                    timeout=self.execution_timeout_seconds,
                ),
                change_state="unknown",
            )
        except asyncio.TimeoutError as error:
            return await self._rollback(plan, applied, cancelled=self._cancelled(operation_id), cause=error)
        except BaseException as error:
            if isinstance(error, asyncio.CancelledError):
                raise
            return await self._rollback(plan, applied, cancelled=self._cancelled(operation_id), cause=error)
        if self._cancelled(operation_id):
            return await self._rollback(plan, applied, cancelled=True, cause=None)
        return self.store.append(
            operation_id,
            "postcondition-validated",
            OperationCheckpoint.FINISHED,
            OperationStatus.SUCCEEDED,
            {
                "result": {
                    "stateRevision": applied.state_revision,
                    "validated": True,
                    "evidence": dict(evidence),
                }
            },
        )

    async def _rollback(
        self,
        plan: OperationPlan,
        applied: ExecutorApplyResult,
        *,
        cancelled: bool,
        cause: BaseException | None,
    ) -> OperationState:
        operation_id = plan.operation_id
        if not self.store.is_latest_resource_intent(operation_id):
            return self.store.append(
                operation_id,
                "rollback-superseded",
                OperationCheckpoint.FINISHED,
                OperationStatus.SUPERSEDED,
                {"error": self._safe_error(operation_error("operation.superseded", "Rollback refused a newer intent."))},
            )
        self.store.append(
            operation_id,
            "rollback-started",
            OperationCheckpoint.ROLLING_BACK,
            OperationStatus.ROLLING_BACK,
            {"cause": self._safe_error(cause) if cause is not None else {"code": "operation.cancelled"}},
        )
        await self._hook(operation_id, OperationCheckpoint.ROLLING_BACK.value)
        try:
            rolled_back = self._validate_apply_result(
                plan,
                await asyncio.wait_for(
                    self.executor.rollback(
                        plan,
                        plan.intent,
                        plan.preflight["currentState"],
                        applied.state_revision,
                        lambda: False,
                    ),
                    timeout=self.execution_timeout_seconds,
                ),
                plan.preflight["currentState"],
            )
            evidence = normalize_executor_evidence(
                await asyncio.wait_for(
                    self.executor.validate(
                        plan,
                        plan.intent,
                        rolled_back.expected_state,
                        lambda: False,
                    ),
                    timeout=self.execution_timeout_seconds,
                ),
                change_state="unknown",
            )
        except BaseException as error:
            if isinstance(error, asyncio.CancelledError):
                raise
            if isinstance(error, FabricError) and error.code == "executor.production-unavailable":
                self._mark_runtime_interrupted(operation_id)
                raise
            return self.store.append(
                operation_id,
                "rollback-failed",
                OperationCheckpoint.FINISHED,
                OperationStatus.FAILED,
                {"error": self._safe_error(error), "manualReconciliationRequired": True},
            )
        status = OperationStatus.CANCELLED if cancelled else OperationStatus.FAILED
        return self.store.append(
            operation_id,
            "rollback-validated",
            OperationCheckpoint.FINISHED,
            status,
            {
                "result": {
                    "rolledBack": True,
                    "stateRevision": rolled_back.state_revision,
                    "evidence": dict(evidence),
                },
                **({"error": self._safe_error(cause)} if cause is not None else {}),
            },
        )

    async def _reconcile_unknown(self, plan: OperationPlan, cause: BaseException) -> OperationState:
        operation_id = plan.operation_id
        if not self.store.is_latest_resource_intent(operation_id):
            return self.store.append(
                operation_id,
                "reconciliation-superseded",
                OperationCheckpoint.FINISHED,
                OperationStatus.SUPERSEDED,
                {"error": self._safe_error(cause)},
            )
        self.store.append(
            operation_id,
            "reconciliation-started",
            OperationCheckpoint.RECONCILING,
            OperationStatus.RECONCILING,
            {"cause": self._safe_error(cause)},
        )
        await self._hook(operation_id, OperationCheckpoint.RECONCILING.value)
        try:
            self._require_executor_available()
            observed = self._validate_reconcile_result(
                plan,
                await asyncio.wait_for(
                    self.executor.reconcile(plan, plan.intent, lambda: self._cancelled(operation_id)),
                    timeout=self.execution_timeout_seconds,
                ),
            )
        except BaseException as error:
            if isinstance(error, asyncio.CancelledError):
                raise
            if isinstance(error, FabricError) and error.code == "executor.production-unavailable":
                self._mark_runtime_interrupted(operation_id)
                raise
            return self.store.append(
                operation_id,
                "reconciliation-failed",
                OperationCheckpoint.FINISHED,
                OperationStatus.FAILED,
                {"error": self._safe_error(error), "manualReconciliationRequired": True},
            )
        cancelled = self._cancelled(operation_id)
        if observed.disposition == "before":
            return self.store.append(
                operation_id,
                "reconciled-before-state",
                OperationCheckpoint.FINISHED,
                OperationStatus.CANCELLED if cancelled else OperationStatus.FAILED,
                {
                    "result": {"mutationApplied": False, "reconciled": True},
                    **({"error": self._safe_error(cause)} if not cancelled else {}),
                },
            )
        if observed.disposition == "diverged":
            return self.store.append(
                operation_id,
                "reconciled-diverged",
                OperationCheckpoint.FINISHED,
                OperationStatus.FAILED,
                {
                    "error": self._safe_error(cause),
                    "manualReconciliationRequired": True,
                    "observedRevision": observed.state_revision,
                },
            )
        applied = ExecutorApplyResult(observed.state_revision, observed.observed_state, observed.evidence)
        if cancelled:
            return await self._rollback(plan, applied, cancelled=True, cause=cause)
        try:
            evidence = normalize_executor_evidence(
                await asyncio.wait_for(
                    self.executor.validate(
                        plan,
                        plan.intent,
                        observed.observed_state,
                        lambda: self._cancelled(operation_id),
                    ),
                    timeout=self.execution_timeout_seconds,
                ),
                change_state="unknown",
            )
        except BaseException as error:
            if isinstance(error, asyncio.CancelledError):
                raise
            return await self._rollback(plan, applied, cancelled=False, cause=error)
        if self._cancelled(operation_id):
            return await self._rollback(plan, applied, cancelled=True, cause=cause)
        return self.store.append(
            operation_id,
            "reconciled-desired-state",
            OperationCheckpoint.FINISHED,
            OperationStatus.SUCCEEDED,
            {
                "result": {
                    "reconciled": True,
                    "stateRevision": observed.state_revision,
                    "evidence": dict(evidence),
                }
            },
        )

    def get(self, principal: EndpointPrincipal, operation_id: str) -> dict[str, Any]:
        principal = self._active(principal)
        state = self.store.get(operation_id)
        self._same_owner(principal, state.plan)
        return state.as_dict()

    def ledger(
        self,
        principal: EndpointPrincipal,
        operation_id: str,
        *,
        after_sequence: int = 0,
        limit: int = 32,
    ) -> dict[str, Any]:
        principal = self._active(principal)
        state = self.store.get(operation_id)
        self._same_owner(principal, state.plan)
        return self.store.ledger(operation_id, after_sequence=after_sequence, limit=limit)

    def cancel(self, principal: EndpointPrincipal, operation_id: str) -> dict[str, Any]:
        principal = self._active(principal)
        state = self.store.get(operation_id)
        self._same_owner(principal, state.plan)
        if principal.session_id != state.plan.session_id and state.status is not OperationStatus.INTERRUPTED:
            raise operation_error(
                "operation.recovery-session-required",
                "A replacement owner session may cancel only an interrupted operation.",
            )
        state = self.store.request_cancel(operation_id)
        if state.status is OperationStatus.AWAITING_APPROVAL:
            state = self._finish_cancelled(state, "cancelled-before-authorization")
        return state.as_dict()

    async def reconcile(self, principal: EndpointPrincipal, operation_id: str) -> dict[str, Any]:
        principal = self._active(principal)
        await self._acquire_capacity()
        try:
            lock = await self._acquire_bounded_operation_lock(operation_id)
            try:
                state = self.store.get(operation_id)
                self._same_owner(principal, state.plan)
                if state.status.terminal:
                    return state.as_dict()
                if state.status is not OperationStatus.INTERRUPTED:
                    raise operation_error("operation.reconcile-state", "Only an interrupted operation can be reconciled.")
                self._require_executor_available()
                if not self.store.is_latest_resource_intent(operation_id):
                    return self.store.append(
                        operation_id,
                        "reconciliation-superseded",
                        OperationCheckpoint.FINISHED,
                        OperationStatus.SUPERSEDED,
                        {"result": {"mutationApplied": "unknown", "superseded": True}},
                    ).as_dict()
                try:
                    return (await self._reconcile_unknown(
                        state.plan,
                        operation_error(
                            "operation.restart-interrupted",
                            "Process restart interrupted execution.",
                            change_state="unknown",
                        ),
                    )).as_dict()
                except asyncio.CancelledError:
                    self._mark_runtime_interrupted(operation_id)
                    raise
            finally:
                self._release_operation_lock_reference(operation_id, lock, acquired=True)
        finally:
            self._capacity.release()

    def recover_startup(self) -> list[str]:
        return self.store.recover_startup()
