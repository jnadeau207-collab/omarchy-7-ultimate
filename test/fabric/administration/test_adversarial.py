from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from helper import BOOT_ID, START_TICKS, principal, resource_cases, runner_outputs

from omarchy_fabric.models import FabricError
from omarchy_fabric.providers._probe import ProbeOutput
from omarchy_fabric.providers.account import provider as account
from omarchy_fabric.providers.device import provider as device
from omarchy_fabric.providers.firewall import provider as firewall
from omarchy_fabric.providers.printer import provider as printer
from omarchy_fabric.providers.process import provider as process
from omarchy_fabric.providers.schedule import provider as schedule
from omarchy_fabric.providers.service import provider as service
from omarchy_fabric.providers.storage import provider as storage

class IdentityAndInjectionTests(unittest.IsolatedAsyncioTestCase):
    async def test_process_grouping_and_pid_reuse_guard_use_start_identity(self) -> None:
        resources = process.parse_processes(runner_outputs()[str(process.PROCESS_COMMAND.argv)], boot_id=BOOT_ID, start_ticks_by_pid=START_TICKS)
        recycled = process.parse_processes(
            runner_outputs()[str(process.PROCESS_COMMAND.argv)],
            boot_id=BOOT_ID,
            start_ticks_by_pid={**START_TICKS, resources[0]["pid"]: START_TICKS[resources[0]["pid"]] + 1},
        )
        self.assertNotEqual(resources[0]["id"], recycled[0]["id"])
        groups = process.group_processes(resources)
        self.assertEqual(sum(group["count"] for group in groups), len(resources))
        process.assert_pid_identity(resources[0], resources[0]["state"]["startToken"])
        with self.assertRaises(ValueError):
            process.assert_pid_identity(resources[0], "0" * 16)
        case = next(candidate for candidate in resource_cases() if candidate.module is process)
        provider = process.build_fake_provider([copy.deepcopy(case.resource)])
        with self.assertRaises(FabricError) as reused:
            await provider.preflight(process.OPERATION_ACTION, {**case.arguments, "expectedStartToken": "0" * 16}, principal())
        self.assertEqual(reused.exception.code, "process.precondition-failed")
        self.assertEqual(provider.backend.write_count, 0)

    async def test_process_probe_drops_identity_that_changes_between_ps_and_proc(self) -> None:
        output = runner_outputs()[str(process.PROCESS_COMMAND.argv)]
        stat_reads = {1: 0, 2: 0}

        def runner(_command):
            return ProbeOutput(output, "")

        def stat(pid: int, command: str, ticks: int) -> str:
            return f"{pid} ({command}) S " + " ".join(["0"] * 18 + [str(ticks)])

        def proc_reader(path: Path, _maximum: int) -> str:
            if path == process.BOOT_ID_PATH:
                return BOOT_ID
            pid = int(path.parent.name)
            if path.name == "status":
                command = "init" if pid == 1 else "replacement"
                uid = 0 if pid == 1 else 1000
                return f"Name:\t{command}\nUid:\t{uid}\t{uid}\t{uid}\t{uid}\n"
            stat_reads[pid] += 1
            if pid == 1:
                return stat(pid, "init", START_TICKS[pid])
            return stat(pid, "worker" if stat_reads[pid] == 1 else "replacement", START_TICKS[pid] + stat_reads[pid] - 1)

        result = await process.build_provider(runner=runner, proc_reader=proc_reader).read("inspect", {})
        self.assertTrue(result["availability"]["read"])
        self.assertEqual([item["pid"] for item in result["resources"]], [1])
        self.assertEqual(result["resources"][0]["observedCount"], 2)
        self.assertTrue(result["resources"][0]["inventoryTruncated"])

    async def test_storage_destructive_plans_require_exact_confirmation_and_never_execute(self) -> None:
        resource = storage.parse_storage(runner_outputs()[str(storage.STORAGE_COMMAND.argv)])[1]
        provider = storage.build_fake_provider([copy.deepcopy(resource)])
        arguments = {"resourceId": resource["id"], "action": "format", "filesystem": "ext4", "confirmation": None}
        with self.assertRaises(FabricError) as missing:
            await provider.preflight(storage.OPERATION_ACTION, arguments, principal())
        self.assertEqual(missing.exception.code, "storage.precondition-failed")
        confirmed = {**arguments, "confirmation": storage.destructive_confirmation(resource["id"])}
        plan = await provider.preflight(storage.OPERATION_ACTION, confirmed, principal())
        self.assertEqual(plan["risk"], "destructive")
        self.assertEqual(plan["effects"], ["mutating", "privileged", "destructive"])
        self.assertNotIn(confirmed["confirmation"], str(plan["proposedState"]))
        self.assertEqual(provider.backend.write_count, 0)

    async def test_argument_injection_is_rejected_before_any_backend_write(self) -> None:
        actor = principal()
        cases = resource_cases()
        for case in cases:
            provider = case.module.build_fake_provider([copy.deepcopy(case.resource)])
            injected = {**case.arguments, "unexpected": "; rm -rf /"}
            with self.subTest(domain=case.module.DOMAIN):
                with self.assertRaises(FabricError) as invalid:
                    await provider.preflight(case.module.OPERATION_ACTION, injected, actor)
                self.assertEqual(invalid.exception.code, f"{case.module.DOMAIN}.contract-invalid")
                self.assertEqual(provider.backend.write_count, 0)

    async def test_firewall_source_is_canonical_and_shell_tokens_are_impossible(self) -> None:
        case = next(candidate for candidate in resource_cases() if candidate.module is firewall)
        provider = firewall.build_fake_provider([copy.deepcopy(case.resource)])
        plan = await provider.preflight(firewall.OPERATION_ACTION, case.arguments, principal())
        self.assertEqual(plan["normalizedArguments"]["source"], "192.0.2.0/24")
        for source in ("192.0.2.1;id", "$(id)", "example.com", "10.0.0.1/999"):
            with self.subTest(source=source), self.assertRaises(FabricError):
                await provider.preflight(firewall.OPERATION_ACTION, {**case.arguments, "source": source}, principal())

    async def test_root_account_and_credential_bearing_printer_uri_fail_closed(self) -> None:
        root = account.parse_accounts(runner_outputs()[str(account.ACCOUNT_COMMAND.argv)])[0]
        provider = account.build_fake_provider([root])
        with self.assertRaises(FabricError) as immutable:
            await provider.preflight(account.OPERATION_ACTION, {"resourceId": root["id"], "action": "demote"}, principal())
        self.assertEqual(immutable.exception.code, "account.precondition-failed")
        with self.assertRaises(ValueError):
            printer.parse_printers("device for evil: ipp://user:password@printer.example/ipp\n")

