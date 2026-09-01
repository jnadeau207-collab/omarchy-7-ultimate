from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[3]
FABRIC_ROOT = ROOT / "default" / "fabric"
if str(FABRIC_ROOT) not in sys.path:
    sys.path.insert(0, str(FABRIC_ROOT))

import json

from omarchy_fabric.operations.coordinator import OperationCoordinator
from omarchy_fabric.operations.device_plane import (
    PRIVILEGED_DEVICE_INTENTS,
    HermeticDeviceExecutor,
    device_definitions,
    device_intents,
)
from omarchy_fabric.operations.executor import IntentCatalog
from omarchy_fabric.operations.package_plane import CoordinatedRegistryGateway
from omarchy_fabric.operations.routing_executor import PrivilegeRoutingExecutor
from omarchy_fabric.operations.store import OperationStore
from omarchy_fabric.provider_registry import ProviderRegistry
from omarchy_fabric.providers.device.provider import build_fake_provider, parse_devices
from omarchy_fabric.security.approval import ApprovalAuthority
from omarchy_fabric.security.grants import CapabilityGrant, GrantPersistence
from omarchy_fabric.security.principal import EndpointAdmission, PrincipalKind, SessionBindingStore
from omarchy_fabric.security.system_executor import validate_system_executor_request
from omarchy_fabric.security.types import RiskLevel


class Clock:
    def __init__(self) -> None:
        self.now = datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc)

    def __call__(self) -> datetime:
        return self.now


class DevicePlaneTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.clock = Clock()
        self.sessions = SessionBindingStore(clock=self.clock)
        self.task, _ = self.sessions.issue(
            1000,
            EndpointAdmission("fabric.task-rpc", PrincipalKind.TASK, task_id="task.device"),
            lifetime=timedelta(hours=1),
        )
        self.resource = parse_devices(
            json.dumps(
                {
                    "DEVPATH": "/devices/pci0/usb1",
                    "SUBSYSTEM": "usb",
                    "DEVNAME": "/dev/bus/usb/001/001",
                    "ID_MODEL": "Test Device",
                    "ID_BUS": "usb",
                    "AUTHORIZED": "1",
                    "DRIVER": "usb",
                }
            )
            + "\n"
        )[0]
        self.arguments = {"resourceId": self.resource["id"], "authorized": False}
        self.devices = build_fake_provider([self.resource])
        self.registry = ProviderRegistry(clock=lambda: 1.0)
        self.registry.register(self.devices)
        self.temp = TemporaryDirectory()
        self.store = OperationStore(Path(self.temp.name) / "operations.db", clock=self.clock)
        self.store.open()
        self.intents = IntentCatalog(device_intents())
        self.executor = HermeticDeviceExecutor(self.devices, self.intents)
        self.approvals = ApprovalAuthority(clock=self.clock)
        self.coordinator = OperationCoordinator(
            store=self.store,
            gateway=CoordinatedRegistryGateway(self.registry),
            definitions=device_definitions(),
            intents=self.intents,
            executor=PrivilegeRoutingExecutor(
                SimpleNamespace(available=True),
                self.executor,
                PRIVILEGED_DEVICE_INTENTS,
            ),
            session_resolver=self.sessions.require_active,
            policy_revision=lambda: "policy.revision.device-v0",
            clock=self.clock,
        )

    async def asyncTearDown(self) -> None:
        self.store.close()
        self.temp.cleanup()

    def _grant(self, operation_id: str) -> CapabilityGrant:
        request = self.coordinator.approval_request(self.task, operation_id)
        return CapabilityGrant(
            grant_id="grant.device.one",
            principal_id=self.task.principal_id,
            principal_kind=PrincipalKind.TASK,
            capability=request.capability,
            resource=request.resource,
            issued_at=self.clock.now - timedelta(seconds=1),
            expires_at=self.clock.now + timedelta(minutes=5),
            maximum_risk=RiskLevel.CONSEQUENTIAL,
            persistence=GrantPersistence.SESSION,
            task_id="task.device",
        )

    async def test_device_authorization_runs_through_coordinator(self) -> None:
        planned = await self.coordinator.preflight(
            self.task,
            provider_id="device.provider",
            action="authorization.plan",
            arguments=self.arguments,
            idempotency_key="device.authorize.one",
        )
        approval = self.approvals.issue(
            self.task,
            self.coordinator.approval_request(self.task, planned["operationId"]),
            expires_at=self.clock.now + timedelta(minutes=5),
        )
        result = await self.coordinator.start(
            self.task,
            planned["operationId"],
            approval_id=approval.approval_id,
            approvals=self.approvals,
            grants=(self._grant(planned["operationId"]),),
        )
        self.assertEqual(result["status"], "succeeded", result)
        self.assertEqual(self.executor.system_requests[0]["action"], "device.authorize")
        validate_system_executor_request(self.executor.system_requests[0])
        observed = await self.devices.backend.snapshot()
        device = next(item for item in observed.resources if item["id"] == self.resource["id"])
        self.assertEqual(device["state"]["pendingAuthorization"], False)

    def test_device_authorize_is_routed_off_the_session_executor(self) -> None:
        session = SimpleNamespace(available=True)
        privileged = SimpleNamespace(available=True)
        router = PrivilegeRoutingExecutor(session, privileged, PRIVILEGED_DEVICE_INTENTS)
        intent = self.intents.build(
            "device.authorize",
            {
                "resourceId": self.resource["id"],
                "device_id": self.resource["id"],
                "authorized": False,
            },
        )
        self.assertIs(router._choose(intent), privileged)


if __name__ == "__main__":
    unittest.main()
