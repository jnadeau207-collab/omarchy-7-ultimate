"""Typed fixed-argv executor boundary with no production mutation implementation."""

from __future__ import annotations

import asyncio
import re
from dataclasses import dataclass, field
from types import MappingProxyType
from typing import Any, Awaitable, Callable, Mapping, Protocol

from ..models import FabricError, FixedArgvCommand
from ..security.normalize import binding_digest, canonical_json, normalize_json
from ..security.redaction import redact, scan_for_secrets
from .contracts import ExecutorIntent, OperationPlan, _freeze_json, operation_error

PayloadValidator = Callable[[Any], Any]

_REVISION = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,255}$")
_STABLE_TOKEN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,159}$")
MAX_EXECUTOR_OBJECT_BYTES = 12 * 1024
MAX_EXECUTOR_EVIDENCE_BYTES = 8 * 1024

def _executor_object(
    value: Any,
    label: str,
    *,
    maximum: int,
    change_state: str,
) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise operation_error(
            "executor.invalid-result",
            f"{label} must be a typed JSON object.",
            change_state=change_state,
        )
    try:
        normalized = normalize_json(value)
        encoded_size = len(canonical_json(normalized).encode("utf-8"))
    except Exception as error:
        raise operation_error(
            "executor.invalid-result",
            f"{label} is not unambiguous bounded JSON.",
            detail=type(error).__name__,
            change_state=change_state,
        ) from error
    if encoded_size > maximum:
        raise operation_error(
            "executor.invalid-result",
            f"{label} exceeds its durable evidence bound.",
            change_state=change_state,
        )
    if scan_for_secrets(normalized):
        raise operation_error(
            "executor.secret-rejected",
            f"{label} contains credential-shaped data.",
            change_state=change_state,
        )
    return _freeze_json(normalized)

def normalize_executor_evidence(value: Any, *, change_state: str = "unknown") -> Mapping[str, Any]:
    return _executor_object(
        value,
        "Executor evidence",
        maximum=MAX_EXECUTOR_EVIDENCE_BYTES,
        change_state=change_state,
    )

def _result_revision(value: Any) -> str:
    if not isinstance(value, str) or not _REVISION.fullmatch(value):
        raise operation_error(
            "executor.invalid-result",
            "Executor result revision is invalid.",
            change_state="unknown",
        )
    return value

@dataclass(frozen=True)
class IntentDefinition:
    """Code-owned immutable argv and closed typed-stdin contract."""

    intent_id: str
    command: FixedArgvCommand
    required: Mapping[str, PayloadValidator]
    optional: Mapping[str, PayloadValidator] = field(default_factory=dict)
    contract_revision: str = "v0"

    def __post_init__(self) -> None:
        if not isinstance(self.command, FixedArgvCommand):
            raise operation_error("executor.invalid-definition", "Executor command must be fixed argv.")
        if not isinstance(self.intent_id, str) or not self.intent_id:
            raise operation_error("executor.invalid-definition", "Executor intent ID is required.")
        if not isinstance(self.contract_revision, str) or not _REVISION.fullmatch(self.contract_revision):
            raise operation_error("executor.invalid-definition", "Executor contract revision is invalid.")
        if not isinstance(self.required, Mapping) or not isinstance(self.optional, Mapping):
            raise operation_error("executor.invalid-definition", "Executor payload field catalogs must be objects.")
        if set(self.required) & set(self.optional):
            raise operation_error("executor.invalid-definition", "Executor payload fields overlap.")
        if not self.required:
            raise operation_error("executor.invalid-definition", "Executor payload must have an exact typed contract.")
        for name, validator in {**self.required, **self.optional}.items():
            if not isinstance(name, str) or not name or not callable(validator):
                raise operation_error("executor.invalid-definition", "Executor payload validators are invalid.")
        object.__setattr__(self, "required", MappingProxyType(dict(self.required)))
        object.__setattr__(self, "optional", MappingProxyType(dict(self.optional)))

    @property
    def fingerprint(self) -> str:
        return binding_digest(
            {
                "intentId": self.intent_id,
                "fixedArgv": list(self.command.argv),
                "requiredFields": sorted(self.required),
                "optionalFields": sorted(self.optional),
                "contractRevision": self.contract_revision,
            }
        )

    def normalize_payload(self, payload: Mapping[str, Any]) -> Mapping[str, Any]:
        if not isinstance(payload, Mapping):
            raise operation_error("executor.invalid-payload", "Executor payload must be an object.")
        try:
            raw_payload = normalize_json(payload)
        except Exception as error:
            raise operation_error(
                "executor.invalid-payload",
                "Executor payload is not unambiguous bounded JSON.",
                detail=type(error).__name__,
            ) from error
        if scan_for_secrets(raw_payload):
            raise operation_error("executor.secret-rejected", "Secrets cannot enter executor payloads.")
        keys = set(payload)
        if not set(self.required).issubset(keys) or not keys.issubset(set(self.required) | set(self.optional)):
            raise operation_error("executor.invalid-payload", "Executor payload fields are not exact.")
        validators = {**self.required, **self.optional}
        try:
            value = normalize_json({key: validators[key](payload[key]) for key in sorted(keys)})
        except FabricError:
            raise
        except Exception as error:
            raise operation_error(
                "executor.invalid-payload",
                "Executor payload failed its code-owned typed contract.",
                detail=type(error).__name__,
            ) from error
        if scan_for_secrets(value):
            raise operation_error("executor.secret-rejected", "Secrets cannot enter executor payloads.")
        return _freeze_json(value)

