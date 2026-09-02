from __future__ import annotations

import asyncio
import copy
import tempfile
import unittest
from unittest import mock
from pathlib import Path

from omarchy_fabric.daemon import DaemonConfig, FabricDaemon
from omarchy_fabric.models import FabricError
from omarchy_fabric.protocol import FabricClient
from omarchy_fabric.provider_registry import ProviderAvailability, ProviderRegistry
from omarchy_fabric.security import EndpointAdmission, PrincipalKind, SessionBindingStore

SCHEMA_DIALECT = "https://json-schema.org/draft/2020-12/schema"

def object_schema(
    schema_id: str,
    properties: dict[str, object],
    required: tuple[str, ...],
) -> dict[str, object]:
    return {
        "$schema": SCHEMA_DIALECT,
        "$id": schema_id,
        "x-omarchy-version": "v0",
        "type": "object",
        "required": list(required),
        "properties": properties,
        "additionalProperties": False,
    }

ARGUMENTS_ID = "urn:omarchy:fabric:provider:test-display:inspect-arguments"
RESULT_ID = "urn:omarchy:fabric:provider:test-display:inspect-result"
PREFLIGHT_ID = "urn:omarchy:fabric:provider:test-display:set-preflight"
STATE_ID = "urn:omarchy:fabric:provider:test-display:set-state"

def schema_reference(schema_id: str) -> dict[str, str]:
    return {"id": schema_id, "version": "v0"}

def read_manifest(
    *,
    provider_id: str = "test.display",
    minimum: int = 0,
    maximum: int = 0,
) -> dict[str, object]:
    return {
        "schemaVersion": "v0",
        "provider": provider_id,
        "providerVersion": "v0.1",
        "minFabricProtocol": minimum,
        "maxFabricProtocol": maximum,
        "capabilities": ["display.inspect"],
        "actions": {
            "inspect": {
                "capability": "display.inspect",
                "mode": "read",
                "risk": "read-only",
                "effects": [],
                "arguments": schema_reference(ARGUMENTS_ID),
                "result": schema_reference(RESULT_ID),
                "preflight": None,
                "state": None,
                "supportsRollback": False,
                "supportsCancellation": False,
            }
        },
    }

def read_schemas() -> dict[str, dict[str, object]]:
    return {
        ARGUMENTS_ID: object_schema(
            ARGUMENTS_ID,
            {"connector": {"type": "string", "minLength": 1, "maxLength": 64}},
            ("connector",),
        ),
        RESULT_ID: object_schema(
            RESULT_ID,
            {
                "connector": {"type": "string", "minLength": 1, "maxLength": 64},
                "enabled": {"type": "boolean"},
            },
            ("connector", "enabled"),
        ),
    }

class ReadProvider:
    def __init__(
        self,
        *,
        manifest: dict[str, object] | None = None,
        result: object | None = None,
    ) -> None:
        self.manifest = manifest or read_manifest()
        self.schemas = read_schemas()
        self.result = result or {"connector": "HDMI-A-1", "enabled": True}
        self.read_calls: list[tuple[str, dict[str, object]]] = []

    async def read(self, action: str, arguments: dict[str, object]) -> object:
        self.read_calls.append((action, copy.deepcopy(arguments)))
        return copy.deepcopy(self.result)

class BlockingProvider(ReadProvider):
    def __init__(self) -> None:
        super().__init__()
        self.entered = asyncio.Event()
        self.release = asyncio.Event()

    async def read(self, action: str, arguments: dict[str, object]) -> object:
        self.entered.set()
        await self.release.wait()
        return await super().read(action, arguments)

class OperationProvider(ReadProvider):
    def __init__(self) -> None:
        manifest = read_manifest()
        manifest["capabilities"] = ["display.configure"]
        manifest["actions"] = {
            "set-mode": {
                "capability": "display.configure",
                "mode": "operation",
                "risk": "consequential",
                "effects": ["mutating"],
                "arguments": schema_reference(ARGUMENTS_ID),
                "result": schema_reference(RESULT_ID),
                "preflight": schema_reference(PREFLIGHT_ID),
                "state": schema_reference(STATE_ID),
                "supportsRollback": True,
                "supportsCancellation": True,
            }
        }
        super().__init__(manifest=manifest)
        self.schemas[PREFLIGHT_ID] = object_schema(
            PREFLIGHT_ID,
            {"summary": {"type": "string", "minLength": 1, "maxLength": 160}},
            ("summary",),
        )
        self.schemas[STATE_ID] = object_schema(
            STATE_ID,
            {"revision": {"type": "string", "minLength": 1, "maxLength": 128}},
            ("revision",),
        )

    async def preflight(self, *args: object) -> object:
        return {"summary": "change display mode"}

    async def apply(self, *args: object) -> object:
        return {"connector": "HDMI-A-1", "enabled": True}

    async def validate(self, *args: object) -> object:
        return {"revision": "revision.2"}

    async def rollback(self, *args: object) -> object:
        return {"revision": "revision.1"}

