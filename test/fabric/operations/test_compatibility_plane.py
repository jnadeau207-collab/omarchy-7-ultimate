from __future__ import annotations

import copy
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[3]
FABRIC_ROOT = ROOT / "default" / "fabric"
if str(FABRIC_ROOT) not in sys.path:
    sys.path.insert(0, str(FABRIC_ROOT))

import importlib.util

_helper_spec = importlib.util.spec_from_file_location(
    "compatibility_operation_plane_helper",
    ROOT / "test" / "fabric" / "compatibility" / "helper.py",
)
_helper = importlib.util.module_from_spec(_helper_spec)
assert _helper_spec.loader is not None
_helper_spec.loader.exec_module(_helper)
arguments = _helper.arguments
host = _helper.host
provider = _helper.provider
recipe_document = _helper.recipe_document
reviewed_request = _helper.reviewed_request

from omarchy_fabric.models import FabricError
from omarchy_fabric.operations.compatibility_plane import (
    COMPATIBILITY_INTENTS,
    HermeticCompatibilityExecutor,
    compatibility_definitions,
    compatibility_intents,
    project_compatibility_preflight,
)
from omarchy_fabric.operations.coordinator import OperationCoordinator
from omarchy_fabric.operations.executor import IntentCatalog
from omarchy_fabric.operations.package_plane import CoordinatedRegistryGateway
from omarchy_fabric.operations.routing_executor import PrivilegeRoutingExecutor
from omarchy_fabric.operations.store import OperationStore
from omarchy_fabric.provider_registry import ProviderRegistry
from omarchy_fabric.providers.compatibility.recipes import RecipeCatalog
from omarchy_fabric.providers.packages.identity import revision
from omarchy_fabric.security.approval import ApprovalAuthority
from omarchy_fabric.security.grants import CapabilityGrant, GrantPersistence
from omarchy_fabric.security.principal import EndpointAdmission, PrincipalKind, SessionBindingStore
from omarchy_fabric.security.release_attestation import default_release_attestation
from omarchy_fabric.security.types import RiskLevel


class Clock:
    def __init__(self) -> None:
        self.now = datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc)

    def __call__(self) -> datetime:
        return self.now


class CompatibilityPlaneTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.clock = Clock()
        self.sessions = SessionBindingStore(clock=self.clock)
        self.task, _ = self.sessions.issue(
            1000,
            EndpointAdmission("fabric.task-rpc", PrincipalKind.TASK, task_id="task.compatibility"),
            lifetime=timedelta(hours=1),
        )
        self.compat = provider()
        self.registry = ProviderRegistry(clock=lambda: 1.0)
        self.registry.register(self.compat)
        self.temp = TemporaryDirectory()
        self.store = OperationStore(Path(self.temp.name) / "operations.db", clock=self.clock)
        self.store.open()
        self.intents = IntentCatalog(compatibility_intents())
        self.executor = HermeticCompatibilityExecutor(self.compat.engine, self.intents)
        self.approvals = ApprovalAuthority(clock=self.clock)
        self.coordinator = OperationCoordinator(
            store=self.store,
            gateway=CoordinatedRegistryGateway(self.registry),
            definitions=compatibility_definitions(),
            intents=self.intents,
            executor=self.executor,
            session_resolver=self.sessions.require_active,
            policy_revision=lambda: "policy.revision.compatibility-v0",
            clock=self.clock,
        )

    async def asyncTearDown(self) -> None:
        self.store.close()
        self.temp.cleanup()

    def _grant(self, operation_id: str) -> CapabilityGrant:
        request = self.coordinator.approval_request(self.task, operation_id)
        return CapabilityGrant(
            grant_id="grant.compatibility.one",
            principal_id=self.task.principal_id,
            principal_kind=PrincipalKind.TASK,
            capability=request.capability,
            resource=request.resource,
            issued_at=self.clock.now - timedelta(seconds=1),
            expires_at=self.clock.now + timedelta(minutes=5),
            maximum_risk=RiskLevel.CONSEQUENTIAL,
            persistence=GrantPersistence.SESSION,
            task_id="task.compatibility",
        )

    async def test_task_deploys_measured_contract_seed_through_coordinator(self) -> None:
        machine = host()
        args = arguments(self.compat.engine, reviewed_request(), machine)
        planned = await self.coordinator.preflight(
            self.task,
            provider_id="compatibility.provider",
            action="deploy",
            arguments=args,
            idempotency_key="compatibility.deploy.reader",
        )
        self.assertEqual(planned["status"], "awaiting-approval")
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
        deployments = self.compat.engine.deployments()["deployments"]
        self.assertEqual(deployments[0]["workloadId"], "workload.adobe-reader")
        self.assertTrue(deployments[0]["state"] == "installed")

    async def test_remove_projects_high_risk(self) -> None:
        deploy_args = arguments(self.compat.engine, reviewed_request(), host())
        deploy_plan = self.compat.engine.preflight("deploy", deploy_args, self.task)
        await self.compat.engine.apply("deploy", deploy_args, deploy_plan["deploymentRevision"])
        remove_args = arguments(
            self.compat.engine,
            reviewed_request(),
            host(),
            request_id="request.compatibility.remove",
            preserve=False,
        )
        raw = await self.registry.preflight("compatibility.provider", "remove", remove_args, self.task)
        projected = project_compatibility_preflight(raw)
        self.assertEqual(projected["risk"], "high")
        self.assertFalse(projected["preflight"]["proposedState"]["value"]["present"])

    def test_empty_attestation_still_refuses_release_verified_deploy_claim(self) -> None:
        attestation = default_release_attestation(ROOT / "default")
        self.assertEqual(attestation.admitted_revisions("compatibility-recipes"), frozenset())
        value = recipe_document()
        value["assurance"] = "release-verified"
        for recipe in value["recipes"]:
            recipe["signature"]["status"] = "verified"
        unsigned = copy.deepcopy(value)
        unsigned["revision"] = "sha256." + "0" * 64
        value["revision"] = revision(unsigned)
        with self.assertRaises(FabricError) as refused:
            RecipeCatalog(
                value,
                verified_recipe_revisions=attestation.admitted_revisions("compatibility-recipes"),
            )
        self.assertEqual(refused.exception.code, "compatibility.recipes-unattested")
        seed = RecipeCatalog(recipe_document())
        self.assertEqual(seed.assurance, "contract-seed")
        self.assertNotEqual(seed.assurance, "release-verified")

    def test_compatibility_intents_are_not_session_intents(self) -> None:
        from types import SimpleNamespace

        session = SimpleNamespace(available=True)
        privileged = SimpleNamespace(available=True)
        router = PrivilegeRoutingExecutor(session, privileged, COMPATIBILITY_INTENTS)
        intent = self.intents.build(
            "compatibility.deploy",
            {
                "resourceId": "workload.adobe-reader",
                "requestId": "request.compatibility.test",
                "preserveData": True,
            },
        )
        self.assertIs(router._choose(intent), privileged)


if __name__ == "__main__":
    unittest.main()