class IntentCatalog:
    """Immutable catalog; request data cannot register or select argv."""

    def __init__(self, definitions: tuple[IntentDefinition, ...]) -> None:
        records: dict[str, IntentDefinition] = {}
        for definition in definitions:
            if not isinstance(definition, IntentDefinition) or definition.intent_id in records:
                raise operation_error("executor.invalid-catalog", "Executor intent catalog is invalid.")
            records[definition.intent_id] = definition
        if not records:
            raise operation_error("executor.invalid-catalog", "At least one code-owned executor intent is required.")
        self._definitions = MappingProxyType(records)

    def build(self, intent_id: str, payload: Mapping[str, Any]) -> ExecutorIntent:
        definition = self._definitions.get(intent_id)
        if definition is None:
            raise operation_error("executor.intent-unavailable", "No code-owned executor intent matches this action.")
        return ExecutorIntent(intent_id, definition.fingerprint, definition.normalize_payload(payload))

    def resolve(self, intent: ExecutorIntent) -> IntentDefinition:
        definition = self._definitions.get(intent.intent_id)
        if definition is None or definition.fingerprint != intent.template_fingerprint:
            raise operation_error(
                "executor.intent-drift",
                "The code-owned executor intent changed after preflight.",
                recovery_actions=("operation.preflight",),
            )
        if dict(definition.normalize_payload(intent.payload)) != dict(intent.payload):
            raise operation_error("executor.intent-corrupt", "The durable executor payload is invalid.")
        return definition

class CancellationProbe(Protocol):
    def __call__(self) -> bool:
        """Return whether durable cancellation has been requested."""