class ProviderRegistryTests(unittest.IsolatedAsyncioTestCase):
    def test_registration_catalog_and_identical_registration_are_stable(self) -> None:
        events: list[tuple[str, dict[str, object]]] = []
        clock = iter((10.0, 11.0, 12.0)).__next__
        registry = ProviderRegistry(
            clock=clock,
            event_sink=lambda topic, payload: events.append((topic, dict(payload))),
        )
        provider = ReadProvider()
        registered = registry.register(provider)
        unchanged = registry.register(ReadProvider())

        self.assertEqual(registered.disposition, "registered")
        self.assertEqual(registered.generation, 1)
        self.assertEqual(registered.state, "available")
        self.assertEqual(unchanged.disposition, "unchanged")
        self.assertEqual(registry.provider_count, 1)
        self.assertEqual(registry.available_count, 1)
        catalog = registry.catalog()
        self.assertEqual(catalog[0]["manifest"]["provider"], "test.display")
        self.assertEqual(catalog[0]["registeredAt"], 10.0)
        self.assertEqual(len(catalog[0]["fingerprint"]), 64)
        catalog[0]["manifest"]["provider"] = "tampered"
        self.assertEqual(registry.catalog()[0]["manifest"]["provider"], "test.display")
        self.assertEqual(events[0][0], "provider.lifecycle")
        self.assertEqual(events[0][1]["transition"], "registered")

    async def test_read_validates_arguments_and_results(self) -> None:
        provider = ReadProvider()
        registry = ProviderRegistry(clock=lambda: 50.0)
        registry.register(provider)

        result = await registry.read("test.display", "inspect", {"connector": "HDMI-A-1"})
        self.assertEqual(result["value"]["enabled"], True)
        self.assertEqual(result["generation"], 1)
        self.assertEqual(result["capability"], "display.inspect")
        self.assertEqual(provider.read_calls, [("inspect", {"connector": "HDMI-A-1"})])

        with self.assertRaises(FabricError) as bad_arguments:
            await registry.read("test.display", "inspect", {"connector": 42})
        self.assertEqual(bad_arguments.exception.code, "provider.invalid-arguments")
        self.assertEqual(len(provider.read_calls), 1)

        provider.result = {"connector": "HDMI-A-1", "enabled": "yes"}
        with self.assertRaises(FabricError) as bad_result:
            await registry.read("test.display", "inspect", {"connector": "HDMI-A-1"})
        self.assertEqual(bad_result.exception.code, "provider.invalid-result")

    async def test_unknown_unavailable_and_mutating_paths_fail_closed(self) -> None:
        registry = ProviderRegistry()
        with self.assertRaises(FabricError) as missing:
            await registry.read("test.missing", "inspect", {})
        self.assertEqual(missing.exception.code, "provider.unavailable")

        registry.register(ReadProvider())
        with self.assertRaises(FabricError) as action:
            await registry.read("test.display", "missing", {"connector": "HDMI-A-1"})
        self.assertEqual(action.exception.code, "provider.action-unavailable")

        operation_registry = ProviderRegistry()
        operation_registry.register(OperationProvider())
        with self.assertRaises(FabricError) as mutation:
            await operation_registry.read(
                "test.display",
                "set-mode",
                {"connector": "HDMI-A-1"},
            )
        self.assertEqual(mutation.exception.code, "operation.durable-route-required")

    async def test_operation_preflight_is_typed_but_exposes_no_apply_route(self) -> None:
        registry = ProviderRegistry(clock=lambda: 75.0)
        provider = OperationProvider()
        registry.register(provider)
        principal, _credential = SessionBindingStore().issue(
            1000,
            EndpointAdmission("endpoint.shell", PrincipalKind.SHELL),
        )

        preflight = await registry.preflight(
            "test.display",
            "set-mode",
            {"connector": "HDMI-A-1"},
            principal,
        )
        self.assertEqual(preflight["preflight"], {"summary": "change display mode"})
        self.assertEqual(preflight["capability"], "display.configure")
        self.assertEqual(preflight["risk"], "consequential")
        self.assertEqual(preflight["effects"], ["mutating"])
        self.assertEqual(len(preflight["providerFingerprint"]), 64)
        self.assertFalse(hasattr(registry, "apply"))

        read_registry = ProviderRegistry()
        read_registry.register(ReadProvider())
        with self.assertRaises(FabricError) as read_mode:
            await read_registry.preflight(
                "test.display",
                "inspect",
                {"connector": "HDMI-A-1"},
                principal,
            )
        self.assertEqual(read_mode.exception.code, "provider.action-mode-invalid")

    async def test_incompatible_protocol_is_catalogued_but_never_dispatched(self) -> None:
        registry = ProviderRegistry(protocol_version=0)
        registration = registry.register(
            ReadProvider(manifest=read_manifest(minimum=1, maximum=2))
        )
        self.assertEqual(registration.state, "incompatible")
        self.assertEqual(registry.catalog()[0]["state"], "incompatible")
        with self.assertRaises(FabricError) as incompatible:
            await registry.read("test.display", "inspect", {"connector": "HDMI-A-1"})
        self.assertEqual(incompatible.exception.code, "provider.incompatible-version")
        self.assertEqual(incompatible.exception.recovery_actions, ("system.update",))

    async def test_generation_guards_disconnect_reregistration_and_inflight_reads(self) -> None:
        registry = ProviderRegistry(clock=iter((1.0, 2.0, 3.0, 4.0, 5.0)).__next__)
        provider = BlockingProvider()
        registry.register(provider)
        read_task = asyncio.create_task(
            registry.read("test.display", "inspect", {"connector": "HDMI-A-1"})
        )
        await asyncio.wait_for(provider.entered.wait(), timeout=1)
        disconnected = registry.mark_unavailable(
            "test.display",
            expected_generation=1,
            detail="test transport disconnected",
        )
        self.assertEqual(disconnected.generation, 2)
        provider.release.set()
        with self.assertRaises(FabricError) as changed:
            await read_task
        self.assertEqual(changed.exception.code, "provider.changed-during-read")

        with self.assertRaises(FabricError) as stale:
            registry.reregister(ReadProvider(), expected_generation=1)
        self.assertEqual(stale.exception.code, "provider.generation-conflict")
        replacement = registry.reregister(ReadProvider(), expected_generation=2)
        self.assertEqual(replacement.generation, 3)
        self.assertEqual(replacement.state, "available")
        value = await registry.read(
            "test.display",
            "inspect",
            {"connector": "HDMI-A-1"},
        )
        self.assertEqual(value["generation"], 3)

    def test_unavailable_detail_is_printable_and_bounded_by_utf8_bytes(self) -> None:
        invalid_details = (
            "contains\x00nul",
            "contains\nnewline",
            "contains\ttab",
            "a" * 501,
            "é" * 251,
            "\ud800",
        )
        for detail in invalid_details:
            with self.subTest(representation=ascii(detail)):
                registry = ProviderRegistry(clock=lambda: 1.0)
                registry.register(ReadProvider())
                with self.assertRaises(FabricError) as invalid:
                    registry.mark_unavailable(
                        "test.display",
                        expected_generation=1,
                        detail=detail,
                    )
                self.assertEqual(invalid.exception.code, "provider.invalid-lifecycle")
                self.assertNotIn("contains", invalid.exception.to_dict().get("detail", ""))
                entry = registry.catalog()[0]
                self.assertEqual(entry["generation"], 1)
                self.assertEqual(entry["state"], "available")
                self.assertEqual(entry["detail"], "")

        registry = ProviderRegistry(clock=iter((1.0, 2.0)).__next__)
        registry.register(ReadProvider())
        accepted = registry.mark_unavailable(
            "test.display",
            expected_generation=1,
            detail="é" * 250,
        )
        self.assertEqual(accepted.state, "unavailable")
        self.assertEqual(registry.catalog()[0]["detail"], "é" * 250)

    def test_initial_availability_uses_the_same_closed_detail_contract(self) -> None:
        available = ReadProvider()
        available.availability = ProviderAvailability("available", "")
        self.assertEqual(ProviderRegistry().register(available).state, "available")

        invalid_declarations = (
            ProviderAvailability("degraded", ""),
            ProviderAvailability("unknown", "bounded but unsupported"),
            ProviderAvailability("unavailable", "contains\nnewline"),
            ProviderAvailability("unavailable", "é" * 251),
        )
        for declaration in invalid_declarations:
            with self.subTest(declaration=declaration):
                provider = ReadProvider()
                provider.availability = declaration
                with self.assertRaises(FabricError) as invalid:
                    ProviderRegistry().register(provider)
                self.assertEqual(invalid.exception.code, "provider.invalid-availability")

    async def test_timeouts_and_unstructured_failures_are_normalized(self) -> None:
        provider = BlockingProvider()
        registry = ProviderRegistry()
        registry.register(provider)
        with mock.patch(
            "omarchy_fabric.provider_registry.MAX_PROVIDER_READ_SECONDS",
            0.01,
        ):
            with self.assertRaises(FabricError) as timeout:
                await registry.read(
                    "test.display",
                    "inspect",
                    {"connector": "HDMI-A-1"},
                )
        self.assertEqual(timeout.exception.code, "provider.timeout")

        class BrokenProvider(ReadProvider):
            async def read(self, action: str, arguments: dict[str, object]) -> object:
                raise RuntimeError("secret implementation detail")

        broken_registry = ProviderRegistry()
        broken_registry.register(BrokenProvider())
        with self.assertRaises(FabricError) as failed:
            await broken_registry.read(
                "test.display",
                "inspect",
                {"connector": "HDMI-A-1"},
            )
        self.assertEqual(failed.exception.code, "provider.failed")
        self.assertEqual(failed.exception.detail, "RuntimeError")
        self.assertNotIn("secret", failed.exception.to_dict()["detail"])

    def test_manifest_schema_and_adapter_errors_are_rejected_at_admission(self) -> None:
        registry = ProviderRegistry()

        bad_capability = ReadProvider()
        bad_capability.manifest["actions"]["inspect"]["capability"] = "network.inspect"
        with self.assertRaises(FabricError) as capability:
            registry.register(bad_capability)
        self.assertEqual(capability.exception.code, "provider.invalid-manifest")

        effectful_read = ReadProvider()
        effectful_read.manifest["actions"]["inspect"]["effects"] = ["mutating"]
        with self.assertRaises(FabricError) as effects:
            registry.register(effectful_read)
        self.assertEqual(effects.exception.code, "provider.invalid-manifest")

        missing_schema = ReadProvider()
        missing_schema.schemas.pop(RESULT_ID)
        with self.assertRaises(FabricError) as schemas:
            registry.register(missing_schema)
        self.assertEqual(schemas.exception.code, "provider.invalid-schemas")

        wrong_version = ReadProvider()
        wrong_version.schemas[RESULT_ID]["x-omarchy-version"] = "v1"
        with self.assertRaises(FabricError) as version:
            registry.register(wrong_version)
        self.assertEqual(version.exception.code, "provider.invalid-schemas")

        open_object = ReadProvider()
        open_object.schemas[RESULT_ID]["additionalProperties"] = True
        with self.assertRaises(FabricError) as openness:
            registry.register(open_object)
        self.assertEqual(openness.exception.code, "provider.invalid-schemas")

        external_reference = ReadProvider()
        external_reference.schemas[RESULT_ID]["properties"]["enabled"] = {
            "$ref": "https://example.invalid/untrusted-schema.json"
        }
        with self.assertRaises(FabricError) as external:
            registry.register(external_reference)
        self.assertEqual(external.exception.code, "provider.invalid-schemas")

        unresolved_reference = ReadProvider()
        unresolved_reference.schemas[RESULT_ID]["properties"]["enabled"] = {
            "$ref": "#/$defs/missing"
        }
        with self.assertRaises(FabricError) as unresolved:
            registry.register(unresolved_reference)
        self.assertEqual(unresolved.exception.code, "provider.invalid-schemas")

        class SyncProvider(ReadProvider):
            def read(self, action: str, arguments: dict[str, object]) -> object:
                return self.result

        with self.assertRaises(FabricError) as synchronous:
            registry.register(SyncProvider())
        self.assertEqual(synchronous.exception.code, "provider.invalid-adapter")

    def test_launch_plane_operations_admit_and_effectless_operations_do_not(self) -> None:
        launched = OperationProvider()
        launched.manifest["actions"]["set-mode"]["effects"] = ["launch"]
        launched.manifest["actions"]["set-mode"]["supportsRollback"] = False
        registration = ProviderRegistry().register(launched)
        self.assertEqual(registration.provider_id, "test.display")

        network_only = OperationProvider()
        network_only.manifest["actions"]["set-mode"]["effects"] = ["network"]
        with self.assertRaises(FabricError) as network:
            ProviderRegistry().register(network_only)
        self.assertEqual(network.exception.code, "provider.invalid-manifest")

        empty = OperationProvider()
        empty.manifest["actions"]["set-mode"]["effects"] = []
        with self.assertRaises(FabricError) as missing:
            ProviderRegistry().register(empty)
        self.assertEqual(missing.exception.code, "provider.invalid-manifest")

    def test_registration_conflicts_require_explicit_generation_handoff(self) -> None:
        registry = ProviderRegistry()
        registry.register(ReadProvider())
        changed = read_manifest()
        changed["providerVersion"] = "v0.2"
        with self.assertRaises(FabricError) as conflict:
            registry.register(ReadProvider(manifest=changed))
        self.assertEqual(conflict.exception.code, "provider.registration-conflict")

        replacement = registry.reregister(
            ReadProvider(manifest=changed),
            expected_generation=1,
        )
        self.assertEqual(replacement.disposition, "reregistered")
        self.assertEqual(replacement.generation, 2)
        self.assertEqual(registry.catalog()[0]["manifest"]["providerVersion"], "v0.2")

class TypedProviderRpcTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        operation_provider = OperationProvider()
        operation_provider.manifest["provider"] = "test.operation-display"
        self.daemon = FabricDaemon(
            DaemonConfig(
                socket_path=root / "runtime" / "fabric.sock",
                database_path=root / "state" / "fabric.db",
                typed_providers=(ReadProvider(), operation_provider),
            )
        )
        await self.daemon.start()
        self.client = FabricClient(
            self.daemon.config.socket_path,
            client_name="typed-provider-rpc-test",
        )
        await self.client.connect()

    async def asyncTearDown(self) -> None:
        await self.client.close()
        await self.daemon.stop("test-complete")
        self.temporary.cleanup()

    async def test_catalog_health_and_typed_read_cross_the_real_socket(self) -> None:
        health = await self.client.request("health")
        catalog = await self.client.request("provider.catalog")
        lifecycle = await self.client.request(
            "events.subscribe",
            {"topics": ["provider.lifecycle"], "after": 0, "limit": 8},
        )
        result = await self.client.request(
            "provider.read",
            {
                "provider": "test.display",
                "action": "inspect",
                "arguments": {"connector": "HDMI-A-1"},
            },
        )

        self.assertEqual(health["providers"]["typed"], 2)
        self.assertEqual(health["providers"]["availableTyped"], 2)
        self.assertEqual(health["providers"]["degradedTyped"], 0)
        self.assertEqual(health["providers"]["usableTyped"], 2)
        self.assertEqual(
            [entry["manifest"]["provider"] for entry in catalog["providers"]],
            ["test.display", "test.operation-display"],
        )
        self.assertEqual(result["value"], {"connector": "HDMI-A-1", "enabled": True})
        self.assertEqual(result["providerVersion"], "v0.1")
        self.assertEqual(len(lifecycle["replay"]), 2)
        self.assertEqual(
            [event["payload"]["transition"] for event in lifecycle["replay"]],
            ["registered", "registered"],
        )
        await self.client.request(
            "events.unsubscribe",
            {"subscriptionId": lifecycle["subscriptionId"]},
        )

    async def test_rpc_rejects_unknown_fields_invalid_values_and_mutation_bypass(self) -> None:
        with self.assertRaises(FabricError) as unknown:
            await self.client.request(
                "provider.read",
                {
                    "provider": "test.display",
                    "action": "inspect",
                    "arguments": {"connector": "HDMI-A-1"},
                    "unexpected": True,
                },
            )
        self.assertEqual(unknown.exception.code, "rpc.invalid-params")

        with self.assertRaises(FabricError) as invalid:
            await self.client.request(
                "provider.read",
                {
                    "provider": "test.display",
                    "action": "inspect",
                    "arguments": {"connector": 42},
                },
            )
        self.assertEqual(invalid.exception.code, "provider.invalid-arguments")

        with self.assertRaises(FabricError) as mutation:
            await self.client.request(
                "provider.read",
                {
                    "provider": "test.operation-display",
                    "action": "set-mode",
                    "arguments": {"connector": "HDMI-A-1"},
                },
            )
        self.assertEqual(mutation.exception.code, "operation.durable-route-required")

if __name__ == "__main__":
    unittest.main()
