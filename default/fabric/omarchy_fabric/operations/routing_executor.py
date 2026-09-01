"""Split session-scoped work from privileged system-executor intents."""

from __future__ import annotations

from typing import Mapping

from .contracts import ExecutorIntent, OperationPlan
from .executor import CancellationProbe, ExecutorApplyResult, ExecutorReconcileResult, OperationExecutor


class PrivilegeRoutingExecutor:
    """Keep privileged package/system intents off the session executor.

    Session-scoped audio and files stay on the user helper. Privileged intents
    go to the system executor. Request data cannot choose the route: the
    intent ID is code-owned.
    """

    def __init__(
        self,
        session: OperationExecutor,
        privileged: OperationExecutor,
        privileged_intents: frozenset[str],
    ) -> None:
        self.session = session
        self.privileged = privileged
        self.privileged_intents = frozenset(privileged_intents)

    @property
    def available(self) -> bool:
        return bool(getattr(self.session, "available", False))

    def _choose(self, intent: ExecutorIntent) -> OperationExecutor:
        if intent.intent_id in self.privileged_intents:
            return self.privileged
        return self.session

    async def apply(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        cancelled: CancellationProbe,
    ) -> ExecutorApplyResult:
        return await self._choose(intent).apply(plan, intent, cancelled)

    async def validate(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        expected_state: Mapping[str, object],
        cancelled: CancellationProbe,
    ) -> Mapping[str, object]:
        return await self._choose(intent).validate(plan, intent, expected_state, cancelled)

    async def rollback(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        prior_state: Mapping[str, object],
        expected_revision: str,
        cancelled: CancellationProbe,
    ) -> ExecutorApplyResult:
        return await self._choose(intent).rollback(plan, intent, prior_state, expected_revision, cancelled)

    async def reconcile(
        self,
        plan: OperationPlan,
        intent: ExecutorIntent,
        cancelled: CancellationProbe,
    ) -> ExecutorReconcileResult:
        return await self._choose(intent).reconcile(plan, intent, cancelled)
