from __future__ import annotations

import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

from omarchy_fabric import provider_builtins as builtins
from omarchy_fabric.daemon import DaemonConfig, FabricDaemon
from omarchy_fabric.models import MAX_FRAME_BYTES, FabricError
from omarchy_fabric.protocol import FabricClient
from omarchy_fabric.provider_builtins import BUILTIN_PROVIDER_IDS, build_builtin_providers
from omarchy_fabric.provider_registry import MAX_PROVIDER_READ_SECONDS, ProviderRegistry
from omarchy_fabric.providers.audio import build_provider as build_audio_provider
from omarchy_fabric.providers.compatibility import provider as compatibility_provider_module
from omarchy_fabric.providers.compatibility.engine import deployment_revision
from omarchy_fabric.providers.packages import provider as package_provider_module
from omarchy_fabric.providers.packages.engine import inventory_revision
from omarchy_fabric.security import EndpointPrincipal, PrincipalKind


def principal() -> EndpointPrincipal:
    now = datetime(2026, 8, 27, tzinfo=timezone.utc)
    return EndpointPrincipal(
        "principal.production-provider-test",
        "session.production-provider-test",
        1000,
        "shell.production-provider-test",
        PrincipalKind.SHELL,
        now,
        now + timedelta(hours=1),
    )


def host() -> dict[str, object]:
    return {
        "architecture": "x86_64",
        "virtualizationAvailable": True,
        "protonAvailable": True,
        "isolationAvailable": True,
        "browserAvailable": True,
        "availableRuntimes": ["wine", "proton", "container", "browser", "native"],
        "memoryMiB": 16384,
        "diskMiB": 262144,
    }


def native_request() -> dict[str, object]:
    return {
        "id": "workload.production-native",
        "name": "Production native contract test",
        "workloadType": "desktop",
        "architecture": "x86_64",
        "artifact": {
            "kind": "native-package",
            "origin": "https://example.invalid/production-native",
            "digest": "sha256:" + "8" * 64,
        },
        "permissions": [],
        "constraints": {
            "requiresKernelDriver": False,
            "requiresAdmin": False,
            "antiCheat": "none",
            "offlineRequired": False,
            "acceptsBrowser": False,
        },
    }


class ProductionProviderSocketTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        with mock.patch.object(builtins, "_trusted_account_home", return_value=Path("/home/fabric-test")):
            providers = build_builtin_providers()
        self.providers = {provider.manifest["provider"]: provider for provider in providers}
        self.daemon = FabricDaemon(
            DaemonConfig(
                socket_path=root / "runtime" / "fabric.sock",
                database_path=root / "state" / "fabric.db",
                typed_providers=providers,
            )
        )
        await self.daemon.start()
        self.client = FabricClient(
            self.daemon.config.socket_path,
            client_name="production-provider-convergence",
            request_timeout=MAX_PROVIDER_READ_SECONDS + 2.0,
        )
        await self.client.connect()

    async def asyncTearDown(self) -> None:
        await self.client.close()
        await self.daemon.stop("test-complete")
        self.temporary.cleanup()

    async def test_catalog_health_and_representative_reads_cross_bounded_socket(self) -> None:
        health = await self.client.request("health")
        catalog = await self.client.request("provider.catalog")
        self.assertEqual(health["providers"]["typed"], 22)
        self.assertEqual(health["providers"]["availableTyped"], 20)
        self.assertEqual(health["providers"]["degradedTyped"], 2)
        self.assertEqual(health["providers"]["usableTyped"], 22)
        self.assertLess(len(json.dumps(health, allow_nan=False).encode("utf-8")), MAX_FRAME_BYTES)
        self.assertEqual(len(catalog["providers"]), 22)
        self.assertEqual(
            tuple(entry["manifest"]["provider"] for entry in catalog["providers"]),
            tuple(sorted(BUILTIN_PROVIDER_IDS)),
        )
        self.assertEqual(
            tuple(
                entry["manifest"]["provider"]
                for entry in sorted(catalog["providers"], key=lambda entry: entry["registrationOrder"])
            ),
            BUILTIN_PROVIDER_IDS,
        )
        degraded = [entry for entry in catalog["providers"] if entry["state"] == "degraded"]
        self.assertEqual(
            {entry["manifest"]["provider"] for entry in degraded},
            {"packages.provider", "compatibility.provider"},
        )
        self.assertTrue(all("contract seed" in entry["detail"] for entry in degraded))
        self.assertLess(len(json.dumps(catalog, allow_nan=False).encode("utf-8")), MAX_FRAME_BYTES)

        requests = (
            ("audio.provider", "inspect", {}),
            ("bluetooth.provider", "inspect", {}),
            ("display.provider", "inspect", {}),
            ("input.provider", "inspect", {}),
            ("network.provider", "inspect", {}),
            ("power.provider", "inspect", {}),
            ("files.provider", "inspect", {}),
            ("defaults.provider", "inspect", {}),
            ("packages.provider", "catalog.search", {"query": "editor", "sourceTypes": []}),
            (
                "compatibility.provider",
                "route.decide",
                {"request": native_request(), "host": host()},
            ),
            ("account.provider", "inspect", {}),
            ("backup.provider", "inspect", {}),
            ("device.provider", "inspect", {}),
            ("diagnostics.provider", "inspect", {}),
            ("firewall.provider", "inspect", {}),
            ("printer.provider", "inspect", {}),
            ("process.provider", "inspect", {}),
            ("recovery.provider", "inspect", {}),
            ("schedule.provider", "inspect", {}),
            ("service.provider", "inspect", {}),
            ("storage.provider", "inspect", {}),
            ("update.provider", "inspect", {}),
        )
        self.assertEqual(tuple(item[0] for item in requests), BUILTIN_PROVIDER_IDS)
        results = []
        for provider_id, action, arguments in requests:
            result = await self.client.request(
                "provider.read",
                {"provider": provider_id, "action": action, "arguments": arguments},
            )
            self.assertEqual(result["provider"], provider_id)
            self.assertLess(len(json.dumps(result, allow_nan=False).encode("utf-8")), MAX_FRAME_BYTES)
            results.append(result)
        self.assertEqual(results[8]["value"]["assurance"], "contract-seed")
        self.assertEqual(results[9]["value"]["recipeAssurance"], "contract-seed")
        self.assertEqual(results[9]["value"]["selectedRoute"], "native")

    async def test_unavailable_provider_reason_crosses_catalog_and_read_without_dispatch(self) -> None:
        display = self.providers["display.provider"]
        display.read = mock.AsyncMock(side_effect=AssertionError("unavailable provider dispatched"))
        detail = "The code-owned display provider was disconnected for a bounded test."
        self.daemon.typed_providers.mark_unavailable(
            "display.provider",
            expected_generation=1,
            detail=detail,
        )

        health = await self.client.request("health")
        catalog = await self.client.request("provider.catalog")
        entry = next(
            item for item in catalog["providers"] if item["manifest"]["provider"] == "display.provider"
        )
        self.assertEqual(health["providers"]["availableTyped"], 19)
        self.assertEqual(health["providers"]["degradedTyped"], 2)
        self.assertEqual(health["providers"]["usableTyped"], 21)
        self.assertEqual(entry["state"], "unavailable")
        self.assertEqual(entry["detail"], detail)
        with self.assertRaises(FabricError) as unavailable:
            await self.client.request(
                "provider.read",
                {"provider": "display.provider", "action": "inspect", "arguments": {}},
            )
        self.assertEqual(unavailable.exception.code, "provider.unavailable")
        self.assertEqual(unavailable.exception.detail, detail)
        display.read.assert_not_awaited()

    async def test_contract_seed_preflights_are_typed_but_live_execution_is_refused(self) -> None:
        with self.assertRaises(FabricError) as public_bypass:
            await self.client.request(
                "provider.preflight",
                {"provider": "packages.provider", "action": "install", "arguments": {}},
            )
        self.assertEqual(public_bypass.exception.code, "rpc.method-not-found")

        package = self.providers["packages.provider"]
        package_arguments = {
            "requestId": "request.packages.production",
            "appId": package.catalog.entries[0]["id"],
            "catalogRevision": package.catalog.revision,
            "expectedInventoryRevision": inventory_revision([]),
            "preserveUserData": True,
        }
        package_plan = await self.daemon.typed_providers.preflight(
            "packages.provider",
            "install",
            package_arguments,
            principal(),
        )
        self.assertEqual(package_plan["preflight"]["provenance"]["assurance"], "contract-seed")
        self.assertLess(len(json.dumps(package_plan, allow_nan=False).encode("utf-8")), MAX_FRAME_BYTES)
        with self.assertRaises(FabricError) as package_apply:
            await package.apply("install", package_arguments, inventory_revision([]))
        self.assertEqual(package_apply.exception.code, "packages.execution-unavailable")
        with self.assertRaises(FabricError) as package_validate:
            await package.validate("install", package_arguments, {})
        self.assertEqual(package_validate.exception.code, "packages.execution-unavailable")
        with self.assertRaises(FabricError) as package_rollback:
            await package.rollback("install", {}, inventory_revision([]))
        self.assertEqual(package_rollback.exception.code, "packages.execution-unavailable")

        compatibility = self.providers["compatibility.provider"]
        compatibility_arguments = {
            "requestId": "request.compatibility.production",
            "request": native_request(),
            "host": host(),
            "recipeRevision": compatibility.recipes.revision,
            "expectedDeploymentRevision": deployment_revision([]),
            "preserveData": True,
        }
        compatibility_plan = await self.daemon.typed_providers.preflight(
            "compatibility.provider",
            "deploy",
            compatibility_arguments,
            principal(),
        )
        self.assertEqual(compatibility_plan["preflight"]["decision"]["recipeAssurance"], "contract-seed")
        self.assertLess(len(json.dumps(compatibility_plan, allow_nan=False).encode("utf-8")), MAX_FRAME_BYTES)
        with self.assertRaises(FabricError) as compatibility_apply:
            await compatibility.apply("deploy", compatibility_arguments, deployment_revision([]))
        self.assertEqual(compatibility_apply.exception.code, "compatibility.execution-unavailable")
        with self.assertRaises(FabricError) as compatibility_validate:
            await compatibility.validate("deploy", compatibility_arguments, {})
        self.assertEqual(compatibility_validate.exception.code, "compatibility.execution-unavailable")
        with self.assertRaises(FabricError) as compatibility_rollback:
            await compatibility.rollback("deploy", {}, deployment_revision([]))
        self.assertEqual(compatibility_rollback.exception.code, "compatibility.execution-unavailable")