class ParserBoundaryTests(unittest.TestCase):
    def test_duplicate_and_malformed_inventories_are_rejected(self) -> None:
        outputs = runner_outputs()
        with self.assertRaises(ValueError):
            process.parse_processes(
                outputs[str(process.PROCESS_COMMAND.argv)] + outputs[str(process.PROCESS_COMMAND.argv)].splitlines()[0] + "\n",
                boot_id=BOOT_ID,
                start_ticks_by_pid=START_TICKS,
            )
        with self.assertRaises(ValueError):
            account.parse_accounts("one:x:1000:1000::/home/one:/bin/bash\ntwo:x:1000:1000::/home/two:/bin/bash\n")
        with self.assertRaises(ValueError):
            firewall.parse_firewall("  interfaces: eth0\n")
        with self.assertRaises(ValueError):
            storage.parse_storage('{"blockdevices":[],"blockdevices":[]}')

    def test_all_real_commands_are_fixed_absolute_argv_without_request_data(self) -> None:
        for case in resource_cases():
            command_name = {
                "process": "PROCESS_COMMAND",
                "device": "DEVICE_COMMAND",
                "storage": "STORAGE_COMMAND",
                "printer": "PRINTER_COMMAND",
                "account": "ACCOUNT_COMMAND",
                "firewall": "FIREWALL_COMMAND",
                "service": "SERVICE_COMMAND",
                "schedule": "SCHEDULE_COMMAND",
            }[case.module.DOMAIN]
            command = getattr(case.module, command_name)
            with self.subTest(domain=case.module.DOMAIN):
                self.assertTrue(command.executable.startswith("/usr/bin/"))
                self.assertNotIn(case.resource["id"], command.argv)
                self.assertTrue(all(";" not in argument and "$" not in argument for argument in command.argv))

    def test_large_inventories_publish_explicit_bounded_selection_truth(self) -> None:
        process_text = "\n".join(f"{pid} {1000 if pid % 2 else 0} 1.0 2.0 4096 proc{pid} /group/{pid % 4}" for pid in range(1, 81))
        processes = process.parse_processes(process_text, boot_id=BOOT_ID, start_ticks_by_pid={pid: pid * 10 for pid in range(1, 81)})
        self.assertEqual(len(processes), 64)
        self.assertEqual(processes[0]["observedCount"], 80)
        self.assertTrue(all(item["inventoryTruncated"] for item in processes))

        device_text = "\n".join(
            json.dumps({"DEVPATH": f"/devices/pci/{index}", "SUBSYSTEM": "pci", "ID_MODEL": f"Device {index}", "ID_BUS": "pci"})
            for index in range(80)
        )
        devices = device.parse_devices(device_text)
        self.assertEqual(len(devices), 64)
        self.assertEqual(devices[0]["observedCount"], 80)
        self.assertTrue(all(item["inventoryTruncated"] for item in devices))

        service_text = "\n".join(f"test{index}.service loaded inactive dead Test service {index}" for index in range(80))
        services = service.parse_services(service_text)
        self.assertEqual(len(services), 64)
        self.assertEqual(services[0]["observedCount"], 80)
        self.assertTrue(all(item["inventoryTruncated"] for item in services))

    def test_swap_and_systemd_escaped_identities_are_modeled_without_coercion(self) -> None:
        swap = storage.parse_storage(
            '{"blockdevices":[{"name":"zram0","path":"/dev/zram0","type":"disk","size":4096,"rm":false,"ro":false,"fstype":"swap","uuid":"swap-a","mountpoints":["[SWAP]"]}]}'
        )[0]
        self.assertTrue(swap["state"]["activeSwap"])
        self.assertFalse(swap["state"]["mounted"])
        self.assertIsNone(swap["state"]["mountPoint"])
        escaped_service = service.parse_services(r"systemd-fsck@dev-disk-by\x2duuid.service loaded active exited File check" + "\n")[0]
        escaped_timer = schedule.parse_schedules(json.dumps([{"unit": r"backup@home\x2djesse.timer", "activates": r"backup@home\x2djesse.service", "next": 1, "last": 0}]))[0]
        self.assertIn(r"\x2d", escaped_service["unit"])
        self.assertIn(r"\x2d", escaped_timer["unit"])

    def test_unproven_inventory_truth_stays_unknown_and_unsafe_storage_paths_fail(self) -> None:
        outputs = runner_outputs()
        device_row = json.loads(outputs[str(device.DEVICE_COMMAND.argv)])
        device_row.pop("AUTHORIZED")
        self.assertIsNone(device.parse_devices(json.dumps(device_row))[0]["state"]["authorized"])
        self.assertIsNone(printer.parse_printers(outputs[str(printer.PRINTER_COMMAND.argv)])[0]["state"]["accepting"])
        self.assertEqual(account.parse_accounts(outputs[str(account.ACCOUNT_COMMAND.argv)])[1]["state"]["role"], "unknown")
        self.assertTrue(firewall.parse_firewall("")[0]["state"]["enabled"])

        unsafe = {"blockdevices": [{"name": "escape", "path": "/dev/../etc/shadow", "type": "part", "size": 1, "rm": False, "ro": False, "fstype": None, "uuid": None, "mountpoints": [None]}]}
        with self.assertRaises(ValueError):
            storage.parse_storage(json.dumps(unsafe))
        unsafe["blockdevices"][0]["path"] = "/dev/sdz"
        unsafe["blockdevices"][0]["rm"] = "0"
        with self.assertRaises(ValueError):
            storage.parse_storage(json.dumps(unsafe))

    def test_stable_resource_ids_still_revision_bind_mutable_identity_metadata(self) -> None:
        original_process = process.parse_processes("2 1000 13.7 4.8 131072 worker /user.slice/app.scope\n", boot_id=BOOT_ID, start_ticks_by_pid={2: 200})[0]
        changed_process = process.parse_processes("2 1001 9.0 2.5 65536 replacement /user.slice/other.scope\n", boot_id=BOOT_ID, start_ticks_by_pid={2: 200})[0]
        self.assertEqual(original_process["id"], changed_process["id"])
        self.assertNotEqual(original_process["state"]["identityRevision"], changed_process["state"]["identityRevision"])

        original_printer = printer.parse_printers("device for office: ipps://one.example/ipp\n")[0]
        changed_printer = printer.parse_printers("device for office: ipps://two.example/ipp\n")[0]
        self.assertEqual(original_printer["id"], changed_printer["id"])
        self.assertNotEqual(original_printer["state"]["configurationRevision"], changed_printer["state"]["configurationRevision"])

        original_timer = schedule.parse_schedules(json.dumps([{"unit": "backup.timer", "activates": "backup.service", "next": 1, "last": 0}]))[0]
        changed_timer = schedule.parse_schedules(json.dumps([{"unit": "backup.timer", "activates": "other.service", "next": 1, "last": 0}]))[0]
        self.assertEqual(original_timer["id"], changed_timer["id"])
        self.assertNotEqual(original_timer["state"]["definitionRevision"], changed_timer["state"]["definitionRevision"])

        template = {"name": "sda1", "path": "/dev/sda1", "type": "part", "size": 4096, "rm": False, "ro": False, "uuid": None, "mountpoints": [None]}
        original_storage = storage.parse_storage(json.dumps({"blockdevices": [{**template, "fstype": "ext4"}]}))[0]
        changed_storage = storage.parse_storage(json.dumps({"blockdevices": [{**template, "fstype": "xfs"}]}))[0]
        self.assertEqual(original_storage["id"], changed_storage["id"])
        self.assertNotEqual(original_storage["state"]["observedRevision"], changed_storage["state"]["observedRevision"])

if __name__ == "__main__":
    unittest.main()
