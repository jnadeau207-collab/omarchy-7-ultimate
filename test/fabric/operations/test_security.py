from __future__ import annotations

import asyncio
import dataclasses
import unittest

from helper import Harness, fake_intents

from omarchy_fabric.models import FabricError, FixedArgvCommand
from omarchy_fabric.operations.contracts import OperationDefinition, OperationPlan, ProviderBinding
from omarchy_fabric.operations.executor import (
    ExecutorApplyResult,
    ExecutorReconcileResult,
    IntentCatalog,
    IntentDefinition,
    UnavailableProductionExecutor,
    boolean,
    stable_token,
)
from omarchy_fabric.operations.registry_gateway import RegistryOperationGateway
from omarchy_fabric.security.principal import EndpointPrincipal


class OperationSecurityTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.harness = Harness()

    async def asyncTearDown(self) -> None:
        self.harness.close()

    async def test_provider_generation_version_fingerprint_and_policy_drift_fail_before_consumption(self) -> None:
        for field, value, code in (
            ("generation", 2, "operation.provider-stale"),
            ("version", "provider.v1", "operation.provider-stale"),
            ("fingerprint", "b" * 64, "operation.provider-stale"),
        ):
            operation_id = await self.harness.preflight(key=f"drift.{field}")
            approval = self.harness.approval(operation_id)
            original = getattr(self.harness.gateway, field)
            setattr(self.harness.gateway, field, value)
            with self.assertRaises(FabricError) as caught:
                await self.harness.start(operation_id, approval)
            self.assertEqual(caught.exception.code, code)
            self.assertIsNone(self.harness.approvals.get(approval.approval_id).consumed_at)
            setattr(self.harness.gateway, field, original)
            self.harness.coordinator.cancel(self.harness.principal, operation_id)

        operation_id = await self.harness.preflight(key="drift.policy")
        approval = self.harness.approval(operation_id)
        self.harness.policy_revision = "policy.revision.2"
        with self.assertRaises(FabricError) as caught:
            await self.harness.start(operation_id, approval)
        self.assertEqual(caught.exception.code, "operation.policy-stale")
        self.assertIsNone(self.harness.approvals.get(approval.approval_id).consumed_at)

    async def test_full_approval_payload_is_durable_and_plan_json_is_deeply_immutable(self) -> None:
        operation_id = await self.harness.preflight()
        plan = self.harness.store.get(operation_id).plan
        approval = self.harness.approval(operation_id)
        self.assertEqual(plan.binding_digest, approval.binding_digest)
        with self.assertRaises(TypeError):
            plan.preflight["currentState"]["value"] = True
        with self.assertRaises(TypeError):
            plan.intent.payload["desired"] = False
        exported = plan.as_dict()
        exported["preflight"]["currentState"]["value"] = "tampered-copy"
        self.assertFalse(plan.preflight["currentState"]["value"])
        corrupt = plan.as_dict()
        corrupt["preflight"]["capability"] = "other.configure"
        corrupt["bindingDigest"] = "0" * 64
        with self.assertRaises(FabricError) as caught:
            OperationPlan.from_dict(corrupt)
        self.assertEqual(caught.exception.code, "operation.plan-corrupt")

    async def test_authority_is_revalidated_after_approval_checkpoint_before_consumption(self) -> None:
        cases = (
            ("policy", "operation.policy-stale"),
            ("provider", "operation.provider-stale"),
            ("session", "principal.revoked"),
            ("executor", "executor.production-unavailable"),
        )
        for mutation, expected_code in cases:
            with self.subTest(mutation=mutation):
                harness = Harness()
                try:
                    operation_id = await harness.preflight(key=f"revalidate.{mutation}")
                    approval = harness.approval(operation_id)

                    async def hook(_operation_id, checkpoint, *, selected=mutation):
                        if checkpoint != "approval":
                            return
                        if selected == "policy":
                            harness.policy_revision = "policy.revision.2"
                        elif selected == "provider":
                            harness.gateway.generation += 1
                        elif selected == "session":
                            harness.sessions.revoke(harness.principal.session_id)
                        else:
                            harness.coordinator.executor = UnavailableProductionExecutor()

                    harness.coordinator.checkpoint_hook = hook
                    with self.assertRaises(FabricError) as caught:
                        await harness.start(operation_id, approval)
                    self.assertEqual(caught.exception.code, expected_code)
                    self.assertIsNone(harness.approvals.get(approval.approval_id).consumed_at)
                    self.assertEqual(harness.store.get(operation_id).status.value, "awaiting-approval")
                    self.assertFalse(harness.executor.state("setting.primary")["value"])
                finally:
                    harness.close()

    async def test_malformed_executor_change_state_is_reconciled_not_trusted(self) -> None:
        async def malformed_error(stage, _plan):
            if stage == "apply":
                raise FabricError(
                    "executor.malformed",
                    "Malformed executor error",
                    "Executor returned an invalid change-state claim.",
                    change_state="changed",
                )

        self.harness.executor.stage_hook = malformed_error
        operation_id = await self.harness.preflight()
        result = await self.harness.start(operation_id)
        self.assertEqual(result["status"], "failed")
        ledger = self.harness.store.ledger(operation_id)
        event_types = [entry["eventType"] for entry in ledger["entries"]]
        self.assertIn("reconciliation-started", event_types)
        self.assertNotIn("apply-failed", event_types)
        self.assertIn('"changeState":"unknown"', str(ledger).replace("'", '"').replace(" ", ""))

    async def test_executor_result_state_mismatch_reconciles_actual_desired_state(self) -> None:
        original_apply = self.harness.executor.apply

        async def misleading_apply(plan, intent, cancelled):
            applied = await original_apply(plan, intent, cancelled)
            wrong_state = dict(applied.expected_state)
            wrong_state["value"] = False
            return ExecutorApplyResult(applied.state_revision, wrong_state, applied.evidence)

        self.harness.executor.apply = misleading_apply
        operation_id = await self.harness.preflight()
        result = await self.harness.start(operation_id)
        self.assertEqual(result["status"], "succeeded")
        self.assertTrue(result["result"]["reconciled"])
        self.assertTrue(self.harness.executor.state("setting.primary")["value"])
        self.assertEqual([call[0] for call in self.harness.executor.calls].count("apply"), 1)

    async def test_false_reconcile_disposition_cannot_hide_diverged_state(self) -> None:
        self.harness.executor.faults["apply"] = "fail-after"

        async def false_before(plan, intent, cancelled):
            actual = self.harness.executor.state(plan.resource.resource_id)
            return ExecutorReconcileResult(
                "before",
                actual["revision"],
                actual,
                {"executor": "fake", "disposition": "before"},
            )

        self.harness.executor.reconcile = false_before
        operation_id = await self.harness.preflight()
        result = await self.harness.start(operation_id)
        self.assertEqual(result["status"], "failed")
        self.assertTrue(self.harness.executor.state("setting.primary")["value"])
        self.assertIn("manualReconciliationRequired", str(self.harness.store.ledger(operation_id)))

    async def test_registry_gateway_accepts_real_float_observation_time(self) -> None:
        harness = self.harness

        class Registry:
            async def preflight(self, provider_id, action, arguments, principal):
                result = dict(await harness.gateway.preflight(provider_id, action, arguments, principal))
                result["observedAt"] = 1_777_777_777.125
                return result

            def catalog(self):
                return [
                    {
                        "manifest": {
                            "provider": "test.settings",
                            "providerVersion": harness.gateway.version,
                        },
                        "fingerprint": harness.gateway.fingerprint,
                        "generation": harness.gateway.generation,
                        "state": "available",
                    }
                ]

        self.harness.coordinator = self.harness.make_coordinator(gateway=RegistryOperationGateway(Registry()))
        operation_id = await self.harness.preflight()
        result = await self.harness.start(operation_id)
        self.assertEqual(result["status"], "succeeded")
        self.assertNotIn("observedAt", self.harness.store.get(operation_id).plan.as_dict())

    async def test_registry_catalog_iterator_failure_is_structured_and_message_safe(self) -> None:
        class BrokenRegistry:
            def catalog(self):
                def records():
                    yield {}
                    raise RuntimeError("token=supersecretvalue")

                return records()

        gateway = RegistryOperationGateway(BrokenRegistry())
        with self.assertRaises(FabricError) as caught:
            gateway.assert_current(ProviderBinding("test.settings", "provider.v0", "a" * 64, 1))
        self.assertEqual(caught.exception.code, "operation.provider-unavailable")
        self.assertNotIn("supersecretvalue", str(caught.exception.to_dict()))

    async def test_replacement_session_cannot_approve_or_start_but_can_read_owner_state(self) -> None:
        operation_id = await self.harness.preflight()
        approval = self.harness.approval(operation_id)
        replacement = self.harness.replacement_session()
        self.assertEqual(self.harness.coordinator.get(replacement, operation_id)["ownerId"], "account.uid.1000")
        with self.assertRaises(FabricError) as caught:
            self.harness.coordinator.approval_request(replacement, operation_id)
        self.assertEqual(caught.exception.code, "operation.origin-session-drift")
        with self.assertRaises(FabricError) as caught:
            await self.harness.coordinator.start(
                replacement,
                operation_id,
                approval_id=approval.approval_id,
                approvals=self.harness.approvals,
            )
        self.assertEqual(caught.exception.code, "operation.origin-session-drift")

    async def test_owner_spoof_and_other_uid_are_rejected_by_session_authority(self) -> None:
        operation_id = await self.harness.preflight()
        forged = dataclasses.replace(self.harness.principal, uid=0)
        with self.assertRaises(FabricError) as caught:
            self.harness.coordinator.get(forged, operation_id)
        self.assertIn(caught.exception.code, {"principal.unknown", "operation.principal-invalid"})
        other = self.harness.replacement_session(uid=1001)
        with self.assertRaises(FabricError) as caught:
            self.harness.coordinator.get(other, operation_id)
        self.assertEqual(caught.exception.code, "operation.owner-drift")

    async def test_revoked_or_expired_endpoint_cannot_authorize(self) -> None:
        operation_id = await self.harness.preflight()
        approval = self.harness.approval(operation_id)
        self.harness.sessions.revoke(self.harness.principal.session_id)
        with self.assertRaises(FabricError) as caught:
            await self.harness.start(operation_id, approval)
        self.assertEqual(caught.exception.code, "principal.revoked")

    async def test_approval_is_one_use_and_cannot_authorize_another_operation(self) -> None:
        first = await self.harness.preflight(resource_id="setting.primary", key="approval.first")
        second = await self.harness.preflight(resource_id="setting.secondary", key="approval.second")
        approval = self.harness.approval(first)
        await self.harness.start(first, approval)
        with self.assertRaises(FabricError) as caught:
            await self.harness.start(second, approval)
        self.assertIn(caught.exception.code, {"approval.consumed", "approval.operation-drift"})
        self.assertFalse(self.harness.executor.state("setting.secondary")["value"])

    async def test_stale_resource_plan_is_not_replayed(self) -> None:
        operation_id = await self.harness.preflight()
        approval = self.harness.approval(operation_id)
        self.harness.executor.external_set("setting.primary", "newer")
        result = await self.harness.start(operation_id, approval)
        self.assertEqual(result["status"], "failed")
        self.assertEqual(self.harness.executor.state("setting.primary")["value"], "newer")
        self.assertIn("executor.stale-resource", str(self.harness.store.ledger(operation_id)))

    async def test_intent_template_drift_fails_before_approval_consumption(self) -> None:
        operation_id = await self.harness.preflight()
        approval = self.harness.approval(operation_id)
        alternate = IntentCatalog(
            (
                IntentDefinition(
                    "test.settings.set",
                    FixedArgvCommand(str(__import__("pathlib").Path(__import__("sys").executable).resolve()), ("different-fixed-verb",)),
                    {"resourceId": stable_token, "desired": boolean},
                ),
            )
        )
        self.harness.coordinator.intents = alternate
        with self.assertRaises(FabricError) as caught:
            await self.harness.start(operation_id, approval)
        self.assertEqual(caught.exception.code, "executor.intent-drift")
        self.assertIsNone(self.harness.approvals.get(approval.approval_id).consumed_at)

    async def test_typed_payload_rejects_argv_control_and_secret_injection(self) -> None:
        catalog = fake_intents()
        with self.assertRaises(FabricError):
            catalog.build("test.settings.set", {"resourceId": "setting.primary", "desired": True, "argv": ["sh"]})
        with self.assertRaises(FabricError):
            catalog.build("test.settings.set", {"resourceId": "setting.primary\n--evil", "desired": True})
        with self.assertRaises(FabricError) as caught:
            catalog.build("test.settings.set", {"resourceId": "token=supersecretvalue", "desired": True})
        self.assertEqual(caught.exception.code, "executor.secret-rejected")
        operation_id = await self.harness.preflight()
        durable = str(self.harness.store.get(operation_id).plan.as_dict())
        self.assertNotIn("/usr/libexec", durable)
        self.assertNotIn("--typed-stdin-v0", durable)

    async def test_secret_shaped_provider_preflight_is_rejected_before_persistence(self) -> None:
        original = self.harness.gateway.preflight

        async def malicious(*args, **kwargs):
            result = dict(await original(*args, **kwargs))
            inner = dict(result["preflight"])
            inner["normalizedArguments"] = {"token": "supersecretvalue"}
            result["preflight"] = inner
            return result

        self.harness.gateway.preflight = malicious
        with self.assertRaises(FabricError) as caught:
            await self.harness.preflight()
        self.assertEqual(caught.exception.code, "operation.secret-rejected")
        self.assertEqual(self.harness.store.verify_all(), 0)

    async def test_preflight_envelope_effects_and_provider_action_are_exact(self) -> None:
        original = self.harness.gateway.preflight
        mutations = (
            lambda result: {**result, "provider": "test.other"},
            lambda result: {**result, "effects": ["settings.other"]},
            lambda result: {**result, "callerSummary": "trust me"},
        )
        for index, mutate in enumerate(mutations):
            async def malicious(*args, _mutate=mutate, **kwargs):
                return _mutate(dict(await original(*args, **kwargs)))

            self.harness.gateway.preflight = malicious
            with self.assertRaises(FabricError) as caught:
                await self.harness.preflight(key=f"envelope.{index}")
            self.assertEqual(caught.exception.code, "operation.preflight-invalid")
        self.assertEqual(self.harness.store.verify_all(), 0)

    async def test_unstructured_preflight_exception_does_not_leak_message(self) -> None:
        async def broken(*args, **kwargs):
            raise RuntimeError("token=supersecretvalue")

        self.harness.gateway.preflight = broken
        with self.assertRaises(FabricError) as caught:
            await self.harness.preflight()
        self.assertEqual(caught.exception.code, "operation.preflight-failed")
        self.assertNotIn("supersecretvalue", str(caught.exception.to_dict()))

    async def test_error_evidence_is_redacted_and_exception_text_is_not_leaked(self) -> None:
        from omarchy_fabric.operations.contracts import operation_error

        async def leaking_hook(stage, plan):
            if stage == "apply":
                raise operation_error("executor.test", "token=supersecretvalue")

        self.harness.executor.stage_hook = leaking_hook
        operation_id = await self.harness.preflight()
        result = await self.harness.start(operation_id)
        self.assertEqual(result["status"], "failed")
        evidence = str(self.harness.store.ledger(operation_id))
        self.assertNotIn("supersecretvalue", evidence)
        self.assertIn("[REDACTED]", evidence)

    async def test_unavailable_production_executor_never_consumes_approval(self) -> None:
        operation_id = await self.harness.preflight()
        approval = self.harness.approval(operation_id)
        self.harness.coordinator.executor = UnavailableProductionExecutor()
        with self.assertRaises(FabricError) as caught:
            await self.harness.start(operation_id, approval)
        self.assertEqual(caught.exception.code, "executor.production-unavailable")
        self.assertIsNone(self.harness.approvals.get(approval.approval_id).consumed_at)
        self.assertEqual(self.harness.store.get(operation_id).status.value, "awaiting-approval")


if __name__ == "__main__":
    unittest.main()
