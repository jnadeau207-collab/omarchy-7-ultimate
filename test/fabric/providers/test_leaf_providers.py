from __future__ import annotations

import asyncio
import copy
import json
import subprocess
import tempfile
import time
import unittest
from unittest import mock
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import MappingProxyType
from typing import Any, Callable, Mapping

from omarchy_fabric.models import FabricError, FixedArgvCommand
from omarchy_fabric.provider_registry import ProviderRegistry
from omarchy_fabric.providers import _probe
from omarchy_fabric.providers._engine import state_revision
from omarchy_fabric.providers._identity import stable_resource_id
from omarchy_fabric.providers._probe import ProbeOutput
from omarchy_fabric.providers.audio import provider as audio
from omarchy_fabric.providers.bluetooth import provider as bluetooth
from omarchy_fabric.providers.display import provider as display
from omarchy_fabric.providers.input import provider as input_provider
from omarchy_fabric.providers.network import provider as network
from omarchy_fabric.providers.power import provider as power
from omarchy_fabric.security.principal import EndpointPrincipal, PrincipalKind

FIXTURES = Path(__file__).with_name("fixtures")
SESSION_OPERABLE_DOMAINS = frozenset({"audio", "process"})

MODULES = (display, audio, network, bluetooth, input_provider, power)

def load_fixture(domain: str) -> dict[str, Any]:
    return json.loads((FIXTURES / f"{domain}-v0.json").read_text(encoding="utf-8"))

class FixtureRunner:
    def __init__(self, outputs: Mapping[tuple[str, ...], str | Exception], *, fallback: str | Exception | None = None) -> None:
        self.outputs = dict(outputs)
        self.fallback = fallback
        self.calls: list[tuple[str, ...]] = []

    def __call__(self, command: FixedArgvCommand) -> ProbeOutput:
        self.calls.append(command.argv)
        value = self.outputs.get(command.argv, self.fallback)
        if value is None:
            raise AssertionError(f"unexpected fixed probe: {command.argv!r}")
        if isinstance(value, Exception):
            raise value
        return ProbeOutput(stdout=value, stderr="")

class DivergentBackend:
    def __init__(self, inner: Any, drift_state: Mapping[str, Any]) -> None:
        self.inner = inner
        self.drift_state = copy.deepcopy(dict(drift_state))

    async def snapshot(self):
        return await self.inner.snapshot()

    async def replace(self, resource_id: str, resource: Mapping[str, Any], expected_revision: str):
        await self.inner.replace(resource_id, resource, expected_revision)
        await self.inner.force_state(resource_id, self.drift_state)
        return await self.inner.snapshot()

def fixture_runner(module: Any, *, reordered: bool = False) -> FixtureRunner:
    fixture = load_fixture(module.DOMAIN)
    if module is network:
        devices = fixture["devices"]
        if reordered:
            devices = "\n".join(reversed(devices.rstrip("\n").splitlines())) + "\n"
        return FixtureRunner({network.WIFI_COMMAND.argv: fixture["wifi"], network.DEVICES_COMMAND.argv: devices})
    if module is bluetooth:
        devices = fixture["devices"]
        if reordered:
            devices = "\n".join(reversed(devices.rstrip("\n").splitlines())) + "\n"
        return FixtureRunner(
            {
                bluetooth.SHOW_COMMAND.argv: fixture["show"],
                bluetooth.DEVICES_COMMAND.argv: devices,
                bluetooth.PAIRED_COMMAND.argv: fixture["paired"],
                bluetooth.CONNECTED_COMMAND.argv: fixture["connected"],
            }
        )
    if module is input_provider:
        document = copy.deepcopy(fixture["devices"])
        if reordered:
            document["keyboards"].reverse()
        return FixtureRunner({input_provider.DEVICES_COMMAND.argv: json.dumps(document)})
    if module is display:
        monitors = copy.deepcopy(fixture["monitors"])
        if reordered:
            monitors.reverse()
        return FixtureRunner({display.MONITORS_COMMAND.argv: json.dumps(monitors)})
    if module is audio:
        sinks = copy.deepcopy(fixture["sinks"])
        if reordered:
            sinks.reverse()
            for sink in sinks:
                sink["index"] = int(sink["index"]) + 1000
        return FixtureRunner(
            {
                audio.SINKS_COMMAND.argv: json.dumps(sinks),
                audio.DEFAULT_SINK_COMMAND.argv: fixture["defaultSink"] + "\n",
            }
        )
    if module is power:
        profiles = fixture["profiles"]
        if reordered:
            profiles = "\n".join(reversed(profiles.rstrip("\n").splitlines())) + "\n"
        return FixtureRunner(
            {
                power.PROFILES_COMMAND.argv: profiles,
                power.SOURCE_COMMAND.argv: fixture["source"],
                power.BATTERY_COMMAND.argv: fixture["battery"],
            }
        )
    raise AssertionError(module)

