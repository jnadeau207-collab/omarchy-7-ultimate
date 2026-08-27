from __future__ import annotations

import dataclasses
import sys
import unittest
from datetime import datetime, timedelta, timezone, tzinfo
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "default" / "fabric"))

from omarchy_fabric.security.approval import ApprovalAuthority
from omarchy_fabric.security.errors import SecurityValidationError
from omarchy_fabric.security.grants import CapabilityGrant, GrantPersistence
from omarchy_fabric.security.policy import PolicyEngine
from omarchy_fabric.security.principal import (
    EndpointAdmission,
    PrincipalKind,
    SessionBindingStore,
    SessionCredential,
)
from omarchy_fabric.security.types import DecisionKind, OperationRequest, ResourceRef, RiskLevel


class Clock:
    def __init__(self) -> None:
        self.now = datetime(2026, 8, 26, 12, 0, tzinfo=timezone.utc)

    def __call__(self) -> datetime:
        return self.now


class BrokenTimezone(tzinfo):
    def utcoffset(self, value):
        raise ValueError("broken offset")

    def dst(self, value):
        return None

    def tzname(self, value):
        return "broken"


class TrustPolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = Clock()
        self.sessions = SessionBindingStore(clock=self.clock)
        self.policy = PolicyEngine()
        self.approvals = ApprovalAuthority(clock=self.clock)

    def issue(self, kind: PrincipalKind, *, task_id: str | None = None):
        return self.sessions.issue(
            1000,
            EndpointAdmission(
                endpoint_id=f"endpoint.{kind.value}",
                kind=kind,
                task_id=task_id,
            ),
            lifetime=timedelta(hours=1),
        )

    def request(
        self,
        principal,
        *,
        operation_id: str = "10000000-0000-0000-0000-000000000001",
        risk: RiskLevel = RiskLevel.LOW,
        arguments=None,
        context=None,
        task_id=None,
        provider_version: str = "provider.v0",
        state_revision: str = "state.one",
        resource_id: str = "display.primary",
    ) -> OperationRequest:
        return OperationRequest(
            operation_id=operation_id,
            principal_id=principal.principal_id,
            session_id=principal.session_id,
            capability="display.configure",
            resource=ResourceRef("display", resource_id),
            provider_version=provider_version,
            state_revision=state_revision,
            risk=risk,
            arguments=arguments or {"mode": "1920x1080"},
            context=context or {},
            task_id=task_id,
        )

    def grant(
        self,
        principal,
        *,
        risk: RiskLevel = RiskLevel.LOW,
        persistence: GrantPersistence = GrantPersistence.DURATION,
        expires_delta: timedelta = timedelta(minutes=30),
        constraints=None,
        task_id=None,
        resource_id: str = "display.primary",
    ) -> CapabilityGrant:
        return CapabilityGrant(
            grant_id="grant.one",
            principal_id=principal.principal_id,
            principal_kind=principal.kind,
            capability="display.configure",
            resource=ResourceRef("display", resource_id),
            issued_at=self.clock.now - timedelta(minutes=1),
            expires_at=self.clock.now + expires_delta,
            maximum_risk=risk,
            persistence=persistence,
            constraints=constraints or {},
            task_id=task_id,
        )

    def test_uid_is_not_an_actor_claim_and_credentials_are_endpoint_bound(self) -> None:
        shell, shell_credential = self.issue(PrincipalKind.SHELL)
        provider, provider_credential = self.sessions.issue(
            1000,
            EndpointAdmission("endpoint.provider", PrincipalKind.PROVIDER, provider_id="display.provider"),
        )
        self.assertEqual(self.sessions.resolve(1000, shell_credential), shell)
        self.assertEqual(self.sessions.resolve(1000, provider_credential), provider)
        with self.assertRaisesRegex(SecurityValidationError, "invalid"):
            self.sessions.resolve(1000, SessionCredential(shell_credential.session_id, provider_credential.token))
        with self.assertRaisesRegex(SecurityValidationError, "different peer UID"):
            self.sessions.resolve(1001, shell_credential)
        with self.assertRaises(dataclasses.FrozenInstanceError):
            shell.kind = PrincipalKind.PROVIDER

    def test_sessions_expire_and_revoke_fail_closed(self) -> None:
        principal, credential = self.issue(PrincipalKind.SHELL)
        self.assertTrue(self.sessions.is_active(principal.session_id))
        self.clock.now += timedelta(hours=2)
        with self.assertRaisesRegex(SecurityValidationError, "expired"):
            self.sessions.resolve(1000, credential)
        with self.assertRaisesRegex(SecurityValidationError, "expired"):
            self.sessions.require_active(principal)
        self.assertFalse(self.sessions.is_active(principal.session_id))
        principal, credential = self.issue(PrincipalKind.SHELL)
        self.sessions.revoke(principal.session_id)
        with self.assertRaisesRegex(SecurityValidationError, "revoked"):
            self.sessions.resolve(1000, credential)
        with self.assertRaisesRegex(SecurityValidationError, "revoked"):
            self.sessions.require_active(principal)
        self.assertFalse(self.sessions.is_active(principal.session_id))

    def test_released_connection_session_is_forgotten(self) -> None:
        principal, credential = self.issue(PrincipalKind.SHELL)
        self.assertTrue(self.sessions.release(principal.session_id))
        self.assertFalse(self.sessions.release(principal.session_id))
        with self.assertRaisesRegex(SecurityValidationError, "invalid"):
            self.sessions.resolve(1000, credential)

    def test_default_deny_and_exact_resource_constraint_grant(self) -> None:
        principal, _ = self.issue(PrincipalKind.TASK, task_id="task.one")
        request = self.request(
            principal,
            task_id="task.one",
            context={"seat": "seat.one"},
        )
        decision = self.policy.decide(principal, request, [], now=self.clock.now)
        self.assertEqual(decision.decision, DecisionKind.DENY)
        self.assertEqual(decision.as_dict()["schemaVersion"], "v0")
        self.assertNotIn("grantId", decision.as_dict())
        grant = self.grant(
            principal,
            task_id="task.one",
            constraints={"arguments.mode": ("1920x1080",), "context.seat": ("seat.one",)},
        )
        decision = self.policy.decide(principal, request, [grant], now=self.clock.now)
        self.assertTrue(decision.allowed)
        wrong_resource = self.request(principal, task_id="task.one", resource_id="display.other")
        self.assertFalse(self.policy.decide(principal, wrong_resource, [grant], now=self.clock.now).allowed)
        wrong_constraint = self.request(principal, task_id="task.one", arguments={"mode": "800x600"})
        self.assertEqual(
            self.policy.decide(principal, wrong_constraint, [grant], now=self.clock.now).code,
            "grant.constraint",
        )

    def test_expired_grant_and_task_scope_are_rejected(self) -> None:
        principal, _ = self.issue(PrincipalKind.TASK, task_id="task.one")
        request = self.request(principal, task_id="task.one")
        expired = self.grant(principal, task_id="task.one", expires_delta=timedelta(seconds=-1))
        self.assertEqual(self.policy.decide(principal, request, [expired], now=self.clock.now).code, "grant.expired")
        spoofed_task = self.request(principal, task_id="task.two")
        self.assertEqual(
            self.policy.decide(principal, spoofed_task, [self.grant(principal, task_id="task.one")], now=self.clock.now).code,
            "principal.task-spoof",
        )
        future = dataclasses.replace(
            self.grant(principal, task_id="task.one"),
            issued_at=self.clock.now + timedelta(minutes=5),
            expires_at=self.clock.now + timedelta(minutes=10),
        )
        self.assertEqual(self.policy.decide(principal, request, [future], now=self.clock.now).code, "grant.not-yet-valid")

    def test_request_cannot_spoof_the_endpoint_principal(self) -> None:
        principal, _ = self.issue(PrincipalKind.TASK, task_id="task.one")
        request = self.request(principal, task_id="task.one")
        forged = dataclasses.replace(request, principal_id="principal.forged")
        decision = self.policy.decide(
            principal,
            forged,
            [self.grant(principal, task_id="task.one")],
            now=self.clock.now,
        )
        self.assertEqual(decision.code, "principal.request-spoof")

    def test_operation_risk_and_policy_time_are_strictly_typed(self) -> None:
        principal, _ = self.issue(PrincipalKind.TASK, task_id="task.one")
        with self.assertRaisesRegex(SecurityValidationError, "risk"):
            dataclasses.replace(self.request(principal, task_id="task.one"), risk="high")
        with self.assertRaisesRegex(SecurityValidationError, "objects"):
            dataclasses.replace(self.request(principal, task_id="task.one"), arguments=["not", "an", "object"])
        request = self.request(principal, task_id="task.one")
        with self.assertRaisesRegex(SecurityValidationError, "timezone-aware"):
            self.policy.decide(
                principal,
                request,
                [self.grant(principal, task_id="task.one")],
                now=datetime(2026, 8, 26, 12, 0),
            )
        broken_time = datetime(2026, 8, 26, 12, 0, tzinfo=BrokenTimezone())
        with self.assertRaisesRegex(SecurityValidationError, "timezone-aware"):
            self.policy.decide(
                principal,
                request,
                [self.grant(principal, task_id="task.one")],
                now=broken_time,
            )
        with self.assertRaisesRegex(SecurityValidationError, "timezone-aware"):
            dataclasses.replace(self.grant(principal, task_id="task.one"), issued_at=broken_time)
        broken_approvals = ApprovalAuthority(clock=lambda: broken_time)
        with self.assertRaisesRegex(SecurityValidationError, "timezone-aware"):
            broken_approvals.issue(principal, request, expires_at=self.clock.now + timedelta(minutes=5))

    def test_persistent_high_risk_and_shell_standing_consequence_are_impossible(self) -> None:
        task, _ = self.issue(PrincipalKind.TASK, task_id="task.one")
        with self.assertRaisesRegex(SecurityValidationError, "never be persistent"):
            self.grant(
                task,
                risk=RiskLevel.HIGH,
                persistence=GrantPersistence.PERSISTENT,
                task_id="task.one",
            )
        shell, _ = self.issue(PrincipalKind.SHELL)
        with self.assertRaisesRegex(SecurityValidationError, "cannot hold"):
            self.grant(shell, risk=RiskLevel.CONSEQUENTIAL)
        with self.assertRaisesRegex(SecurityValidationError, "JSON scalars"):
            self.grant(task, task_id="task.one", constraints={"arguments.mode": ({"nested": True},)})

    def test_shell_consequence_requires_and_consumes_exact_operation_approval(self) -> None:
        shell, _ = self.issue(PrincipalKind.SHELL)
        request = self.request(shell, risk=RiskLevel.CONSEQUENTIAL)
        decision = self.policy.decide(shell, request, [], now=self.clock.now)
        self.assertEqual(decision.decision, DecisionKind.CONSENT_REQUIRED)
        approval = self.approvals.issue(shell, request, expires_at=self.clock.now + timedelta(minutes=5))
        allowed = self.policy.decide(
            shell,
            request,
            [],
            approval_authority=self.approvals,
            approval_id=approval.approval_id,
            now=self.clock.now,
        )
        self.assertTrue(allowed.allowed)
        replay = self.policy.decide(
            shell,
            request,
            [],
            approval_authority=self.approvals,
            approval_id=approval.approval_id,
            now=self.clock.now,
        )
        self.assertEqual(replay.code, "approval.consumed")

    def test_approval_rejects_provider_state_argument_and_resource_drift(self) -> None:
        shell, _ = self.issue(PrincipalKind.SHELL)
        base = self.request(shell, risk=RiskLevel.CONSEQUENTIAL)
        variants = (
            (self.request(shell, risk=RiskLevel.CONSEQUENTIAL, operation_id="20000000-0000-0000-0000-000000000002"), "approval.operation-drift"),
            (self.request(shell, risk=RiskLevel.CONSEQUENTIAL, provider_version="provider.v2"), "approval.provider-drift"),
            (self.request(shell, risk=RiskLevel.CONSEQUENTIAL, state_revision="state.two"), "approval.state-drift"),
            (self.request(shell, risk=RiskLevel.HIGH), "approval.risk-drift"),
            (self.request(shell, risk=RiskLevel.CONSEQUENTIAL, arguments={"mode": "800x600"}), "approval.argument-drift"),
            (self.request(shell, risk=RiskLevel.CONSEQUENTIAL, resource_id="display.other"), "approval.resource-drift"),
        )
        for changed, expected_code in variants:
            with self.subTest(expected_code=expected_code):
                approval = self.approvals.issue(shell, base, expires_at=self.clock.now + timedelta(minutes=5))
                decision = self.policy.decide(
                    shell,
                    changed,
                    [],
                    approval_authority=self.approvals,
                    approval_id=approval.approval_id,
                    now=self.clock.now,
                )
                self.assertEqual(decision.code, expected_code)

    def test_expired_approval_is_rejected(self) -> None:
        shell, _ = self.issue(PrincipalKind.SHELL)
        request = self.request(shell, risk=RiskLevel.CONSEQUENTIAL)
        approval = self.approvals.issue(shell, request, expires_at=self.clock.now + timedelta(seconds=1))
        self.clock.now += timedelta(seconds=2)
        decision = self.policy.decide(
            shell,
            request,
            [],
            approval_authority=self.approvals,
            approval_id=approval.approval_id,
            now=self.clock.now,
        )
        self.assertEqual(decision.code, "approval.expired")

    def test_approval_authority_is_capacity_bounded_and_prunes_terminal_records(self) -> None:
        shell, _ = self.issue(PrincipalKind.SHELL)
        request = self.request(shell, risk=RiskLevel.CONSEQUENTIAL)
        approvals = ApprovalAuthority(clock=self.clock, max_records=2)
        first = approvals.issue(shell, request, expires_at=self.clock.now + timedelta(minutes=5))
        second = approvals.issue(shell, request, expires_at=self.clock.now + timedelta(minutes=5))
        self.assertEqual(approvals.record_count, 2)
        with self.assertRaisesRegex(SecurityValidationError, "capacity"):
            approvals.issue(shell, request, expires_at=self.clock.now + timedelta(minutes=5))
        self.assertEqual(approvals.record_count, 2)
        self.assertTrue(approvals.discard(second.approval_id))
        self.assertFalse(approvals.discard(second.approval_id))
        replacement = approvals.issue(shell, request, expires_at=self.clock.now + timedelta(minutes=5))
        self.assertEqual(approvals.record_count, 2)
        self.assertTrue(approvals.check(first.approval_id, shell, request, consume=True).valid)
        approvals.issue(shell, request, expires_at=self.clock.now + timedelta(minutes=5))
        self.assertEqual(approvals.record_count, 2)
        self.clock.now += timedelta(minutes=6)
        self.assertEqual(approvals.prune(), 2)
        self.assertEqual(approvals.record_count, 0)
        self.assertIsNotNone(replacement)

    def test_high_risk_task_needs_both_task_grant_and_exact_approval(self) -> None:
        task, _ = self.issue(PrincipalKind.TASK, task_id="task.one")
        request = self.request(task, task_id="task.one", risk=RiskLevel.HIGH)
        grant = self.grant(task, task_id="task.one", risk=RiskLevel.HIGH)
        self.assertEqual(
            self.policy.decide(task, request, [grant], now=self.clock.now).decision,
            DecisionKind.CONSENT_REQUIRED,
        )
        approval = self.approvals.issue(task, request, expires_at=self.clock.now + timedelta(minutes=5))
        self.assertTrue(
            self.policy.decide(
                task,
                request,
                [grant],
                approval_authority=self.approvals,
                approval_id=approval.approval_id,
                now=self.clock.now,
            ).allowed
        )


if __name__ == "__main__":
    unittest.main()
