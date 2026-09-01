from __future__ import annotations

import copy
import json
import subprocess
import unittest

from helper import principal, resource_cases

from omarchy_fabric.models import FabricError, FixedArgvCommand
from omarchy_fabric.provider_registry import ProviderRegistry, ensure_async_provider_hooks
from omarchy_fabric.providers.backup import provider as backup
from omarchy_fabric.providers.diagnostics import provider as diagnostics
from omarchy_fabric.providers.recovery import provider as recovery
from omarchy_fabric.providers.update import provider as update
from omarchy_fabric.providers._probe import ProbeOutput

class RecoveryAdmissionTests(unittest.IsolatedAsyncioTestCase):
    async def test_all_recovery_leaves_admit_and_fake_lifecycle_is_exact(self) -> None:
        registry = ProviderRegistry(clock=lambda: 84.0)
        actor = principal()
        for case in resource_cases():
            provider = case.module.build_fake_provider([copy.deepcopy(case.resource)])
            ensure_async_provider_hooks(provider)
            self.assertEqual(registry.register(provider).state, "available")
            read = await registry.read(case.module.PROVIDER_ID, "inspect", {})
            self.assertEqual(read["observedAt"], 84.0)
            preflight = await registry.preflight(case.module.PROVIDER_ID, case.module.OPERATION_ACTION, case.arguments, actor)
            with self.subTest(domain=case.module.DOMAIN):
                self.assertTrue(preflight["preflight"]["changed"])
                self.assertEqual(provider.backend.write_count, 0)
                applied = await provider.apply(case.module.OPERATION_ACTION, case.arguments, preflight["preflight"]["stateRevision"])
                self.assertTrue(applied["changed"])
                validated = await provider.validate(case.module.OPERATION_ACTION, case.arguments, applied["state"])
                self.assertFalse(validated["changed"])
                rolled_back = await provider.rollback(case.module.OPERATION_ACTION, preflight["preflight"]["currentState"], applied["stateRevision"])
                self.assertTrue(rolled_back["changed"])
        self.assertEqual(registry.provider_count, 4)

    async def test_real_update_recovery_backup_and_diagnostics_use_only_fixed_probes(self) -> None:
        outputs = {
            update.UPDATE_COMMAND.argv: "linux 6.1 -> 6.2\n",
            recovery.RECOVERY_COMMAND.argv: json.dumps({"data": [{"number": 1, "date": "2026-08-27T00:00:00Z", "description": "checkpoint"}]}),
            backup.BACKUP_COMMAND.argv: json.dumps([{"id": "abcdef1234567890", "time": "2026-08-27T00:00:00Z", "paths": ["/home/jesse"]}]),
            diagnostics.COMMANDS["service-failures"].argv: "",
            diagnostics.COMMANDS["journal-usage"].argv: "Archived and active journals take up 12.0M in the file system.\n",
            diagnostics.COMMANDS["filesystem-usage"].argv: "Filesystem Use% Mounted on\n/dev/sda1 40% /\n",
        }
        calls: list[tuple[str, ...]] = []

        def runner(command: FixedArgvCommand) -> ProbeOutput:
            calls.append(command.argv)
            return ProbeOutput(outputs[command.argv], "")

        cases = {case.module: case for case in resource_cases()}
        for module in (update, recovery, backup, diagnostics):
            provider = module.build_provider(runner=runner, **({"home_root": "/home/jesse"} if module is backup else {}))
            value = await provider.read("inspect", {})
            with self.subTest(domain=module.DOMAIN):
                self.assertTrue(value["availability"]["read"])
                self.assertFalse(value["availability"]["operation"])
                self.assertTrue(value["resources"])
                with self.assertRaises(FabricError) as unavailable:
                    await provider.preflight(module.OPERATION_ACTION, cases[module].arguments, principal())
                self.assertEqual(unavailable.exception.code, f"{module.DOMAIN}.operation-unavailable")
        self.assertTrue(all(argv[0].startswith("/usr/bin/") for argv in calls))

    async def test_individual_diagnostic_probe_failure_is_structured_unavailable_check(self) -> None:
        def runner(command: FixedArgvCommand) -> ProbeOutput:
            if command == diagnostics.COMMANDS["journal-usage"]:
                raise subprocess.CalledProcessError(1, command.argv, "", "private stderr")
            output = "" if command == diagnostics.COMMANDS["service-failures"] else "Filesystem Use% Mounted on\n/dev/sda1 40% /\n"
            return ProbeOutput(output, "")

        value = await diagnostics.build_provider(runner=runner).read("inspect", {})
        checks = {check["id"]: check for check in value["resources"][0]["state"]["checks"]}
        self.assertEqual(checks["journal-usage"]["status"], "unavailable")
        self.assertEqual(checks["journal-usage"]["code"], "provider.probe-failed")
        self.assertNotIn("private stderr", str(value))

    async def test_checkupdates_exit_two_is_exactly_no_updates(self) -> None:
        def no_updates(command: FixedArgvCommand) -> ProbeOutput:
            raise subprocess.CalledProcessError(2, command.argv, "", "")

        value = await update.build_provider(runner=no_updates).read("inspect", {})
        self.assertTrue(value["availability"]["read"])
        self.assertEqual(value["resources"][0]["state"]["availableCount"], 0)
        self.assertEqual(value["resources"][0]["state"]["phase"], "idle")

        def noisy_failure(command: FixedArgvCommand) -> ProbeOutput:
            raise subprocess.CalledProcessError(2, command.argv, "", "repository database failed")

        failed = await update.build_provider(runner=noisy_failure).read("inspect", {})
        self.assertFalse(failed["availability"]["read"])
        self.assertEqual(failed["availability"]["reason"]["code"], "provider.probe-failed")

