from __future__ import annotations

import json
import unittest
from collections.abc import Mapping
from pathlib import Path

from helper import ROOT, clone_workspace, principal

from omarchy_fabric.provider_registry import ProviderRegistry
from omarchy_fabric.providers.files import provider as files
from omarchy_fabric.providers.files._engine import StateSnapshot

class SnapshotBackend:
    def __init__(self, snapshot):
        self.value = snapshot

    async def snapshot(self):
        return self.value

    async def compare_and_swap(self, expected_revision, proposed_state):
        raise AssertionError("read test must not mutate")

class ContractAndReadTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.provider = files.build_fake_provider(clone_workspace())

    def test_manifest_and_all_referenced_schemas_cross_central_admission(self) -> None:
        registration = ProviderRegistry().register(self.provider)
        self.assertEqual(registration.provider_id, "files.provider")
        references = {
            reference["id"]
            for action in self.provider.manifest["actions"].values()
            for phase in ("arguments", "result", "preflight", "state")
            if (reference := action[phase]) is not None
        }
        self.assertEqual(set(self.provider.schemas), references)
        self.assertEqual(len(self.provider.manifest["actions"]), 14)

    async def test_central_registry_dispatches_read_and_preflight_contracts(self) -> None:
        registry = ProviderRegistry(clock=lambda: 42.0)
        registry.register(self.provider)
        read = await registry.read("files.provider", "inspect", {})
        self.assertEqual(read["capability"], "files.inspect")
        self.assertEqual(read["observedAt"], 42.0)
        plan = await registry.preflight(
            "files.provider",
            "entry.rename",
            {"entryId": "files.entry.notes", "newName": "memo.txt"},
            principal(),
        )
        self.assertEqual(plan["capability"], "files.entry.rename")
        self.assertEqual(plan["preflight"]["guards"]["pathPolicy"], "location-relative-v0")

    def test_every_schema_object_is_closed_and_versioned(self) -> None:
        def walk(value):
            yield value
            if isinstance(value, Mapping):
                for child in value.values():
                    yield from walk(child)
            elif isinstance(value, list):
                for child in value:
                    yield from walk(child)

        for schema_id, schema in self.provider.schemas.items():
            with self.subTest(schema=schema_id):
                self.assertEqual(schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
                self.assertEqual(schema["x-omarchy-version"], schema_id.rsplit(":", 1)[1])
                for node in walk(schema):
                    if isinstance(node, Mapping) and node.get("type") == "object":
                        self.assertIs(node.get("additionalProperties"), False)

    async def test_inventory_browse_search_and_recent_are_deterministic(self) -> None:
        inventory = await self.provider.read("inspect", {})
        self.assertEqual(inventory["availability"], {"state": "available", "read": True, "operation": True, "reasons": []})
        self.assertEqual({item["kind"] for item in inventory["state"]["locations"]}, {"this-pc", "desktop", "trash", "mount", "network"})
        self.assertEqual({item["kind"] for item in inventory["state"]["mounts"]}, {"removable", "smb"})

        browse = await self.provider.read("browse", {"locationId": "files.location.desktop", "relativePath": "", "includeHidden": False, "limit": 20})
        self.assertEqual([item["name"] for item in browse["entries"]], ["Project", "notes.txt", "outside"])
        search = await self.provider.read("search", {"query": "read", "locationIds": [], "includeHidden": False, "limit": 20})
        self.assertEqual([item["id"] for item in search["entries"]], ["files.entry.readme"])
        recent = await self.provider.read("recent", {"limit": 20})
        self.assertEqual([item["id"] for item in recent["entries"]], ["files.entry.notes"])

        reordered = clone_workspace()
        for key in ("locations", "entries", "mounts"):
            reordered[key].reverse()
        other = files.build_fake_provider(reordered)
        second = await other.read("inspect", {})
        self.assertEqual(inventory["revision"], second["revision"])
        self.assertEqual(inventory["state"], second["state"])

    async def test_closed_read_arguments_reject_traversal_and_unknown_fields(self) -> None:
        with self.assertRaisesRegex(Exception, "contract-invalid"):
            await self.provider.read("browse", {"locationId": "files.location.desktop", "relativePath": "", "includeHidden": False, "limit": 20, "extra": True})
        with self.assertRaisesRegex(Exception, "read-invalid"):
            await self.provider.read("browse", {"locationId": "files.location.desktop", "relativePath": "../secret", "includeHidden": False, "limit": 20})

    async def test_semantically_invalid_and_incoherent_backend_snapshots_fail_closed(self) -> None:
        duplicate = clone_workspace()
        duplicate["locations"].append(duplicate["locations"][0].copy())
        provider = files.build_fake_provider(clone_workspace())
        provider.backend = SnapshotBackend(StateSnapshot("available", True, duplicate))
        with self.assertRaisesRegex(Exception, "backend-invalid"):
            await provider.read("inspect", {})
        provider.backend = SnapshotBackend(StateSnapshot("unavailable", True, None, ()))
        with self.assertRaisesRegex(Exception, "backend-invalid"):
            await provider.read("inspect", {})

    def test_shipped_location_config_is_closed_code_owned_data(self) -> None:
        document = json.loads((ROOT / "default" / "ultimate" / "files" / "locations-v0.json").read_text())
        self.assertEqual(set(document), {"schemaVersion", "locations", "limits"})
        self.assertEqual([item["kind"] for item in document["locations"]], ["this-pc", "home", "desktop", "documents", "downloads", "pictures", "music", "videos", "trash"])

if __name__ == "__main__":
    unittest.main()