class UnavailableDependencyTests(unittest.TestCase):
    def test_missing_fixed_probe_is_an_explicit_bounded_inventory_result(self) -> None:
        def missing(_command):
            raise FileNotFoundError("/usr/bin/missing-audio-probe")

        provider = build_audio_provider(runner=missing)
        registry = ProviderRegistry()
        registry.register(provider)
        result = __import__("asyncio").run(registry.read("audio.provider", "inspect", {}))
        availability = result["value"]["availability"]
        self.assertFalse(availability["read"])
        self.assertFalse(availability["operation"])
        self.assertEqual(availability["reason"]["code"], "provider.dependency-missing")
        self.assertLess(len(json.dumps(result, allow_nan=False).encode("utf-8")), MAX_FRAME_BYTES)


class ProductionPolicyBoundsTests(unittest.TestCase):
    def test_code_owned_policy_schemas_are_read_with_hard_byte_bounds(self) -> None:
        cases = (
            (
                package_provider_module._load_source_policy,
                package_provider_module.MAX_POLICY_BYTES,
                "packages.policy-too-large",
            ),
            (
                compatibility_provider_module._load_routing_policy,
                compatibility_provider_module.MAX_POLICY_BYTES,
                "compatibility.policy-too-large",
            ),
        )
        for loader, maximum, expected_code in cases:
            with self.subTest(expected_code=expected_code), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                policy = root / "policy.json"
                schema = root / "schema.json"
                policy.write_bytes(b"{}")
                schema.write_bytes(b" " * (maximum + 1))
                with self.assertRaises(FabricError) as too_large:
                    loader(policy, schema)
                self.assertEqual(too_large.exception.code, expected_code)

    def test_code_owned_policies_and_schemas_reject_duplicate_json_keys(self) -> None:
        cases = (
            (
                package_provider_module._load_source_policy,
                "packages.policy-invalid",
            ),
            (
                compatibility_provider_module._load_routing_policy,
                "compatibility.policy-invalid",
            ),
        )
        duplicate_document = b'{"schemaVersion":"v0","schemaVersion":"v0"}'
        duplicate_schema = b'{"type":"object","type":"object"}'
        for loader, expected_code in cases:
            for policy_bytes, schema_bytes in (
                (duplicate_document, b"{}"),
                (b"{}", duplicate_schema),
            ):
                with self.subTest(
                    expected_code=expected_code,
                    schema=schema_bytes == duplicate_schema,
                ), tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    policy = root / "policy.json"
                    schema = root / "schema.json"
                    policy.write_bytes(policy_bytes)
                    schema.write_bytes(schema_bytes)
                    with self.assertRaises(FabricError) as invalid:
                        loader(policy, schema)
                    self.assertEqual(invalid.exception.code, expected_code)


if __name__ == "__main__":
    unittest.main()
