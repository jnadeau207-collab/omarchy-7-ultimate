from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from helper import ACTOR, ManagedWorkPlane, policy, template
from omarchy_fabric.managed_work import CapacityLimits, ManagedWorkError


class AutomationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.plane = ManagedWorkPlane(Path(self.temporary.name) / "managed-work.db").open()

    def tearDown(self) -> None:
        self.plane.close()
        self.temporary.cleanup()

    def assert_code(self, code: str, call) -> None:
        with self.assertRaises(ManagedWorkError) as caught:
            call()
        self.assertEqual(code, caught.exception.code)

    def create_interval(
        self,
        *,
        missed: str = "run-once",
        coalescing: str = "latest",
        max_catch_up: int = 4,
        key: str = "automation.interval",
    ) -> dict[str, object]:
        return self.plane.create_automation(
            ACTOR,
            name="Inventory interval",
            task_template=template(),
            trigger={"kind": "interval", "seconds": 60, "anchor": 1_060},
            policy=policy(missed=missed, coalescing=coalescing, max_catch_up=max_catch_up),
            idempotency_key=key,
            now=1_000,
        )

    def test_missed_interval_run_once_chooses_latest_and_stays_unavailable(self) -> None:
        automation = self.create_interval()
        self.assertEqual(1_060, automation["nextDueAt"])
        result = self.plane.reconcile_schedules(ACTOR, now=1_300)
        self.assertEqual(5, result["missedCount"])
        self.assertEqual(1, result["createdCount"])
        self.assertEqual(1_300, result["firings"][0]["dueAt"])
        self.assertEqual("pending-unavailable", result["firings"][0]["state"])
        self.assertFalse(result["execution"]["available"])
        refreshed = self.plane.get_automation(ACTOR, automation["automationId"])
        self.assertEqual(1_360, refreshed["nextDueAt"])
        replay = self.plane.reconcile_schedules(ACTOR, now=1_300)
        self.assertEqual(0, replay["createdCount"])
        self.assertEqual(0, replay["missedCount"])

    def test_catch_up_coalescing_is_bounded_and_skip_is_audited(self) -> None:
        catch_up = self.create_interval(
            missed="catch-up",
            coalescing="earliest",
            max_catch_up=2,
            key="automation.catch-up",
        )
        result = self.plane.reconcile_schedules(ACTOR, now=1_300)
        self.assertEqual([1_060, 1_120], [item["dueAt"] for item in result["firings"]])
        self.assertEqual(5, result["missedCount"])
        self.assertEqual(1_360, self.plane.get_automation(ACTOR, catch_up["automationId"])["nextDueAt"])
        self.plane.set_automation_state(
            ACTOR,
            catch_up["automationId"],
            expected_revision=1,
            state="paused",
            now=2_000,
        )

        self.plane.create_automation(
            ACTOR,
            name="Skip missed work",
            task_template=template(),
            trigger={"kind": "interval", "seconds": 60, "anchor": 2_060},
            policy=policy(missed="skip"),
            idempotency_key="automation.skip",
            now=2_000,
        )
        skipped = self.plane.reconcile_schedules(ACTOR, now=2_180)
        self.assertEqual(3, skipped["skippedCount"])
        self.assertEqual(0, skipped["createdCount"])
        query = self.plane.query(ACTOR, "agent.automations", now=2_181)
        skip_records = [
            firing
            for item in query["items"]
            for firing in item["firings"]
            if firing["state"] == "skipped"
        ]
        self.assertEqual(1, len(skip_records))
        self.assertEqual(3, skip_records[0]["detail"]["missedCount"])

    def test_signed_out_pause_retains_due_work_and_clock_rollback_does_not_guess(self) -> None:
        automation = self.create_interval()
        paused = self.plane.reconcile_schedules(ACTOR, now=1_180, signed_in=False)
        self.assertEqual(0, paused["missedCount"])
        self.assertEqual(1_060, self.plane.get_automation(ACTOR, automation["automationId"])["nextDueAt"])
        rollback = self.plane.reconcile_schedules(ACTOR, now=1_100, signed_in=True)
        self.assertEqual(1, rollback["clockRollbackCount"])
        self.assertEqual(0, rollback["createdCount"])
        resumed = self.plane.reconcile_schedules(ACTOR, now=1_240, signed_in=True)
        self.assertEqual(4, resumed["missedCount"])
        self.assertEqual(1, resumed["createdCount"])

    def test_event_trigger_deduplicates_event_identity(self) -> None:
        automation = self.plane.create_automation(
            ACTOR,
            name="React to provider health",
            task_template=template(),
            trigger={"kind": "event", "topic": "provider.health-changed"},
            policy=policy(),
            idempotency_key="automation.event",
            now=1_000,
        )
        first = self.plane.ingest_event(
            ACTOR,
            topic="provider.health-changed",
            event_id="provider-event.one",
            payload={"provider": "network", "state": "degraded"},
            occurred_at=1_100,
            now=1_101,
        )
        duplicate = self.plane.ingest_event(
            ACTOR,
            topic="provider.health-changed",
            event_id="provider-event.one",
            payload={"provider": "network", "state": "degraded"},
            occurred_at=1_100,
            now=1_102,
        )
        self.assertEqual(1, first["matchedCount"])
        self.assertEqual(0, duplicate["matchedCount"])
        self.assertEqual("pending-unavailable", first["firings"][0]["state"])
        self.assert_code(
            "event.conflict",
            lambda: self.plane.ingest_event(
                ACTOR,
                topic="provider.health-changed",
                event_id="provider-event.one",
                payload={"provider": "network", "state": "tampered duplicate"},
                occurred_at=1_100,
                now=1_103,
            ),
        )
        newest = self.plane.ingest_event(
            ACTOR,
            topic="provider.health-changed",
            event_id="provider-event.two",
            payload={"provider": "network", "state": "ready"},
            occurred_at=1_104,
            now=1_105,
        )
        self.assertEqual("pending-unavailable", newest["firings"][0]["state"])
        states = [
            firing["state"]
            for firing in self.plane.query(ACTOR, "agent.automations", now=1_106)["items"][0]["firings"]
        ]
        self.assertEqual(["pending-unavailable", "cancelled"], states)
        disabled = self.plane.set_automation_state(
            ACTOR,
            automation["automationId"],
            expected_revision=1,
            state="disabled",
            now=1_107,
        )
        self.assertTrue(all(firing["state"] == "cancelled" for firing in disabled["firings"]))

    def test_calendar_schedule_is_time_zone_explicit(self) -> None:
        automation = self.plane.create_automation(
            ACTOR,
            name="Weekday UTC",
            task_template=template(),
            trigger={
                "kind": "calendar",
                "timeZone": "UTC",
                "hour": 12,
                "minute": 30,
                "weekdays": [0, 1, 2, 3, 4],
                "dstPolicy": "skip-invalid",
            },
            policy=policy(),
            idempotency_key="automation.calendar",
            now=1_700_000_000,
        )
        self.assertEqual("UTC", automation["trigger"]["timeZone"])
        self.assertGreater(automation["nextDueAt"], 1_700_000_000)

    def test_event_earliest_coalescing_audits_later_event_as_skipped(self) -> None:
        self.plane.create_automation(
            ACTOR,
            name="Keep earliest event",
            task_template=template(),
            trigger={"kind": "event", "topic": "storage.changed"},
            policy=policy(coalescing="earliest"),
            idempotency_key="automation.event-earliest",
            now=1_000,
        )
        first = self.plane.ingest_event(
            ACTOR,
            topic="storage.changed",
            event_id="storage-event.one",
            payload={"state": "first"},
            occurred_at=1_010,
            now=1_011,
        )
        later = self.plane.ingest_event(
            ACTOR,
            topic="storage.changed",
            event_id="storage-event.two",
            payload={"state": "later"},
            occurred_at=1_012,
            now=1_013,
        )
        self.assertEqual("pending-unavailable", first["firings"][0]["state"])
        self.assertEqual("skipped", later["firings"][0]["state"])
        self.assertEqual("earliest", later["firings"][0]["detail"]["coalesced"]["policy"])

    def test_calendar_run_once_selects_latest_even_when_coalescing_is_earliest(self) -> None:
        created_at = datetime(2026, 1, 5, 12, 0, tzinfo=timezone.utc).timestamp()
        expected = datetime(2026, 1, 9, 12, 30, tzinfo=timezone.utc).timestamp()
        reconcile_at = datetime(2026, 1, 9, 13, 0, tzinfo=timezone.utc).timestamp()
        self.plane.create_automation(
            ACTOR,
            name="Latest weekday",
            task_template=template(),
            trigger={
                "kind": "calendar",
                "timeZone": "UTC",
                "hour": 12,
                "minute": 30,
                "weekdays": [0, 1, 2, 3, 4],
                "dstPolicy": "skip-invalid",
            },
            policy=policy(missed="run-once", coalescing="earliest", max_catch_up=1),
            idempotency_key="automation.calendar-latest",
            now=created_at,
        )
        result = self.plane.reconcile_schedules(ACTOR, now=reconcile_at)
        self.assertEqual(5, result["missedCount"])
        self.assertEqual(expected, result["firings"][0]["dueAt"])

    def test_lingering_unknown_policy_and_stale_revision_are_rejected(self) -> None:
        lingering = policy()
        lingering["signedOut"] = "linger"
        self.assert_code(
            "validation.enum",
            lambda: self.plane.create_automation(
                ACTOR,
                name="Unsafe lingering",
                task_template=template(),
                trigger={"kind": "event", "topic": "test.event"},
                policy=lingering,
                idempotency_key="automation.linger",
                now=1_000,
            ),
        )
        automation = self.create_interval()
        paused = self.plane.set_automation_state(
            ACTOR,
            automation["automationId"],
            expected_revision=1,
            state="paused",
            now=1_010,
        )
        self.assertEqual("paused", paused["state"])
        self.assert_code(
            "revision.stale",
            lambda: self.plane.set_automation_state(
                ACTOR,
                automation["automationId"],
                expected_revision=1,
                state="enabled",
                now=1_011,
            ),
        )

    def test_firing_capacity_rolls_back_due_cursor(self) -> None:
        self.plane.close()
        self.plane = ManagedWorkPlane(
            Path(self.temporary.name) / "bounded.db",
            capacities=CapacityLimits(event_firings=1),
        ).open()
        automation = self.create_interval(missed="catch-up", max_catch_up=2)
        self.assert_code(
            "capacity.exceeded",
            lambda: self.plane.reconcile_schedules(ACTOR, now=1_180),
        )
        self.assertEqual(1_060, self.plane.get_automation(ACTOR, automation["automationId"])["nextDueAt"])
        count = self.plane.store.execute("SELECT COUNT(*) FROM automation_firings").fetchone()[0]
        self.assertEqual(0, count)


if __name__ == "__main__":
    unittest.main()
