from __future__ import annotations

import asyncio
import json
import tempfile
import unittest
from pathlib import Path

from omarchy_fabric.models import FabricError
from omarchy_fabric.providers.compatibility.engine import CompatibilityEngine, FakeCompatibilityAdapter, deployment_revision

from helper import arguments, host, principal, provider, recipes, request, reviewed_request

class CompatibilityLifecycleTests(unittest.IsolatedAsyncioTestCase):
    def workload(self):
        return reviewed_request()

    async def deploy(self, value, request_id="request.compatibility.deploy"):
        args = arguments(value.engine, self.workload(), request_id=request_id)
        plan = await value.preflight("deploy", args, principal())
        result = await value.apply("deploy", args, plan["deploymentRevision"])
        return args, plan, result

    async def test_deploy_restart_validate_export_remove_and_rollback(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "compatibility.json"
            value = provider(state_path=state)
            _, plan, deployed = await self.deploy(value)
            self.assertEqual(deployed["status"], "succeeded")
            self.assertEqual(plan["decision"]["selectedRoute"], "known-good-recipe")
            self.assertEqual(plan["lifecycle"]["permissions"], ["filesystem-home", "network"])
            self.assertEqual(await value.validate("deploy", plan["normalizedArguments"], deployed["state"]), deployed["state"])
            restarted = CompatibilityEngine(recipes(), state_path=state)
            self.assertEqual(restarted.deployments()["deployments"][0]["workloadId"], "workload.adobe-reader")

            export_args = arguments(value.engine, self.workload(), request_id="request.compatibility.export")
            export_plan = await value.preflight("export", export_args, principal())
            exported = await value.apply("export", export_args, export_plan["deploymentRevision"])
            self.assertEqual(exported["exportArtifact"]["format"], "compatibility-export-v0")

            remove_args = arguments(value.engine, self.workload(), request_id="request.compatibility.remove")
            remove_plan = await value.preflight("remove", remove_args, principal())
            self.assertEqual(remove_plan["risk"], "destructive")
            self.assertIn("data.user-documents", remove_plan["recovery"]["removalPlan"]["preserve"])
            removed = await value.apply("remove", remove_args, remove_plan["deploymentRevision"])
            self.assertEqual(value.engine.deployments()["deployments"], [])
            rolled = await value.rollback("remove", removed["state"], removed["deploymentRevision"])
            self.assertEqual(rolled["status"], "rolled-back")
            self.assertEqual(rolled["state"]["targetState"], "installed")
            self.assertEqual(rolled["changeState"], "complete")
            self.assertEqual(len(value.engine.deployments()["deployments"]), 1)

    async def test_unsupported_preflight_explains_and_refuses(self):
        value = provider()
        workload = request(identity="workload.kernel-game", workload_type="windows-game", artifact_kind="windows-executable", antiCheat="blocked", requiresKernelDriver=True)
        args = arguments(value.engine, workload, host(virtualizationAvailable=False), request_id="request.unsupported")
        with self.assertRaises(FabricError) as unsupported:
            await value.preflight("deploy", args, principal())
        self.assertEqual(unsupported.exception.code, "compatibility.unsupported")
        self.assertEqual(value.engine.deployments()["deployments"], [])

    async def test_recipe_and_deployment_drift_fail_closed(self):
        value = provider()
        args = arguments(value.engine, self.workload())
        args["recipeRevision"] = "sha256." + "0" * 64
        with self.assertRaises(FabricError) as recipe_drift:
            await value.preflight("deploy", args, principal())
        self.assertEqual(recipe_drift.exception.code, "compatibility.recipe-drift")
        args = arguments(value.engine, self.workload()); args["expectedDeploymentRevision"] = "sha256." + "0" * 64
        with self.assertRaises(FabricError) as deployment_drift:
            await value.preflight("deploy", args, principal())
        self.assertEqual(deployment_drift.exception.code, "compatibility.deployment-drift")

    async def test_cancellation_concurrency_failure_and_reconciliation(self):
        adapter = FakeCompatibilityAdapter(pause_at="prepare")
        value = provider(adapter=adapter)
        args = arguments(value.engine, self.workload(), request_id="request.compatibility.paused")
        plan = await value.preflight("deploy", args, principal())
        task = asyncio.create_task(value.apply("deploy", args, plan["deploymentRevision"]))
        await asyncio.wait_for(adapter.entered.wait(), 1)
        competing = arguments(value.engine, self.workload(), request_id="request.compatibility.competing")
        with self.assertRaises(FabricError) as conflict:
            await value.apply("deploy", competing, competing["expectedDeploymentRevision"])
        self.assertEqual(conflict.exception.code, "compatibility.operation-conflict")
        value.engine.cancel(plan["operationId"]); adapter.release.set()
        self.assertEqual((await task)["status"], "cancelled")

        failed = provider(adapter=FakeCompatibilityAdapter(fail_at="validate"))
        args = arguments(failed.engine, self.workload(), request_id="request.compatibility.failed")
        plan = await failed.preflight("deploy", args, principal())
        result = await failed.apply("deploy", args, plan["deploymentRevision"])
        self.assertEqual(result["status"], "needs-reconcile")
        self.assertEqual((await failed.engine.reconcile())[0]["status"], "succeeded")

    async def test_restart_and_corrupt_state_are_explicit(self):
        invalid_deployment = {"id":"deployment.bad","workloadId":"workload.bad","displayName":"Bad","decisionId":"decision.bad","decisionRevision":"sha256." + "0" * 64,"route":"shell","recipeId":None,"state":"installed","permissions":[],"dataArtifacts":[]}
        with self.assertRaises(FabricError) as invalid:
            CompatibilityEngine(recipes(), deployments=[invalid_deployment])
        self.assertEqual(invalid.exception.code, "compatibility.deployments-invalid")
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "compatibility.json"
            adapter = FakeCompatibilityAdapter(pause_at="prepare")
            value = provider(state_path=state, adapter=adapter)
            args = arguments(value.engine, self.workload(), request_id="request.compatibility.restart")
            plan = await value.preflight("deploy", args, principal())
            task = asyncio.create_task(value.apply("deploy", args, plan["deploymentRevision"]))
            await asyncio.wait_for(adapter.entered.wait(), 1)
            restarted = CompatibilityEngine(recipes(), state_path=state)
            self.assertEqual(next(iter(restarted._operations.values()))["status"], "needs-reconcile")
            value.engine.cancel(plan["operationId"])
            adapter.release.set()
            with self.assertRaises(FabricError) as concurrent:
                await task
            self.assertEqual(concurrent.exception.code, "compatibility.state-concurrent")

            state.write_text("[]", encoding="utf-8")
            with self.assertRaises(FabricError) as corrupt:
                CompatibilityEngine(recipes(), state_path=state)
            self.assertEqual(corrupt.exception.code, "compatibility.state-corrupt")

    async def test_export_requires_deployment_and_preserve_false_moves_data_to_delete(self):
        value = provider()
        args = arguments(value.engine, self.workload(), request_id="request.export.missing")
        with self.assertRaises(FabricError) as missing:
            await value.preflight("export", args, principal())
        self.assertEqual(missing.exception.code, "compatibility.deployment-missing")
        await self.deploy(value)
        remove_args = arguments(value.engine, self.workload(), request_id="request.remove.delete", preserve=False)
        plan = await value.preflight("remove", remove_args, principal())
        self.assertEqual(plan["recovery"]["removalPlan"]["preserve"], [])
        self.assertIn("data.user-documents", plan["recovery"]["removalPlan"]["delete"])

    async def test_removal_uses_installed_route_when_host_can_no_longer_route_workload(self):
        value = provider()
        await self.deploy(value)
        workload = self.workload()
        workload["artifact"]["digest"] = "sha256:" + "0" * 64
        unavailable_host = host(virtualizationAvailable=False, protonAvailable=False, isolationAvailable=False, browserAvailable=False)
        remove_args = arguments(value.engine, workload, unavailable_host, request_id="request.remove.offline")
        plan = await value.preflight("remove", remove_args, principal())
        self.assertEqual(plan["decision"]["eligibility"], "unsupported")
        self.assertEqual(plan["adapter"]["adapterId"], "compatibility.recipe")
        removed = await value.apply("remove", remove_args, plan["deploymentRevision"])
        self.assertEqual(removed["status"], "succeeded")

if __name__ == "__main__":
    unittest.main()
