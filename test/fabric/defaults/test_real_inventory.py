from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from helper import ROOT, principal

from omarchy_fabric.models import FabricError
from omarchy_fabric.providers._probe import ProbeOutput
from omarchy_fabric.providers.defaults import provider as defaults


class FixtureRunner:
    def __init__(self, values=None, error: Exception | None = None) -> None:
        self.values = values or {}
        self.error = error
        self.calls: list[tuple[str, ...]] = []

    def __call__(self, command):
        self.calls.append(command.argv)
        if self.error is not None:
            raise self.error
        return ProbeOutput(self.values.get(command.argv, ""), "")


@unittest.skipUnless(os.name == "posix", "desktop-file no-follow coverage requires Linux")
class RealDefaultsInventoryTests(unittest.IsolatedAsyncioTestCase):
    async def test_real_inventory_uses_only_fixed_argv_and_never_exposes_a_live_mutator(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            applications = home / ".local" / "share" / "applications"
            applications.mkdir(parents=True)
            (applications / "test-editor.desktop").write_text(
                "[Desktop Entry]\nType=Application\nName=Test Editor\nMimeType=text/plain;application/json;\n"
            )
            (applications / "ignored-link.desktop").symlink_to(applications / "test-editor.desktop")
            values = {
                defaults.QUERY_COMMANDS[("mime", "text/plain")].argv: "test-editor.desktop\n",
            }
            runner = FixtureRunner(values)
            config = ROOT / "default" / "ultimate" / "files" / "default-associations-v0.json"
            provider = defaults.build_provider(home=home, config_path=config, runner=runner)
            inventory = await provider.read("inspect", {})

            self.assertEqual(set(runner.calls), {command.argv for command in defaults.QUERY_COMMANDS.values()})
            self.assertEqual(len(runner.calls), len(defaults.QUERY_COMMANDS))
            for argv in runner.calls:
                self.assertEqual(argv[0], "/usr/bin/xdg-mime")
                self.assertEqual(argv[1:3], ("query", "default"))
                self.assertNotIn("-c", argv)
            self.assertEqual(inventory["availability"]["state"], "degraded")
            self.assertTrue(inventory["availability"]["read"])
            self.assertFalse(inventory["availability"]["operation"])
            app = next(item for item in inventory["state"]["applications"] if item["desktopId"] == "test-editor.desktop")
            self.assertEqual(app["mimeTypes"], ["application/json", "text/plain"])
            self.assertNotIn("ignored-link.desktop", {item["desktopId"] for item in inventory["state"]["applications"]})
            association = next(item for item in inventory["state"]["associations"] if item["kind"] == "mime" and item["key"] == "text/plain")
            self.assertEqual(association["defaultAppId"], app["id"])
            self.assertEqual(association["status"], "configured")
            with self.assertRaises(FabricError) as unavailable:
                await provider.preflight("mime.set", {"mimeType": "text/plain", "appId": app["id"]}, principal())
            self.assertEqual(unavailable.exception.code, "defaults.operation-unavailable")

    async def test_missing_and_malformed_fixed_probes_are_explicit_degradation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = ROOT / "default" / "ultimate" / "files" / "default-associations-v0.json"
            missing = defaults.build_provider(home=home, config_path=config, runner=FixtureRunner(error=FileNotFoundError("xdg-mime")))
            missing_result = await missing.read("inspect", {})
            self.assertTrue(any(reason["code"] == "provider.dependency-missing" for reason in missing_result["availability"]["reasons"]))
            malformed_values = {command.argv: "one.desktop\ntwo.desktop\n" for command in defaults.QUERY_COMMANDS.values()}
            malformed = defaults.build_provider(home=home, config_path=config, runner=FixtureRunner(malformed_values))
            malformed_result = await malformed.read("inspect", {})
            self.assertTrue(any(reason["code"] == "defaults.probe-invalid" for reason in malformed_result["availability"]["reasons"]))
            self.assertTrue(all(item["status"] == "unconfigured" for item in malformed_result["state"]["associations"]))

    def test_command_catalog_matches_shipped_config_exactly(self) -> None:
        document = defaults._load_json(ROOT / "default" / "ultimate" / "files" / "default-associations-v0.json")
        self.assertEqual(tuple(document["mimeTypes"]), defaults.MIME_TYPES)
        self.assertEqual(tuple(document["protocols"]), defaults.PROTOCOLS)
        self.assertEqual(
            set(defaults.QUERY_COMMANDS),
            {*(('mime', key) for key in defaults.MIME_TYPES), *(('protocol', key) for key in defaults.PROTOCOLS)},
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "hidden.desktop"
            path.write_text("fixture")
            parsed = defaults._parse_desktop(
                b"[Desktop Entry]\nType=Application\nName=Hidden\nHidden=true\n",
                "hidden.desktop",
                "user",
                path.stat(),
            )
            self.assertEqual(parsed, {"hidden": True})

    def test_provider_rejects_symlinked_code_owned_config(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir()
            config = ROOT / "default" / "ultimate" / "files" / "default-associations-v0.json"
            link = root / "defaults.json"
            link.symlink_to(config)
            with self.assertRaisesRegex(ValueError, "real file"):
                defaults.build_provider(home=home, config_path=link, runner=FixtureRunner())


if __name__ == "__main__":
    unittest.main()