def principal() -> EndpointPrincipal:
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    return EndpointPrincipal(
        principal_id="principal.provider-tests",
        session_id="session.provider-tests",
        uid=1000,
        endpoint_id="shell.provider-tests",
        kind=PrincipalKind.SHELL,
        issued_at=now,
        expires_at=now + timedelta(hours=1),
    )

@dataclass(frozen=True)
class FakeCase:
    module: Any
    resources: list[dict[str, Any]]
    arguments: dict[str, Any]
    expected_state: dict[str, Any]
    drift_state: dict[str, Any]

    @property
    def resource_id(self) -> str:
        return self.arguments["resourceId"]

def fake_cases() -> tuple[FakeCase, ...]:
    display_id = stable_resource_id("display", "output", "eDP-1")
    audio_id = stable_resource_id("audio", "sink", "alsa_output.test")
    bluetooth_id = stable_resource_id("bluetooth", "device", "11:22:33:44:55:66")
    input_id = stable_resource_id("input", "keyboard", "test-keyboard")
    return (
        FakeCase(
            display,
            [
                {
                    "id": display_id,
                    "label": "eDP-1",
                    "kind": "output",
                    "enabled": True,
                    "focused": True,
                    "mode": {"width": 1920, "height": 1200, "refreshHz": 60.0},
                    "position": {"x": 0, "y": 0},
                    "scale": 1.25,
                    "transform": 0,
                    "mirrorOf": None,
                    "dpms": True,
                    "state": {"available": True, "percent": 40},
                }
            ],
            {"resourceId": display_id, "percent": 65},
            {"available": True, "percent": 65},
            {"available": True, "percent": 50},
        ),
        FakeCase(
            audio,
            [
                {
                    "id": audio_id,
                    "label": "Test speakers",
                    "kind": "sink",
                    "default": True,
                    "physical": True,
                    "ports": [],
                    "activePort": None,
                    "state": {
                        "muted": False,
                        "channels": {"front-left": 25, "front-right": 30},
                    },
                }
            ],
            {"resourceId": audio_id, "percent": 60},
            {
                "muted": False,
                "channels": {"front-left": 60, "front-right": 60},
            },
            {
                "muted": False,
                "channels": {"front-left": 35, "front-right": 35},
            },
        ),
        FakeCase(
            network,
            [
                {
                    "id": network.WIFI_ID,
                    "label": "Wi-Fi radio",
                    "kind": "wifi-radio",
                    "state": {"managerRunning": True, "hardwareEnabled": True, "enabled": True},
                }
            ],
            {"resourceId": network.WIFI_ID, "enabled": False},
            {"managerRunning": True, "hardwareEnabled": True, "enabled": False},
            {"managerRunning": True, "hardwareEnabled": False, "enabled": False},
        ),
        FakeCase(
            bluetooth,
            [{"id": bluetooth_id, "label": "Headphones", "kind": "device", "state": {"paired": False, "connected": False}}],
            {"resourceId": bluetooth_id},
            {"paired": True, "connected": True},
            {"paired": True, "connected": False},
        ),
        FakeCase(
            input_provider,
            [
                {
                    "id": input_id,
                    "label": "test-keyboard",
                    "kind": "keyboard",
                    "main": True,
                    "state": {"activeIndex": 0, "activeKeymap": "English", "layouts": ["English", "German"], "switchable": True},
                }
            ],
            {"resourceId": input_id, "layoutIndex": 1},
            {"activeIndex": 1, "activeKeymap": "German", "layouts": ["English", "German"], "switchable": True},
            {"activeIndex": None, "activeKeymap": None, "layouts": ["English", "German"], "switchable": False},
        ),
        FakeCase(
            power,
            [
                {
                    "id": power.RESOURCE_ID,
                    "label": "Power profile",
                    "kind": "profile",
                    "battery": None,
                    "state": {"source": "ac", "activeProfile": "balanced", "availableProfiles": list(power.PROFILES)},
                }
            ],
            {"resourceId": power.RESOURCE_ID, "profile": "performance"},
            {"source": "ac", "activeProfile": "performance", "availableProfiles": list(power.PROFILES)},
            {"source": "battery", "activeProfile": "power-saver", "availableProfiles": list(power.PROFILES)},
        ),
    )

