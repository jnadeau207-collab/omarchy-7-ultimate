from __future__ import annotations

import asyncio
import copy
import json
import os
import tempfile
import unittest
from pathlib import Path

from omarchy_fabric.models import FabricError
from omarchy_fabric.providers.compatibility.engine import CompatibilityEngine, FakeCompatibilityAdapter, _acquire_state_lock, _release_state_lock, deployment_revision
from omarchy_fabric.providers.packages.identity import revision, stable_id

from helper import arguments, host, principal, provider, recipes, request, reviewed_request


class UnexpectedAdapter:
    async def checkpoint(self, name, plan):
        raise RuntimeError("untrusted adapter text must not escape")


class CompatibilityAdversarialTests(unittest.IsolatedAsyncioTestCase):
    async def deploy(self, value, request_id="request.adversarial.deploy"):
        workload = reviewed_request()
        args = arguments(value.engine, workload, request_id=request_id)
        plan = await value.preflight("deploy", args, principal())
        result = await value.apply("deploy", args, plan["deploymentRevision"])
        return workload, args, plan, result

    async def test_recipe_route_enforces_runtime_memory_disk_and_constraints(self):
        value = provider()
        workload = reviewed_request()
        cases = [
            host(availableRuntimes=["native"], virtualizationAvailable=False),
            host(memoryMiB=1024, virtualizationAvailable=False),
            host(diskMiB=1024, virtualizationAvailable=False),
        ]
        for machine in cases:
            with self.subTest(machine=machine):
                result = await value.read("route.decide", {"request": workload, "host": machine})
                self.assertEqual(result["eligibility"], "unsupported")
                recipe = next(item for item in result["considered"] if item["route"] == "known-good-recipe")
                self.assertEqual(recipe["status"], "ineligible")
        workload = reviewed_request()
        workload["constraints"]["requiresAdmin"] = True
        result = await value.read("route.decide", {"request": workload, "host": host(virtualizationAvailable=False)})
        self.assertEqual(result["eligibility"], "unsupported")

    async def test_routes_require_pinned_compatible_artifacts_and_bounded_permissions(self):
        value = provider()
        native = request(identity="workload.unpinned", artifact_kind="native-package")
        native["artifact"]["digest"] = None
        with self.assertRaises(FabricError) as invalid:
            await value.read("route.decide", {"request": native, "host": host()})
        self.assertEqual(invalid.exception.code, "compatibility.contract-invalid")

        web = request(identity="workload.web.overreach", workload_type="web", artifact_kind="web-url", acceptsBrowser=True, permissions=["network", "filesystem-home"])
        result = await value.read("route.decide", {"request": web, "host": host()})
        self.assertEqual(result["eligibility"], "unsupported")

        malformed = request(identity="workload.url.malformed", workload_type="web", artifact_kind="web-url", acceptsBrowser=True)
        malformed["artifact"]["origin"] = "https://["
        result = await value.read("route.decide", {"request": malformed, "host": host()})
        self.assertEqual(result["eligibility"], "unsupported")

        contradictory = request(identity="workload.windows.native", workload_type="windows-app", artifact_kind="native-package")
        result = await value.read("route.decide", {"request": contradictory, "host": host()})
        self.assertEqual(result["eligibility"], "unsupported")

        unknown = request(identity="workload.game.unknown", workload_type="windows-game", artifact_kind="windows-executable", antiCheat="unknown")
        result = await value.read("route.decide", {"request": unknown, "host": host()})
        self.assertEqual(result["selectedRoute"], "vm")

    async def test_remove_uses_installed_identity_permissions_and_export_identity_is_stable(self):
        value = provider()
        workload, _, _, _ = await self.deploy(value)
        changed = copy.deepcopy(workload)
        changed["name"] = "Caller-supplied misleading name"
        changed["permissions"] = ["devices", "camera"]
        changed["artifact"]["digest"] = "sha256:" + "0" * 64
        remove_args = arguments(value.engine, changed, host(virtualizationAvailable=False), request_id="request.remove.bound")
        remove_plan = await value.preflight("remove", remove_args, principal())
        self.assertEqual(remove_plan["lifecycle"]["permissions"], ["filesystem-home", "network"])
        self.assertIn("Adobe Reader", remove_plan["summary"])
        self.assertNotIn(changed["name"], remove_plan["summary"])

        first_args = arguments(value.engine, workload, host(), request_id="request.export.first")
        first = await value.preflight("export", first_args, principal())
        changed_host = host(memoryMiB=32768, diskMiB=524288, virtualizationAvailable=False)
        second_args = arguments(value.engine, changed, changed_host, request_id="request.export.second")
        second = await value.preflight("export", second_args, principal())
        self.assertEqual(first["recovery"]["exportArtifact"], second["recovery"]["exportArtifact"])

    async def test_global_revision_owner_and_reconciliation_required_state_block_all_mutations(self):
        adapter = FakeCompatibilityAdapter(pause_at="prepare")
        value = provider(adapter=adapter)
        first_workload = reviewed_request()
        first_args = arguments(value.engine, first_workload, request_id="request.global.compat.one")
        first_plan = await value.preflight("deploy", first_args, principal())
        task = asyncio.create_task(value.apply("deploy", first_args, first_plan["deploymentRevision"]))
        await asyncio.wait_for(adapter.entered.wait(), 1)
        other = request(identity="workload.other.native", artifact_kind="native-package")
        second_args = arguments(value.engine, other, request_id="request.global.compat.two")
        with self.assertRaises(FabricError) as conflict:
            await value.apply("deploy", second_args, second_args["expectedDeploymentRevision"])
        self.assertEqual(conflict.exception.code, "compatibility.operation-conflict")
        value.engine.cancel(first_plan["operationId"])
        adapter.release.set()
        await task

        failed = provider(adapter=FakeCompatibilityAdapter(fail_at="validate"))
        args = arguments(failed.engine, reviewed_request(), request_id="request.needs.reconcile")
        plan = await failed.preflight("deploy", args, principal())
        result = await failed.apply("deploy", args, plan["deploymentRevision"])
        self.assertEqual(result["status"], "needs-reconcile")
        other_args = arguments(failed.engine, other, request_id="request.blocked.by.reconcile")
        with self.assertRaises(FabricError) as blocked:
            await failed.apply("deploy", other_args, other_args["expectedDeploymentRevision"])
        self.assertEqual(blocked.exception.code, "compatibility.operation-conflict")

    async def test_cancellation_during_final_checkpoint_cannot_be_reported_as_success(self):
        adapter = FakeCompatibilityAdapter(pause_at="commit")
        value = provider(adapter=adapter)
        args = arguments(value.engine, reviewed_request(), request_id="request.cancel.commit.compat")
        plan = await value.preflight("deploy", args, principal())
        task = asyncio.create_task(value.apply("deploy", args, plan["deploymentRevision"]))
        await asyncio.wait_for(adapter.entered.wait(), 1)
        value.engine.cancel(plan["operationId"])
        adapter.release.set()
        result = await task
        self.assertEqual(result["status"], "needs-reconcile")
        self.assertEqual(result["changeState"], "unknown")
        self.assertEqual((await value.engine.reconcile())[0]["status"], "succeeded")

    async def test_unexpected_adapter_validate_and_rollback_fail_closed(self):
        value = provider(adapter=UnexpectedAdapter())
        args = arguments(value.engine, reviewed_request(), request_id="request.adapter.unexpected")
        plan = await value.preflight("deploy", args, principal())
        result = await value.apply("deploy", args, plan["deploymentRevision"])
        self.assertEqual(result["status"], "failed")
        self.assertNotIn("untrusted adapter text", result["error"])

        value = provider()
        _, args, _, result = await self.deploy(value, request_id="request.binding.compat")
        altered = copy.deepcopy(args)
        altered["preserveData"] = not args["preserveData"]
        with self.assertRaises(FabricError) as validation:
            await value.validate("deploy", altered, result["state"])
        self.assertEqual(validation.exception.code, "compatibility.validation-failed")
        forged = dict(result["state"])
        forged["status"] = "failed"
        with self.assertRaises(FabricError) as rollback:
            await value.rollback("deploy", forged, result["deploymentRevision"])
        self.assertEqual(rollback.exception.code, "compatibility.rollback-state-invalid")

    async def test_running_superseded_and_unprovable_export_cannot_claim_success(self):
        adapter = FakeCompatibilityAdapter(pause_at="prepare")
        value = provider(adapter=adapter)
        args = arguments(value.engine, reviewed_request(), request_id="request.rollback.running.compat")
        plan = await value.preflight("deploy", args, principal())
        task = asyncio.create_task(value.apply("deploy", args, plan["deploymentRevision"]))
        await asyncio.wait_for(adapter.entered.wait(), 1)
        with self.assertRaises(FabricError) as running:
            await value.engine.rollback(plan["operationId"], deployment_revision(value.engine._deployments))
        self.assertEqual(running.exception.code, "compatibility.rollback-invalid")
        value.engine.cancel(plan["operationId"]); adapter.release.set(); await task

        value = provider()
        workload, _, _, deployed = await self.deploy(value, request_id="request.rollback.first.compat")
        remove_args = arguments(value.engine, workload, request_id="request.rollback.second.compat")
        remove_plan = await value.preflight("remove", remove_args, principal())
        await value.apply("remove", remove_args, remove_plan["deploymentRevision"])
        with self.assertRaises(FabricError) as superseded:
            await value.engine.rollback(deployed["operationId"], deployment_revision(value.engine._deployments))
        self.assertEqual(superseded.exception.code, "compatibility.rollback-superseded")

        value = provider()
        workload, _, _, _ = await self.deploy(value, request_id="request.export.base")
        value.engine.adapter = FakeCompatibilityAdapter(fail_at="validate")
        export_args = arguments(value.engine, workload, request_id="request.export.unknown")
        export_plan = await value.preflight("export", export_args, principal())
        result = await value.apply("export", export_args, export_plan["deploymentRevision"])
        self.assertEqual(result["status"], "needs-reconcile")
        reconciled = await value.engine.reconcile()
        self.assertEqual(reconciled[0]["status"], "failed")
        self.assertEqual(reconciled[0]["changeState"], "unknown")
        self.assertIn("cannot be proven", reconciled[0]["error"])

    async def test_recomputed_nested_journal_tamper_and_nonfinite_json_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "compatibility.json"
            value = provider(state_path=state)
            await self.deploy(value, request_id="request.journal.compat")
            document = json.loads(state.read_text(encoding="utf-8"))
            operation = document["operations"][0]
            operation["plan"]["summary"] = "attacker-rewritten-plan"
            operation["plan"]["planRevision"] = revision({**operation["plan"], "planRevision": "sha256." + "0" * 64})
            operation["revision"] = CompatibilityEngine._operation_revision(operation)
            state.write_text(json.dumps(document), encoding="utf-8")
            with self.assertRaises(FabricError) as tampered:
                CompatibilityEngine(recipes(), state_path=state)
            self.assertEqual(tampered.exception.code, "compatibility.state-corrupt")
            state.write_text('{"schemaVersion":"v0","recipeRevision":NaN,"deployments":[],"operations":[]}', encoding="utf-8")
            with self.assertRaises(FabricError) as nonfinite:
                CompatibilityEngine(recipes(), state_path=state)
            self.assertEqual(nonfinite.exception.code, "compatibility.state-corrupt")

    async def test_two_engine_instances_use_durable_compare_and_swap(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "compatibility.json"
            initial = provider(state_path=state)
            workload, _, _, _ = await self.deploy(initial, request_id="request.cas.compat.seed")
            first = provider(state_path=state)
            second = provider(state_path=state)
            first_args = arguments(first.engine, workload, request_id="request.cas.compat.first")
            second_args = arguments(second.engine, workload, request_id="request.cas.compat.second")
            first_plan = await first.preflight("remove", first_args, principal())
            await first.apply("remove", first_args, first_plan["deploymentRevision"])
            with self.assertRaises(FabricError) as stale_writer:
                await second.apply("remove", second_args, second_args["expectedDeploymentRevision"])
            self.assertEqual(stale_writer.exception.code, "compatibility.state-concurrent")

    def test_process_lock_contention_fails_fast(self):
        if os.name != "posix":
            self.skipTest("POSIX advisory locks are the production path")
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "compatibility.json"
            descriptor = _acquire_state_lock(state)
            try:
                with self.assertRaises(FabricError) as busy:
                    _acquire_state_lock(state)
                self.assertEqual(busy.exception.code, "compatibility.state-busy")
                self.assertTrue(busy.exception.retryable)
            finally:
                _release_state_lock(descriptor)

    def test_deployments_reject_duplicate_workloads_unbounded_fields_and_recipe_lies(self):
        base = {
            "id": stable_id("deployment.compatibility", "workload.duplicate", "native"),
            "workloadId": "workload.duplicate",
            "displayName": "Native",
            "decisionId": "decision.duplicate.native",
            "decisionRevision": "sha256." + "0" * 64,
            "route": "native",
            "recipeId": None,
            "state": "installed",
            "permissions": [],
            "dataArtifacts": [],
        }
        second = copy.deepcopy(base)
        second.update({"id": stable_id("deployment.compatibility", "workload.duplicate", "vm"), "route": "vm", "decisionId": "decision.duplicate.vm"})
        with self.assertRaises(FabricError):
            CompatibilityEngine(recipes(), deployments=[base, second])
        oversized = copy.deepcopy(base); oversized["displayName"] = "x" * 161
        with self.assertRaises(FabricError):
            CompatibilityEngine(recipes(), deployments=[oversized])
        lie = copy.deepcopy(base); lie.update({"id": stable_id("deployment.compatibility", "workload.duplicate", "known-good-recipe"), "route": "known-good-recipe", "recipeId": "recipe.adobe-reader.v1"})
        with self.assertRaises(FabricError):
            CompatibilityEngine(recipes(), deployments=[lie])


if __name__ == "__main__":
    unittest.main()
