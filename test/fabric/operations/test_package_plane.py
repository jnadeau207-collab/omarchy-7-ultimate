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

import importlib.util

_packages_helper_spec = importlib.util.spec_from_file_location(
    "packages_operation_plane_helper",
    ROOT / "test" / "fabric" / "packages" / "helper.py",
)
_packages_helper = importlib.util.module_from_spec(_packages_helper_spec)
assert _packages_helper_spec.loader is not None
_packages_helper_spec.loader.exec_module(_packages_helper)
arguments = _packages_helper.arguments
installed = _packages_helper.installed
package_provider = _packages_helper.provider

from omarchy_fabric.operations.coordinator import OperationCoordinator
from omarchy_fabric.operations.executor import IntentCatalog
from omarchy_fabric.operations.package_plane import (
    PRIVILEGED_PACKAGE_INTENTS,
    CoordinatedRegistryGateway,
    HermeticPackageExecutor,
    package_definitions,
    package_intents,
    project_package_preflight,
)
from omarchy_fabric.operations.routing_executor import PrivilegeRoutingExecutor
from omarchy_fabric.operations.store import OperationStore
from omarchy_fabric.provider_registry import ProviderRegistry
from omarchy_fabric.security.approval import ApprovalAuthority
from omarchy_fabric.security.errors import SecurityValidationError
from omarchy_fabric.security.grants import CapabilityGrant, GrantPersistence
from omarchy_fabric.security.principal import EndpointAdmission, PrincipalKind, SessionBindingStore
from omarchy_fabric.security.types import ResourceRef, RiskLevel


class Clock:
    def __init__(self) -> None:
        self.now = datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc)

    def __call__(self) -> datetime:
        return self.now


class PackagePlaneTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.clock = Clock()
        self.sessions = SessionBindingStore(clock=self.clock)
        self.task, _ = self.sessions.issue(
            1000,
            EndpointAdmission("fabric.task-rpc", PrincipalKind.TASK, task_id="task.software"),
            lifetime=timedelta(hours=1),
        )
        self.shell, _ = self.sessions.issue(
            1000,
            EndpointAdmission("fabric.owner-rpc", PrincipalKind.SHELL),
            lifetime=timedelta(hours=1),
        )
        self.packages = package_provider()
        self.registry = ProviderRegistry(clock=lambda: 1.0)
        self.registry.register(self.packages)
        self.temp = TemporaryDirectory()
        self.store = OperationStore(Path(self.temp.name) / "operations.db", clock=self.clock)
        self.store.open()
        self.intents = IntentCatalog(package_intents())
        self.executor = HermeticPackageExecutor(self.packages.engine, self.intents)
        self.approvals = ApprovalAuthority(clock=self.clock)
        self.coordinator = OperationCoordinator(
            store=self.store,
            gateway=CoordinatedRegistryGateway(self.registry),
            definitions=package_definitions(),
            intents=self.intents,
            executor=self.executor,
            session_resolver=self.sessions.require_active,
            policy_revision=lambda: "policy.revision.packages-v0",
            clock=self.clock,
        )

    async def asyncTearDown(self) -> None:
        self.store.close()
        self.temp.cleanup()

    def _grant(self, operation_id: str, *, risk: RiskLevel) -> CapabilityGrant:
        request = self.coordinator.approval_request(self.task, operation_id)
        return CapabilityGrant(
            grant_id="grant.packages.one",
            principal_id=self.task.principal_id,
            principal_kind=PrincipalKind.TASK,
            capability=request.capability,
            resource=request.resource,
            issued_at=self.clock.now - timedelta(seconds=1),
            expires_at=self.clock.now + timedelta(minutes=5),
            maximum_risk=risk,
            persistence=GrantPersistence.SESSION,
            task_id="task.software",
        )

    async def test_task_principal_installs_through_the_coordinator(self) -> None:
        args = arguments(self.packages.engine, "software.curated.neovim")
        planned = await self.coordinator.preflight(
            self.task,
            provider_id="packages.provider",
            action="install",
            arguments=args,
            idempotency_key="packages.install.neovim",
        )
        operation_id = planned["operationId"]
        approval = self.approvals.issue(
            self.task,
            self.coordinator.approval_request(self.task, operation_id),
            expires_at=self.clock.now + timedelta(minutes=5),
        )
        result = await self.coordinator.start(
            self.task,
            operation_id,
            approval_id=approval.approval_id,
            approvals=self.approvals,
            grants=(self._grant(operation_id, risk=RiskLevel.CONSEQUENTIAL),),
        )
        self.assertEqual(result["status"], "succeeded")
        inventory = self.packages.engine.inventory(include_unmanaged=True)["items"]
        self.assertEqual(inventory[0]["catalogId"], "software.curated.neovim")
        self.assertEqual(self.executor.system_requests[0]["action"], "packages.install")
        self.assertEqual(self.executor.system_requests[0]["arguments"]["package_ids"], ["software.curated.neovim"])

    async def test_shell_cannot_hold_a_package_grant(self) -> None:
        args = arguments(self.packages.engine, "software.curated.neovim")
        planned = await self.coordinator.preflight(
            self.shell,
            provider_id="packages.provider",
            action="install",
            arguments=args,
            idempotency_key="packages.install.shell",
        )
        with self.assertRaises(SecurityValidationError) as caught:
            CapabilityGrant(
                grant_id="grant.packages.shell",
                principal_id=self.shell.principal_id,
                principal_kind=PrincipalKind.SHELL,
                capability="packages.install",
                resource=ResourceRef("software", "software.curated.neovim"),
                issued_at=self.clock.now,
                expires_at=self.clock.now + timedelta(minutes=5),
                maximum_risk=RiskLevel.CONSEQUENTIAL,
                persistence=GrantPersistence.SESSION,
            )
        self.assertIn("cannot hold", str(caught.exception))
        self.assertEqual(planned["status"], "awaiting-approval")

    async def test_remove_projects_high_risk_and_restores_on_rollback_path(self) -> None:
        seeded = package_provider([installed()])
        registry = ProviderRegistry(clock=lambda: 2.0)
        registry.register(seeded)
        executor = HermeticPackageExecutor(seeded.engine, self.intents)
        store = OperationStore(Path(self.temp.name) / "remove.db", clock=self.clock)
        store.open()
        try:
            coordinator = OperationCoordinator(
                store=store,
                gateway=CoordinatedRegistryGateway(registry),
                definitions=package_definitions(),
                intents=self.intents,
                executor=executor,
                session_resolver=self.sessions.require_active,
                policy_revision=lambda: "policy.revision.packages-v0",
                clock=self.clock,
            )
            args = arguments(seeded.engine, "software.curated.neovim", request_id="request.software.remove")
            envelope = await registry.preflight("packages.provider", "remove", args, self.task)
            projected = project_package_preflight(envelope)
            self.assertEqual(projected["risk"], "high")
            self.assertFalse(projected["preflight"]["proposedState"]["value"]["present"])
            planned = await coordinator.preflight(
                self.task,
                provider_id="packages.provider",
                action="remove",
                arguments=args,
                idempotency_key="packages.remove.neovim",
            )
            approval = self.approvals.issue(
                self.task,
                coordinator.approval_request(self.task, planned["operationId"]),
                expires_at=self.clock.now + timedelta(minutes=5),
            )
            request = coordinator.approval_request(self.task, planned["operationId"])
            grant = CapabilityGrant(
                grant_id="grant.packages.remove",
                principal_id=self.task.principal_id,
                principal_kind=PrincipalKind.TASK,
                capability=request.capability,
                resource=request.resource,
                issued_at=self.clock.now - timedelta(seconds=1),
                expires_at=self.clock.now + timedelta(minutes=5),
                maximum_risk=RiskLevel.HIGH,
                persistence=GrantPersistence.SESSION,
                task_id="task.software",
            )
            result = await coordinator.start(
                self.task,
                planned["operationId"],
                approval_id=approval.approval_id,
                approvals=self.approvals,
                grants=(grant,),
            )
            self.assertEqual(result["status"], "succeeded")
            self.assertEqual(seeded.engine.inventory(include_unmanaged=True)["items"], [])
        finally:
            store.close()

    def test_package_intents_are_routed_off_the_session_executor(self) -> None:
        session = SimpleNamespace(available=True)
        privileged = SimpleNamespace(available=False)
        router = PrivilegeRoutingExecutor(session, privileged, PRIVILEGED_PACKAGE_INTENTS)
        intent = self.intents.build(
            "packages.install",
            {"resourceId": "software.curated.neovim", "package_ids": ["software.curated.neovim"]},
        )
        self.assertIn(intent.intent_id, PRIVILEGED_PACKAGE_INTENTS)
        self.assertIs(router._choose(intent), privileged)
        self.assertTrue(router.available)


if __name__ == "__main__":
    unittest.main()
