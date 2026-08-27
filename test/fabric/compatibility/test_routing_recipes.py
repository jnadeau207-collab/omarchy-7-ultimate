from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator

from omarchy_fabric.models import FabricError
from omarchy_fabric.provider_registry import ProviderRegistry
from omarchy_fabric.providers.compatibility.adapters import command_matrix, route_adapter
from omarchy_fabric.providers.compatibility.recipes import RecipeCatalog
from omarchy_fabric.providers.packages.identity import revision

from helper import arguments, host, principal, provider, recipe_document, recipes, request, reviewed_request


class CompatibilityRoutingTests(unittest.IsolatedAsyncioTestCase):
    async def test_all_six_routes_and_honest_unsupported_state(self):
        value = provider()
        cases = [
            (request(identity="workload.native", artifact_kind="native-package"), host(), "native"),
            (request(identity="workload.web", workload_type="web", artifact_kind="web-url", acceptsBrowser=True), host(), "pwa"),
            (reviewed_request(), host(), "known-good-recipe"),
            (request(identity="workload.game", workload_type="windows-game", artifact_kind="windows-executable", permissions=["audio"], antiCheat="supported"), host(), "game-proton"),
            (request(identity="workload.portable", workload_type="portable", artifact_kind="portable", permissions=["network"]), host(), "isolated-app"),
            (request(identity="workload.windows-admin", workload_type="windows-app", artifact_kind="windows-executable", requiresAdmin=True), host(protonAvailable=False), "vm"),
        ]
        for workload, machine, route in cases:
            with self.subTest(route=route):
                result = await value.read("route.decide", {"request": workload, "host": machine})
                self.assertEqual(result["selectedRoute"], route)
                self.assertEqual(result["eligibility"], "supported")
                self.assertEqual(result["recipeAssurance"], "contract-seed")
                self.assertEqual(len(result["considered"]), 6)
                schema = json.loads((Path(__file__).resolve().parents[3] / "default/fabric/schema/compatibility-decision-v0.json").read_text(encoding="utf-8"))
                Draft202012Validator(schema).validate(result)
        unsupported = await value.read("route.decide", {"request": request(identity="workload.blocked", workload_type="windows-game", artifact_kind="windows-executable", antiCheat="unknown", requiresKernelDriver=True), "host": host(virtualizationAvailable=False)})
        self.assertEqual(unsupported["eligibility"], "unsupported")
        self.assertIsNone(unsupported["selectedRoute"])

    async def test_route_identity_and_revision_are_order_independent(self):
        value = provider()
        workload = request(identity="workload.portable", workload_type="portable", artifact_kind="portable", permissions=["network", "audio"])
        first = await value.read("route.decide", {"request": workload, "host": host()})
        workload["permissions"].reverse()
        second = await value.read("route.decide", {"request": workload, "host": host()})
        self.assertEqual(first["decisionId"], second["decisionId"])
        self.assertEqual(first["revision"], second["revision"])
        self.assertEqual(first["requiredPermissions"], second["requiredPermissions"])

    async def test_permission_expansion_disqualifies_recipe(self):
        value = provider()
        workload = reviewed_request(permissions=["network", "devices"])
        result = await value.read("route.decide", {"request": workload, "host": host(virtualizationAvailable=False)})
        self.assertEqual(result["eligibility"], "unsupported")
        recipe_considered = next(item for item in result["considered"] if item["route"] == "known-good-recipe")
        self.assertEqual(recipe_considered["status"], "ineligible")

    async def test_provider_registers_and_registry_rejects_injection_shape(self):
        registry = ProviderRegistry(clock=lambda: 1.0)
        registration = registry.register(provider())
        self.assertEqual(registration.state, "available")
        workload = request()
        result = await registry.read("compatibility.provider", "route.decide", {"request": workload, "host": host()})
        self.assertEqual(result["value"]["selectedRoute"], "native")
        workload["shell"] = "$(rm -rf /)"
        with self.assertRaises(FabricError) as injected:
            await registry.read("compatibility.provider", "route.decide", {"request": workload, "host": host()})
        self.assertEqual(injected.exception.code, "provider.invalid-arguments")

        value = provider()
        registry = ProviderRegistry(clock=lambda: 2.0)
        registry.register(value)
        workload = reviewed_request()
        args = arguments(value.engine, workload)
        planned = await registry.preflight("compatibility.provider", "deploy", args, principal())
        self.assertEqual(planned["preflight"]["decision"]["selectedRoute"], "known-good-recipe")
        self.assertFalse(hasattr(registry, "apply"))

    async def test_recipe_route_requires_exact_reviewed_artifact(self):
        value = provider()
        workload = reviewed_request()
        workload["artifact"]["digest"] = "sha256:" + "0" * 64
        result = await value.read("route.decide", {"request": workload, "host": host(virtualizationAvailable=False)})
        self.assertEqual(result["eligibility"], "unsupported")
        recipe = next(item for item in result["considered"] if item["route"] == "known-good-recipe")
        self.assertEqual(recipe["status"], "ineligible")


