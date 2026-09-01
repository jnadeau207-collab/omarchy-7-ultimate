from __future__ import annotations

import asyncio
import multiprocessing
import os
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from unittest.mock import patch

from helper import ROOT, clone_workspace, entry, principal

from omarchy_fabric.models import FabricError
from omarchy_fabric.providers._engine import state_revision
from omarchy_fabric.providers.files import provider as files

def _persistent_cas_worker(state_path: str, new_name: str, barrier, results) -> None:
    async def run() -> tuple[str, str]:
        provider = files.build_fake_provider(clone_workspace(), state_path=Path(state_path))
        plan = await provider.preflight(
            "entry.rename",
            {"entryId": "files.entry.notes", "newName": new_name},
            principal(),
        )
        barrier.wait(timeout=10)
        try:
            changed = await provider.execute(
                "entry.rename",
                plan["normalizedArguments"],
                plan["stateRevision"],
            )
            return "ok", changed["stateRevision"]
        except FabricError as error:
            return "error", f"{error.code}:{error.detail}"

    results.put(asyncio.run(run()))

class FilesAdversarialHardeningTests(unittest.IsolatedAsyncioTestCase):
    def test_workspace_rejects_orphaned_descendant_paths(self) -> None:
        state = clone_workspace()
        state["entries"].append(
            entry(
                "files.entry.orphan",
                "files.location.desktop",
                "child.txt",
                "missing/child.txt",
                "file",
            )
        )
        with self.assertRaisesRegex(ValueError, "parent"):
            files.build_fake_provider(state)

    def test_unicode_controls_and_mount_authority_spoofing_are_rejected(self) -> None:
        for value in ("safe/\u202e.txt", "safe/\udcff.txt"):
            with self.subTest(value=repr(value)), self.assertRaises(ValueError):
                files.normalize_relative_path(value, allow_empty=False)
        self.assertEqual(
            files._safe_smb_source("//domain;user:secret@server/share/private/path"),
            ("server", "share"),
        )
        for source in ("server/share", "//server", "//user:secret@/share", "//server/share\\escape"):
            with self.subTest(source=source):
                self.assertIsNone(files._safe_smb_source(source))
        spoofed = clone_workspace()
        team = next(mount for mount in spoofed["mounts"] if mount["id"] == "files.mount.team")
        team["source"] = {"scheme": "device", "display": "spoof", "host": None, "share": None}
        with self.assertRaisesRegex(ValueError, "SMB mount authority"):
            files.build_fake_provider(spoofed)

    def test_mount_inventory_uses_kernel_type_and_aggregates_redacted_degradation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = ROOT / "default" / "ultimate" / "files" / "locations-v0.json"
            backend = files.RealFilesBackend(home, config)
            lines = [
                f"{index + 30} 25 0:{index + 40} / /mnt/share-{index} rw - cifs //user:secret@server/share-{index}/private rw"
                for index in range(20)
            ]
            lines.append("99 25 0:99 / /mnt/spoof rw - ext4 //user:secret@spoof/share rw")
            with patch.object(Path, "read_bytes", return_value=("\n".join(lines) + "\n").encode()):
                mounts, locations, reasons = backend._mounts(64)
            self.assertEqual(len(mounts), 21)
            self.assertEqual(len(locations), 20)
            self.assertEqual([reason.code for reason in reasons], ["files.mount-browse-deferred"])
            serialized = str((mounts, locations, [reason.to_dict() for reason in reasons]))
            self.assertNotIn("secret", serialized)
            spoof = next(mount for mount in mounts if mount["label"] == "spoof")
            self.assertEqual(spoof["kind"], "system")
            self.assertEqual(spoof["source"], {"scheme": "system", "display": "System mount", "host": None, "share": None})

    async def test_forged_recovery_revision_is_rejected_before_any_write(self) -> None:
        provider = files.build_fake_provider(clone_workspace())
        plan = await provider.preflight(
            "entry.rename",
            {"entryId": "files.entry.notes", "newName": "memo.txt"},
            principal(),
        )
        changed = await provider.execute(
            "entry.rename",
            plan["normalizedArguments"],
            plan["stateRevision"],
        )
        forged = deepcopy(plan["recovery"]["priorState"])
        forged["revision"] = f"sha256.{64 * '0'}"
        with self.assertRaises(FabricError) as rejected:
            await provider.undo("entry.rename", forged, changed["stateRevision"])
        self.assertEqual(rejected.exception.code, "files.state-corrupt")
        self.assertEqual(provider.backend.write_count, 1)
        current = await provider.read("inspect", {})
        note = next(item for item in current["state"]["entries"] if item["id"] == "files.entry.notes")
        self.assertEqual(note["relativePath"], "memo.txt")

    async def test_old_recovery_plan_cannot_rollback_over_newer_intent(self) -> None:
        provider = files.build_fake_provider(clone_workspace())
        old_plan = await provider.preflight(
            "entry.rename",
            {"entryId": "files.entry.notes", "newName": "memo.txt"},
            principal(),
        )
        first = await provider.execute(
            "entry.rename",
            old_plan["normalizedArguments"],
            old_plan["stateRevision"],
        )
        new_plan = await provider.preflight(
            "entry.rename",
            {"entryId": "files.entry.readme", "newName": "GUIDE.txt"},
            principal(),
        )
        newer = await provider.execute(
            "entry.rename",
            new_plan["normalizedArguments"],
            new_plan["stateRevision"],
        )
        with self.assertRaises(FabricError) as stale:
            await provider.undo(
                "entry.rename",
                old_plan["recovery"]["priorState"],
                newer["stateRevision"],
            )
        self.assertEqual(stale.exception.code, "files.state-stale")
        current = await provider.read("inspect", {})
        paths = {item["id"]: item["relativePath"] for item in current["state"]["entries"]}
        self.assertEqual(paths["files.entry.notes"], "memo.txt")
        self.assertEqual(paths["files.entry.readme"], "Project/GUIDE.txt")
        self.assertNotEqual(first["stateRevision"], newer["stateRevision"])

    async def test_two_restarted_instances_share_one_durable_cas_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "files.json"
            first = files.build_fake_provider(clone_workspace(), state_path=state_path)
            second = files.build_fake_provider(clone_workspace(), state_path=state_path)
            first_plan = await first.preflight(
                "entry.rename",
                {"entryId": "files.entry.notes", "newName": "first.txt"},
                principal(),
            )
            second_plan = await second.preflight(
                "entry.rename",
                {"entryId": "files.entry.notes", "newName": "second.txt"},
                principal(),
            )
            await first.execute(
                "entry.rename",
                first_plan["normalizedArguments"],
                first_plan["stateRevision"],
            )
            with self.assertRaises(FabricError) as stale:
                await second.execute(
                    "entry.rename",
                    second_plan["normalizedArguments"],
                    second_plan["stateRevision"],
                )
            self.assertEqual(stale.exception.code, "files.state-stale")
            restarted = files.build_fake_provider(clone_workspace(), state_path=state_path)
            current = await restarted.read("inspect", {})
            note = next(item for item in current["state"]["entries"] if item["id"] == "files.entry.notes")
            self.assertEqual(note["relativePath"], "first.txt")

    @unittest.skipUnless(os.name == "posix", "cross-process advisory lock coverage requires Linux")
    def test_independent_processes_share_one_durable_cas_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "files.json"
            context = multiprocessing.get_context("fork")
            barrier = context.Barrier(2)
            results = context.Queue()
            processes = [
                context.Process(
                    target=_persistent_cas_worker,
                    args=(os.fspath(state_path), name, barrier, results),
                )
                for name in ("first.txt", "second.txt")
            ]
            for process in processes:
                process.start()
            for process in processes:
                process.join(timeout=15)
            try:
                self.assertTrue(all(not process.is_alive() for process in processes))
                self.assertTrue(all(process.exitcode == 0 for process in processes))
                outcomes = [results.get(timeout=5) for _process in processes]
            finally:
                for process in processes:
                    if process.is_alive():
                        process.terminate()
                        process.join(timeout=5)
                results.close()
                results.join_thread()
            self.assertEqual(sum(outcome[0] == "ok" for outcome in outcomes), 1)
            self.assertEqual(
                [outcome for outcome in outcomes if outcome[0] == "error"],
                [("error", "files.state-stale:")],
            )

    async def test_cancel_while_waiting_for_cas_lock_performs_no_write(self) -> None:
        provider = files.build_fake_provider(clone_workspace())
        plan = await provider.preflight(
            "entry.rename",
            {"entryId": "files.entry.notes", "newName": "memo.txt"},
            principal(),
        )
        await provider.backend._lock.acquire()
        task = asyncio.create_task(
            provider.execute("entry.rename", plan["normalizedArguments"], plan["stateRevision"])
        )
        await asyncio.sleep(0)
        task.cancel()
        try:
            with self.assertRaises(asyncio.CancelledError):
                await task
        finally:
            provider.backend._lock.release()
        self.assertEqual(provider.backend.write_count, 0)

    async def test_trashing_a_directory_removes_its_whole_subtree_from_recent(self) -> None:
        state = clone_workspace()
        state["recent"] = [
            {"entryId": "files.entry.readme", "rank": 0},
            {"entryId": "files.entry.notes", "rank": 1},
        ]
        provider = files.build_fake_provider(state)
        plan = await provider.preflight("entry.trash", {"entryId": "files.entry.project"}, principal())
        changed = await provider.execute("entry.trash", plan["normalizedArguments"], plan["stateRevision"])
        self.assertEqual(changed["state"]["value"]["recent"], [{"entryId": "files.entry.notes", "rank": 0}])

    def test_trash_recovery_metadata_cannot_reintroduce_traversal(self) -> None:
        state = clone_workspace()
        project = next(item for item in state["entries"] if item["id"] == "files.entry.project")
        readme = next(item for item in state["entries"] if item["id"] == "files.entry.readme")
        project["locationId"] = "files.location.trash"
        project["trash"] = {
            "originalLocationId": "files.location.desktop",
            "originalParentId": None,
            "originalRelativePath": "../escape",
        }
        readme["locationId"] = "files.location.trash"
        with self.assertRaises(ValueError):
            files.build_fake_provider(state)

    @unittest.skipUnless(os.name == "posix", "no-follow persistence coverage requires Linux")
    async def test_persistent_state_and_metadata_inputs_refuse_symlink_hops(self) -> None:
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as outside_directory:
            root = Path(directory)
            outside = Path(outside_directory)
            state_path = outside / "state.json"
            provider = files.build_fake_provider(clone_workspace(), state_path=state_path)
            plan = await provider.preflight(
                "entry.rename",
                {"entryId": "files.entry.notes", "newName": "memo.txt"},
                principal(),
            )
            await provider.execute("entry.rename", plan["normalizedArguments"], plan["stateRevision"])
            state_link = root / "state.json"
            state_link.symlink_to(state_path)
            with self.assertRaises(ValueError):
                files.build_fake_provider(clone_workspace(), state_path=state_link)

            home = root / "home"
            desktop = home / "Desktop"
            recent_parent = home / ".local" / "share"
            desktop.mkdir(parents=True)
            recent_parent.mkdir(parents=True)
            (desktop / "visible.txt").write_text("visible")
            outside_recent = outside / "recently-used.xbel"
            outside_recent.write_text(
                f'<xbel><bookmark href="{(desktop / "visible.txt").as_uri()}"/></xbel>'
            )
            (recent_parent / "recently-used.xbel").symlink_to(outside_recent)
            config = ROOT / "default" / "ultimate" / "files" / "locations-v0.json"
            inventory = await files.build_provider(home=home, config_path=config).read("inspect", {})
            self.assertEqual(inventory["state"]["recent"], [])
            self.assertTrue(
                any(reason["code"] == "files.recent-invalid" for reason in inventory["availability"]["reasons"])
            )

    @unittest.skipUnless(os.name == "posix", "ancestor no-follow coverage requires Linux")
    def test_code_owned_config_refuses_an_ancestor_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            real = root / "real"
            real.mkdir()
            config = real / "locations.json"
            config.write_bytes((ROOT / "default" / "ultimate" / "files" / "locations-v0.json").read_bytes())
            alias = root / "alias"
            alias.symlink_to(real, target_is_directory=True)
            home = root / "home"
            home.mkdir()
            with self.assertRaises(ValueError):
                files.build_provider(home=home, config_path=alias / "locations.json")

if __name__ == "__main__":
    unittest.main()
