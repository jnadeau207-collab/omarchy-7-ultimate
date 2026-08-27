from __future__ import annotations

import asyncio
import json
import tempfile
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator

from omarchy_fabric.models import FabricError
from omarchy_fabric.providers.packages.engine import FakeExecutionAdapter, PackageOperationEngine, inventory_revision

from helper import arguments, catalog, installed, principal, provider


class PackageOperationTests(unittest.IsolatedAsyncioTestCase):
    async def test_install_checkpoints_persists_validates_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "packages.json"
            value = provider(state_path=state)
            args = arguments(value.engine, "software.flatpak.spotify")
            preflight = await value.preflight("install", args, principal())
            self.assertEqual(preflight["adapter"]["adapterId"], "packages.flatpak.install")
            self.assertEqual(preflight["steps"][2]["mutationBoundary"], True)
            result = await value.apply("install", args, preflight["inventoryRevision"])
            self.assertEqual(result["status"], "succeeded")
            self.assertEqual(result["checkpoints"], ["verify-provenance", "stage-payload", "apply", "validate", "commit"])
            self.assertEqual(len(value.engine.inventory(include_unmanaged=True)["items"]), 1)
            projection_schema = json.loads((Path(__file__).resolve().parents[3] / "default/fabric/schema/packages-operation-v0.json").read_text(encoding="utf-8"))
            Draft202012Validator(projection_schema).validate(value.engine.operations()["operations"][0])
            self.assertEqual(await value.validate("install", args, result["state"]), result["state"])
            again = await value.apply("install", args, preflight["inventoryRevision"])
            self.assertEqual(again["operationId"], result["operationId"])
            restarted = PackageOperationEngine(catalog(), [], state_path=state)
            self.assertEqual(restarted.inventory(include_unmanaged=True)["items"][0]["catalogId"], "software.flatpak.spotify")

    async def test_remove_has_data_recovery_and_rollback_restores_exact_item(self):
        item = installed()
        value = provider([item])
        args = arguments(value.engine, item["catalogId"], request_id="request.software.remove")
        preflight = await value.preflight("remove", args, principal())
        self.assertEqual(preflight["risk"], "destructive")
        self.assertEqual(preflight["recovery"]["priorItem"], item)
        self.assertEqual(preflight["recovery"]["dataDisposition"]["preserve"], sorted(item["configPaths"] + item["dataPaths"]))
        self.assertEqual(preflight["recovery"]["dataDisposition"]["delete"], [])
        delete_args = arguments(value.engine, item["catalogId"], request_id="request.software.remove-data", preserve=False)
        delete_plan = await value.preflight("remove", delete_args, principal())
        self.assertEqual(delete_plan["recovery"]["dataDisposition"]["preserve"], [])
        self.assertEqual(delete_plan["recovery"]["dataDisposition"]["delete"], sorted(item["configPaths"] + item["dataPaths"]))
        result = await value.apply("remove", args, preflight["inventoryRevision"])
        self.assertEqual(value.engine.inventory(include_unmanaged=True)["items"], [])
        rolled = await value.rollback("remove", result["state"], result["inventoryRevision"])
        self.assertEqual(rolled["status"], "rolled-back")
        self.assertEqual(rolled["state"]["targetState"], "installed")
        self.assertEqual(rolled["changeState"], "complete")
        self.assertEqual(value.engine.inventory(include_unmanaged=True)["items"], [item])

    async def test_catalog_and_inventory_drift_are_refused(self):
        value = provider()
        args = arguments(value.engine, "software.curated.neovim")
        args["catalogRevision"] = "sha256." + "0" * 64
        with self.assertRaises(FabricError) as catalog_drift:
            await value.preflight("install", args, principal())
        self.assertEqual(catalog_drift.exception.code, "packages.catalog-drift")
        args = arguments(value.engine, "software.curated.neovim")
        args["expectedInventoryRevision"] = "sha256." + "0" * 64
        with self.assertRaises(FabricError) as inventory_drift:
            await value.preflight("install", args, principal())
        self.assertEqual(inventory_drift.exception.code, "packages.inventory-drift")

    async def test_cancellation_before_and_after_mutation_is_honest(self):
        early_adapter = FakeExecutionAdapter(pause_at="stage-payload")
        early = provider(adapter=early_adapter)
        args = arguments(early.engine, "software.curated.neovim", request_id="request.cancel.early")
        plan = await early.preflight("install", args, principal())
        task = asyncio.create_task(early.apply("install", args, plan["inventoryRevision"]))
        await asyncio.wait_for(early_adapter.entered.wait(), 1)
        early.engine.cancel(plan["operationId"])
        early_adapter.release.set()
        result = await task
        self.assertEqual(result["status"], "cancelled")
        self.assertEqual(early.engine.inventory(include_unmanaged=True)["items"], [])

        late_adapter = FakeExecutionAdapter(pause_at="validate")
        late = provider(adapter=late_adapter)
        args = arguments(late.engine, "software.curated.neovim", request_id="request.cancel.late")
        plan = await late.preflight("install", args, principal())
        task = asyncio.create_task(late.apply("install", args, plan["inventoryRevision"]))
        await asyncio.wait_for(late_adapter.entered.wait(), 1)
        late.engine.cancel(plan["operationId"])
        late_adapter.release.set()
        result = await task
        self.assertEqual(result["status"], "needs-reconcile")
        reconciled = await late.engine.reconcile()
        self.assertEqual(reconciled[0]["status"], "succeeded")

    async def test_concurrent_resource_owner_is_rejected(self):
        adapter = FakeExecutionAdapter(pause_at="prepare" if False else "stage-payload")
        value = provider(adapter=adapter)
        first_args = arguments(value.engine, "software.curated.neovim", request_id="request.concurrent.one")
        first_plan = await value.preflight("install", first_args, principal())
        first = asyncio.create_task(value.apply("install", first_args, first_plan["inventoryRevision"]))
        await asyncio.wait_for(adapter.entered.wait(), 1)
        second_args = arguments(value.engine, "software.curated.neovim", request_id="request.concurrent.two")
        with self.assertRaises(FabricError) as conflict:
            await value.apply("install", second_args, second_args["expectedInventoryRevision"])
        self.assertEqual(conflict.exception.code, "packages.operation-conflict")
        value.engine.cancel(first_plan["operationId"]); adapter.release.set(); await first

    async def test_adapter_failure_after_apply_requires_reconciliation(self):
        value = provider(adapter=FakeExecutionAdapter(fail_at="validate"))
        args = arguments(value.engine, "software.curated.neovim", request_id="request.failure.after")
        plan = await value.preflight("install", args, principal())
        result = await value.apply("install", args, plan["inventoryRevision"])
        self.assertEqual(result["status"], "needs-reconcile")
        self.assertEqual(result["changeState"], "unknown")
        reconciled = await value.engine.reconcile()
        self.assertEqual(reconciled[0]["status"], "succeeded")

    async def test_restart_marks_running_operation_for_reconcile(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "packages.json"
            adapter = FakeExecutionAdapter(pause_at="stage-payload")
            value = provider(state_path=state, adapter=adapter)
            args = arguments(value.engine, "software.curated.neovim", request_id="request.restart")
            plan = await value.preflight("install", args, principal())
            task = asyncio.create_task(value.apply("install", args, plan["inventoryRevision"]))
            await asyncio.wait_for(adapter.entered.wait(), 1)
            restarted = PackageOperationEngine(catalog(), [], state_path=state)
            self.assertEqual(restarted.operations()["operations"][0]["status"], "needs-reconcile")
            value.engine.cancel(plan["operationId"])
            adapter.release.set()
            with self.assertRaises(FabricError) as concurrent:
                await task
            self.assertEqual(concurrent.exception.code, "packages.state-concurrent")

    async def test_corrupt_and_cross_catalog_state_are_rejected(self):
        unsafe = installed()
        unsafe["configPaths"] = ["/home/test/../escape"]
        with self.assertRaises(FabricError) as invalid_inventory:
            PackageOperationEngine(catalog(), [unsafe])
        self.assertEqual(invalid_inventory.exception.code, "packages.inventory-invalid")
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "packages.json"
            state.write_text("{broken", encoding="utf-8")
            with self.assertRaises(FabricError) as corrupt:
                PackageOperationEngine(catalog(), [], state_path=state)
            self.assertEqual(corrupt.exception.code, "packages.state-corrupt")
            state.write_text(json.dumps({"schemaVersion":"v0","catalogRevision":"sha256." + "0" * 64,"inventory":[],"operations":[]}), encoding="utf-8")
            with self.assertRaises(FabricError) as wrong_catalog:
                PackageOperationEngine(catalog(), [], state_path=state)
            self.assertEqual(wrong_catalog.exception.code, "packages.state-corrupt")


if __name__ == "__main__":
    unittest.main()
