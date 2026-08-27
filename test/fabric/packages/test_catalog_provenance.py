from __future__ import annotations

import asyncio
import copy
import unittest

from jsonschema import Draft202012Validator

from omarchy_fabric.models import FabricError
from omarchy_fabric.provider_registry import ProviderRegistry
from omarchy_fabric.providers.packages.adapters import command_matrix, plan_adapter
from omarchy_fabric.providers.packages.catalog import PackageCatalog, catalog_revision
from omarchy_fabric.providers.packages.identity import stable_id

from helper import arguments, catalog, catalog_document, installed, principal, provider


class CatalogProvenanceTests(unittest.TestCase):
    def test_catalog_covers_every_supported_channel_and_is_deterministic(self):
        first = catalog()
        second = PackageCatalog(copy.deepcopy(catalog_document()))
        self.assertEqual(first.revision, second.revision)
        self.assertEqual([entry["id"] for entry in first.entries], sorted(entry["id"] for entry in first.entries))
        self.assertEqual({entry["sourceType"] for entry in first.entries}, {"curated", "signed-repo", "flatpak", "reviewed-aur", "appimage", "web-app"})

    def test_tampered_revision_and_unsigned_signed_channel_fail_closed(self):
        value = catalog_document()
        value["entries"][0]["summary"] = "tampered"
        with self.assertRaises(FabricError) as stale:
            PackageCatalog(value)
        self.assertEqual(stale.exception.code, "packages.catalog-revision-invalid")

        value = catalog_document()
        value["entries"][1]["provenance"]["signature"] = {"status": "not-applicable", "keyId": None}
        value["revision"] = catalog_revision(value)
        with self.assertRaises(FabricError) as unsigned:
            PackageCatalog(value)
        self.assertEqual(unsigned.exception.code, "packages.provenance-unverified")

        value = catalog_document()
        value["entries"][0]["provenance"]["signature"]["keyId"] = "attacker-key"
        value["revision"] = catalog_revision(value)
        with self.assertRaises(FabricError) as source_mismatch:
            PackageCatalog(value)
        self.assertEqual(source_mismatch.exception.code, "packages.provenance-invalid")

    def test_seed_assurance_is_explicit_and_release_claims_require_external_attestation(self):
        seed = catalog()
        self.assertEqual(seed.assurance, "contract-seed")
        self.assertTrue(all(entry["provenance"]["assurance"] == "contract-seed" for entry in seed.entries))
        self.assertTrue(all(entry["provenance"]["signature"]["status"] == "declared" for entry in seed.entries))

        value = catalog_document()
        value["assurance"] = "release-verified"
        for entry in value["entries"]:
            entry["provenance"]["assurance"] = "release-verified"
            entry["provenance"]["signature"]["status"] = "reviewed" if entry["sourceType"] == "reviewed-aur" else "verified"
        value["revision"] = catalog_revision(value)
        with self.assertRaises(FabricError) as unattested:
            PackageCatalog(value)
        self.assertEqual(unattested.exception.code, "packages.catalog-unattested")
        admitted = PackageCatalog(value, verified_catalog_revisions=frozenset({value["revision"]}))
        self.assertEqual(admitted.assurance, "release-verified")

    def test_schema_and_runtime_reject_unknown_properties_and_duplicate_ids(self):
        value = catalog_document()
        value["surprise"] = True
        schema = __import__("json").loads((__import__("pathlib").Path(__file__).resolve().parents[3] / "default/fabric/schema/packages-catalog-v0.json").read_text())
        self.assertIsNotNone(next(iter(Draft202012Validator(schema).iter_errors(value)), None))

        value = catalog_document()
        value["entries"].append(copy.deepcopy(value["entries"][0]))
        value["revision"] = catalog_revision(value)
        with self.assertRaises(FabricError) as duplicate:
            PackageCatalog(value)
        self.assertEqual(duplicate.exception.code, "packages.catalog-invalid")

        value = catalog_document()
        value["entries"][0]["provenance"]["origin"] = "https://["
        value["revision"] = catalog_revision(value)
        with self.assertRaises(FabricError) as malformed_origin:
            PackageCatalog(value)
        self.assertEqual(malformed_origin.exception.code, "packages.provenance-invalid")

    def test_adoption_distinguishes_exact_conflict_and_missing(self):
        value = catalog()
        exact = installed(adopted=False)
        conflict = installed("software.repo.libreoffice", adopted=False, digest="sha256:" + "0" * 64)
        foreign = copy.deepcopy(exact)
        foreign.update({"id": stable_id("installed.software", foreign["sourceType"], "foreign-tool"), "catalogId": "software.foreign.tool", "packageRef": "foreign-tool", "artifactDigest": "sha256:" + "f" * 64})
        states = {item["installedId"]: item["state"] for item in value.adoption([exact, conflict, foreign])}
        self.assertEqual(states[exact["id"]], "adoptable")
        self.assertEqual(states[conflict["id"]], "conflict")
        self.assertEqual(states[foreign["id"]], "unmanaged")

    def test_fixed_argv_never_contains_rpc_payload(self):
        payload = {"appId": "$(touch /tmp/pwned); rm -rf /", "requestId": "request.bad"}
        planned = plan_adapter("flatpak", "install", payload)
        self.assertNotIn(payload["appId"], planned.command.argv)
        self.assertEqual(planned.stdin_payload, payload)
        for command in command_matrix():
            self.assertTrue(command.executable.startswith("/"))
            self.assertNotIn("-c", command.arguments)


class PackageRegistryTests(unittest.IsolatedAsyncioTestCase):
    async def test_provider_is_admitted_and_read_results_are_closed(self):
        value = provider([installed(adopted=False)])
        registry = ProviderRegistry(clock=lambda: 10.0)
        registration = registry.register(value)
        self.assertEqual(registration.state, "available")
        search = await registry.read("packages.provider", "catalog.search", {"query": "editor", "sourceTypes": []})
        self.assertEqual(search["value"]["assurance"], "contract-seed")
        self.assertIn("software.curated.neovim", {entry["id"] for entry in search["value"]["entries"]})
        adoption = await registry.read("packages.provider", "adoption.inspect", {})
        self.assertEqual(adoption["value"]["items"][0]["state"], "adoptable")

    async def test_unknown_query_and_injected_argument_fail_before_provider(self):
        registry = ProviderRegistry()
        registry.register(provider())
        with self.assertRaises(FabricError) as unknown:
            await registry.read("packages.provider", "catalog.search", {"query": "", "sourceTypes": ["random"]})
        self.assertEqual(unknown.exception.code, "provider.invalid-arguments")
        with self.assertRaises(FabricError) as extra:
            await registry.read("packages.provider", "inventory.inspect", {"includeUnmanaged": True, "shell": "rm -rf /"})
        self.assertEqual(extra.exception.code, "provider.invalid-arguments")

    async def test_registry_validates_typed_operation_preflight_without_apply_route(self):
        value = provider()
        registry = ProviderRegistry(clock=lambda: 20.0)
        registry.register(value)
        args = arguments(value.engine, "software.curated.neovim")
        planned = await registry.preflight("packages.provider", "install", args, principal())
        self.assertEqual(planned["preflight"]["adapter"]["adapterId"], "packages.pacman.install")
        self.assertFalse(hasattr(registry, "apply"))


if __name__ == "__main__":
    unittest.main()
