from __future__ import annotations

import importlib.util
import os
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from helper import ACTOR, OTHER_ACTOR, ManagedWorkPlane, budget, create_task, inspect_intent
from omarchy_fabric.desktop_context import capture_desktop_context
from omarchy_fabric.managed_runtime import ManagedRuntime
from omarchy_fabric.managed_work import ManagedWorkError
from omarchy_fabric.models import FabricError
from omarchy_fabric.protocol import _validate_remote_error
from sandbox.runner import IsolatedRun


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
                "intent": inspect_intent(),
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
        desktops = capture_desktop_context(
            self.plane,
            ACTOR,
            source="virtual-desktops",
            snapshot={
                **snapshot,
                "desktops": [
                    {"id": "1", "name": "Desktop 1", "active": True},
                    {"id": "2", "name": "Desktop 2", "active": False},
                ],
            },
            idempotency_key="context.desktops",
            now=1_002.5,
        )
        self.assertEqual("1", desktops["content"]["desktops"][0]["id"])
        self.assertTrue(desktops["content"]["desktops"][0]["active"])
        profile = capture_desktop_context(
            self.plane,
            ACTOR,
            source="mode-profile",
            snapshot={**snapshot, "mode": "desktop", "features": {"taskbar": True, "topBar": False}},
            idempotency_key="context.mode",
            now=1_002.75,
        )
        self.assertEqual("desktop", profile["content"]["mode"])
        self.assertEqual(True, profile["content"]["features"]["taskbar"])
        self.assertEqual(False, profile["content"]["features"]["topBar"])
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
                "intent": inspect_intent(),
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
                "title": "Sandbox inspect",
                "intent": inspect_intent(),
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
            self.assertEqual("sandbox.unavailable", error.code)
            _validate_remote_error(error.to_dict())
            stored = self.plane.get_task(ACTOR, task["taskId"])
            self.assertNotEqual("succeeded", stored["state"])
            return
        self.assertEqual("sandboxed-run", result["kind"])
        self.assertTrue(result["isolation"]["unshareAll"])
        self.assertEqual("succeeded", result["task"]["state"])
        self.assertEqual("succeeded", result["run"]["state"])
        self.assertEqual("system.info.read", result["result"]["capability"])
        self.assertEqual(True, result["result"]["ok"])
        self.assertIn("manifest.json", result["result"]["workspace"])

    def test_failed_sandbox_run_error_is_wire_valid(self) -> None:
        task = self.runtime.create_task(
            ACTOR,
            {
                "title": "Sandbox inspect",
                "intent": inspect_intent(),
                "contextIds": [],
                "budget": budget(),
                "idempotencyKey": "task.runtime-wire-failed",
            },
        )
        failed = IsolatedRun(
            returncode=1,
            stdout="",
            stderr="bwrap: Can't mount proc on /newroot/proc: Operation not permitted",
            argv=("/usr/bin/bwrap", "--unshare-all", "--proc", "/proc"),
            result=None,
        )
        with mock.patch.object(self.runtime, "_run_sandbox", return_value=(failed, ["manifest.json"])):
            with self.assertRaises(FabricError) as refused:
                self.runtime.execute(
                    ACTOR,
                    {"taskId": task["taskId"], "idempotencyKey": "run.runtime-wire-failed"},
                )
        self.assertEqual("sandbox.run-failed", refused.exception.code)
        _validate_remote_error(refused.exception.to_dict())
        stored = self.plane.get_task(ACTOR, task["taskId"])
        self.assertNotEqual("succeeded", stored["state"])

    def test_create_without_sandbox_capability_fails(self) -> None:
        with self.assertRaises(FabricError) as refused:
            self.runtime.create_task(
                ACTOR,
                {
                    "title": "No capability",
                    "intent": {"goal": "inventory"},
                    "contextIds": [],
                    "budget": budget(),
                    "idempotencyKey": "task.missing-capability",
                },
            )
        self.assertEqual("task.capability", refused.exception.code)

    def test_live_selection_fails_closed_without_protocol(self) -> None:
        with mock.patch(
            "omarchy_fabric.desktop_context._hypr_json",
            side_effect=lambda command: [] if command == "clients" else {},
        ):
            with mock.patch(
                "omarchy_fabric.desktop_context._wl_paste_bin",
                side_effect=ManagedWorkError(
                    "context.selection-unavailable",
                    "Desktop selection cannot be captured because wl-paste is unavailable.",
                ),
            ):
                with self.assertRaises(FabricError) as refused:
                    self.runtime.capture_context(
                        ACTOR,
                        {
                            "source": "selection",
                            "idempotencyKey": "context.missing-selection",
                        },
                    )
        self.assertEqual("context.selection-unavailable", refused.exception.code)

    def test_injected_empty_selection_is_available_empty(self) -> None:
        captured = capture_desktop_context(
            self.plane,
            ACTOR,
            source="selection",
            snapshot={
                "windows": [{"class": "foot", "title": "term", "address": "0x1", "focused": True}],
                "focus": {"class": "foot", "title": "term", "address": "0x1"},
                "selection": {"text": ""},
            },
            idempotency_key="context.empty-selection",
            now=1_010,
        )
        self.assertEqual(True, captured["content"]["selection"]["available"])
        self.assertEqual("empty", captured["content"]["selection"]["reason"])
        self.assertEqual("", captured["content"]["selection"]["text"])

    @unittest.skipUnless(
        os.environ.get("WAYLAND_DISPLAY")
        and os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        and Path("/usr/bin/wl-copy").is_file()
        and Path("/usr/bin/wl-paste").is_file(),
        "live Hyprland clipboard",
    )
    def test_metal_wl_copy_selection_round_trip(self) -> None:
        known = "omarchy-fabric-selection-proof"
        server = subprocess.Popen(
            ["/usr/bin/wl-copy", "--", known],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            captured = capture_desktop_context(
                self.plane,
                ACTOR,
                source="selection",
                idempotency_key="context.metal-selection",
                now=1_020,
            )
            self.assertEqual(known, captured["content"]["selection"]["text"])
        finally:
            server.terminate()
            try:
                server.wait(timeout=2)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=2)
        windows = capture_desktop_context(
            self.plane,
            ACTOR,
            source="open-windows",
            idempotency_key="context.metal-windows",
            now=1_021,
        )
        classes = [item["class"].lower() for item in windows["content"]["windows"]]
        for banned in ("hyprlock", "pinentry", "pinentry-qt", "pinentry-gtk-2"):
            self.assertNotIn(banned, classes)


