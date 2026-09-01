from __future__ import annotations

import json
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
    "packages_system_routing_helper",
    ROOT / "test" / "fabric" / "packages" / "helper.py",
)
_packages_helper = importlib.util.module_from_spec(_packages_helper_spec)
assert _packages_helper_spec.loader is not None
_packages_helper_spec.loader.exec_module(_packages_helper)
arguments = _packages_helper.arguments
package_provider = _packages_helper.provider

from omarchy_fabric.models import FixedArgvCommand
from omarchy_fabric.operations.coordinator import OperationCoordinator
from omarchy_fabric.operations.executor import IntentCatalog, UnavailableProductionExecutor
from omarchy_fabric.operations.package_plane import (
    PRIVILEGED_PACKAGE_INTENTS,
    SYSTEM_EXECUTOR,
    CoordinatedRegistryGateway,
    package_definitions,
    package_intents,
)
from omarchy_fabric.operations.device_plane import PRIVILEGED_DEVICE_INTENTS
from omarchy_fabric.operations.routing_executor import PrivilegeRoutingExecutor
from omarchy_fabric.operations.session_executor import SessionCommandResult
from omarchy_fabric.operations.store import OperationStore
from omarchy_fabric.operations.system_command_executor import SystemCommandExecutor
from omarchy_fabric.provider_registry import ProviderRegistry
from omarchy_fabric.security.approval import ApprovalAuthority
from omarchy_fabric.security.grants import CapabilityGrant, GrantPersistence
from omarchy_fabric.security.principal import EndpointAdmission, PrincipalKind, SessionBindingStore
from omarchy_fabric.security.types import RiskLevel


class Clock:
    def __init__(self) -> None:
        self.now = datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc)

    def __call__(self) -> datetime:
        return self.now


class RecordingSystemRunner:
    def __init__(self, values: dict[str, object], catalog) -> None:
        self.values = values
        self.catalog = catalog
        self.calls: list[tuple[tuple[str, ...], dict[str, object]]] = []

    async def __call__(self, command: FixedArgvCommand, payload: str) -> SessionCommandResult:
        document = json.loads(payload)
        self.calls.append(((command.executable, *command.arguments), document))
        resource_id = document["arguments"].get("package_ids", [None])[0]
        if resource_id:
            entry = self.catalog.by_id[resource_id]
            self.values[resource_id] = {
                "catalogId": resource_id,
                "present": True,
                "artifactDigest": entry["provenance"]["artifactDigest"],
                "adopted": True,
            }
        return SessionCommandResult(0, "applied", "")


class ForbiddenSession:
    available = True

    async def apply(self, *args, **kwargs):
        raise AssertionError("session executor must not run privileged intents")

    async def validate(self, *args, **kwargs):
        raise AssertionError("session executor must not validate privileged intents")

    async def rollback(self, *args, **kwargs):
        raise AssertionError("session executor must not roll back privileged intents")

    async def reconcile(self, *args, **kwargs):
        raise AssertionError("session executor must not reconcile privileged intents")


class SystemRoutingTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.clock = Clock()
        self.sessions = SessionBindingStore(clock=self.clock)
        self.task, _ = self.sessions.issue(
            1000,
            EndpointAdmission("fabric.task-rpc", PrincipalKind.TASK, task_id="task.software"),
            lifetime=timedelta(hours=1),
        )
        self.packages = package_provider()
        self.registry = ProviderRegistry(clock=lambda: 1.0)
        self.registry.register(self.packages)
        self.temp = TemporaryDirectory()
        self.store = OperationStore(Path(self.temp.name) / "operations.db", clock=self.clock)
        self.store.open()
        self.intents = IntentCatalog(package_intents())
        self.values: dict[str, object] = {}

        async def reader(resource_id: str):
            inventory = self.packages.engine.inventory(include_unmanaged=True)
            item = next((entry for entry in inventory["items"] if entry["catalogId"] == resource_id), None)
            value = {
                "catalogId": resource_id,
                "present": item is not None,
                "artifactDigest": item["artifactDigest"] if item is not None else None,
                "adopted": bool(item.get("adopted")) if item is not None else False,
            }
            if resource_id in self.values:
                value = self.values[resource_id]
            return {"resourceId": resource_id, "revision": inventory["revision"], "value": value}

        self.runner = RecordingSystemRunner(self.values, self.packages.engine.catalog)
        self.system = SystemCommandExecutor(self.intents, reader, runner=self.runner)
        self.approvals = ApprovalAuthority(clock=self.clock)
        self.coordinator = OperationCoordinator(
            store=self.store,
            gateway=CoordinatedRegistryGateway(self.registry),
            definitions=package_definitions(),
            intents=self.intents,
            executor=PrivilegeRoutingExecutor(
                ForbiddenSession(),
                self.system,
                PRIVILEGED_PACKAGE_INTENTS | PRIVILEGED_DEVICE_INTENTS,
            ),
            session_resolver=self.sessions.require_active,
            policy_revision=lambda: "policy.revision.system-v0",
            clock=self.clock,
        )

    async def asyncTearDown(self) -> None:
        self.store.close()
        self.temp.cleanup()

    def _grant(self, operation_id: str) -> CapabilityGrant:
        request = self.coordinator.approval_request(self.task, operation_id)
        return CapabilityGrant(
            grant_id="grant.packages.system",
            principal_id=self.task.principal_id,
            principal_kind=PrincipalKind.TASK,
            capability=request.capability,
            resource=request.resource,
            issued_at=self.clock.now - timedelta(seconds=1),
            expires_at=self.clock.now + timedelta(minutes=5),
            maximum_risk=RiskLevel.CONSEQUENTIAL,
            persistence=GrantPersistence.SESSION,
            task_id="task.software",
        )

    async def test_package_install_runs_system_executor_not_session(self) -> None:
        args = arguments(self.packages.engine, "software.curated.neovim")
        planned = await self.coordinator.preflight(
            self.task,
            provider_id="packages.provider",
            action="install",
            arguments=args,
            idempotency_key="packages.install.system",
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
        self.assertEqual(result["status"], "succeeded")
        self.assertEqual(len(self.runner.calls), 1)
        argv, document = self.runner.calls[0]
        self.assertEqual(argv[0], SYSTEM_EXECUTOR)
        self.assertEqual(argv[1], "packages.install")
        self.assertEqual(document["action"], "packages.install")
        self.assertEqual(document["arguments"]["package_ids"], ["software.curated.neovim"])
        self.assertEqual(self.system.system_requests[0]["action"], "packages.install")

    def test_privileged_intents_choose_system_executor(self) -> None:
        session = SimpleNamespace(available=True)
        privileged = SimpleNamespace(available=True)
        router = PrivilegeRoutingExecutor(
            session,
            privileged,
            PRIVILEGED_PACKAGE_INTENTS | PRIVILEGED_DEVICE_INTENTS,
        )
        install = self.intents.build(
            "packages.install",
            {"resourceId": "software.curated.neovim", "package_ids": ["software.curated.neovim"]},
        )
        self.assertIs(router._choose(install), privileged)
        self.assertNotIsInstance(router._choose(install), UnavailableProductionExecutor)

    async def test_missing_system_helper_fails_closed(self) -> None:
        async def missing(command, payload):
            raise FileNotFoundError(command.executable)

        executor = SystemCommandExecutor(self.intents, self.system.reader, runner=missing)
        args = arguments(self.packages.engine, "software.curated.neovim")
        store = OperationStore(Path(self.temp.name) / "missing.db", clock=self.clock)
        store.open()
        try:
            coordinator = OperationCoordinator(
                store=store,
                gateway=CoordinatedRegistryGateway(self.registry),
                definitions=package_definitions(),
                intents=self.intents,
                executor=PrivilegeRoutingExecutor(
                    ForbiddenSession(),
                    executor,
                    PRIVILEGED_PACKAGE_INTENTS,
                ),
                session_resolver=self.sessions.require_active,
                policy_revision=lambda: "policy.revision.system-v0",
                clock=self.clock,
            )
            planned = await coordinator.preflight(
                self.task,
                provider_id="packages.provider",
                action="install",
                arguments=args,
                idempotency_key="packages.install.missing",
            )
            approval = self.approvals.issue(
                self.task,
                coordinator.approval_request(self.task, planned["operationId"]),
                expires_at=self.clock.now + timedelta(minutes=5),
            )
            result = await coordinator.start(
                self.task,
                planned["operationId"],
                approval_id=approval.approval_id,
                approvals=self.approvals,
                grants=(
                    CapabilityGrant(
                        grant_id="grant.packages.missing",
                        principal_id=self.task.principal_id,
                        principal_kind=PrincipalKind.TASK,
                        capability=coordinator.approval_request(self.task, planned["operationId"]).capability,
                        resource=coordinator.approval_request(self.task, planned["operationId"]).resource,
                        issued_at=self.clock.now - timedelta(seconds=1),
                        expires_at=self.clock.now + timedelta(minutes=5),
                        maximum_risk=RiskLevel.CONSEQUENTIAL,
                        persistence=GrantPersistence.SESSION,
                        task_id="task.software",
                    ),
                ),
            )
            self.assertEqual(result["status"], "failed")
            self.assertEqual(result["error"]["code"], "executor.system-unavailable")
        finally:
            store.close()


if __name__ == "__main__":
    unittest.main()
