from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from helper import ROOT, principal

from omarchy_fabric.models import FabricError
from omarchy_fabric.providers.files import provider as files


@unittest.skipUnless(os.name == "posix", "no-follow openat coverage requires Linux")
class RealFilesSafetyTests(unittest.IsolatedAsyncioTestCase):
    async def test_real_inventory_reads_bounded_state_without_following_symlinks(self) -> None:
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as outside_directory:
            home = Path(directory)
            desktop = home / "Desktop"
            desktop.mkdir()
            (desktop / "visible.txt").write_text("visible")
            nested = desktop / "Folder"
            nested.mkdir()
            (nested / "inside.txt").write_text("inside")
            outside = Path(outside_directory) / "secret"
            outside.write_text("must not be read")
            (desktop / "escape").symlink_to(outside)
            config = ROOT / "default" / "ultimate" / "files" / "locations-v0.json"
            provider = files.build_provider(home=home, config_path=config)

            inventory = await provider.read("inspect", {})
            self.assertTrue(inventory["availability"]["read"])
            self.assertEqual(inventory["availability"]["state"], "degraded")
            self.assertFalse(inventory["availability"]["operation"])
            desktop_entries = [item for item in inventory["state"]["entries"] if item["locationId"] == "files.location.desktop"]
            by_name = {item["name"]: item for item in desktop_entries}
            self.assertEqual(by_name["escape"]["kind"], "symlink")
            self.assertEqual(by_name["escape"]["symlinkTargetState"], "unknown")
            self.assertNotIn("secret", {item["name"] for item in desktop_entries})
            self.assertIn("Folder/inside.txt", {item["relativePath"] for item in desktop_entries})
            self.assertTrue(any(reason["code"] == "files.operation-read-only" for reason in inventory["availability"]["reasons"]))

            with self.assertRaises(FabricError) as unavailable:
                await provider.preflight(
                    "directory.create",
                    {"locationId": "files.location.desktop", "parentRelativePath": "", "name": "NeverWritten"},
                    principal(),
                )
            self.assertEqual(unavailable.exception.code, "files.operation-unavailable")
            self.assertFalse((desktop / "NeverWritten").exists())

    async def test_standard_xdg_home_root_and_escaped_spaces_parse_without_shell_evaluation(self) -> None:
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as downloads_directory:
            home = Path(directory)
            (home / ".config").mkdir()
            (home / "My Documents").mkdir()
            (home / ".config" / "user-dirs.dirs").write_text(
                'XDG_DESKTOP_DIR="$HOME/"\n'
                'XDG_DOCUMENTS_DIR="$HOME/My\\ Documents"\n'
                f'XDG_DOWNLOAD_DIR="{downloads_directory}"\n'
            )
            config = ROOT / "default" / "ultimate" / "files" / "locations-v0.json"
            inventory = await files.build_provider(home=home, config_path=config).read("inspect", {})
            reason_codes = {reason["code"] for reason in inventory["availability"]["reasons"]}
            self.assertNotIn("files.user-dirs-invalid", reason_codes)
            locations = {item["id"]: item for item in inventory["state"]["locations"]}
            self.assertEqual(locations["files.location.desktop"]["state"], "available")
            self.assertEqual(locations["files.location.documents"]["state"], "available")
            self.assertEqual(locations["files.location.downloads"]["state"], "available")

    async def test_symlink_home_and_malicious_recent_document_fail_honestly(self) -> None:
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as target_directory:
            root = Path(directory)
            home_link = root / "home"
            home_link.symlink_to(Path(target_directory), target_is_directory=True)
            config = ROOT / "default" / "ultimate" / "files" / "locations-v0.json"
            unavailable_provider = files.build_provider(home=home_link, config_path=config)
            unavailable = await unavailable_provider.read("inspect", {})
            self.assertEqual(unavailable["availability"]["state"], "unavailable")
            self.assertIsNone(unavailable["state"])
            self.assertEqual(unavailable["availability"]["reasons"][0]["code"], "files.home-unsafe")

            home = root / "real-home"
            (home / ".local" / "share").mkdir(parents=True)
            (home / ".local" / "share" / "recently-used.xbel").write_text(
                '<!DOCTYPE xbel [<!ENTITY leak SYSTEM "file:///etc/passwd">]><xbel>&leak;</xbel>'
            )
            provider = files.build_provider(home=home, config_path=config)
            inventory = await provider.read("inspect", {})
            self.assertTrue(any(reason["code"] == "files.recent-invalid" for reason in inventory["availability"]["reasons"]))
            self.assertEqual(inventory["state"]["recent"], [])

    async def test_start_places_survive_a_fat_home_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            pictures = home / "Pictures"
            pictures.mkdir()
            (pictures / "sunset.png").write_text("photo")
            for index in range(256):
                (home / f"noise-{index:03d}.txt").write_text("pad")
            config = ROOT / "default" / "ultimate" / "files" / "locations-v0.json"
            provider = files.build_provider(home=home, config_path=config)
            inventory = await provider.read("inspect", {})
            pictures_entries = [
                item for item in inventory["state"]["entries"]
                if item["locationId"] == "files.location.pictures"
            ]
            self.assertIn("sunset.png", {item["name"] for item in pictures_entries})
            locations = {item["id"]: item for item in inventory["state"]["locations"]}
            self.assertEqual(locations["files.location.pictures"]["state"], "available")
            reason_codes = {reason["code"] for reason in inventory["availability"]["reasons"]}
            self.assertNotIn("files.location-absent", reason_codes)
            self.assertNotIn("files.location-unavailable", reason_codes)
            browse = await provider.read(
                "browse",
                {"locationId": "files.location.pictures", "relativePath": "", "includeHidden": False, "limit": 20},
            )
            self.assertIn("sunset.png", {item["name"] for item in browse["entries"]})
            self.assertEqual(browse["availability"]["state"], "available")
            self.assertEqual(browse["availability"]["reasons"], [])
            trash_browse = await provider.read(
                "browse",
                {"locationId": "files.location.trash", "relativePath": "", "includeHidden": False, "limit": 20},
            )
            self.assertEqual(trash_browse["availability"]["state"], "unavailable")
            self.assertEqual(trash_browse["availability"]["reasons"][0]["code"], "files.location-absent")

    def test_path_normalizer_rejects_every_escape_vocabulary(self) -> None:
        for candidate in ("..", "../x", "x/..", "/x", "x/", "x//y", "x\\y", "x\x00y", "x/./y", "x\ny"):
            with self.subTest(candidate=repr(candidate)), self.assertRaises(ValueError):
                files.normalize_relative_path(candidate, allow_empty=False)
        self.assertEqual(files.normalize_relative_path("Folder/Child", allow_empty=False), "Folder/Child")
        self.assertEqual(files.normalize_relative_path("", allow_empty=True), "")

    def test_provider_rejects_relative_or_symlinked_code_owned_config(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir()
            config = ROOT / "default" / "ultimate" / "files" / "locations-v0.json"
            config_link = root / "locations.json"
            config_link.symlink_to(config)
            with self.assertRaisesRegex(ValueError, "real file"):
                files.build_provider(home=home, config_path=config_link)
            with self.assertRaisesRegex(ValueError, "absolute"):
                files.build_provider(home=Path("relative-home"), config_path=config)


if __name__ == "__main__":
    unittest.main()