def _daemon_process_class():
    path = Path(__file__).resolve().parents[1] / "core" / "helper.py"
    spec = importlib.util.spec_from_file_location("fabric_core_helper", path)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module.DaemonProcess


@unittest.skipIf(os.name == "nt", "fabricd requires a Unix socket")
class FabricdKillInterruptTests(unittest.IsolatedAsyncioTestCase):
    async def test_killed_fabricd_marks_running_work_interrupted(self) -> None:
        DaemonProcess = _daemon_process_class()
        temporary = tempfile.TemporaryDirectory()
        try:
            root = Path(temporary.name)
            daemon = DaemonProcess(root)
            daemon.start()
            try:
                client = await daemon.client("fabric-kill-test")
                created = await client.request(
                    "managed-work.task.create",
                    {
                        "version": "v0",
                        "title": "Running across crash",
                        "intent": inspect_intent(),
                        "budget": budget(),
                        "idempotencyKey": "task.fabricd-kill",
                    },
                )
                await client.close()
                connection = sqlite3.connect(root / "state" / "managed-work.db")
                try:
                    connection.execute(
                        "UPDATE tasks SET state = 'running' WHERE task_id = ?",
                        (created["taskId"],),
                    )
                    connection.commit()
                finally:
                    connection.close()
            finally:
                daemon.crash()
            restarted = DaemonProcess(root)
            restarted.start()
            try:
                client = await restarted.client("fabric-kill-reopen")
                listed = await client.request("managed-work.task.list", {"version": "v0", "limit": 10})
                await client.close()
                recovered = next(
                    item["task"]
                    for item in listed["items"]
                    if item.get("task", {}).get("taskId") == created["taskId"]
                )
                self.assertEqual("interrupted", recovered["state"])
                self.assertNotEqual("succeeded", recovered["state"])
            finally:
                restarted.stop()
        finally:
            temporary.cleanup()


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
