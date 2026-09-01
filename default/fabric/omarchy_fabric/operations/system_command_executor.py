"""Privileged system executor for root-journaled Fabric intents.

Request data never selects argv. The catalog resolves the code-owned
``/usr/libexec/omarchy-fabric-system-executor`` command. The validated
system-executor document is delivered on stdin. Pacman stays off the
session helper.
"""

from __future__ import annotations

import asyncio
import uuid
from typing import Any, Awaitable, Callable, Mapping

from ..models import FixedArgvCommand
from ..security.normalize import binding_digest, canonical_json, normalize_json
from ..security.redaction import redact
from ..security.system_executor import validate_system_executor_request
from .contracts import ExecutorIntent, OperationPlan, operation_error
from .executor import (
    CancellationProbe,
    ExecutorApplyResult,
    ExecutorReconcileResult,
    IntentCatalog,
    _REVISION,
)
from .session_executor import SessionCommandResult, SessionStateReader

SystemCommandRunner = Callable[[FixedArgvCommand, str], Awaitable[SessionCommandResult]]


async def run_system_command(command: FixedArgvCommand, payload: str) -> SessionCommandResult:
    process = await asyncio.create_subprocess_exec(
        command.executable,
        *command.arguments,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await process.communicate(payload.encode("utf-8"))
    return SessionCommandResult(
        int(process.returncode or 0),
        stdout.decode("utf-8", errors="replace")[:4096],
        stderr.decode("utf-8", errors="replace")[:4096],
    )


def _json_argument(value: Any) -> Any:
    if isinstance(value, tuple):
        return [_json_argument(item) for item in value]
    return value


def build_system_executor_document(plan: OperationPlan, intent: ExecutorIntent) -> dict[str, Any]:
    arguments = {
        key: _json_argument(value)
        for key, value in intent.payload.items()
        if key != "resourceId"
    }
    return {
        "schemaVersion": "v0",
        "requestId": str(uuid.uuid4()),
        "operationId": plan.operation_id,
        "action": intent.intent_id,
        "arguments": arguments,
        "providerVersion": plan.provider.version,
        "stateRevision": plan.resource.revision,
        "approvalBinding": plan.binding_digest,
        "consentNonce": str(uuid.uuid4()),
    }


class SystemCommandExecutor:
    """Runs the code-owned system executor for privileged intents only.

    Session-scoped work stays on SessionCommandExecutor. Missing helper
    binaries fail closed; they are not treated as success.
    """

    available = True

    def __init__(
        self,
        catalog: IntentCatalog,
        reader: SessionStateReader,
        *,
        runner: SystemCommandRunner | None = None,
        timeout_seconds: float = 30.0,
    ) -> None:
        if not 0.05 <= timeout_seconds <= 600:
            raise operation_error("executor.invalid-definition", "System executor deadline is invalid.")
        self.catalog = catalog
        self.reader = reader
        self.runner = runner or run_system_command
        self.timeout_seconds = timeout_seconds
        self.system_requests: list[dict[str, Any]] = []

    async def state(self, resource_id: str) -> dict[str, Any]:
        observed = await self.reader(resource_id)
        if not isinstance(observed, Mapping):
            raise operation_error("executor.resource-unavailable", "System state reader returned no typed state.")
        value = normalize_json(observed.get("value"))
        revision = observed.get("revision")
        if not isinstance(revision, str) or not _REVISION.fullmatch(revision):
            revision = "state." + binding_digest(value)
        return {"resourceId": resource_id, "revision": revision, "value": value}

    def _resolve(self, plan: OperationPlan, intent: ExecutorIntent) -> Any:
        definition = self.catalog.resolve(intent)
        if intent.digest != plan.intent.digest:
            raise operation_error("executor.intent-drift", "Executor intent does not match the durable plan.")
        if intent.payload.get("resourceId") != plan.resource.resource_id:
            raise operation_error("executor.resource-drift", "Executor payload targets another resource.")
        return definition

    def _document(self, plan: OperationPlan, intent: ExecutorIntent) -> dict[str, Any]:
        document = build_system_executor_document(plan, intent)
        validate_system_executor_request(document)
        self.system_requests.append(document)
        return document

    @staticmethod
    def _require_live(cancelled: CancellationProbe, change_state: str) -> None:
        if cancelled():
            raise operation_error(
                "operation.cancelled",
                "Execution observed durable cancellation.",
                change_state=change_state,
            )

    async def _run(self, definition: Any, document: Mapping[str, Any], change_state: str) -> SessionCommandResult:
        text = canonical_json(normalize_json(document))
        try:
            result = await asyncio.wait_for(
                self.runner(definition.command, text),
                timeout=self.timeout_seconds,
            )
        except asyncio.TimeoutError as error:
            raise operation_error(
                "executor.system-timeout",
                "The system command did not finish within its deadline.",
                change_state="unknown",
                retryable=True,
                recovery_actions=("operation.reconcile",),
            ) from error
        except FileNotFoundError as error:
            raise operation_error(
                "executor.system-unavailable",
                "The code-owned system executor is not installed.",
                change_state="none",
                recovery_actions=("system.executor.install",),
            ) from error
        if result.returncode != 0:
            raise operation_error(
                "executor.system-failed",
                "The system command reported a failure status.",
                detail=redact(result.stderr)[:480],
                change_state=change_state,
                retryable=True,
                recovery_actions=("operation.reconcile",),
            )
        return result

    @staticmethod
    def _evidence(result: SessionCommandResult, stage: str) -> dict[str, Any]:
        return {
            "stage": stage,
            "exitStatus": result.returncode,
            "output": redact(result.stdout)[:480],
        }

    async def apply(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        cancelled: CancellationProbe,
    ) -> ExecutorApplyResult:
        definition = self._resolve(plan, intent)
        self._require_live(cancelled, "none")
        current = await self.state(plan.resource.resource_id)
        if current["revision"] != plan.resource.revision:
            raise operation_error(
                "executor.stale-resource",
                "Resource revision changed after preflight.",
                change_state="none",
                recovery_actions=("operation.preflight",),
            )
        document = self._document(plan, intent)
        self._require_live(cancelled, "none")
        result = await self._run(definition, document, "unknown")
        observed = await self.state(plan.resource.resource_id)
        return ExecutorApplyResult(observed["revision"], observed, self._evidence(result, "apply"))

    async def validate(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        expected_state: Mapping[str, Any],
        cancelled: CancellationProbe,
    ) -> Mapping[str, Any]:
        self._resolve(plan, intent)
        self._require_live(cancelled, "unknown")
        observed = await self.state(plan.resource.resource_id)
        expected = normalize_json(dict(expected_state).get("value"))
        return {"observedState": observed, "matchesExpected": observed["value"] == expected}

    async def rollback(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        prior_state: Mapping[str, Any],
        expected_revision: str,
        cancelled: CancellationProbe,
    ) -> ExecutorApplyResult:
        definition = self._resolve(plan, intent)
        self._require_live(cancelled, "unknown")
        document = self._document(plan, intent)
        restore = dict(document)
        restore["arguments"] = dict(document["arguments"])
        restore["arguments"]["desired"] = normalize_json(dict(prior_state).get("value"))
        result = await self._run(definition, restore, "unknown")
        observed = await self.state(plan.resource.resource_id)
        return ExecutorApplyResult(observed["revision"], observed, self._evidence(result, "rollback"))

    async def reconcile(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        cancelled: CancellationProbe,
    ) -> ExecutorReconcileResult:
        self._resolve(plan, intent)
        self._require_live(cancelled, "unknown")
        observed = await self.state(plan.resource.resource_id)
        desired = normalize_json(plan.preflight["proposedState"]["value"])
        before = normalize_json(plan.preflight.get("currentState", {}).get("value"))
        if observed["value"] == desired:
            disposition = "desired"
        elif observed["value"] == before:
            disposition = "before"
        else:
            disposition = "diverged"
        return ExecutorReconcileResult(disposition, observed["revision"], observed, {"stage": "reconcile"})
