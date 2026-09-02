from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from tempfile import TemporaryDirectory

import importlib.util

ROOT = Path(__file__).resolve().parents[3]
FABRIC_ROOT = ROOT / "default" / "fabric"
if str(FABRIC_ROOT) not in sys.path:
    sys.path.insert(0, str(FABRIC_ROOT))

_files_helper_spec = importlib.util.spec_from_file_location(
    "files_operation_plane_helper",
    ROOT / "test" / "fabric" / "files" / "helper.py",
)
_files_helper = importlib.util.module_from_spec(_files_helper_spec)
assert _files_helper_spec.loader is not None
_files_helper_spec.loader.exec_module(_files_helper)
clone_workspace = _files_helper.clone_workspace

from omarchy_fabric.daemon import FabricDaemon
from omarchy_fabric.models import FabricError, FixedArgvCommand
from omarchy_fabric.operations.coordinator import OperationCoordinator
from omarchy_fabric.operations.contracts import OperationDefinition
from omarchy_fabric.operations.executor import IntentCatalog, IntentDefinition, stable_token
from omarchy_fabric.operations.package_plane import CoordinatedRegistryGateway
from omarchy_fabric.operations.store import OperationStore
from omarchy_fabric.provider_registry import ProviderRegistry
from omarchy_fabric.providers.files import provider as files
from omarchy_fabric.security.errors import SecurityValidationError
from omarchy_fabric.security.grants import CapabilityGrant, GrantPersistence
from omarchy_fabric.security.principal import EndpointAdmission, PrincipalKind, SessionBindingStore
from omarchy_fabric.security.types import ResourceRef, RiskLevel


class Clock:
    def __init__(self) -> None:
        self.now = datetime(2026, 9, 2, 12, 0, tzinfo=timezone.utc)

    def __call__(self) -> datetime:
        return self.now


class FilesPlaneTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.clock = Clock()
        self.sessions = SessionBindingStore(clock=self.clock)
        self.shell, _ = self.sessions.issue(
            1000,
            EndpointAdmission("fabric.owner-rpc", PrincipalKind.SHELL),
            lifetime=timedelta(hours=1),
        )
        self.files = files.build_fake_provider(clone_workspace())
        self.registry = ProviderRegistry(clock=lambda: 1.0)
        self.registry.register(self.files)
        self.temp = TemporaryDirectory()
        self.store = OperationStore(Path(self.temp.name) / "operations.db", clock=self.clock)
        self.store.open()
        self.intents = IntentCatalog(
            (
                IntentDefinition(
                    "files.directory.create",
                    FixedArgvCommand("/bin/true", ("files-directory-create",)),
                    required={
                        "resourceId": stable_token,
                        "locationId": stable_token,
                        "parentRelativePath": lambda value: value,
                        "name": lambda value: value,
                    },
                ),
                IntentDefinition(
                    "files.entry.trash",
                    FixedArgvCommand("/bin/true", ("files-entry-trash",)),
                    required={
                        "resourceId": stable_token,
                        "entryId": stable_token,
                        "locationId": stable_token,
                        "entryRelativePath": lambda value: value,
                    },
                ),
            )
        )
        self.coordinator = OperationCoordinator(
            store=self.store,
            gateway=CoordinatedRegistryGateway(self.registry),
            definitions=(
                OperationDefinition(
                    "files.provider",
                    "directory.create",
                    "files.directory.create",
                    lambda preflight: {
                        "resourceId": preflight["resource"]["id"],
                        "locationId": preflight["normalizedArguments"]["locationId"],
                        "parentRelativePath": preflight["normalizedArguments"]["parentRelativePath"],
                        "name": preflight["normalizedArguments"]["name"],
                    },
                ),
                OperationDefinition(
                    "files.provider",
                    "entry.trash",
                    "files.entry.trash",
                    FabricDaemon._trash_payload,
                ),
            ),
            intents=self.intents,
            executor=type("Unavailable", (), {"available": True})(),
            session_resolver=self.sessions.require_active,
            policy_revision=lambda: "policy.revision.files-v0",
            clock=self.clock,
        )

    async def asyncTearDown(self) -> None:
        self.store.close()
        self.temp.cleanup()

    def _shell_grant(self, operation_id: str) -> CapabilityGrant:
        request = self.coordinator.approval_request(self.shell, operation_id)
        return CapabilityGrant(
            grant_id=f"grant.files.{operation_id}",
            principal_id=self.shell.principal_id,
            principal_kind=PrincipalKind.SHELL,
            capability=request.capability,
            resource=request.resource,
            issued_at=self.clock.now,
            expires_at=self.clock.now + timedelta(minutes=5),
            maximum_risk=request.risk,
            persistence=GrantPersistence.SESSION,
        )

    async def test_directory_create_and_entry_trash_are_the_same_shell_write_class(self) -> None:
        created = await self.coordinator.preflight(
            self.shell,
            provider_id="files.provider",
            action="directory.create",
            arguments={
                "locationId": "files.location.desktop",
                "parentRelativePath": "Project",
                "name": "Assets",
            },
            idempotency_key="files.directory.create.assets",
        )
        create_request = self.coordinator.approval_request(self.shell, created["operationId"])
        self.assertEqual(create_request.risk, RiskLevel.LOW)
        self.assertEqual(create_request.capability, "files.directory.create")
        self.assertTrue(create_request.resource.resource_id.startswith("files.directory."))
        self._shell_grant(created["operationId"])

        trashed = await self.coordinator.preflight(
            self.shell,
            provider_id="files.provider",
            action="entry.trash",
            arguments={"entryId": "files.entry.notes"},
            idempotency_key="files.entry.trash.notes",
        )
        trash_request = self.coordinator.approval_request(self.shell, trashed["operationId"])
        self.assertEqual(trash_request.risk, RiskLevel.LOW)
        self.assertEqual(trash_request.capability, "files.entry.trash")
        self.assertTrue(trash_request.resource.resource_id.startswith("files.directory."))
        self.assertNotEqual(trash_request.resource.resource_id, create_request.resource.resource_id)
        payload = self.store.get(trashed["operationId"]).plan.intent.payload
        self.assertEqual(payload["locationId"], "files.location.desktop")
        self.assertEqual(payload["entryRelativePath"], "notes.txt")
        self.assertEqual(payload["entryId"], "files.entry.notes")
        self._shell_grant(trashed["operationId"])

    async def test_trash_restore_is_not_a_coordinator_definition(self) -> None:
        with self.assertRaises(FabricError) as caught:
            await self.coordinator.preflight(
                self.shell,
                provider_id="files.provider",
                action="trash.restore",
                arguments={"entryId": "files.entry.project"},
                idempotency_key="files.trash.restore.project",
            )
        self.assertEqual(caught.exception.code, "operation.definition-unavailable")

    def test_shell_cannot_hold_a_consequential_files_grant(self) -> None:
        with self.assertRaises(SecurityValidationError) as caught:
            CapabilityGrant(
                grant_id="grant.files.shell-consequential",
                principal_id=self.shell.principal_id,
                principal_kind=PrincipalKind.SHELL,
                capability="files.entry.trash",
                resource=ResourceRef("files.directory", "files.directory." + "a" * 64),
                issued_at=self.clock.now,
                expires_at=self.clock.now + timedelta(minutes=5),
                maximum_risk=RiskLevel.CONSEQUENTIAL,
                persistence=GrantPersistence.SESSION,
            )
        self.assertEqual(caught.exception.code, "grant.shell-consequential")


if __name__ == "__main__":
    unittest.main()