class RecipeTrustTests(unittest.TestCase):
    def test_recipe_inventory_is_deterministic_and_explicitly_seed_assured(self):
        first = recipes(); second = RecipeCatalog(copy.deepcopy(recipe_document()))
        self.assertEqual(first.revision, second.revision)
        self.assertEqual(first.assurance, "contract-seed")
        self.assertTrue(all(recipe["signature"]["status"] == "declared" for recipe in first.recipes.values()))

    def test_release_verification_cannot_be_self_asserted(self):
        value = recipe_document()
        value["assurance"] = "release-verified"
        for recipe in value["recipes"]:
            recipe["signature"]["status"] = "verified"
        value["revision"] = self._revision(value)
        with self.assertRaises(FabricError) as unattested:
            RecipeCatalog(value)
        self.assertEqual(unattested.exception.code, "compatibility.recipes-unattested")
        admitted = RecipeCatalog(value, verified_recipe_revisions=frozenset({value["revision"]}))
        self.assertEqual(admitted.assurance, "release-verified")

    def test_untrusted_key_invalid_action_and_revision_tamper_fail(self):
        value = recipe_document(); value["recipes"][0]["signature"]["keyId"] = "attacker-key"; value["revision"] = self._revision(value)
        with self.assertRaises(FabricError) as untrusted:
            RecipeCatalog(value)
        self.assertEqual(untrusted.exception.code, "compatibility.recipe-untrusted")
        value = recipe_document(); value["recipes"][0]["lifecycle"]["install"][0]["action"] = "shell-command"; value["revision"] = self._revision(value)
        with self.assertRaises(FabricError) as invalid:
            RecipeCatalog(value)
        self.assertEqual(invalid.exception.code, "compatibility.recipes-invalid")
        value = recipe_document(); value["recipes"][0]["displayName"] = "tampered"
        with self.assertRaises(FabricError) as drift:
            RecipeCatalog(value)
        self.assertEqual(drift.exception.code, "compatibility.recipes-revision-invalid")

    def test_phase_action_misuse_duplicate_steps_and_missing_verify_first_fail(self):
        value = recipe_document(); value["recipes"][0]["lifecycle"]["validate"][0]["action"] = "remove-runtime"; value["revision"] = self._revision(value)
        with self.assertRaises(FabricError) as wrong_phase:
            RecipeCatalog(value)
        self.assertEqual(wrong_phase.exception.code, "compatibility.recipe-action-invalid")

        value = recipe_document(); value["recipes"][0]["lifecycle"]["validate"][0]["id"] = value["recipes"][0]["lifecycle"]["install"][0]["id"]; value["revision"] = self._revision(value)
        with self.assertRaises(FabricError) as duplicate:
            RecipeCatalog(value)
        self.assertEqual(duplicate.exception.code, "compatibility.recipe-action-invalid")

        value = recipe_document(); value["recipes"][0]["lifecycle"]["install"].reverse(); value["revision"] = self._revision(value)
        with self.assertRaises(FabricError) as ordering:
            RecipeCatalog(value)
        self.assertEqual(ordering.exception.code, "compatibility.recipe-action-invalid")

    @staticmethod
    def _revision(value):
        normalized = copy.deepcopy(value); normalized["revision"] = "sha256." + "0" * 64
        return revision(normalized)

    def test_route_adapters_keep_payload_out_of_argv(self):
        payload = {"origin": "$(touch /tmp/pwned); --command=sh"}
        for route in ("native", "pwa", "known-good-recipe", "game-proton", "isolated-app", "vm"):
            planned = route_adapter(route, payload)
            self.assertNotIn(payload["origin"], planned.command.argv)
            self.assertEqual(planned.typed_input, payload)
        self.assertTrue(all(command.executable.startswith("/") for command in command_matrix()))


if __name__ == "__main__":
    unittest.main()