def walk(value: Any):
    yield value
    if isinstance(value, Mapping):
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, (list, tuple)):
        for child in value:
            yield from walk(child)

class ProviderContractTests(unittest.TestCase):
    def test_all_manifests_and_standalone_schemas_are_admitted_and_deeply_immutable(self) -> None:
        registry = ProviderRegistry()
        for module in MODULES:
            with self.subTest(domain=module.DOMAIN):
                provider = module.build_provider(runner=fixture_runner(module))
                registration = registry.register(provider)
                self.assertEqual(registration.provider_id, module.PROVIDER_ID)
                self.assertEqual(registration.state, "available")
                self.assertIsInstance(provider.manifest, MappingProxyType)
                with self.assertRaises(TypeError):
                    provider.manifest["provider"] = "tampered"
                referenced = {
                    reference["id"]
                    for action in provider.manifest["actions"].values()
                    for reference in (action["arguments"], action["result"], action["preflight"], action["state"])
                    if reference is not None
                }
                self.assertEqual(referenced, set(provider.schemas))
                for schema_id, schema in provider.schemas.items():
                    self.assertEqual(schema["$id"], schema_id)
                    self.assertEqual(schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
                    self.assertEqual(schema["x-omarchy-version"], "v0")
                    for node in walk(schema):
                        if isinstance(node, Mapping) and node.get("type") == "object":
                            self.assertIs(node.get("additionalProperties"), False)
                        if isinstance(node, Mapping):
                            self.assertNotIn("$ref", node)

    def test_manifest_action_invariants_are_exact(self) -> None:
        for module in MODULES:
            provider = module.build_provider(runner=fixture_runner(module))
            actions = provider.manifest["actions"]
            read = actions["inspect"]
            operation = actions[module.OPERATION_ACTION]
            with self.subTest(domain=module.DOMAIN):
                self.assertEqual(
                    set(read),
                    {"capability", "mode", "risk", "effects", "arguments", "result", "preflight", "state", "supportsRollback", "supportsCancellation"},
                )
                self.assertEqual((read["mode"], read["risk"], tuple(read["effects"])), ("read", "read-only", ()))
                self.assertIsNone(read["preflight"])
                self.assertIsNone(read["state"])
                self.assertFalse(read["supportsRollback"])
                self.assertFalse(read["supportsCancellation"])
                self.assertEqual(operation["mode"], "operation")
                self.assertIn("mutating", operation["effects"])
                self.assertIsNotNone(operation["preflight"])
                self.assertIsNotNone(operation["state"])
                self.assertTrue(operation["supportsRollback"])
                self.assertFalse(operation["supportsCancellation"])
                self.assertIn(read["capability"], provider.manifest["capabilities"])
                self.assertIn(operation["capability"], provider.manifest["capabilities"])

class RealInventoryTests(unittest.IsolatedAsyncioTestCase):
    async def test_audio_normalizes_every_real_pactl_port_availability_and_rejects_unknown_vocabulary(self) -> None:
        runner = fixture_runner(audio)
        result = await audio.build_provider(runner=runner).read("inspect", {})
        physical = next(resource for resource in result["resources"] if resource["physical"])
        self.assertEqual(
            {port["label"]: port["availability"] for port in physical["ports"]},
            {"Speakers": "yes", "Headphones": "no", "Line Out": "unknown"},
        )

        fixture = load_fixture("audio")
        invalid_sinks = copy.deepcopy(fixture["sinks"])
        invalid_sinks[1]["ports"][0]["availability"] = "maybe available"
        invalid = audio.build_provider(
            runner=FixtureRunner(
                {
                    audio.SINKS_COMMAND.argv: json.dumps(invalid_sinks),
                    audio.DEFAULT_SINK_COMMAND.argv: fixture["defaultSink"] + "\n",
                }
            )
        )
        invalid_result = await invalid.read("inspect", {})
        self.assertFalse(invalid_result["availability"]["read"])
        self.assertEqual(invalid_result["availability"]["reason"]["code"], "provider.probe-invalid")

    async def test_every_real_leaf_runs_only_its_fixed_read_only_probe_and_returns_typed_inventory(self) -> None:
        for module in MODULES:
            runner = fixture_runner(module)
            provider = module.build_provider(runner=runner)
            with self.subTest(domain=module.DOMAIN):
                result = await provider.read("inspect", {})
                self.assertTrue(result["availability"]["read"])
                if module.DOMAIN in SESSION_OPERABLE_DOMAINS:
                    self.assertTrue(result["availability"]["operation"])
                    self.assertIsNone(result["availability"]["reason"])
                else:
                    self.assertFalse(result["availability"]["operation"])
                    self.assertEqual(result["availability"]["reason"]["code"], f"{module.DOMAIN}.operation-read-only")
                self.assertGreaterEqual(len(result["resources"]), 1)
                self.assertRegex(result["revision"], r"^sha256\.[0-9a-f]{64}$")
                self.assertTrue(runner.calls)
                for argv in runner.calls:
                    self.assertTrue(argv[0].startswith("/usr/bin/"))
                    self.assertNotIn("bash", argv[0])
                    self.assertNotIn("-c", argv)

    async def test_display_inspect_treats_hyprctl_none_as_no_mirror(self) -> None:
        fixture = load_fixture("display")
        monitors = copy.deepcopy(fixture["monitors"])
        for monitor in monitors:
            if monitor.get("mirrorOf") == "":
                monitor["mirrorOf"] = "none"
        result = await display.build_provider(
            runner=FixtureRunner({display.MONITORS_COMMAND.argv: json.dumps(monitors)})
        ).read("inspect", {})
        self.assertTrue(result["availability"]["read"])
        by_label = {resource["label"]: resource for resource in result["resources"]}
        self.assertIsNone(by_label["eDP-1"]["mirrorOf"])
        self.assertIsNone(by_label["HDMI-A-1"]["mirrorOf"])
        self.assertEqual(by_label["DP-1"]["mirrorOf"], stable_resource_id("display", "output", "eDP-1"))

        metal = [
            {
                "name": "HDMI-A-1",
                "disabled": False,
                "width": 1920,
                "height": 1080,
                "refreshRate": 60.0,
                "x": 0,
                "y": 0,
                "scale": 1.0,
                "transform": 0,
                "focused": True,
                "mirrorOf": "none",
                "dpmsStatus": True,
            }
        ]
        metal_result = await display.build_provider(
            runner=FixtureRunner({display.MONITORS_COMMAND.argv: json.dumps(metal)})
        ).read("inspect", {})
        self.assertTrue(metal_result["availability"]["read"])
        output = metal_result["resources"][0]
        self.assertEqual(output["label"], "HDMI-A-1")
        self.assertEqual(output["mode"], {"width": 1920, "height": 1080, "refreshHz": 60.0})
        self.assertEqual(output["scale"], 1.0)
        self.assertIsNone(output["mirrorOf"])

    async def test_inventory_identity_and_revision_ignore_probe_order_and_transient_audio_index(self) -> None:
        for module in MODULES:
            first = await module.build_provider(runner=fixture_runner(module)).read("inspect", {})
            second = await module.build_provider(runner=fixture_runner(module, reordered=True)).read("inspect", {})
            with self.subTest(domain=module.DOMAIN):
                self.assertEqual(first["resources"], second["resources"])
                self.assertEqual(first["revision"], second["revision"])

    async def test_native_selectors_are_never_resource_ids(self) -> None:
        native_values = {
            "display": ("eDP-1", "DP-1"),
            "audio": ("alsa_output", "effect_output"),
            "network": ("wlan0", "eth0"),
            "bluetooth": ("11:22:33:44:55:66", "aa:bb:cc:dd:ee:ff"),
            "input": ("at-translated", "weird/usb"),
            "power": (),
        }
        for module in MODULES:
            result = await module.build_provider(runner=fixture_runner(module)).read("inspect", {})
            ids = [resource["id"] for resource in result["resources"]]
            with self.subTest(domain=module.DOMAIN):
                for resource_id in ids:
                    for native in native_values[module.DOMAIN]:
                        self.assertNotIn(native.lower(), resource_id.lower())
                if module is not power and module is not network:
                    self.assertTrue(any(resource_id.startswith(f"{module.DOMAIN}.") for resource_id in ids))

    async def test_missing_and_malformed_probes_are_explicit_unavailable_results(self) -> None:
        for module in MODULES:
            missing = module.build_provider(runner=FixtureRunner({}, fallback=FileNotFoundError("fixed-probe")))
            malformed = module.build_provider(runner=FixtureRunner({}, fallback="not valid provider data"))
            with self.subTest(domain=module.DOMAIN):
                missing_result = await missing.read("inspect", {})
                self.assertFalse(missing_result["availability"]["read"])
                self.assertEqual(missing_result["availability"]["reason"]["code"], "provider.dependency-missing")
                malformed_result = await malformed.read("inspect", {})
                self.assertFalse(malformed_result["availability"]["read"])
                self.assertEqual(malformed_result["availability"]["reason"]["code"], "provider.probe-invalid")

    async def test_real_operation_hooks_fail_closed_without_any_mutation_command(self) -> None:
        actor = principal()
        for module in MODULES:
            case = next(case for case in fake_cases() if case.module is module)
            runner = fixture_runner(module)
            provider = module.build_provider(runner=runner)
            with self.subTest(domain=module.DOMAIN):
                with self.assertRaises(FabricError) as unavailable:
                    await provider.preflight(module.OPERATION_ACTION, case.arguments, actor)
                if module.DOMAIN in SESSION_OPERABLE_DOMAINS:
                    self.assertEqual(unavailable.exception.code, f"{module.DOMAIN}.resource-unavailable")
                    with self.assertRaises(FabricError) as refused:
                        await provider.backend.replace(case.arguments["resourceId"], {}, "sha256." + "0" * 64)
                    self.assertEqual(refused.exception.code, f"{module.DOMAIN}.operation-unavailable")
                else:
                    self.assertEqual(unavailable.exception.code, f"{module.DOMAIN}.operation-unavailable")
                self.assertTrue(runner.calls)
                self.assertTrue(all(call[0].startswith("/usr/bin/") for call in runner.calls))

    async def test_all_readers_cross_the_central_registry_same_path(self) -> None:
        registry = ProviderRegistry(clock=lambda: 42.0)
        direct: dict[str, Mapping[str, Any]] = {}
        for module in MODULES:
            provider = module.build_provider(runner=fixture_runner(module))
            registry.register(provider)
            direct[module.PROVIDER_ID] = await provider.read("inspect", {})
        for module in MODULES:
            provider_result = await registry.read(module.PROVIDER_ID, "inspect", {})
            with self.subTest(domain=module.DOMAIN):
                self.assertEqual(provider_result["value"], direct[module.PROVIDER_ID])
                self.assertEqual(provider_result["capability"], f"{module.DOMAIN}.inspect")
                self.assertEqual(provider_result["observedAt"], 42.0)

class FakeLifecycleTests(unittest.IsolatedAsyncioTestCase):
    async def test_every_fake_preflight_crosses_the_central_typed_preflight_seam(self) -> None:
        registry = ProviderRegistry(clock=lambda: 84.0)
        actor = principal()
        for case in fake_cases():
            provider = case.module.build_fake_provider(copy.deepcopy(case.resources))
            registry.register(provider)
            plan = await registry.preflight(
                case.module.PROVIDER_ID,
                case.module.OPERATION_ACTION,
                case.arguments,
                actor,
            )
            with self.subTest(domain=case.module.DOMAIN):
                self.assertEqual(plan["provider"], case.module.PROVIDER_ID)
                self.assertEqual(plan["action"], case.module.OPERATION_ACTION)
                self.assertEqual(plan["capability"], provider.manifest["actions"][case.module.OPERATION_ACTION]["capability"])
                self.assertEqual(plan["preflight"]["normalizedArguments"], case.arguments)
                self.assertEqual(plan["preflight"]["proposedState"]["value"], case.expected_state)
                self.assertEqual(plan["observedAt"], 84.0)
                self.assertEqual(len(plan["providerFingerprint"]), 64)
                self.assertEqual(provider.backend.write_count, 0)

    async def test_every_domain_executes_preflight_apply_validate_noop_and_exact_rollback(self) -> None:
        actor = principal()
        for case in fake_cases():
            provider = case.module.build_fake_provider(copy.deepcopy(case.resources))
            with self.subTest(domain=case.module.DOMAIN):
                preflight = await provider.preflight(case.module.OPERATION_ACTION, case.arguments, actor)
                self.assertTrue(preflight["changed"])
                self.assertEqual(preflight["proposedState"]["value"], case.expected_state)
                self.assertEqual(provider.backend.write_count, 0)
                applied = await provider.apply(case.module.OPERATION_ACTION, case.arguments, preflight["stateRevision"])
                self.assertTrue(applied["changed"])
                self.assertEqual(applied["changeState"], "complete")
                self.assertEqual(applied["state"]["value"], case.expected_state)
                self.assertEqual(provider.backend.write_count, 1)
                validated = await provider.validate(case.module.OPERATION_ACTION, case.arguments, applied["state"])
                self.assertFalse(validated["changed"])
                no_op = await provider.apply(case.module.OPERATION_ACTION, case.arguments, applied["stateRevision"])
                self.assertFalse(no_op["changed"])
                self.assertEqual(no_op["changeState"], "none")
                self.assertEqual(provider.backend.write_count, 1)
                rolled_back = await provider.rollback(
                    case.module.OPERATION_ACTION,
                    preflight["currentState"],
                    applied["stateRevision"],
                )
                self.assertTrue(rolled_back["changed"])
                self.assertEqual(rolled_back["state"], preflight["currentState"])
                self.assertEqual(provider.backend.write_count, 2)

    async def test_fake_state_survives_provider_restart_and_validates_on_the_same_contract(self) -> None:
        actor = principal()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for case in fake_cases():
                state_path = root / f"{case.module.DOMAIN}.json"
                provider = case.module.build_fake_provider(copy.deepcopy(case.resources), state_path=state_path)
                preflight = await provider.preflight(case.module.OPERATION_ACTION, case.arguments, actor)
                applied = await provider.apply(case.module.OPERATION_ACTION, case.arguments, preflight["stateRevision"])
                restarted = case.module.build_fake_provider(copy.deepcopy(case.resources), state_path=state_path)
                with self.subTest(domain=case.module.DOMAIN):
                    inventory = await restarted.read("inspect", {})
                    resource = next(resource for resource in inventory["resources"] if resource["id"] == case.resource_id)
                    self.assertEqual(resource["state"], case.expected_state)
                    validated = await restarted.validate(case.module.OPERATION_ACTION, case.arguments, applied["state"])
                    self.assertEqual(validated["state"], applied["state"])

    async def test_stale_state_duplicate_resources_and_backend_failures_are_contained(self) -> None:
        actor = principal()
        for case in fake_cases():
            with self.subTest(domain=case.module.DOMAIN):
                stale_provider = case.module.build_fake_provider(copy.deepcopy(case.resources))
                preflight = await stale_provider.preflight(case.module.OPERATION_ACTION, case.arguments, actor)
                await stale_provider.backend.force_state(case.resource_id, case.drift_state)
                with self.assertRaises(FabricError) as stale:
                    await stale_provider.apply(case.module.OPERATION_ACTION, case.arguments, preflight["stateRevision"])
                self.assertEqual(stale.exception.code, f"{case.module.DOMAIN}.state-stale")
                self.assertEqual(stale_provider.backend.write_count, 0)

                duplicate = case.module.build_fake_provider(copy.deepcopy(case.resources + case.resources))
                with self.assertRaises(FabricError) as invalid:
                    await duplicate.read("inspect", {})
                self.assertEqual(invalid.exception.code, f"{case.module.DOMAIN}.backend-invalid")

                failing = case.module.build_fake_provider(copy.deepcopy(case.resources), fail_on=frozenset({"apply"}))
                failure_preflight = await failing.preflight(case.module.OPERATION_ACTION, case.arguments, actor)
                with self.assertRaises(FabricError) as failed:
                    await failing.apply(case.module.OPERATION_ACTION, case.arguments, failure_preflight["stateRevision"])
                self.assertEqual(failed.exception.code, f"{case.module.DOMAIN}.fake-apply-failed")
                self.assertEqual(failing.backend.write_count, 0)

    async def test_post_apply_drift_is_reported_unknown_and_exact_rollback_recovers(self) -> None:
        actor = principal()
        for case in fake_cases():
            provider = case.module.build_fake_provider(copy.deepcopy(case.resources))
            original_backend = provider.backend
            provider.backend = DivergentBackend(original_backend, case.drift_state)
            preflight = await provider.preflight(case.module.OPERATION_ACTION, case.arguments, actor)
            with self.subTest(domain=case.module.DOMAIN):
                with self.assertRaises(FabricError) as drifted:
                    await provider.apply(case.module.OPERATION_ACTION, case.arguments, preflight["stateRevision"])
                self.assertEqual(drifted.exception.code, f"{case.module.DOMAIN}.validation-failed")
                self.assertEqual(drifted.exception.change_state, "unknown")
                self.assertIn(f"{case.module.DOMAIN}.rollback", drifted.exception.recovery_actions)
                provider.backend = original_backend
                recovered = await provider.rollback(
                    case.module.OPERATION_ACTION,
                    preflight["currentState"],
                    state_revision(case.drift_state),
                )
                self.assertEqual(recovered["state"], preflight["currentState"])

    async def test_closed_arguments_principal_and_preconditions_fail_with_structured_errors(self) -> None:
        actor = principal()
        for case in fake_cases():
            provider = case.module.build_fake_provider(copy.deepcopy(case.resources))
            extra = {**case.arguments, "unexpected": True}
            with self.subTest(domain=case.module.DOMAIN):
                with self.assertRaises(FabricError) as invalid:
                    await provider.preflight(case.module.OPERATION_ACTION, extra, actor)
                self.assertEqual(invalid.exception.code, f"{case.module.DOMAIN}.contract-invalid")
                with self.assertRaises(FabricError) as unauthenticated:
                    await provider.preflight(case.module.OPERATION_ACTION, case.arguments, object())
                self.assertEqual(unauthenticated.exception.code, "principal.required")
                with self.assertRaises(FabricError) as unknown:
                    await provider.read("missing", {})
                self.assertEqual(unknown.exception.code, f"{case.module.DOMAIN}.action-unavailable")

        network_case = next(case for case in fake_cases() if case.module is network)
        with self.assertRaises(FabricError) as credential:
            await network.build_fake_provider(copy.deepcopy(network_case.resources)).preflight(
                network.OPERATION_ACTION,
                {**network_case.arguments, "password": "must-never-enter-this-contract"},
                actor,
            )
        self.assertEqual(credential.exception.code, "network.contract-invalid")

        display_case = next(case for case in fake_cases() if case.module is display)
        unavailable_resource = copy.deepcopy(display_case.resources)
        unavailable_resource[0]["state"] = {"available": False, "percent": None}
        with self.assertRaises(FabricError) as precondition:
            await display.build_fake_provider(unavailable_resource).preflight(
                display.OPERATION_ACTION,
                display_case.arguments,
                actor,
            )
        self.assertEqual(precondition.exception.code, "display.precondition-failed")

class ProbeBoundaryTests(unittest.TestCase):
    def test_probe_json_rejects_duplicate_keys_and_non_finite_numbers(self) -> None:
        for payload in ('{"value":1,"value":2}', '{"value":NaN}', '{"value":Infinity}'):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                _probe.parse_probe_json(payload)

    def test_probe_errors_are_normalized_without_backend_exception_text(self) -> None:
        cases = (
            (FileNotFoundError("/private/path"), "provider.dependency-missing"),
            (TimeoutError("slow"), "provider.probe-timeout"),
            (subprocess.CalledProcessError(7, ("fixed",), stderr="bounded"), "provider.probe-failed"),
            (ValueError("bad"), "provider.probe-invalid"),
        )
        for error, code in cases:
            with self.subTest(code=code):
                normalized = _probe.probe_error("display", error)
                self.assertEqual(normalized.code, code)
                if isinstance(error, subprocess.CalledProcessError):
                    self.assertEqual(normalized.detail, "exit status 7")
                    self.assertNotIn("bounded", normalized.detail)

    def test_real_probe_runner_bounds_combined_output_and_terminates_timeouts(self) -> None:
        successful = _probe.run_probe(FixedArgvCommand("/usr/bin/printf", ("ok",)))
        self.assertEqual(successful, ProbeOutput(stdout="ok", stderr=""))

        oversized = FixedArgvCommand(
            "/usr/bin/python3",
            ("-c", f"import sys; sys.stdout.write('x' * {_probe.MAX_PROBE_BYTES + 1})"),
        )
        with self.assertRaises(ValueError):
            _probe.run_probe(oversized)

        sleeping = FixedArgvCommand("/usr/bin/python3", ("-c", "import time; time.sleep(10)"))
        with mock.patch.object(_probe, "MAX_PROBE_SECONDS", 0.05):
            started = time.monotonic()
            with self.assertRaises(TimeoutError):
                _probe.run_probe(sleeping)
            self.assertLess(time.monotonic() - started, 1.0)

if __name__ == "__main__":
    unittest.main()
