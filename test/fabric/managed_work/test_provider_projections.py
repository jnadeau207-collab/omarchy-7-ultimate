from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator

from helper import ACTOR, OTHER_ACTOR
from omarchy_fabric.managed_work import CapacityLimits, ManagedWorkError, ManagedWorkPlane


def catalog_item(
    provider_id: str,
    *,
    generation: int = 1,
    state: str = "available",
    detail: str = "",
    changed_at: float = 1_000,
    registration_order: int = 0,
) -> dict[str, object]:
    return {
        "manifest": {"provider": provider_id, "providerVersion": "v0"},
        "fingerprint": "a" * 64,
        "generation": generation,
        "registrationOrder": registration_order,
        "state": state,
        "detail": detail,
        "registeredAt": 1_000,
        "changedAt": changed_at,
    }


class ProviderProjectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        schema_path = Path(__file__).resolve().parents[3] / "default" / "fabric" / "schema" / "managed-work-v0.json"
        cls.validator = Draft202012Validator(json.loads(schema_path.read_text(encoding="utf-8")))

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.path = Path(self.temporary.name) / "managed-work.db"
        self.plane = ManagedWorkPlane(self.path).open()

    def tearDown(self) -> None:
        self.plane.close()
        self.temporary.cleanup()

    def assert_valid(self, value: object) -> None:
        errors = sorted(self.validator.iter_errors(value), key=lambda error: list(error.path))
        if errors:
            self.fail("\n".join(error.message for error in errors[:10]))

    def assert_code(self, code: str, call) -> None:
        with self.assertRaises(ManagedWorkError) as caught:
            call()
        self.assertEqual(code, caught.exception.code)

    def test_revision_is_monotonic_across_health_change_remove_and_reappear(self) -> None:
        first = self.plane.project_provider_inventory(
            ACTOR,
            [catalog_item("alpha.provider")],
            now=1_001,
        )[0]
        self.assert_valid(first)
        self.assertEqual(1, first["sourceRevision"])
        replay = self.plane.project_provider_inventory(
            ACTOR,
            [catalog_item("alpha.provider")],
            now=1_002,
        )[0]
        self.assertEqual(first, replay)

        incompatible = self.plane.project_provider_inventory(
            ACTOR,
            [
                catalog_item(
                    "alpha.provider",
                    generation=2,
                    state="incompatible",
                    detail="authorizationToken=must-never-persist",
                    changed_at=1_003,
                )
            ],
            now=1_003,
        )[0]
        self.assertEqual(2, incompatible["sourceRevision"])
        self.assertEqual("provider.incompatible-version", incompatible["code"])
        self.assertNotIn("must-never-persist", json.dumps(incompatible))

        degraded = self.plane.project_provider_inventory(
            ACTOR,
            [
                catalog_item(
                    "alpha.provider",
                    generation=3,
                    state="degraded",
                    detail="optional dependency unavailable",
                    changed_at=1_003.5,
                )
            ],
            now=1_003.5,
        )[0]
        self.assertEqual(3, degraded["sourceRevision"])
        self.assertEqual("degraded", degraded["state"])
        self.assertEqual("provider.degraded", degraded["code"])
        self.assertTrue(degraded["available"])

        removed = self.plane.project_provider_inventory(ACTOR, [], now=1_004)[0]
        self.assertEqual(4, removed["sourceRevision"])
        self.assertFalse(removed["installed"])
        reappeared = self.plane.project_provider_inventory(
            ACTOR,
            [catalog_item("alpha.provider", generation=1, changed_at=1_005)],
            now=1_005,
        )[0]
        self.assertEqual(5, reappeared["sourceRevision"])
        self.assertTrue(reappeared["available"])
        self.assert_valid(self.plane.query(ACTOR, "agent.providers", now=1_006))

        payload = self.plane.store.execute(
            "SELECT payload_json FROM provider_projections WHERE provider_id = 'alpha.provider'"
        ).fetchone()[0]
        self.assertNotIn("must-never-persist", payload)

    def test_inventory_is_owner_scoped_cursor_bounded_and_closed(self) -> None:
        inventory = [catalog_item(f"provider.{index}") for index in range(4)]
        self.plane.project_provider_inventory(ACTOR, inventory, now=1_001)
        self.plane.project_provider_inventory(
            OTHER_ACTOR,
            [catalog_item("other.provider")],
            now=1_001,
        )
        first = self.plane.query(ACTOR, "agent.providers", limit=2, now=1_002)
        self.assertEqual(2, len(first["items"]))
        self.assertIsNotNone(first["nextCursor"])
        second = self.plane.query(
            ACTOR,
            "agent.providers",
            limit=2,
            cursor=first["nextCursor"],
            now=1_002,
        )
        self.assertEqual(2, len(second["items"]))
        self.assertNotIn("other.provider", {item["providerId"] for item in first["items"] + second["items"]})
        self.assert_code(
            "query.cursor",
            lambda: self.plane.query(
                OTHER_ACTOR,
                "agent.providers",
                cursor=first["nextCursor"],
                now=1_002,
            ),
        )
        entity = self.plane.query(
            ACTOR,
            "agent.providers",
            entity_type="provider",
            entity_id="provider.1",
            now=1_002,
        )
        self.assertEqual("provider.1", entity["items"][0]["providerId"])
        opened = dict(entity["items"][0])
        opened["detail"] = "secret"
        self.assertTrue(list(self.validator.iter_errors(opened)))

    def test_invalid_catalog_and_capacity_roll_back_without_partial_projection(self) -> None:
        limited = ManagedWorkPlane(
            Path(self.temporary.name) / "limited.db",
            capacities=CapacityLimits(provider_projections=1),
        ).open()
        try:
            with self.assertRaises(ManagedWorkError) as capacity:
                limited.project_provider_inventory(
                    ACTOR,
                    [catalog_item("one.provider"), catalog_item("two.provider")],
                    now=1_001,
                )
            self.assertEqual("capacity.provider-projections", capacity.exception.code)
            self.assertEqual([], limited.query(ACTOR, "agent.providers", now=1_002)["items"])
        finally:
            limited.close()

        invalid = catalog_item("invalid.provider")
        invalid["detail"] = None
        self.assert_code(
            "validation.text",
            lambda: self.plane.project_provider_inventory(ACTOR, [invalid], now=1_001),
        )
        opened = catalog_item("invalid.provider")
        opened["unexpected"] = True
        self.assert_code(
            "validation.unknown-field",
            lambda: self.plane.project_provider_inventory(ACTOR, [opened], now=1_001),
        )


if __name__ == "__main__":
    unittest.main()
