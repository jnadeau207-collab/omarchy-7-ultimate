from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from helper import ROOT, clone_database, principal

from omarchy_fabric.provider_registry import ProviderRegistry
from omarchy_fabric.providers._probe import ProbeOutput
from omarchy_fabric.providers.defaults import provider as defaults


class FixtureRunner:
    def __init__(self, values=None) -> None:
        self.values = values or {}

    def __call__(self, command):
        return ProbeOutput(self.values.get(command.argv, ""), "")


def startup_entry(source: str, desktop_id: str, name: str = "Starter", enabled: bool = True) -> dict[str, object]:
    return {
        "id": defaults._startup_id(source, desktop_id),
        "desktopId": desktop_id,
        "name": name,
        "enabled": enabled,
        "source": source,
        "identity": "sha256." + "0" * 64,
    }


class StartupParseTests(unittest.TestCase):
    def test_enabled_entry_parses(self) -> None:
        raw = b"[Desktop Entry]\nType=Application\nName=Backintime\n"
        parsed = defaults._parse_autostart(raw, "backintime.desktop", "user", fake_stat())
        self.assertIsNotNone(parsed)
        assert parsed is not None
        self.assertEqual(parsed["name"], "Backintime")
        self.assertTrue(parsed["enabled"])
        self.assertEqual(parsed["source"], "user")
        self.assertNotIn("Exec", parsed)

    def test_hidden_and_gnome_disabled_entries_parse_disabled(self) -> None:
        hidden = defaults._parse_autostart(
            b"[Desktop Entry]\nType=Application\nName=Hidden\nHidden=true\n",
            "hidden.desktop",
            "user",
            fake_stat(),
        )
        assert hidden is not None
        self.assertFalse(hidden["enabled"])
        gnome_off = defaults._parse_autostart(
            b"[Desktop Entry]\nType=Application\nName=Off\nX-GNOME-Autostart-enabled=false\n",
            "off.desktop",
            "system",
            fake_stat(),
        )
        assert gnome_off is not None
        self.assertFalse(gnome_off["enabled"])

    def test_non_application_or_nameless_entries_are_skipped(self) -> None:
        self.assertIsNone(
            defaults._parse_autostart(b"[Desktop Entry]\nType=Link\nName=Link\n", "link.desktop", "user", fake_stat())
        )
        self.assertIsNone(
            defaults._parse_autostart(b"[Desktop Entry]\nType=Application\n", "noname.desktop", "user", fake_stat())
        )

    def test_duplicate_keys_and_bad_names_are_rejected(self) -> None:
        with self.assertRaises(ValueError):
            defaults._parse_autostart(
                b"[Desktop Entry]\nType=Application\nName=One\nName=Two\n", "dup.desktop", "user", fake_stat()
            )
        with self.assertRaises(ValueError):
            defaults._parse_autostart(
                "[Desktop Entry]\nType=Application\nName=Bad\0Name\n".encode("utf-8"),
                "bad.desktop",
                "user",
                fake_stat(),
            )

    def test_startup_id_is_deterministic(self) -> None:
        self.assertEqual(
            defaults._startup_id("user", "same.desktop"), defaults._startup_id("user", "same.desktop")
        )
        self.assertNotEqual(
            defaults._startup_id("user", "same.desktop"), defaults._startup_id("system", "same.desktop")
        )


def fake_stat() -> os.stat_result:
    return os.stat_result((0,) * 10)


