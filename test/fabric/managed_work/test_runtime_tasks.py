from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from helper import ACTOR, OTHER_ACTOR, ManagedWorkPlane, budget, create_task
from omarchy_fabric.desktop_context import capture_desktop_context
from omarchy_fabric.managed_runtime import ManagedRuntime
from omarchy_fabric.managed_work import ManagedWorkError
from omarchy_fabric.models import FabricError
from sandbox.builder import SandboxUnavailable


class RuntimeTaskTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.plane = ManagedWorkPlane(Path(self.temporary.name) / "managed-work.db").open()
        self.runtime = ManagedRuntime(self.plane)

    def tearDown(self) -> None:
        self.plane.close()
        self.temporary.cleanup()

    def test_create_list_cancel_round_trip(self) -> None:
        created = self.runtime.create_task(
            ACTOR,
            {
                "title": "Inventory probe",
                "intent": {"goal": "inventory", "readOnly": True},
                "contextIds": [],
                "budget": budget(),
                "idempotencyKey": "task.runtime-create",
            },
        )
        self.assertEqual("draft", created["state"])
        listed = self.runtime.list_tasks(ACTOR, {"limit": 10})
        identities = [item["task"]["taskId"] for item in listed["items"] if item.get("task")]
        self.assertIn(created["taskId"], identities)
        cancelled = self.runtime.cancel_task(
            ACTOR,
            {"taskId": created["taskId"], "expectedRevision": created["revision"]},
        )
        self.assertEqual("cancelled", cancelled["state"])
        self.assertEqual("cancelled", self.plane.get_task(ACTOR, created["taskId"])["state"])

    def test_context_capture_windows_focus_selection_and_exclusions(self) -> None:
        snapshot = {
            "windows": [
                {"class": "foot", "title": "terminal", "address": "0x1", "focused": True},
                {"class": "hyprlock", "title": "Lock", "address": "0x2", "focused": False},
                {"class": "pinentry", "title": "Password", "address": "0x3", "focused": False},
            ],
            "focus": {"class": "foot", "title": "terminal", "address": "0x1"},
            "selection": {"text": "visible phrase"},
        }
        windows = capture_desktop_context(
            self.plane,
            ACTOR,
            source="open-windows",
            snapshot=snapshot,
            idempotency_key="context.windows",
            now=1_000,
        )
        classes = [item["class"] for item in windows["content"]["windows"]]
        self.assertEqual(["foot"], classes)
        focus = capture_desktop_context(
            self.plane,
            ACTOR,
            source="focused-application",
            snapshot=snapshot,
            idempotency_key="context.focus",
            now=1_001,
        )
        self.assertEqual("foot", focus["content"]["application"])
        selection = capture_desktop_context(
            self.plane,
            ACTOR,
            source="selection",
            snapshot=snapshot,
            idempotency_key="context.selection",
            now=1_002,
        )
        self.assertEqual("visible phrase", selection["content"]["selection"]["text"])
        with self.assertRaises(ManagedWorkError) as excluded:
            capture_desktop_context(
                self.plane,
                ACTOR,
                source="password-field",
                snapshot=snapshot,
                idempotency_key="context.password",
                now=1_003,
            )
        self.assertEqual("context.source-excluded", excluded.exception.code)

    def test_restart_recovery_does_not_guess_success(self) -> None:
        path = Path(self.temporary.name) / "restart.db"
        plane = ManagedWorkPlane(path).open()
        runtime = ManagedRuntime(plane)
        task = runtime.create_task(
            ACTOR,
            {
                "title": "Running work",
                "intent": {"goal": "inventory"},
                "contextIds": [],
                "budget": budget(),
                "idempotencyKey": "task.runtime-running",
            },
        )
        queued = plane.transition_task(ACTOR, task["taskId"], expected_revision=1, target="queued", now=1_002)
        plane.transition_task(
            ACTOR,
            queued["taskId"],
            expected_revision=queued["revision"],
            target="running",
            executor_attested=True,
            now=1_003,
        )
        plane.close()
        reopened = ManagedWorkPlane(path).open()
        try:
            recovered = reopened.get_task(ACTOR, task["taskId"])
            self.assertEqual("interrupted", recovered["state"])
            retried = ManagedRuntime(reopened).recover_task(
                ACTOR,
                {"taskId": recovered["taskId"], "expectedRevision": recovered["revision"]},
            )
            self.assertEqual("retrying", retried["state"])
        finally:
            reopened.close()

    def test_representative_execute_is_not_an_unavailable_success(self) -> None:
        task = self.runtime.create_task(
            ACTOR,
            {
                "title": "Sandbox probe",
                "intent": {"kind": "sandbox-probe"},
                "contextIds": [],
                "budget": budget(),
                "idempotencyKey": "task.runtime-execute",
            },
        )
        try:
            result = self.runtime.execute(
                ACTOR,
                {"taskId": task["taskId"], "idempotencyKey": "run.runtime-execute"},
            )
        except FabricError as error:
            self.assertIn(error.code, {"sandbox.unavailable", "sandbox.probe-failed"})
            self.assertNotEqual("managed-execution.unavailable", error.code)
            stored = self.plane.get_task(ACTOR, task["taskId"])
            self.assertNotEqual("succeeded", stored["state"])
            if error.code == "sandbox.probe-failed":
                self.fail(error.detail or error.explanation)
            return
        self.assertEqual("sandboxed-run", result["kind"])
        self.assertTrue(result["isolation"]["unshareAll"])
        self.assertEqual("succeeded", result["task"]["state"])
        self.assertEqual("succeeded", result["run"]["state"])
        self.assertEqual(True, result["result"]["ok"])


class OtherPrincipalTests(unittest.TestCase):
    def test_cancel_is_principal_bound(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            plane = ManagedWorkPlane(Path(temporary) / "managed-work.db").open()
            runtime = ManagedRuntime(plane)
            try:
                task = create_task(plane)
                with self.assertRaises(FabricError) as denied:
                    runtime.cancel_task(
                        OTHER_ACTOR,
                        {"taskId": task["taskId"], "expectedRevision": 1},
                    )
                self.assertEqual("access.denied", denied.exception.code)
            finally:
                plane.close()
