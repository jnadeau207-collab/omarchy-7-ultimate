"""Deny-by-default authorization for endpoint-bound Fabric operations."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Iterable

from .approval import ApprovalAuthority
from .errors import SecurityValidationError
from .grants import CapabilityGrant
from .principal import EndpointPrincipal, PrincipalKind
from .types import DecisionKind, OperationRequest, PolicyDecision, RiskLevel


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


class PolicyEngine:
    def decide(
        self,
        principal: EndpointPrincipal,
        request: OperationRequest,
        grants: Iterable[CapabilityGrant],
        *,
        approval_authority: ApprovalAuthority | None = None,
        approval_id: str | None = None,
        now: datetime | None = None,
        consume_approval: bool = True,
    ) -> PolicyDecision:
        checked_at = now or _utc_now()
        try:
            time_is_aware = (
                isinstance(checked_at, datetime)
                and checked_at.tzinfo is not None
                and checked_at.utcoffset() is not None
            )
        except (TypeError, ValueError, OverflowError):
            time_is_aware = False
        if not time_is_aware:
            raise SecurityValidationError("policy.time", "Policy evaluation time must be timezone-aware.")
        if request.principal_id != principal.principal_id or request.session_id != principal.session_id:
            return self._deny(request, "principal.request-spoof", "Request identity does not match the endpoint session.")
        if checked_at >= principal.expires_at:
            return self._deny(request, "principal.expired", "Endpoint session has expired.")
        if checked_at < principal.issued_at:
            return self._deny(request, "principal.not-yet-valid", "Endpoint session is not valid yet.")
        if principal.kind is PrincipalKind.TASK and request.task_id != principal.task_id:
            return self._deny(request, "principal.task-spoof", "Request is outside the endpoint's task scope.")

        requires_per_operation_approval = (
            principal.kind is PrincipalKind.SHELL and request.risk.rank >= RiskLevel.CONSEQUENTIAL.rank
        ) or request.risk is RiskLevel.HIGH

        matching_grant: CapabilityGrant | None = None
        last_grant_failure = "grant.missing"
        for grant in grants:
            if grant.principal_kind is not principal.kind:
                continue
            matched, code = grant.matches(request, now=checked_at)
            if matched:
                matching_grant = grant
                break
            if grant.principal_id == principal.principal_id:
                last_grant_failure = code

        # The shell intentionally cannot hold a standing consequential grant. A
        # one-operation approval is its entire authority for such a request.
        approval_can_replace_grant = (
            principal.kind is PrincipalKind.SHELL
            and request.risk.rank >= RiskLevel.CONSEQUENTIAL.rank
        )
        if matching_grant is None and not approval_can_replace_grant:
            return self._deny(request, last_grant_failure, "No active grant matches this exact operation scope.")

        if requires_per_operation_approval:
            if approval_id is None or approval_authority is None:
                return PolicyDecision(
                    decision=DecisionKind.CONSENT_REQUIRED,
                    code="approval.required",
                    explanation="This operation requires fresh, operation-specific consent.",
                    operation_id=request.operation_id,
                    principal_id=request.principal_id,
                    grant_id=matching_grant.grant_id if matching_grant else None,
                )
            check = approval_authority.check(
                approval_id,
                principal,
                request,
                consume=consume_approval,
            )
            if not check.valid:
                return self._deny(request, check.code, check.explanation, approval_id=approval_id)
            return PolicyDecision(
                decision=DecisionKind.ALLOW,
                code="policy.approved",
                explanation="Exact operation approval and scope checks passed.",
                operation_id=request.operation_id,
                principal_id=request.principal_id,
                grant_id=matching_grant.grant_id if matching_grant else None,
                approval_id=approval_id,
            )

        return PolicyDecision(
            decision=DecisionKind.ALLOW,
            code="policy.granted",
            explanation="An active exact-scope grant authorizes this operation.",
            operation_id=request.operation_id,
            principal_id=request.principal_id,
            grant_id=matching_grant.grant_id if matching_grant else None,
        )

    @staticmethod
    def _deny(
        request: OperationRequest,
        code: str,
        explanation: str,
        *,
        approval_id: str | None = None,
    ) -> PolicyDecision:
        return PolicyDecision(
            decision=DecisionKind.DENY,
            code=code,
            explanation=explanation,
            operation_id=request.operation_id,
            principal_id=request.principal_id,
            approval_id=approval_id,
        )