@dataclass(frozen=True)
class ExecutorApplyResult:
    state_revision: str
    expected_state: Mapping[str, Any]
    evidence: Mapping[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        _result_revision(self.state_revision)
        expected = _executor_object(
            self.expected_state,
            "Executor expected state",
            maximum=MAX_EXECUTOR_OBJECT_BYTES,
            change_state="unknown",
        )
        evidence = normalize_executor_evidence(self.evidence)
        if len(canonical_json({"expectedState": expected, "evidence": evidence}).encode("utf-8")) > MAX_EXECUTOR_OBJECT_BYTES:
            raise operation_error(
                "executor.invalid-result",
                "Executor apply result exceeds its durable checkpoint bound.",
                change_state="unknown",
            )
        object.__setattr__(self, "expected_state", expected)
        object.__setattr__(self, "evidence", evidence)

@dataclass(frozen=True)
class ExecutorReconcileResult:
    disposition: str
    state_revision: str
    observed_state: Mapping[str, Any]
    evidence: Mapping[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if self.disposition not in {"before", "desired", "diverged"}:
            raise operation_error("executor.invalid-result", "Executor reconciliation disposition is invalid.")
        _result_revision(self.state_revision)
        observed = _executor_object(
            self.observed_state,
            "Executor observed state",
            maximum=MAX_EXECUTOR_OBJECT_BYTES,
            change_state="none",
        )
        evidence = normalize_executor_evidence(self.evidence, change_state="none")
        if len(canonical_json({"observedState": observed, "evidence": evidence}).encode("utf-8")) > MAX_EXECUTOR_OBJECT_BYTES:
            raise operation_error(
                "executor.invalid-result",
                "Executor reconciliation result exceeds its evidence bound.",
            )
        object.__setattr__(self, "observed_state", observed)
        object.__setattr__(self, "evidence", evidence)

class OperationExecutor(Protocol):
    available: bool

    async def apply(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        cancelled: CancellationProbe,
    ) -> ExecutorApplyResult:
        ...

    async def validate(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        expected_state: Mapping[str, Any],
        cancelled: CancellationProbe,
    ) -> Mapping[str, Any]:
        ...

    async def rollback(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        prior_state: Mapping[str, Any],
        expected_revision: str,
        cancelled: CancellationProbe,
    ) -> ExecutorApplyResult:
        ...

    async def reconcile(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        cancelled: CancellationProbe,
    ) -> ExecutorReconcileResult:
        ...

class UnavailableProductionExecutor:
    """Explicit production boundary: typed intents exist, execution does not."""

    available = False

    @staticmethod
    def _unavailable() -> FabricError:
        return operation_error(
            "executor.production-unavailable",
            "No privileged production executor is installed for this coordinator tranche.",
            recovery_actions=("system.executor.install",),
        )

    async def apply(self, *args: Any, **kwargs: Any) -> ExecutorApplyResult:
        raise self._unavailable()

    async def validate(self, *args: Any, **kwargs: Any) -> Mapping[str, Any]:
        raise self._unavailable()

    async def rollback(self, *args: Any, **kwargs: Any) -> ExecutorApplyResult:
        raise self._unavailable()

    async def reconcile(self, *args: Any, **kwargs: Any) -> ExecutorReconcileResult:
        raise self._unavailable()

def stable_token(value: Any) -> str:
    if not isinstance(value, str) or not _STABLE_TOKEN.fullmatch(value):
        raise ValueError("expected an opaque stable token")
    return value

def boolean(value: Any) -> bool:
    if not isinstance(value, bool):
        raise ValueError("expected a boolean")
    return value

class FakeResourceExecutor:
    """Hermetic unprivileged executor used to prove the coordinator protocol.

    It never invokes ``FixedArgvCommand``. The command is resolved only to prove
    that the durable intent still matches code-owned argv.
    """

    available = True

    def __init__(
        self,
        catalog: IntentCatalog,
        resources: Mapping[str, Any],
        *,
        delay_seconds: float = 0.0,
        faults: Mapping[str, str] | None = None,
        stage_hook: Callable[[str, OperationPlan], Awaitable[None] | None] | None = None,
    ) -> None:
        self.catalog = catalog
        self._values = dict(normalize_json(resources))
        self.delay_seconds = delay_seconds
        self.faults = dict(faults or {})
        self.stage_hook = stage_hook
        self.calls: list[tuple[str, str]] = []

    @staticmethod
    def _revision(value: Any) -> str:
        return f"state.{binding_digest(value)}"

    def state(self, resource_id: str) -> dict[str, Any]:
        if resource_id not in self._values:
            raise operation_error("executor.resource-unavailable", "The fake resource is unavailable.")
        value = normalize_json(self._values[resource_id])
        return {"resourceId": resource_id, "revision": self._revision(value), "value": value}

    def external_set(self, resource_id: str, value: Any) -> None:
        self._values[resource_id] = normalize_json(value)

    async def _stage(self, name: str, plan: OperationPlan, cancelled: CancellationProbe) -> None:
        self.calls.append((name, plan.operation_id))
        if self.stage_hook is not None:
            result = self.stage_hook(name, plan)
            if asyncio.iscoroutine(result):
                await result
        if self.delay_seconds:
            deadline = asyncio.get_running_loop().time() + self.delay_seconds
            while asyncio.get_running_loop().time() < deadline:
                if cancelled():
                    raise operation_error("operation.cancelled", "Execution observed durable cancellation.")
                await asyncio.sleep(min(0.01, self.delay_seconds))
        if cancelled():
            raise operation_error("operation.cancelled", "Execution observed durable cancellation.")
        fault = self.faults.get(name)
        if fault == "timeout":
            await asyncio.Event().wait()
        if fault == "fail-before":
            raise operation_error(f"executor.{name}-failed", f"Fake executor {name} failed before mutation.")

    def _resolve(self, plan: OperationPlan, intent: ExecutorIntent) -> None:
        self.catalog.resolve(intent)
        if intent.digest != plan.intent.digest:
            raise operation_error("executor.intent-drift", "Executor intent does not match the durable plan.")
        if intent.payload.get("resourceId") != plan.resource.resource_id:
            raise operation_error("executor.resource-drift", "Executor payload targets another resource.")

    async def apply(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        cancelled: CancellationProbe,
    ) -> ExecutorApplyResult:
        self._resolve(plan, intent)
        await self._stage("apply", plan, cancelled)
        current = self.state(plan.resource.resource_id)
        if current["revision"] != plan.resource.revision:
            raise operation_error(
                "executor.stale-resource",
                "Resource revision changed after preflight.",
                change_state="none",
                recovery_actions=("operation.preflight",),
            )
        desired = normalize_json(plan.preflight["proposedState"]["value"])
        if self.faults.get("apply") == "partial":
            self._values[plan.resource.resource_id] = {"partial": True}
            raise operation_error(
                "executor.apply-partial",
                "The fake executor stopped after a partial mutation.",
                change_state="unknown",
                recovery_actions=("operation.reconcile",),
            )
        self._values[plan.resource.resource_id] = desired
        result = self.state(plan.resource.resource_id)
        if self.faults.get("apply") == "fail-after":
            raise operation_error(
                "executor.apply-unknown",
                "The fake executor lost its response after applying.",
                change_state="unknown",
                recovery_actions=("operation.reconcile",),
            )
        return ExecutorApplyResult(
            result["revision"],
            result,
            MappingProxyType({"executor": "fake", "applied": current != result}),
        )

    async def validate(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        expected_state: Mapping[str, Any],
        cancelled: CancellationProbe,
    ) -> Mapping[str, Any]:
        self._resolve(plan, intent)
        await self._stage("validate", plan, cancelled)
        actual = self.state(plan.resource.resource_id)
        forced_mismatch = self.faults.get("validate") == "mismatch"
        if forced_mismatch:
            self.faults.pop("validate", None)
        if forced_mismatch or actual != normalize_json(expected_state):
            raise operation_error(
                "executor.validation-failed",
                "Executor postcondition validation failed.",
                change_state="unknown",
                recovery_actions=("operation.rollback",),
            )
        return MappingProxyType({"executor": "fake", "validatedRevision": actual["revision"]})

    async def rollback(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        prior_state: Mapping[str, Any],
        expected_revision: str,
        cancelled: CancellationProbe,
    ) -> ExecutorApplyResult:
        self._resolve(plan, intent)
        await self._stage("rollback", plan, lambda: False)
        current = self.state(plan.resource.resource_id)
        if current["revision"] != expected_revision:
            raise operation_error(
                "executor.rollback-superseded",
                "Rollback refused to overwrite a newer resource revision.",
                change_state="unknown",
                recovery_actions=("operation.reconcile",),
            )
        if self.faults.get("rollback") == "fail-after":
            self._values[plan.resource.resource_id] = normalize_json(prior_state["value"])
            raise operation_error(
                "executor.rollback-unknown",
                "Rollback response was lost after mutation.",
                change_state="unknown",
                recovery_actions=("operation.reconcile",),
            )
        self._values[plan.resource.resource_id] = normalize_json(prior_state["value"])
        result = self.state(plan.resource.resource_id)
        return ExecutorApplyResult(
            result["revision"],
            result,
            MappingProxyType({"executor": "fake", "rolledBack": True}),
        )

    async def reconcile(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        cancelled: CancellationProbe,
    ) -> ExecutorReconcileResult:
        self._resolve(plan, intent)
        await self._stage("reconcile", plan, lambda: False)
        actual = self.state(plan.resource.resource_id)
        before = normalize_json(plan.preflight["currentState"]["value"])
        desired = normalize_json(plan.preflight["proposedState"]["value"])
        if actual["value"] == before:
            disposition = "before"
        elif actual["value"] == desired:
            disposition = "desired"
        else:
            disposition = "diverged"
        return ExecutorReconcileResult(
            disposition,
            actual["revision"],
            actual,
            MappingProxyType(redact({"executor": "fake", "disposition": disposition})),
        )
