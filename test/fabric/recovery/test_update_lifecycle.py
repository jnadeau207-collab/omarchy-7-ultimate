from __future__ import annotations

import concurrent.futures
import json
import os
import tempfile
import unittest
from pathlib import Path

from helper import FABRIC

from omarchy_fabric.models import FabricError
from omarchy_fabric.providers._engine import state_revision
from omarchy_fabric.providers.update.lifecycle import MAX_JOURNAL_BYTES, UpdateJournal


CATALOG = "sha256." + "a" * 64


class UpdateJournalTests(unittest.TestCase):
    def test_restart_preserves_revision_and_safe_cancel(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "update.json"
            journal = UpdateJournal(path)
            created = journal.create(CATALOG, mode="apply", checkpoint_required=True)
            downloading = journal.transition(created["revision"], "downloading")
            restarted = UpdateJournal(path)
            self.assertEqual(restarted.load(), downloading)
            cancelled = restarted.cancel(downloading["revision"])
            self.assertEqual(cancelled["status"], "cancelled")
            self.assertEqual(cancelled["detail"], "Cancelled before the irreversible apply boundary.")

    def test_cancellation_closes_at_apply_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            journal = UpdateJournal(Path(directory) / "update.json")
            run = journal.create(CATALOG, mode="apply", checkpoint_required=True)
            run = journal.transition(run["revision"], "staged", checkpoint="created")
            run = journal.transition(run["revision"], "applying")
            with self.assertRaises(FabricError) as unsafe:
                journal.cancel(run["revision"])
            self.assertEqual(unsafe.exception.code, "update.cancel-unsafe")

    def test_interrupted_run_reconciles_to_observed_checkpoint_and_reboot_truth(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            journal = UpdateJournal(Path(directory) / "update.json")
            run = journal.create(CATALOG, mode="apply", checkpoint_required=True)
            run = journal.transition(run["revision"], "staged", checkpoint="created")
            run = journal.transition(run["revision"], "applying")
            run = journal.transition(run["revision"], "interrupted")
            reconciled = journal.reconcile(run["revision"], {"catalogRevision": CATALOG, "checkpoint": "created", "rebootRequired": True, "complete": True})
            self.assertEqual(reconciled["status"], "waiting-reboot")
            self.assertTrue(reconciled["rebootRequired"])

    def test_catalog_drift_reconciles_to_needs_attention(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            journal = UpdateJournal(Path(directory) / "update.json")
            run = journal.create(CATALOG, mode="check", checkpoint_required=False)
            run = journal.transition(run["revision"], "checking")
            run = journal.transition(run["revision"], "interrupted")
            drifted = journal.reconcile(run["revision"], {"catalogRevision": "sha256." + "b" * 64, "checkpoint": "none", "rebootRequired": False, "complete": False})
            self.assertEqual(drifted["status"], "needs-attention")

    def test_non_apply_reconcile_cannot_report_success_with_reboot_truth(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            journal = UpdateJournal(Path(directory) / "update.json")
            run = journal.create(CATALOG, mode="check", checkpoint_required=False)
            run = journal.transition(run["revision"], "checking")
            run = journal.transition(run["revision"], "interrupted")
            reconciled = journal.reconcile(run["revision"], {"catalogRevision": CATALOG, "checkpoint": "none", "rebootRequired": True, "complete": True})
            self.assertEqual(reconciled["status"], "needs-attention")

    def test_stale_revision_wins_exactly_once_under_concurrency(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "update.json"
            journal = UpdateJournal(path)
            other = UpdateJournal(path)
            created = journal.create(CATALOG, mode="download", checkpoint_required=False)

            def transition(item: tuple[UpdateJournal, str]) -> str:
                try:
                    candidate, status = item
                    return candidate.transition(created["revision"], status)["status"]
                except FabricError as error:
                    return error.code

            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                outcomes = sorted(pool.map(transition, ((journal, "checking"), (other, "downloading"))))
            self.assertEqual(len([value for value in outcomes if value in {"checking", "downloading"}]), 1)
            self.assertEqual(outcomes.count("update.state-stale"), 1)

    def test_concurrent_create_across_instances_creates_exactly_one_run(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "update.json"
            journals = (UpdateJournal(path), UpdateJournal(path))

            def create(journal: UpdateJournal) -> str:
                try:
                    return journal.create(CATALOG, mode="check", checkpoint_required=False)["runId"]
                except FabricError as error:
                    return error.code

            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                outcomes = list(pool.map(create, journals))
            self.assertEqual(sum(value.startswith("update-run.") for value in outcomes), 1)
            self.assertEqual(outcomes.count("update.journal-exists"), 1)

    @unittest.skipUnless(hasattr(os, "fork"), "fork is required for the cross-process lock proof")
    def test_concurrent_create_across_processes_creates_exactly_one_run(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "update.json"
            start_read, start_write = os.pipe()
            result_read, result_write = os.pipe()
            child = os.fork()
            if child == 0:
                exit_code = 0
                try:
                    os.close(start_write)
                    os.close(result_read)
                    os.read(start_read, 1)
                    try:
                        outcome = UpdateJournal(path).create(CATALOG, mode="check", checkpoint_required=False)["runId"]
                    except FabricError as error:
                        outcome = error.code
                    os.write(result_write, outcome.encode("ascii"))
                except BaseException:
                    exit_code = 1
                    try:
                        os.write(result_write, b"child-error")
                    except OSError:
                        pass
                finally:
                    os._exit(exit_code)

            os.close(start_read)
            os.close(result_write)
            try:
                os.write(start_write, b"1")
                try:
                    parent_outcome = UpdateJournal(path).create(CATALOG, mode="check", checkpoint_required=False)["runId"]
                except FabricError as error:
                    parent_outcome = error.code
                child_outcome = os.read(result_read, 256).decode("ascii")
                _pid, wait_status = os.waitpid(child, 0)
            finally:
                os.close(start_write)
                os.close(result_read)
            self.assertEqual(wait_status, 0)
            outcomes = (parent_outcome, child_outcome)
            self.assertEqual(sum(value.startswith("update-run.") for value in outcomes), 1)
            self.assertEqual(outcomes.count("update.journal-exists"), 1)

    def test_apply_requires_observed_checkpoint_and_failed_checkpoint_needs_attention(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            journal = UpdateJournal(Path(directory) / "update.json")
            run = journal.create(CATALOG, mode="apply", checkpoint_required=True)
            run = journal.transition(run["revision"], "staged")
            with self.assertRaises(FabricError) as missing:
                journal.transition(run["revision"], "applying")
            self.assertEqual(missing.exception.code, "update.checkpoint-required")
            run = journal.transition(run["revision"], "applying", checkpoint="created")
            run = journal.transition(run["revision"], "interrupted")
            reconciled = journal.reconcile(run["revision"], {"catalogRevision": CATALOG, "checkpoint": "failed", "rebootRequired": False, "complete": True})
            self.assertEqual(reconciled["status"], "needs-attention")
            self.assertEqual(reconciled["checkpoint"], "failed")

    def test_mode_invariants_and_sensitive_detail_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "update.json"
            journal = UpdateJournal(path)
            run = journal.create(CATALOG, mode="check", checkpoint_required=False)
            with self.assertRaises(FabricError) as wrong_mode:
                journal.transition(run["revision"], "applying")
            self.assertEqual(wrong_mode.exception.code, "update.transition-invalid")
            run = journal.transition(run["revision"], "checking", detail="token=super-secret-value")
            self.assertEqual(run["detail"], "Sensitive update detail was redacted.")
            self.assertNotIn("super-secret-value", path.read_text(encoding="utf-8"))
            run = journal.transition(run["revision"], "succeeded", detail='{"AWS_SECRET_ACCESS_KEY":"another-secret"}')
            self.assertEqual(run["detail"], "Sensitive update detail was redacted.")
            self.assertNotIn("another-secret", path.read_text(encoding="utf-8"))

    @unittest.skipUnless(hasattr(os, "symlink"), "symbolic links are required")
    def test_symbolic_link_journal_and_parent_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target_directory = root / "target"
            target_directory.mkdir()
            linked_directory = root / "linked"
            linked_directory.symlink_to(target_directory, target_is_directory=True)
            with self.assertRaises(FabricError) as parent_link:
                UpdateJournal(linked_directory / "update.json").create(CATALOG, mode="check", checkpoint_required=False)
            self.assertEqual(parent_link.exception.code, "update.journal-path-unsafe")

            real = root / "real.json"
            real.write_text("not a journal", encoding="utf-8")
            linked_file = root / "update.json"
            linked_file.symlink_to(real)
            with self.assertRaises(FabricError) as file_link:
                UpdateJournal(linked_file).load()
            self.assertEqual(file_link.exception.code, "update.journal-path-unsafe")

    def test_corruption_duplicate_keys_revision_tampering_and_oversize_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "update.json"
            journal = UpdateJournal(path)
            valid = journal.create(CATALOG, mode="check", checkpoint_required=False)
            path.write_text(json.dumps(valid, indent=2), encoding="utf-8")
            with self.assertRaises(FabricError) as noncanonical:
                journal.load()
            self.assertEqual(noncanonical.exception.code, "update.journal-corrupt")
            path.write_text('{"schemaVersion":"v0","schemaVersion":"v0"}', encoding="utf-8")
            with self.assertRaises(FabricError) as duplicate:
                journal.load()
            self.assertEqual(duplicate.exception.code, "update.journal-corrupt")
            unsigned = {key: value for key, value in valid.items() if key != "revision"}
            unsigned["status"] = "succeeded"
            path.write_text(json.dumps({**unsigned, "revision": valid["revision"]}), encoding="utf-8")
            with self.assertRaises(FabricError) as tampered:
                journal.load()
            self.assertEqual(tampered.exception.code, "update.journal-revision-invalid")
            path.write_bytes(b"x" * (MAX_JOURNAL_BYTES + 1))
            with self.assertRaises(FabricError) as oversized:
                journal.load()
            self.assertEqual(oversized.exception.code, "update.journal-too-large")


if __name__ == "__main__":
    unittest.main()
