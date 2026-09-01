from __future__ import annotations

import copy
import subprocess
import tempfile
import unittest
from pathlib import Path

from helper import BOOT_ID, START_TICKS, principal, resource_cases, runner_outputs

from omarchy_fabric.models import FabricError, FixedArgvCommand
from omarchy_fabric.provider_registry import ProviderRegistry, ensure_async_provider_hooks
from omarchy_fabric.providers._probe import ProbeOutput

class AdministrationAdmissionTests(unittest.IsolatedAsyncioTestCase):
    async def test_all_administration_leaves_admit_and_read_through_central_registry(self) -> None:
        registry = ProviderRegistry(clock=lambda: 42.0)
        outputs = runner_outputs()
        calls: list[FixedArgvCommand] = []

        def runner(command: FixedArgvCommand) -> ProbeOutput:
            calls.append(command)
            return ProbeOutput(outputs[str(command.argv)], "")

        def proc_reader(path: Path, _maximum: int) -> str:
            if path == Path("/proc/sys/kernel/random/boot_id"):
                return BOOT_ID
            pid = int(path.parent.name)
            command = "init" if pid == 1 else "worker"
            uid = 0 if pid == 1 else 1000
            if path.name == "status":
                return f"Name:\t{command}\nUid:\t{uid}\t{uid}\t{uid}\t{uid}\n"
            return f"{pid} ({command}) S " + " ".join(["0"] * 18 + [str(START_TICKS[pid])])

        for case in resource_cases():
            provider = case.module.build_provider(runner=runner, **({"proc_reader": proc_reader} if case.module.DOMAIN == "process" else {}))
            ensure_async_provider_hooks(provider)
            admission = registry.register(provider)
            self.assertEqual(admission.state, "available")
            result = await registry.read(case.module.PROVIDER_ID, "inspect", {})
            self.assertEqual(result["observedAt"], 42.0)
            self.assertEqual(result["value"]["availability"]["read"], True)
            self.assertEqual(result["value"]["availability"]["operation"], False)
            self.assertEqual(result["value"]["availability"]["reason"]["code"], f"{case.module.DOMAIN}.operation-read-only")
            self.assertGreaterEqual(len(result["value"]["resources"]), 1)
            with self.assertRaises(FabricError) as unavailable:
                await provider.preflight(case.module.OPERATION_ACTION, case.arguments, principal())
            self.assertEqual(unavailable.exception.code, f"{case.module.DOMAIN}.operation-unavailable")
        self.assertEqual(registry.provider_count, 8)
        self.assertTrue(all(call.argv[0].startswith("/") for call in calls))

    async def test_missing_real_dependencies_are_honest_unavailable_results(self) -> None:
        def missing(command: FixedArgvCommand) -> ProbeOutput:
            raise FileNotFoundError(command.executable)

        for case in resource_cases():
            provider = case.module.build_provider(runner=missing)
            result = await provider.read("inspect", {})
            with self.subTest(domain=case.module.DOMAIN):
                self.assertFalse(result["availability"]["read"])
                self.assertFalse(result["availability"]["operation"])
                self.assertEqual(result["availability"]["reason"]["code"], "provider.dependency-missing")
                self.assertEqual(result["resources"], [])

    async def test_lpstat_exact_empty_destination_sentinel_is_zero_printers(self) -> None:
        from omarchy_fabric.providers.printer import provider as printer

        def empty(command: FixedArgvCommand) -> ProbeOutput:
            raise subprocess.CalledProcessError(1, command.argv, "", "lpstat: No destinations added.\n")

        result = await printer.build_provider(runner=empty).read("inspect", {})
        self.assertTrue(result["availability"]["read"])
        self.assertEqual(result["resources"], [])

        def failed(command: FixedArgvCommand) -> ProbeOutput:
            raise subprocess.CalledProcessError(1, command.argv, "", "lpstat: Scheduler is not running.\n")

        failed_result = await printer.build_provider(runner=failed).read("inspect", {})
        self.assertFalse(failed_result["availability"]["read"])

