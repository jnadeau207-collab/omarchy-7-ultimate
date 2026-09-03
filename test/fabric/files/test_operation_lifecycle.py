from __future__ import annotations

import asyncio
import os
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path

from helper import clone_workspace, entry, principal

from omarchy_fabric.models import FabricError
from omarchy_fabric.providers._engine import state_revision
from omarchy_fabric.providers.files import provider as files

class OperationLifecycleTests(unittest.IsolatedAsyncioTestCase):
    async def exercise(
        self,
        action: str,
        arguments: dict[str, object],
        assertion,
    ) -> None:
        provider = files.build_fake_provider(clone_workspace())
        before = await provider.read("inspect", {})
        plan = await provider.preflight(action, arguments, principal())
        self.assertEqual(plan["guards"]["snapshotRevision"], plan["stateRevision"])
        self.assertTrue(plan["guards"]["noFollow"])
        self.assertEqual(plan["guards"]["pathPolicy"], "location-relative-v0")
        self.assertGreaterEqual(len(plan["guards"]["anchors"]), 1)
        self.assertEqual(provider.backend.write_count, 0)
        result = await provider.execute(action, plan["normalizedArguments"], plan["stateRevision"])
        self.assertTrue(result["changed"])
        self.assertEqual(provider.backend.write_count, 1)
        assertion(result["state"]["value"])
        validated = await provider.validate(action, plan["normalizedArguments"], result["state"])
        self.assertFalse(validated["changed"])
        undone = await provider.undo(action, plan["recovery"]["priorState"], result["stateRevision"])
        self.assertTrue(undone["changed"])
        self.assertEqual(undone["state"]["value"], before["state"])
        self.assertEqual(provider.backend.write_count, 2)

    async def test_all_safe_representative_operations_execute_validate_and_undo(self) -> None:
        await self.exercise(
            "directory.create",
            {"locationId": "files.location.desktop", "parentRelativePath": "Project", "name": "Assets"},
            lambda state: self.assertIn("Assets", state["names"]),
        )
        await self.exercise(
            "entry.rename",
            {"entryId": "files.entry.project", "newName": "Renamed"},
            lambda state: self.assertEqual(
                (
                    state["locationId"],
                    state["parentRelativePath"],
                    "Renamed" in state["names"],
                    "Project" in state["names"],
                    state["selectedEntry"]["entryId"],
                ),
                ("files.location.desktop", "", True, False, "files.entry.project"),
            ),
        )
        await self.exercise(
            "entry.trash",
            {"entryId": "files.entry.project"},
            lambda state: self.assertEqual(
                (state["locationId"], state["parentRelativePath"], "Project" in state["names"]),
                ("files.location.desktop", "", False),
            ),
        )
        await self.exercise(
            "mount.connect",
            {"mountId": "files.mount.usb"},
            lambda state: self.assertEqual(next(item for item in state["mounts"] if item["id"] == "files.mount.usb")["state"], "mounted"),
        )
        await self.exercise(
            "mount.disconnect",
            {"mountId": "files.mount.team"},
            lambda state: self.assertEqual(next(item for item in state["mounts"] if item["id"] == "files.mount.team")["state"], "unmounted"),
        )

    async def test_trash_restore_has_exact_recovery_metadata_and_undo(self) -> None:
        provider = files.build_fake_provider(clone_workspace())
        trash_plan = await provider.preflight("entry.trash", {"entryId": "files.entry.project"}, principal())
        trashed = await provider.execute("entry.trash", trash_plan["normalizedArguments"], trash_plan["stateRevision"])
        self.assertNotIn("Project", trashed["state"]["value"]["names"])
        workspace = await provider.read("inspect", {})
        selected = next(item for item in workspace["state"]["entries"] if item["id"] == "files.entry.project")
        self.assertEqual(selected["trash"], {
            "originalLocationId": "files.location.desktop",
            "originalParentId": None,
            "originalRelativePath": "Project",
        })
        restore_plan = await provider.preflight("trash.restore", {"entryId": "files.entry.project"}, principal())
        before_restore = await provider.read("inspect", {})
        restored = await provider.execute("trash.restore", restore_plan["normalizedArguments"], restore_plan["stateRevision"])
        self.assertIn("Project", restored["state"]["value"]["names"])
        workspace = await provider.read("inspect", {})
        paths = {item["id"]: item["relativePath"] for item in workspace["state"]["entries"]}
        self.assertEqual(paths["files.entry.project"], "Project")
        self.assertEqual(paths["files.entry.readme"], "Project/README.txt")
        undone = await provider.undo("trash.restore", restore_plan["recovery"]["priorState"], restored["stateRevision"])
        self.assertEqual(undone["state"]["value"], before_restore["state"])

    async def test_entry_open_is_a_low_risk_launch_with_no_listing_change(self) -> None:
        provider = files.build_fake_provider(clone_workspace())
        before = await provider.read("inspect", {})
        plan = await provider.preflight("entry.open", {"entryId": "files.entry.notes"}, principal())
        self.assertEqual(plan["capability"], "files.entry.open")
        self.assertEqual(plan["risk"], "low")
        self.assertEqual(plan["effects"], ["launch"])
        self.assertFalse(plan["changed"])
        self.assertEqual(plan["guards"]["selectedEntry"], {
            "entryId": "files.entry.notes",
            "locationId": "files.location.desktop",
            "entryRelativePath": "notes.txt",
        })
        self.assertEqual(plan["currentState"]["value"]["names"], plan["proposedState"]["value"]["names"])
        self.assertEqual(provider.backend.write_count, 0)
        result = await provider.execute("entry.open", plan["normalizedArguments"], plan["stateRevision"])
        self.assertFalse(result["changed"])
        self.assertEqual(provider.backend.write_count, 0)
        after = await provider.read("inspect", {})
        self.assertEqual(after["state"], before["state"])
        with self.assertRaises(FabricError) as directory:
            await provider.preflight("entry.open", {"entryId": "files.entry.project"}, principal())
        self.assertEqual(directory.exception.code, "files.precondition-failed")
        with self.assertRaises(FabricError) as symlink:
            await provider.preflight("entry.open", {"entryId": "files.entry.unsafe-link"}, principal())
        self.assertEqual(symlink.exception.code, "files.precondition-failed")
        with self.assertRaises(FabricError) as undo:
            await provider.undo("entry.open", plan["recovery"]["priorState"], plan["stateRevision"])
        self.assertEqual(undo.exception.code, "files.undo-unavailable")

    async def test_compare_and_swap_contains_concurrent_execution_and_toctou_drift(self) -> None:
        provider = files.build_fake_provider(clone_workspace())
        arguments = {"entryId": "files.entry.notes", "newName": "memo.txt"}
        plan = await provider.preflight("entry.rename", arguments, principal())
        results = await asyncio.gather(
            provider.execute("entry.rename", plan["normalizedArguments"], plan["stateRevision"]),
            provider.execute("entry.rename", plan["normalizedArguments"], plan["stateRevision"]),
            return_exceptions=True,
        )
        self.assertEqual(sum(not isinstance(result, Exception) for result in results), 1)
        stale = next(result for result in results if isinstance(result, FabricError))
        self.assertEqual(stale.code, "files.state-stale")
        self.assertEqual(provider.backend.write_count, 1)

        drift_provider = files.build_fake_provider(clone_workspace())
        drift_plan = await drift_provider.preflight("entry.rename", arguments, principal())
        drift = clone_workspace()
        note = next(item for item in drift["entries"] if item["id"] == "files.entry.notes")
        note["identity"] = state_revision({"entry": note["id"], "generation": 2})
        await drift_provider.backend.force_state(files.canonicalize_workspace(drift))
        with self.assertRaises(FabricError) as changed:
            await drift_provider.execute("entry.rename", drift_plan["normalizedArguments"], drift_plan["stateRevision"])
        self.assertEqual(changed.exception.code, "files.state-stale")
        self.assertEqual(drift_provider.backend.write_count, 0)

    async def test_symlink_traversal_collision_and_principal_fail_closed(self) -> None:
        provider = files.build_fake_provider(clone_workspace())
        with self.assertRaises(FabricError) as symlink:
            await provider.preflight("entry.rename", {"entryId": "files.entry.unsafe-link", "newName": "safe"}, principal())
        self.assertEqual(symlink.exception.code, "files.precondition-failed")
        for path in ("../escape", "/absolute", "Project//child", "Project\\child", "Project/./child"):
            with self.subTest(path=path), self.assertRaises(FabricError):
                await provider.preflight(
                    "directory.create",
                    {"locationId": "files.location.desktop", "parentRelativePath": path, "name": "New"},
                    principal(),
                )
        with self.assertRaises(FabricError) as collision:
            await provider.preflight(
                "directory.create",
                {"locationId": "files.location.desktop", "parentRelativePath": "", "name": "Project"},
                principal(),
            )
        self.assertEqual(collision.exception.code, "files.precondition-failed")
        with self.assertRaises(FabricError) as unauthenticated:
            await provider.preflight("entry.rename", {"entryId": "files.entry.notes", "newName": "memo"}, object())
        self.assertEqual(unauthenticated.exception.code, "principal.required")

    async def test_restart_noop_backend_failure_and_corruption_are_contained(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "files.json"
            provider = files.build_fake_provider(clone_workspace(), state_path=state_path)
            plan = await provider.preflight("entry.rename", {"entryId": "files.entry.notes", "newName": "memo.txt"}, principal())
            result = await provider.execute("entry.rename", plan["normalizedArguments"], plan["stateRevision"])
            if os.name == "posix":
                self.assertEqual(state_path.stat().st_mode & 0o777, 0o600)
            restarted = files.build_fake_provider(clone_workspace(), state_path=state_path)
            inventory = await restarted.read("inspect", {})
            note = next(item for item in inventory["state"]["entries"] if item["id"] == "files.entry.notes")
            self.assertEqual(note["relativePath"], "memo.txt")
            self.assertEqual(result["state"]["value"]["selectedEntry"]["entryId"], "files.entry.notes")
            self.assertIn("memo.txt", result["state"]["value"]["names"])
            noop = await restarted.execute("entry.rename", plan["normalizedArguments"], result["stateRevision"])
            self.assertFalse(noop["changed"])
            self.assertEqual(restarted.backend.write_count, 0)

            state_path.write_text('{"schemaVersion":"v0","domain":"files","state":{},"state":{}}')
            with self.assertRaises(ValueError):
                files.build_fake_provider(clone_workspace(), state_path=state_path)
            state_path.write_text('{"schemaVersion":"v0","domain":"files","state":{"value":NaN}}')
            with self.assertRaises(ValueError):
                files.build_fake_provider(clone_workspace(), state_path=state_path)

        failing = files.build_fake_provider(clone_workspace(), fail_on=frozenset({"execute"}))
        plan = await failing.preflight("entry.rename", {"entryId": "files.entry.notes", "newName": "memo.txt"}, principal())
        with self.assertRaises(FabricError) as failure:
            await failing.execute("entry.rename", plan["normalizedArguments"], plan["stateRevision"])
        self.assertEqual(failure.exception.code, "files.fake-execute-failed")
        self.assertEqual(failing.backend.write_count, 0)

        oversized = clone_workspace()
        for index in range(64):
            oversized["entries"].append(entry(
                f"files.entry.extra-{index}",
                "files.location.desktop",
                f"extra-{index}.txt",
                f"extra-{index}.txt",
                "file",
            ))
        with self.assertRaisesRegex(ValueError, "12 KiB"):
            files.build_fake_provider(oversized)

if __name__ == "__main__":
    unittest.main()