class RecoveryProviderFailureTests(unittest.IsolatedAsyncioTestCase):
    async def test_stale_state_duplicate_resources_and_closed_arguments_fail(self) -> None:
        actor = principal()
        for case in resource_cases():
            provider = case.module.build_fake_provider([copy.deepcopy(case.resource)])
            preflight = await provider.preflight(case.module.OPERATION_ACTION, case.arguments, actor)
            await provider.backend.force_state(case.resource["id"], copy.deepcopy(case.resource["state"]))
            drift = copy.deepcopy(case.resource["state"])
            if "pendingPlan" in drift:
                drift["pendingPlan"] = preflight["proposedState"]["value"]["pendingPlan"]
            await provider.backend.force_state(case.resource["id"], drift)
            with self.subTest(domain=case.module.DOMAIN):
                with self.assertRaises(FabricError) as stale:
                    await provider.apply(case.module.OPERATION_ACTION, case.arguments, preflight["stateRevision"])
                self.assertEqual(stale.exception.code, f"{case.module.DOMAIN}.state-stale")
                duplicate = case.module.build_fake_provider([copy.deepcopy(case.resource), copy.deepcopy(case.resource)])
                with self.assertRaises(FabricError) as invalid:
                    await duplicate.read("inspect", {})
                self.assertEqual(invalid.exception.code, f"{case.module.DOMAIN}.backend-invalid")
                with self.assertRaises(FabricError) as closed:
                    await provider.preflight(case.module.OPERATION_ACTION, {**case.arguments, "shell": "$(id)"}, actor)
                self.assertEqual(closed.exception.code, f"{case.module.DOMAIN}.contract-invalid")

    async def test_pending_plans_are_idempotent_but_cannot_be_overwritten(self) -> None:
        actor = principal()
        cases = {case.module.DOMAIN: case for case in resource_cases()}
        replacements = {
            "update": {"resourceId": update.RESOURCE_ID, "mode": "download", "createCheckpoint": False},
            "backup": {"resourceId": backup.RESOURCE_ID, "action": "snapshot", "scope": "home", "snapshotId": None, "relativePath": None, "retention": dict(backup.DEFAULT_RETENTION)},
            "diagnostics": {"resourceId": diagnostics.RESOURCE_ID, "sources": ["service-failures"], "maximumBytes": 4096},
        }
        for domain, replacement in replacements.items():
            case = cases[domain]
            provider = case.module.build_fake_provider([copy.deepcopy(case.resource)])
            preflight = await provider.preflight(case.module.OPERATION_ACTION, case.arguments, actor)
            applied = await provider.apply(case.module.OPERATION_ACTION, case.arguments, preflight["stateRevision"])
            repeated = await provider.preflight(case.module.OPERATION_ACTION, case.arguments, actor)
            with self.subTest(domain=domain):
                self.assertFalse(repeated["changed"])
                with self.assertRaises(FabricError) as conflict:
                    await provider.preflight(case.module.OPERATION_ACTION, replacement, actor)
                self.assertEqual(conflict.exception.code, f"{domain}.precondition-failed")
                self.assertEqual((await provider.read("inspect", {}))["resources"][0]["state"], applied["state"]["value"])

if __name__ == "__main__":
    unittest.main()
