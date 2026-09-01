"""Fixtures for the administration provider tranche."""

from __future__ import annotations

import copy
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Mapping

ROOT = Path(__file__).resolve().parents[3]
FABRIC = ROOT / "default" / "fabric"
if str(FABRIC) not in sys.path:
    sys.path.insert(0, str(FABRIC))

from omarchy_fabric.providers.account import provider as account
from omarchy_fabric.providers.device import provider as device
from omarchy_fabric.providers.firewall import provider as firewall
from omarchy_fabric.providers.printer import provider as printer
from omarchy_fabric.providers.process import provider as process
from omarchy_fabric.providers.schedule import provider as schedule
from omarchy_fabric.providers.service import provider as service
from omarchy_fabric.providers.storage import provider as storage
from omarchy_fabric.security.principal import EndpointPrincipal, PrincipalKind

BOOT_ID = "11111111-2222-3333-4444-555555555555"
START_TICKS = {1: 100, 2: 200}

@dataclass(frozen=True)
class Case:
    module: Any
    resource: Mapping[str, Any]
    arguments: Mapping[str, Any]

def principal() -> EndpointPrincipal:
    now = datetime(2026, 8, 27, tzinfo=timezone.utc)
    return EndpointPrincipal(
        principal_id="principal.administration-test",
        session_id="session.administration-test",
        uid=1000,
        endpoint_id="shell.administration-test",
        kind=PrincipalKind.SHELL,
        issued_at=now,
        expires_at=now + timedelta(hours=1),
    )

def runner_outputs() -> dict[str, str]:
    return {
        str(process.PROCESS_COMMAND.argv): "1 0 init /init.scope\n2 1000 worker /user.slice/app.scope\n",
        str(device.DEVICE_COMMAND.argv): json.dumps({"DEVPATH": "/devices/pci0/usb1", "SUBSYSTEM": "usb", "DEVNAME": "/dev/bus/usb/001/001", "ID_MODEL": "Test Device", "ID_BUS": "usb", "AUTHORIZED": "1", "DRIVER": "usb"}) + "\n",
        str(storage.STORAGE_COMMAND.argv): json.dumps({"blockdevices": [{"name": "sda1", "path": "/dev/sda1", "type": "part", "size": 4096, "rm": False, "ro": False, "fstype": "ext4", "uuid": "volume-a", "mountpoints": ["/"]}, {"name": "sdb1", "path": "/dev/sdb1", "type": "part", "size": 8192, "rm": True, "ro": False, "fstype": "exfat", "uuid": "volume-b", "mountpoints": [None]}]}),
        str(printer.PRINTER_COMMAND.argv): "device for office: ipps://printer.example/ipp/print\n",
        str(account.ACCOUNT_COMMAND.argv): "root:x:0:0:root:/root:/bin/bash\njesse:x:1000:1000:Jesse:/home/jesse:/bin/bash\n",
        str(firewall.FIREWALL_COMMAND.argv): "public\n  interfaces: eth0 wlan0\n",
        str(service.SERVICE_COMMAND.argv): "sshd.service loaded active running OpenSSH daemon\ncron.service loaded inactive dead Scheduler\n",
        str(schedule.SCHEDULE_COMMAND.argv): json.dumps([{"unit": "backup.timer", "activates": "backup.service", "next": 1787841991967848, "last": 1787741178650348}]),
    }

def resource_cases() -> list[Case]:
    process_resource = process.parse_processes(runner_outputs()[str(process.PROCESS_COMMAND.argv)], boot_id=BOOT_ID, start_ticks_by_pid=START_TICKS)[1]
    device_resource = device.parse_devices(runner_outputs()[str(device.DEVICE_COMMAND.argv)])[0]
    storage_resources = storage.parse_storage(runner_outputs()[str(storage.STORAGE_COMMAND.argv)])
    printer_resource = printer.parse_printers(runner_outputs()[str(printer.PRINTER_COMMAND.argv)])[0]
    account_resource = account.parse_accounts(runner_outputs()[str(account.ACCOUNT_COMMAND.argv)])[1]
    firewall_resource = firewall.parse_firewall(runner_outputs()[str(firewall.FIREWALL_COMMAND.argv)])[0]
    service_resource = service.parse_services(runner_outputs()[str(service.SERVICE_COMMAND.argv)])[0]
    schedule_resource = schedule.parse_schedules(runner_outputs()[str(schedule.SCHEDULE_COMMAND.argv)])[0]
    return [
        Case(process, process_resource, {"resourceId": process_resource["id"], "expectedStartToken": process_resource["state"]["startToken"], "signal": "term"}),
        Case(device, device_resource, {"resourceId": device_resource["id"], "authorized": False}),
        Case(storage, storage_resources[1], {"resourceId": storage_resources[1]["id"], "action": "eject", "filesystem": None, "confirmation": None}),
        Case(printer, printer_resource, {"resourceId": printer_resource["id"], "action": "pause"}),
        Case(account, account_resource, {"resourceId": account_resource["id"], "action": "promote"}),
        Case(firewall, firewall_resource, {"resourceId": firewall.RESOURCE_ID, "operation": "allow", "protocol": "tcp", "port": 443, "direction": "inbound", "source": "192.0.2.7/24"}),
        Case(service, service_resource, {"resourceId": service_resource["id"], "action": "stop"}),
        Case(schedule, schedule_resource, {"resourceId": schedule_resource["id"], "action": "run"}),
    ]

def copied_case(case: Case) -> Case:
    return Case(case.module, copy.deepcopy(case.resource), copy.deepcopy(case.arguments))
