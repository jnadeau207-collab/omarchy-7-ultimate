from __future__ import annotations

import os
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path

from helper import ROOT, clone_database, principal

from omarchy_fabric.models import FabricError
from omarchy_fabric.providers.defaults import provider as defaults

class DefaultsAdversarialHardeningTests(unittest.IsolatedAsyncioTestCase):
    async def test_forged_recovery_revision_is_rejected_before_any_write(self) -> None:
        state = clone_database()
        alternate = next(app for app in state["applications"] if app["desktopId"] == "alternate.desktop")
        provider = defaults.build_fake_provider(state)
        plan = await provider.preflight(
            "mime.set",
            {"mimeType": "text/plain", "appId": alternate["id"]},
            principal(),
        )
        changed = await provider.execute("mime.set", plan["normalizedArguments"], plan["stateRevision"])
        forged = deepcopy(plan["recovery"]["priorState"])
        forged["revision"] = f"sha256.{64 * '0'}"
        with self.assertRaises(FabricError) as rejected:
            await provider.undo("mime.set", forged, changed["stateRevision"])
        self.assertEqual(rejected.exception.code, "defaults.state-corrupt")
        self.assertEqual(provider.backend.write_count, 1)

    async def test_old_association_recovery_cannot_clobber_newer_intent(self) -> None:
        state = clone_database()
        alternate = next(app for app in state["applications"] if app["desktopId"] == "alternate.desktop")
        provider = defaults.build_fake_provider(state)
        old_plan = await provider.preflight(
            "mime.set",
            {"mimeType": "text/plain", "appId": alternate["id"]},
            principal(),
        )
        await provider.execute("mime.set", old_plan["normalizedArguments"], old_plan["stateRevision"])
        newer_plan = await provider.preflight(
            "association.clear",
            {"associationId": defaults._association_id("protocol", "mailto")},
            principal(),
        )
        newer = await provider.execute(
            "association.clear",
            newer_plan["normalizedArguments"],
            newer_plan["stateRevision"],
        )
        with self.assertRaises(FabricError) as stale:
            await provider.undo(
                "mime.set",
                old_plan["recovery"]["priorState"],
                newer["stateRevision"],
            )
        self.assertEqual(stale.exception.code, "defaults.state-stale")
        current = await provider.read("inspect", {})
        text = next(item for item in current["state"]["associations"] if item["key"] == "text/plain")
        mailto = next(item for item in current["state"]["associations"] if item["key"] == "mailto")
        self.assertEqual(text["defaultAppId"], alternate["id"])
        self.assertEqual(mailto["status"], "unconfigured")

    async def test_two_restarted_instances_cannot_clobber_associations(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "defaults.json"
            first = defaults.build_fake_provider(clone_database(), state_path=state_path)
            second = defaults.build_fake_provider(clone_database(), state_path=state_path)
            association_id = defaults._association_id("protocol", "mailto")
            first_plan = await first.preflight("association.clear", {"associationId": association_id}, principal())
            second_plan = await second.preflight("association.clear", {"associationId": association_id}, principal())
            await first.execute(
                "association.clear",
                first_plan["normalizedArguments"],
                first_plan["stateRevision"],
            )
            with self.assertRaises(FabricError) as stale:
                await second.execute(
                    "association.clear",
                    second_plan["normalizedArguments"],
                    second_plan["stateRevision"],
                )
            self.assertEqual(stale.exception.code, "defaults.state-stale")

    def test_desktop_identifiers_and_display_fields_are_ascii_control_safe(self) -> None:
        self.assertFalse(defaults._valid_desktop_id("é.desktop"))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "unsafe.desktop"
            path.write_text("fixture")
            with self.assertRaises(ValueError):
                defaults._parse_desktop(
                    b"[Desktop Entry]\nType=Application\nName=Safe\tInjected\n",
                    "unsafe.desktop",
                    "user",
                    path.stat(),
                )
            parsed = defaults._parse_desktop(
                b"[Desktop Entry]\nType=Application\nName=Safe\nIcon=/private/icon.png\n",
                "safe.desktop",
                "user",
                path.stat(),
            )
            self.assertIsNotNone(parsed)
            self.assertIsNone(parsed["icon"])

    def test_association_status_requires_an_authoritative_source(self) -> None:
        state = clone_database()
        selected = next(item for item in state["associations"] if item["key"] == "text/plain")
        selected["source"] = "none"
        selected["identity"] = defaults._association_identity(selected)
        with self.assertRaisesRegex(ValueError, "authoritative source"):
            defaults.build_fake_provider(state)

    @unittest.skipUnless(os.name == "posix", "desktop root authority coverage requires Linux")
    async def test_user_application_inventory_refuses_ancestor_symlinks(self) -> None:
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as outside_directory:
            home = Path(directory)
            outside = Path(outside_directory)
            (outside / "share" / "applications").mkdir(parents=True)
            (outside / "share" / "applications" / "leaked.desktop").write_text(
                "[Desktop Entry]\nType=Application\nName=Leaked\nMimeType=text/plain;\n"
            )
            (home / ".local").symlink_to(outside, target_is_directory=True)
            config = ROOT / "default" / "ultimate" / "files" / "default-associations-v0.json"

            class EmptyRunner:
                def __call__(self, _command):
                    from omarchy_fabric.providers._probe import ProbeOutput

                    return ProbeOutput("", "")

            inventory = await defaults.build_provider(home=home, config_path=config, runner=EmptyRunner()).read("inspect", {})
            self.assertNotIn("leaked.desktop", {item["desktopId"] for item in inventory["state"]["applications"]})
            self.assertTrue(
                any(reason["code"] == "defaults.application-root-unsafe" for reason in inventory["availability"]["reasons"])
            )

    @unittest.skipUnless(os.name == "posix", "bounded precedence coverage requires Linux")
    def test_scan_bound_prioritizes_user_over_lower_priority_roots(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            user = root / "user"
            local = root / "local"
            system = root / "system"
            for path in (user, local, system):
                path.mkdir()
            (user / "chosen.desktop").write_text(
                "[Desktop Entry]\nType=Application\nName=User Choice\nMimeType=text/plain;\n"
            )
            for index in range(4):
                (system / f"system-{index}.desktop").write_text(
                    f"[Desktop Entry]\nType=Application\nName=System {index}\nMimeType=text/plain;\n"
                )
            config = ROOT / "default" / "ultimate" / "files" / "default-associations-v0.json"
            backend = defaults.RealDefaultsBackend(root, config, lambda _command: None)
            backend._application_roots = lambda: (("user", user), ("local", local), ("system", system))
            original_limit = defaults.MAX_DESKTOP_FILES
            try:
                defaults.MAX_DESKTOP_FILES = 2
                applications, reasons = backend._applications()
            finally:
                defaults.MAX_DESKTOP_FILES = original_limit
            self.assertIn("chosen.desktop", {item["desktopId"] for item in applications})
            self.assertTrue(any(reason.code == "defaults.application-inventory-truncated" for reason in reasons))

    async def test_unexpected_probe_errors_do_not_leak_paths_or_secrets(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = ROOT / "default" / "ultimate" / "files" / "default-associations-v0.json"

            class SecretRunner:
                def __call__(self, _command):
                    raise RuntimeError("TOKEN=do-not-return /private/path")

            inventory = await defaults.build_provider(home=home, config_path=config, runner=SecretRunner()).read("inspect", {})
            serialized = str(inventory["availability"]["reasons"])
            self.assertNotIn("do-not-return", serialized)
            self.assertNotIn("/private/path", serialized)

            class SecretMissingRunner:
                def __call__(self, _command):
                    raise FileNotFoundError("TOKEN=still-secret /private/tool")

            missing = await defaults.build_provider(home=home, config_path=config, runner=SecretMissingRunner()).read("inspect", {})
            missing_serialized = str(missing["availability"]["reasons"])
            self.assertNotIn("still-secret", missing_serialized)
            self.assertNotIn("/private/tool", missing_serialized)

if __name__ == "__main__":
    unittest.main()
