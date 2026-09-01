from __future__ import annotations

import asyncio
import os
import tempfile
import unittest
from pathlib import Path

from helper import clone_database, principal

from omarchy_fabric.models import FabricError
from omarchy_fabric.provider_registry import ProviderRegistry
from omarchy_fabric.providers._engine import state_revision
from omarchy_fabric.providers.defaults import provider as defaults

class DefaultsContractLifecycleTests(unittest.IsolatedAsyncioTestCase):
    def test_manifest_and_schemas_cross_central_admission(self) -> None:
        provider = defaults.build_fake_provider(clone_database())
        registration = ProviderRegistry().register(provider)
        self.assertEqual(registration.provider_id, "defaults.provider")
        self.assertEqual(set(provider.manifest["capabilities"]), {
            "defaults.inspect", "defaults.mime.query", "defaults.protocol.query",
            "defaults.mime.set", "defaults.protocol.set", "defaults.association.clear",
        })

    async def test_central_registry_dispatches_query_and_preflight_contracts(self) -> None:
        provider = defaults.build_fake_provider(clone_database())
        registry = ProviderRegistry(clock=lambda: 84.0)
        registry.register(provider)
        query = await registry.read("defaults.provider", "mime.query", {"mimeType": "text/plain"})
        self.assertEqual(query["capability"], "defaults.mime.query")
        alternate = next(app for app in provider.backend._state["applications"] if app["desktopId"] == "alternate.desktop")
        plan = await registry.preflight(
            "defaults.provider",
            "mime.set",
            {"mimeType": "text/plain", "appId": alternate["id"]},
            principal(),
        )
        self.assertEqual(plan["capability"], "defaults.mime.set")
        self.assertEqual(plan["preflight"]["guards"]["executor"]["shell"], False)

    async def test_inventory_mime_and_protocol_queries_are_typed(self) -> None:
        provider = defaults.build_fake_provider(clone_database())
        inventory = await provider.read("inspect", {})
        self.assertEqual(inventory["availability"], {"state": "available", "read": True, "operation": True, "reasons": []})
        self.assertEqual([app["id"] for app in inventory["state"]["applications"]], sorted(app["id"] for app in inventory["state"]["applications"]))
        mime = await provider.read("mime.query", {"mimeType": "text/plain"})
        self.assertEqual(mime["application"]["desktopId"], "editor.desktop")
        protocol = await provider.read("protocol.query", {"scheme": "https"})
        self.assertEqual(protocol["application"]["desktopId"], "browser.desktop")
        absent = await provider.read("protocol.query", {"scheme": "gemini"})
        self.assertIsNone(absent["association"])
        self.assertIsNone(absent["application"])

    async def exercise(self, action: str, arguments: dict[str, object], assertion) -> None:
        provider = defaults.build_fake_provider(clone_database())
        before = await provider.read("inspect", {})
        plan = await provider.preflight(action, arguments, principal())
        self.assertEqual(plan["guards"]["snapshotRevision"], plan["stateRevision"])
        self.assertEqual(plan["guards"]["executor"], {"mode": "typed-helper", "commandId": "defaults.apply-v0", "shell": False})
        result = await provider.execute(action, plan["normalizedArguments"], plan["stateRevision"])
        self.assertTrue(result["changed"])
        assertion(result["state"]["value"])
        validated = await provider.validate(action, plan["normalizedArguments"], result["state"])
        self.assertFalse(validated["changed"])
        undone = await provider.undo(action, plan["recovery"]["priorState"], result["stateRevision"])
        self.assertEqual(undone["state"]["value"], before["state"])

    async def test_mime_protocol_and_clear_plans_execute_validate_and_undo(self) -> None:
        state = clone_database()
        editor_id = next(app["id"] for app in state["applications"] if app["desktopId"] == "editor.desktop")
        alternate_id = next(app["id"] for app in state["applications"] if app["desktopId"] == "alternate.desktop")
        await self.exercise(
            "mime.set",
            {"mimeType": "text/plain", "appId": alternate_id},
            lambda value: self.assertEqual(next(item for item in value["associations"] if item["key"] == "text/plain")["defaultAppId"], alternate_id),
        )
        provider = defaults.build_fake_provider(clone_database())
        html = next(item for item in provider.backend._state["associations"] if item["key"] == "text/html")
        html["candidateAppIds"].append(editor_id)
        html["candidateAppIds"].sort()
        editor = next(app for app in provider.backend._state["applications"] if app["id"] == editor_id)
        editor["mimeTypes"].append("text/html")
        editor["mimeTypes"].sort()
        html["identity"] = defaults._association_identity(html)
        defaults.validate_database(provider.backend._state)
        plan = await provider.preflight("mime.set", {"mimeType": "text/html", "appId": editor_id}, principal())
        changed = await provider.execute("mime.set", plan["normalizedArguments"], plan["stateRevision"])
        self.assertEqual(next(item for item in changed["state"]["value"]["associations"] if item["key"] == "text/html")["defaultAppId"], editor_id)

        await self.exercise(
            "protocol.set",
            {"scheme": "http", "appId": alternate_id},
            lambda value: self.assertEqual(next(item for item in value["associations"] if item["key"] == "http")["defaultAppId"], alternate_id),
        )
        association_id = defaults._association_id("protocol", "mailto")
        await self.exercise(
            "association.clear",
            {"associationId": association_id},
            lambda value: self.assertEqual(next(item for item in value["associations"] if item["id"] == association_id)["status"], "unconfigured"),
        )

    async def test_noop_unsupported_readonly_and_unauthenticated_changes_fail_closed(self) -> None:
        provider = defaults.build_fake_provider(clone_database())
        editor = next(app for app in provider.backend._state["applications"] if app["desktopId"] == "editor.desktop")
        plan = await provider.preflight("mime.set", {"mimeType": "text/plain", "appId": editor["id"]}, principal())
        self.assertFalse(plan["changed"])
        result = await provider.execute("mime.set", plan["normalizedArguments"], plan["stateRevision"])
        self.assertFalse(result["changed"])
        self.assertEqual(provider.backend.write_count, 0)

        browser = next(app for app in provider.backend._state["applications"] if app["desktopId"] == "browser.desktop")
        with self.assertRaises(FabricError) as unsupported:
            await provider.preflight("mime.set", {"mimeType": "text/plain", "appId": browser["id"]}, principal())
        self.assertEqual(unsupported.exception.code, "defaults.precondition-failed")
        read_only = clone_database()
        next(item for item in read_only["associations"] if item["key"] == "text/plain")["writable"] = False
        read_only_provider = defaults.build_fake_provider(read_only)
        with self.assertRaises(FabricError) as denied:
            await read_only_provider.preflight("mime.set", {"mimeType": "text/plain", "appId": editor["id"]}, principal())
        self.assertEqual(denied.exception.code, "defaults.precondition-failed")
        with self.assertRaises(FabricError) as principal_required:
            await provider.preflight("mime.set", {"mimeType": "text/plain", "appId": editor["id"]}, object())
        self.assertEqual(principal_required.exception.code, "principal.required")

    async def test_concurrency_restart_corruption_and_drift_are_contained(self) -> None:
        state = clone_database()
        mailer = next(app for app in state["applications"] if app["desktopId"] == "mailer.desktop")
        provider = defaults.build_fake_provider(state)
        plan = await provider.preflight("association.clear", {"associationId": defaults._association_id("protocol", "mailto")}, principal())
        results = await asyncio.gather(
            provider.execute("association.clear", plan["normalizedArguments"], plan["stateRevision"]),
            provider.execute("association.clear", plan["normalizedArguments"], plan["stateRevision"]),
            return_exceptions=True,
        )
        self.assertEqual(sum(not isinstance(result, Exception) for result in results), 1)
        self.assertEqual(next(result.code for result in results if isinstance(result, FabricError)), "defaults.state-stale")

        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "defaults.json"
            persistent = defaults.build_fake_provider(clone_database(), state_path=state_path)
            persistent_plan = await persistent.preflight("association.clear", {"associationId": defaults._association_id("protocol", "mailto")}, principal())
            changed = await persistent.execute("association.clear", persistent_plan["normalizedArguments"], persistent_plan["stateRevision"])
            if os.name == "posix":
                self.assertEqual(state_path.stat().st_mode & 0o777, 0o600)
            restarted = defaults.build_fake_provider(clone_database(), state_path=state_path)
            self.assertEqual((await restarted.read("inspect", {}))["state"], changed["state"]["value"])
            state_path.write_text('{"schemaVersion":"v0","domain":"defaults","state":{},"state":{}}')
            with self.assertRaises(ValueError):
                defaults.build_fake_provider(clone_database(), state_path=state_path)

        drift = defaults.build_fake_provider(clone_database())
        drift_plan = await drift.preflight("association.clear", {"associationId": defaults._association_id("protocol", "mailto")}, principal())
        changed_state = clone_database()
        mailer_state = next(app for app in changed_state["applications"] if app["id"] == mailer["id"])
        mailer_state["identity"] = state_revision({"app": mailer["id"], "generation": 2})
        await drift.backend.force_state(defaults.canonicalize_database(changed_state))
        with self.assertRaises(FabricError) as stale:
            await drift.execute("association.clear", drift_plan["normalizedArguments"], drift_plan["stateRevision"])
        self.assertEqual(stale.exception.code, "defaults.state-stale")

if __name__ == "__main__":
    unittest.main()