class StartupValidationTests(unittest.TestCase):
    def test_missing_startup_section_stays_valid(self) -> None:
        state = clone_database()
        self.assertNotIn("startup", state)
        defaults.validate_database(state)

    def test_duplicate_bad_source_or_shape_is_rejected(self) -> None:
        state = clone_database()
        first = startup_entry("user", "one.desktop")
        state["startup"] = [first, dict(first)]
        with self.assertRaises(ValueError):
            defaults.validate_database(state)
        state["startup"] = [startup_entry("local", "one.desktop")]
        with self.assertRaises(ValueError):
            defaults.validate_database(state)
        broken = startup_entry("user", "one.desktop")
        broken["enabled"] = "yes"
        state["startup"] = [broken]
        with self.assertRaises(ValueError):
            defaults.validate_database(state)
        nameless = startup_entry("user", "one.desktop")
        nameless["name"] = ""
        state["startup"] = [nameless]
        with self.assertRaises(ValueError):
            defaults.validate_database(state)
        state["startup"] = "nope"
        with self.assertRaises(ValueError):
            defaults.validate_database(state)

    def test_canonicalize_sorts_and_defaults_startup(self) -> None:
        state = clone_database()
        second = startup_entry("system", "b.desktop", name="Bee")
        first = startup_entry("user", "a.desktop", name="Aye", enabled=False)
        state["startup"] = [second, first]
        canonical = defaults.canonicalize_database(state)
        self.assertEqual([entry["desktopId"] for entry in canonical["startup"]], ["a.desktop", "b.desktop"])
        plain = clone_database()
        self.assertEqual(defaults.canonicalize_database(plain)["startup"], [])

    def test_schema_accepts_and_rejects_startup_entries(self) -> None:
        state = clone_database()
        state["startup"] = [startup_entry("user", "ok.desktop")]
        defaults.validate_database(state)
        state["startup"] = [dict(startup_entry("user", "ok.desktop"), enabled="yes")]
        with self.assertRaises(ValueError):
            defaults.validate_database(state)


@unittest.skipUnless(os.name == "posix", "autostart no-follow coverage requires Linux")
class StartupReaderTests(unittest.IsolatedAsyncioTestCase):
    async def test_snapshot_reads_user_and_system_autostart_without_commands(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            user_dir = home / ".config" / "autostart"
            user_dir.mkdir(parents=True)
            (user_dir / "notes.desktop").write_text(
                "[Desktop Entry]\nType=Application\nName=Notes\nExec=notes --bg\n"
            )
            (user_dir / "quiet.desktop").write_text(
                "[Desktop Entry]\nType=Application\nName=Quiet\nHidden=true\nExec=quiet\n"
            )
            (user_dir / "not-a-desktop.txt").write_text("nothing\n")
            config = ROOT / "default" / "ultimate" / "files" / "default-associations-v0.json"
            provider = defaults.build_provider(home=home, config_path=config, runner=FixtureRunner())
            inventory = await provider.read("inspect", {})
            startup = {entry["desktopId"]: entry for entry in inventory["state"]["startup"]}
            self.assertIn("notes.desktop", startup)
            self.assertTrue(startup["notes.desktop"]["enabled"])
            self.assertEqual(startup["notes.desktop"]["source"], "user")
            self.assertIn("quiet.desktop", startup)
            self.assertFalse(startup["quiet.desktop"]["enabled"])
            self.assertNotIn("not-a-desktop.txt", startup)
            for entry in inventory["state"]["startup"]:
                self.assertNotIn("Exec", entry)
                self.assertNotIn("exec", entry)
            ids = [entry["id"] for entry in inventory["state"]["startup"]]
            self.assertEqual(ids, sorted(ids))

    async def test_missing_autostart_directories_yield_empty_startup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = ROOT / "default" / "ultimate" / "files" / "default-associations-v0.json"
            provider = defaults.build_provider(home=home, config_path=config, runner=FixtureRunner())
            inventory = await provider.read("inspect", {})
            user_entries = [entry for entry in inventory["state"]["startup"] if entry["source"] == "user"]
            self.assertEqual(user_entries, [])


class StartupFakeBackendTests(unittest.IsolatedAsyncioTestCase):
    async def test_fake_backend_serves_startup_through_inspect(self) -> None:
        state = clone_database()
        state["startup"] = [startup_entry("user", "notes.desktop")]
        provider = defaults.build_fake_provider(state)
        registry = ProviderRegistry(clock=lambda: 84.0)
        registry.register(provider)
        inventory = await registry.read("defaults.provider", "inspect", {})
        self.assertEqual(
            [entry["desktopId"] for entry in inventory["value"]["state"]["startup"]], ["notes.desktop"]
        )
