from __future__ import annotations

import asyncio
import copy
import json
import os
import tempfile
import unittest
from pathlib import Path

from omarchy_fabric.models import FabricError
from omarchy_fabric.providers.packages.catalog import PackageCatalog, catalog_revision
from omarchy_fabric.providers.packages.engine import FakeExecutionAdapter, PackageOperationEngine, _acquire_state_lock, _release_state_lock, inventory_revision
from omarchy_fabric.providers.packages.identity import revision
from omarchy_fabric.providers.packages.provider import PackageProvider

from helper import arguments, catalog, installed, principal, provider


class UnexpectedAdapter:
    async def checkpoint(self, name, plan):
        raise RuntimeError("untrusted adapter text must not escape")


class PackageAdversarialTests(unittest.IsolatedAsyncioTestCase):
    async def test_installed_but_tampered_item_is_recovered_instead_of_treated_as_satisfied(self):
        item = installed(digest="sha256:" + "0" * 64, state="installed")
        value = provider([item])
        args = arguments(value.engine, item["catalogId"], request_id="request.recover.tampered")
        plan = await value.preflight("install", args, principal())
        self.assertTrue(plan["changed"])
        result = await value.apply("install", args, plan["inventoryRevision"])
        self.assertEqual(result["status"], "succeeded")
        self.assertEqual(value.engine._inventory[0]["artifactDigest"], value.catalog.by_id[item["catalogId"]]["provenance"]["artifactDigest"])

        exact = provider([installed()])
        args = arguments(exact.engine, "software.curated.neovim", request_id="request.install.noop")
        plan = await exact.preflight("install", args, principal())
        result = await exact.apply("install", args, plan["inventoryRevision"])
        self.assertFalse(result["changed"])
        self.assertEqual(result["changeState"], "none")

    async def test_cancellation_during_final_checkpoint_cannot_be_reported_as_success(self):
        adapter = FakeExecutionAdapter(pause_at="commit")
        value = provider(adapter=adapter)
        args = arguments(value.engine, "software.curated.neovim", request_id="request.cancel.commit")
        plan = await value.preflight("install", args, principal())
        task = asyncio.create_task(value.apply("install", args, plan["inventoryRevision"]))
        await asyncio.wait_for(adapter.entered.wait(), 1)
        value.engine.cancel(plan["operationId"])
        adapter.release.set()
        result = await task
        self.assertEqual(result["status"], "needs-reconcile")
        self.assertEqual(result["changeState"], "unknown")
        self.assertEqual((await value.engine.reconcile())[0]["status"], "succeeded")

    async def test_catalog_conflicts_are_enforced_in_both_directions(self):
        document = copy.deepcopy(catalog().document)
        document["entries"][0]["install"]["conflicts"] = ["software.repo.libreoffice"]
        document["revision"] = catalog_revision(document)
        trusted = PackageCatalog(document)
        engine = PackageOperationEngine(trusted, [installed("software.repo.libreoffice")])
        value = PackageProvider(trusted, engine)
        args = arguments(engine, "software.curated.neovim", request_id="request.conflict.forward")
        with self.assertRaises(FabricError) as conflict:
            await value.preflight("install", args, principal())
        self.assertEqual(conflict.exception.code, "packages.install-conflict")

        document = copy.deepcopy(catalog().document)
        for entry in document["entries"]:
            if entry["id"] == "software.repo.libreoffice":
                entry["install"]["conflicts"] = ["software.curated.neovim"]
        document["revision"] = catalog_revision(document)
        trusted = PackageCatalog(document)
        engine = PackageOperationEngine(trusted, [installed("software.repo.libreoffice")])
        value = PackageProvider(trusted, engine)
        args = arguments(engine, "software.curated.neovim", request_id="request.conflict.reverse")
        with self.assertRaises(FabricError) as reverse:
            await value.preflight("install", args, principal())
        self.assertEqual(reverse.exception.code, "packages.install-conflict")

    async def test_global_revision_owner_blocks_different_resource_and_unknown_adapter_is_terminal(self):
        adapter = FakeExecutionAdapter(pause_at="stage-payload")
        value = provider(adapter=adapter)
        first_args = arguments(value.engine, "software.curated.neovim", request_id="request.global.one")
        first_plan = await value.preflight("install", first_args, principal())
        first = asyncio.create_task(value.apply("install", first_args, first_plan["inventoryRevision"]))
        await asyncio.wait_for(adapter.entered.wait(), 1)
        second_args = arguments(value.engine, "software.repo.libreoffice", request_id="request.global.two")
        with self.assertRaises(FabricError) as conflict:
            await value.apply("install", second_args, second_args["expectedInventoryRevision"])
        self.assertEqual(conflict.exception.code, "packages.operation-conflict")
        value.engine.cancel(first_plan["operationId"])
        adapter.release.set()
        await first

        failed = provider(adapter=UnexpectedAdapter())
        args = arguments(failed.engine, "software.curated.neovim", request_id="request.adapter.unexpected")
        plan = await failed.preflight("install", args, principal())
        result = await failed.apply("install", args, plan["inventoryRevision"])
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["changeState"], "none")
        self.assertNotIn("untrusted adapter text", result["error"])

    async def test_validate_and_rollback_bind_exact_action_arguments_and_state(self):
        value = provider()
        args = arguments(value.engine, "software.curated.neovim", request_id="request.binding")
        plan = await value.preflight("install", args, principal())
        result = await value.apply("install", args, plan["inventoryRevision"])
        altered = dict(args)
        altered["preserveUserData"] = not args["preserveUserData"]
        with self.assertRaises(FabricError) as validation:
            await value.validate("install", altered, result["state"])
        self.assertEqual(validation.exception.code, "packages.validation-failed")
        forged_state = dict(result["state"])
        forged_state["status"] = "failed"
        with self.assertRaises(FabricError) as rollback:
            await value.rollback("install", forged_state, result["inventoryRevision"])
        self.assertEqual(rollback.exception.code, "packages.rollback-state-invalid")

    async def test_running_and_superseded_operations_cannot_be_rolled_back(self):
        adapter = FakeExecutionAdapter(pause_at="stage-payload")
        value = provider(adapter=adapter)
        args = arguments(value.engine, "software.curated.neovim", request_id="request.rollback.running")
        plan = await value.preflight("install", args, principal())
        task = asyncio.create_task(value.apply("install", args, plan["inventoryRevision"]))
        await asyncio.wait_for(adapter.entered.wait(), 1)
        with self.assertRaises(FabricError) as running:
            await value.engine.rollback(plan["operationId"], inventory_revision(value.engine._inventory))
        self.assertEqual(running.exception.code, "packages.rollback-invalid")
        value.engine.cancel(plan["operationId"])
        adapter.release.set()
        await task

        value = provider()
        install_args = arguments(value.engine, "software.curated.neovim", request_id="request.rollback.first")
        install_plan = await value.preflight("install", install_args, principal())
        installed_result = await value.apply("install", install_args, install_plan["inventoryRevision"])
        remove_args = arguments(value.engine, "software.curated.neovim", request_id="request.rollback.second")
        remove_plan = await value.preflight("remove", remove_args, principal())
        await value.apply("remove", remove_args, remove_plan["inventoryRevision"])
        with self.assertRaises(FabricError) as superseded:
            await value.engine.rollback(installed_result["operationId"], inventory_revision(value.engine._inventory))
        self.assertEqual(superseded.exception.code, "packages.rollback-superseded")

    async def test_recomputed_nested_journal_tamper_and_nonfinite_json_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "packages.json"
            value = provider(state_path=state)
            args = arguments(value.engine, "software.curated.neovim", request_id="request.journal.tamper")
            plan = await value.preflight("install", args, principal())
            await value.apply("install", args, plan["inventoryRevision"])
            document = json.loads(state.read_text(encoding="utf-8"))
            operation = document["operations"][0]
            operation["plan"]["summary"] = "attacker-rewritten-plan"
            operation["plan"]["planRevision"] = revision({**operation["plan"], "planRevision": "sha256." + "0" * 64})
            operation["revision"] = PackageOperationEngine._operation_revision(operation)
            state.write_text(json.dumps(document), encoding="utf-8")
            with self.assertRaises(FabricError) as tampered:
                PackageOperationEngine(catalog(), [], state_path=state)
            self.assertEqual(tampered.exception.code, "packages.state-corrupt")

            state.write_text('{"schemaVersion":"v0","catalogRevision":NaN,"inventory":[],"operations":[]}', encoding="utf-8")
            with self.assertRaises(FabricError) as nonfinite:
                PackageOperationEngine(catalog(), [], state_path=state)
            self.assertEqual(nonfinite.exception.code, "packages.state-corrupt")

    async def test_two_engine_instances_use_durable_compare_and_swap(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "packages.json"
            initial = provider(state_path=state)
            args = arguments(initial.engine, "software.curated.neovim", request_id="request.cas.seed")
            plan = await initial.preflight("install", args, principal())
            await initial.apply("install", args, plan["inventoryRevision"])

            first_catalog = catalog()
            second_catalog = catalog()
            first = PackageProvider(first_catalog, PackageOperationEngine(first_catalog, [], state_path=state))
            second = PackageProvider(second_catalog, PackageOperationEngine(second_catalog, [], state_path=state))
            first_args = arguments(first.engine, "software.curated.neovim", request_id="request.cas.first")
            second_args = arguments(second.engine, "software.curated.neovim", request_id="request.cas.second")
            first_plan = await first.preflight("remove", first_args, principal())
            await first.apply("remove", first_args, first_plan["inventoryRevision"])
            with self.assertRaises(FabricError) as stale_writer:
                await second.apply("remove", second_args, second_args["expectedInventoryRevision"])
            self.assertEqual(stale_writer.exception.code, "packages.state-concurrent")

    def test_process_lock_contention_fails_fast(self):
        if os.name != "posix":
            self.skipTest("POSIX advisory locks are the production path")
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "packages.json"
            descriptor = _acquire_state_lock(state)
            try:
                with self.assertRaises(FabricError) as busy:
                    _acquire_state_lock(state)
                self.assertEqual(busy.exception.code, "packages.state-busy")
                self.assertTrue(busy.exception.retryable)
            finally:
                _release_state_lock(descriptor)

    def test_inventory_rejects_duplicate_resources_broad_paths_and_unbounded_fields(self):
        first = installed()
        duplicate = copy.deepcopy(first)
        duplicate["id"] = "installed.software.duplicate"
        with self.assertRaises(FabricError):
            PackageOperationEngine(catalog(), [first, duplicate])
        for path in ("/", "/home/test//unsafe", "/home/test/control\npath"):
            unsafe = installed()
            unsafe["configPaths"] = [path]
            with self.subTest(path=path), self.assertRaises(FabricError):
                PackageOperationEngine(catalog(), [unsafe])
        oversized = installed()
        oversized["installedVersion"] = "x" * 101
        with self.assertRaises(FabricError):
            PackageOperationEngine(catalog(), [oversized])


if __name__ == "__main__":
    unittest.main()
