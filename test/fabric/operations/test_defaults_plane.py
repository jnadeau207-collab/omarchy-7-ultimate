from __future__ import annotations

import importlib.util
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[3]
FABRIC_ROOT = ROOT / "default" / "fabric"
if str(FABRIC_ROOT) not in sys.path:
    sys.path.insert(0, str(FABRIC_ROOT))

_defaults_helper_spec = importlib.util.spec_from_file_location(
    "defaults_operation_plane_helper",
    ROOT / "test" / "fabric" / "defaults" / "helper.py",
)
_defaults_helper = importlib.util.module_from_spec(_defaults_helper_spec)
assert _defaults_helper_spec.loader is not None
_defaults_helper_spec.loader.exec_module(_defaults_helper)
clone_database = _defaults_helper.clone_database

from omarchy_fabric.daemon import FabricDaemon
from omarchy_fabric.models import FixedArgvCommand
from omarchy_fabric.operations.coordinator import OperationCoordinator
from omarchy_fabric.operations.contracts import OperationDefinition
from omarchy_fabric.operations.executor import IntentCatalog, IntentDefinition, stable_token
from omarchy_fabric.operations.package_plane import CoordinatedRegistryGateway
from omarchy_fabric.operations.store import OperationStore
from omarchy_fabric.provider_registry import ProviderRegistry
from omarchy_fabric.providers.defaults import provider as defaults
from omarchy_fabric.security.grants import CapabilityGrant, GrantPersistence
from omarchy_fabric.security.principal import EndpointAdmission, PrincipalKind, SessionBindingStore
from omarchy_fabric.security.types import RiskLevel


class Clock:
    def __init__(self) -> None:
        self.now = datetime(2026, 9, 5, 12, 0, tzinfo=timezone.utc)

    def __call__(self) -> datetime:
        return self.now


class DefaultsPlaneTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.clock = Clock()
        self.sessions = SessionBindingStore(clock=self.clock)
        self.shell, _ = self.sessions.issue(
            1000,
            EndpointAdmission("fabric.owner-rpc", PrincipalKind.SHELL),
            lifetime=timedelta(hours=1),
        )
        self.database = clone_database()
        self.defaults = defaults.build_fake_provider(self.database)
        self.registry = ProviderRegistry(clock=lambda: 1.0)
        self.registry.register(self.defaults)
        self.temp = TemporaryDirectory()
        self.store = OperationStore(Path(self.temp.name) / "operations.db", clock=self.clock)
        self.store.open()
        self.intents = IntentCatalog(
            (
                IntentDefinition(
                    "defaults.mime.set",
                    FixedArgvCommand("/bin/true", ("defaults-mime-set",)),
                    required={
                        "resourceId": stable_token,
                        "mimeType": lambda value: value,
                        "appId": stable_token,
                    },
                ),
                IntentDefinition(
                    "defaults.protocol.set",
                    FixedArgvCommand("/bin/true", ("defaults-protocol-set",)),
                    required={
                        "resourceId": stable_token,
                        "scheme": lambda value: value,
                        "appId": stable_token,
                    },
                ),
            )
        )
        self.coordinator = OperationCoordinator(
            store=self.store,
            gateway=CoordinatedRegistryGateway(self.registry),
            definitions=(
                OperationDefinition(
                    "defaults.provider",
                    "mime.set",
                    "defaults.mime.set",
                    FabricDaemon._defaults_mime_payload,
                ),
                OperationDefinition(
                    "defaults.provider",
                    "protocol.set",
                    "defaults.protocol.set",
                    FabricDaemon._defaults_payload,
                ),
            ),
            intents=self.intents,
            executor=type("Unavailable", (), {"available": True})(),
            session_resolver=self.sessions.require_active,
            policy_revision=lambda: "policy.revision.defaults-v0",
            clock=self.clock,
        )
        self.alternate = next(
            app for app in self.database["applications"] if app["desktopId"] == "alternate.desktop"
        )
        self.mailer = next(
            app for app in self.database["applications"] if app["desktopId"] == "mailer.desktop"
        )

    async def asyncTearDown(self) -> None:
        self.store.close()
        self.temp.cleanup()

    def _shell_grant(self, operation_id: str) -> CapabilityGrant:
        request = self.coordinator.approval_request(self.shell, operation_id)
        return CapabilityGrant(
            grant_id=f"grant.defaults.{operation_id}",
            principal_id=self.shell.principal_id,
            principal_kind=PrincipalKind.SHELL,
            capability=request.capability,
            resource=request.resource,
            issued_at=self.clock.now,
            expires_at=self.clock.now + timedelta(minutes=5),
            maximum_risk=request.risk,
            persistence=GrantPersistence.SESSION,
        )

    async def test_mime_set_preflight_builds_coordinator_intent(self) -> None:
        planned = await self.coordinator.preflight(
            self.shell,
            provider_id="defaults.provider",
            action="mime.set",
            arguments={"mimeType": "text/plain", "appId": self.alternate["id"]},
            idempotency_key="settings.mime-default.text.plain",
        )
        request = self.coordinator.approval_request(self.shell, planned["operationId"])
        self.assertEqual(request.risk, RiskLevel.LOW)
        self.assertEqual(request.capability, "defaults.mime.set")
        payload = self.store.get(planned["operationId"]).plan.intent.payload
        self.assertEqual(payload["mimeType"], "text/plain")
        self.assertEqual(payload["appId"], self.alternate["id"])
        self.assertTrue(payload["resourceId"])
        grant = self._shell_grant(planned["operationId"])
        self.assertEqual(grant.maximum_risk, RiskLevel.LOW)

    async def test_protocol_set_preflight_builds_browser_and_mailto_intents(self) -> None:
        browser = await self.coordinator.preflight(
            self.shell,
            provider_id="defaults.provider",
            action="protocol.set",
            arguments={"scheme": "http", "appId": self.alternate["id"]},
            idempotency_key="settings.default-browser.http",
        )
        browser_payload = self.store.get(browser["operationId"]).plan.intent.payload
        self.assertEqual(browser_payload["scheme"], "http")
        self.assertEqual(browser_payload["appId"], self.alternate["id"])
        self.assertEqual(
            self.coordinator.approval_request(self.shell, browser["operationId"]).capability,
            "defaults.protocol.set",
        )

        mailer = await self.coordinator.preflight(
            self.shell,
            provider_id="defaults.provider",
            action="protocol.set",
            arguments={"scheme": "mailto", "appId": self.mailer["id"]},
            idempotency_key="settings.default-mailer.mailto",
        )
        mailer_payload = self.store.get(mailer["operationId"]).plan.intent.payload
        self.assertEqual(mailer_payload["scheme"], "mailto")
        self.assertEqual(mailer_payload["appId"], self.mailer["id"])

    def test_payload_builders_read_provider_preflight_shape(self) -> None:
        preflight = {
            "resource": {"kind": "defaults.association", "id": "defaults.association.plain"},
            "normalizedArguments": {"mimeType": "text/plain", "appId": "defaults.app.alt"},
            "proposedState": {
                "resourceId": "defaults.association.plain",
                "revision": "rev.1",
                "value": {"kind": "mime", "key": "text/plain", "defaultAppId": "defaults.app.alt"},
            },
        }
        mime = FabricDaemon._defaults_mime_payload(preflight)
        self.assertEqual(mime["mimeType"], "text/plain")
        self.assertEqual(mime["appId"], "defaults.app.alt")
        self.assertEqual(mime["resourceId"], "defaults.association.plain")

        protocol_preflight = {
            "resource": {"kind": "defaults.association", "id": "defaults.association.https"},
            "normalizedArguments": {"scheme": "https", "appId": "defaults.app.browser"},
            "proposedState": {
                "resourceId": "defaults.association.https",
                "revision": "rev.1",
                "value": {"kind": "protocol", "key": "https", "defaultAppId": "defaults.app.browser"},
            },
        }
        protocol = FabricDaemon._defaults_payload(protocol_preflight)
        self.assertEqual(protocol["scheme"], "https")
        self.assertEqual(protocol["appId"], "defaults.app.browser")
        self.assertEqual(protocol["resourceId"], "defaults.association.https")