class AdministrationFakeLifecycleTests(unittest.IsolatedAsyncioTestCase):
    async def test_every_fake_crosses_preflight_apply_validate_noop_and_rollback(self) -> None:
        actor = principal()
        for case in resource_cases():
            provider = case.module.build_fake_provider([copy.deepcopy(case.resource)])
            preflight = await provider.preflight(case.module.OPERATION_ACTION, case.arguments, actor)
            with self.subTest(domain=case.module.DOMAIN):
                self.assertTrue(preflight["changed"])
                self.assertEqual(provider.backend.write_count, 0)
                applied = await provider.apply(case.module.OPERATION_ACTION, case.arguments, preflight["stateRevision"])
                self.assertTrue(applied["changed"])
                self.assertEqual(provider.backend.write_count, 1)
                validated = await provider.validate(case.module.OPERATION_ACTION, case.arguments, applied["state"])
                self.assertFalse(validated["changed"])
                no_op = await provider.apply(case.module.OPERATION_ACTION, case.arguments, applied["stateRevision"])
                self.assertFalse(no_op["changed"])
                self.assertEqual(provider.backend.write_count, 1)
                rolled_back = await provider.rollback(case.module.OPERATION_ACTION, preflight["currentState"], applied["stateRevision"])
                self.assertTrue(rolled_back["changed"])
                self.assertEqual(rolled_back["state"], preflight["currentState"])

    async def test_restart_persistence_and_stale_revision_are_fail_closed(self) -> None:
        actor = principal()
        with tempfile.TemporaryDirectory() as directory:
            for case in resource_cases():
                path = Path(directory) / f"{case.module.DOMAIN}.json"
                provider = case.module.build_fake_provider([copy.deepcopy(case.resource)], state_path=path)
                preflight = await provider.preflight(case.module.OPERATION_ACTION, case.arguments, actor)
                applied = await provider.apply(case.module.OPERATION_ACTION, case.arguments, preflight["stateRevision"])
                restarted = case.module.build_fake_provider([copy.deepcopy(case.resource)], state_path=path)
                inventory = await restarted.read("inspect", {})
                with self.subTest(domain=case.module.DOMAIN):
                    self.assertEqual(inventory["resources"][0]["state"], applied["state"]["value"])
                    with self.assertRaises(FabricError) as stale:
                        await restarted.apply(case.module.OPERATION_ACTION, case.arguments, preflight["stateRevision"])
                    self.assertEqual(stale.exception.code, f"{case.module.DOMAIN}.state-stale")

    async def test_duplicate_resources_backend_failures_and_corrupt_state_are_contained(self) -> None:
        actor = principal()
        with tempfile.TemporaryDirectory() as directory:
            for case in resource_cases():
                duplicate = case.module.build_fake_provider([copy.deepcopy(case.resource), copy.deepcopy(case.resource)])
                with self.subTest(domain=case.module.DOMAIN):
                    with self.assertRaises(FabricError) as invalid:
                        await duplicate.read("inspect", {})
                    self.assertEqual(invalid.exception.code, f"{case.module.DOMAIN}.backend-invalid")
                    failing = case.module.build_fake_provider([copy.deepcopy(case.resource)], fail_on=frozenset({"apply"}))
                    preflight = await failing.preflight(case.module.OPERATION_ACTION, case.arguments, actor)
                    with self.assertRaises(FabricError) as failed:
                        await failing.apply(case.module.OPERATION_ACTION, case.arguments, preflight["stateRevision"])
                    self.assertEqual(failed.exception.code, f"{case.module.DOMAIN}.fake-apply-failed")
                    path = Path(directory) / f"corrupt-{case.module.DOMAIN}.json"
                    path.write_text('{"schemaVersion":"v0","domain":"wrong","resources":[]}', encoding="utf-8")
                    with self.assertRaises(ValueError):
                        case.module.build_fake_provider([copy.deepcopy(case.resource)], state_path=path)

if __name__ == "__main__":
    unittest.main()
