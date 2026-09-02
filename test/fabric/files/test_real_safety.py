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
            home_entries = [
                item for item in inventory["state"]["entries"]
                if item["locationId"] == "files.location.home"
            ]
            self.assertGreater(len(home_entries), 0)
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

    async def test_byte_bound_keeps_home_and_pictures_when_both_are_fat(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            pictures = home / "Pictures"
            desktop = home / "Desktop"
            pictures.mkdir()
            desktop.mkdir()
            (desktop / "note.txt").write_text("desktop")
            pad = "x" * 80
            for index in range(80):
                (pictures / f"shot-{index:03d}-{pad}.png").write_text("photo")
            for index in range(80):
                (home / f"dotfile-{index:03d}.txt").write_text("home")
            config = ROOT / "default" / "ultimate" / "files" / "locations-v0.json"
            provider = files.build_provider(home=home, config_path=config)
            inventory = await provider.read("inspect", {})
            by_location: dict[str, list[str]] = {}
            for item in inventory["state"]["entries"]:
                by_location.setdefault(item["locationId"], []).append(item["name"])
            self.assertGreaterEqual(len(by_location.get("files.location.home", [])), 1)
            self.assertGreaterEqual(len(by_location.get("files.location.pictures", [])), 1)
            self.assertGreaterEqual(len(by_location.get("files.location.desktop", [])), 1)
            self.assertIn("note.txt", by_location["files.location.desktop"])
            self.assertEqual(inventory["availability"]["state"], "degraded")
            self.assertFalse(inventory["availability"]["operation"])
            reason_codes = {reason["code"] for reason in inventory["availability"]["reasons"]}
            self.assertIn("files.operation-read-only", reason_codes)
            self.assertIn("files.inventory-truncated", reason_codes)
            browse = await provider.read(
                "browse",
                {"locationId": "files.location.pictures", "relativePath": "", "includeHidden": False, "limit": 20},
            )
            self.assertGreater(len(browse["entries"]), 0)
            self.assertEqual(browse["availability"]["state"], "available")

    def test_eviction_takes_surplus_pictures_before_home_floor(self) -> None:
        pictures = [
            {"id": f"files.entry.picture-{index}", "locationId": "files.location.pictures", "parentId": None}
            for index in range(20)
        ]
        home = [
            {"id": f"files.entry.home-{index}", "locationId": "files.location.home", "parentId": None}
            for index in range(files.LOCATION_ENTRY_FLOOR)
        ]
        entries = pictures + home
        index = files._evictable_leaf_index(entries, set())
        self.assertEqual(entries[index]["locationId"], "files.location.pictures")

    def test_path_normalizer_rejects_every_escape_vocabulary(self) -> None:
        for candidate in ("..", "../x", "x/..", "/x", "x/", "x//y", "x\\y", "x\x00y", "x/./y", "x\ny"):
            with self.subTest(candidate=repr(candidate)), self.assertRaises(ValueError):
                files.normalize_relative_path(candidate, allow_empty=False)
        self.assertEqual(files.normalize_relative_path("Folder/Child", allow_empty=False), "Folder/Child")
        self.assertEqual(files.normalize_relative_path("", allow_empty=True), "")

    async def test_restore_preflight_reads_real_trashinfo_and_keeps_inspect_honest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            documents = home / "Documents"
            documents.mkdir()
            trash_files = home / ".local" / "share" / "Trash" / "files"
            trash_info = home / ".local" / "share" / "Trash" / "info"
            trash_files.mkdir(parents=True)
            trash_info.mkdir(parents=True)
            original = documents / "report.txt"
            (trash_files / "report.txt").write_text("restore-me\n", encoding="utf-8")
            (trash_info / "report.txt.trashinfo").write_text(
                "[Trash Info]\n"
                f"Path={original.as_posix()}\n"
                "DeletionDate=2026-09-02T12:00:00\n",
                encoding="utf-8",
            )
            config = ROOT / "default" / "ultimate" / "files" / "locations-v0.json"
            provider = files.build_provider(home=home, config_path=config, session_operable=True)
            inventory = await provider.read("inspect", {})
            trash_entries = [
                item
                for item in inventory["state"]["entries"]
                if item["locationId"] == "files.location.trash" and item["name"] == "report.txt"
            ]
            self.assertEqual(len(trash_entries), 1)
            self.assertIsNone(trash_entries[0]["trash"])
            plan = await provider.preflight("trash.restore", {"entryId": trash_entries[0]["id"]}, principal())
            self.assertEqual(plan["risk"], "consequential")
            current = plan["currentState"]["value"]
            proposed = plan["proposedState"]["value"]
            self.assertEqual(current["locationId"], "files.location.documents")
            self.assertNotIn("report.txt", current["names"])
            self.assertIn("report.txt", proposed["names"])
            reread = await provider.read("inspect", {})
            again = next(item for item in reread["state"]["entries"] if item["id"] == trash_entries[0]["id"])
            self.assertIsNone(again["trash"])

    async def test_restore_preflight_refuses_unsafe_or_unresolvable_trash_records(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            documents = home / "Documents"
            documents.mkdir()
            trash_files = home / ".local" / "share" / "Trash" / "files"
            trash_info = home / ".local" / "share" / "Trash" / "info"
            (trash_files / "folder").mkdir(parents=True)
            trash_info.mkdir(parents=True)
            records = {
                "report.txt": f"{documents}/report.txt",
                "outside.txt": "/etc/outside.txt",
                "dotdot.txt": f"{documents}/../Documents/dotdot.txt",
                "orphan.txt": f"{documents}/Gone/orphan.txt",
            }
            for name, original in records.items():
                (trash_files / name).write_text("x", encoding="utf-8")
                (trash_info / f"{name}.trashinfo").write_text(
                    f"[Trash Info]\nPath={original}\nDeletionDate=2026-09-02T12:00:00\n",
                    encoding="utf-8",
                )
            (trash_files / "folder" / "report.txt").write_text("nested", encoding="utf-8")
            config = ROOT / "default" / "ultimate" / "files" / "locations-v0.json"
            provider = files.build_provider(home=home, config_path=config, session_operable=True)
            inventory = await provider.read("inspect", {})
            by_path = {
                item["relativePath"]: item["id"]
                for item in inventory["state"]["entries"]
                if item["locationId"] == "files.location.trash"
            }
            expectations = {
                "outside.txt": "The Trash record points outside this account's home.",
                "dotdot.txt": "The Trash record does not name a writable Files location.",
                "orphan.txt": "The original restore parent is unavailable.",
                "folder/report.txt": "The Trash record for this entry is missing or unsafe.",
                "folder": "The Trash record for this entry is missing or unsafe.",
            }
            for relative, explanation in expectations.items():
                with self.assertRaises(FabricError) as caught:
                    await provider.preflight("trash.restore", {"entryId": by_path[relative]}, principal())
                self.assertEqual(caught.exception.code, "files.precondition-failed", relative)
                self.assertEqual(caught.exception.explanation, explanation, relative)
            plan = await provider.preflight("trash.restore", {"entryId": by_path["report.txt"]}, principal())
            self.assertEqual(plan["currentState"]["value"]["locationId"], "files.location.documents")

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
