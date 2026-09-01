from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path

from helper import ROOT

from jsonschema import Draft202012Validator, ValidationError

from omarchy_fabric.providers.update.lifecycle import UpdateJournal

SCHEMA_NAMES = (
    "admin-inventory-v0.json",
    "update-plan-v0.json",
    "recovery-point-v0.json",
    "backup-plan-v0.json",
    "diagnostics-bundle-v0.json",
)

def walk(value):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)

class PublicSchemaTests(unittest.TestCase):
    def test_all_public_schemas_are_valid_closed_draft_2020_12_documents(self) -> None:
        directory = ROOT / "default" / "fabric" / "schema"
        identities = set()
        for name in SCHEMA_NAMES:
            document = json.loads((directory / name).read_text(encoding="utf-8"))
            Draft202012Validator.check_schema(document)
            self.assertEqual(document["$schema"], "https://json-schema.org/draft/2020-12/schema")
            self.assertEqual(document["x-omarchy-version"], "v0")
            self.assertNotIn(document["$id"], identities)
            identities.add(document["$id"])
            for node in walk(document):
                if isinstance(node, dict) and node.get("type") == "object":
                    self.assertIs(node.get("additionalProperties"), False, f"open object in {name}")

    def test_default_catalog_and_recovery_policy_pin_plan_only_boundaries(self) -> None:
        catalog = json.loads((ROOT / "default" / "ultimate" / "administration" / "provider-catalog-v0.json").read_text(encoding="utf-8"))
        policy = json.loads((ROOT / "default" / "ultimate" / "recovery" / "policy-v0.json").read_text(encoding="utf-8"))
        self.assertEqual(catalog["executionBoundary"], "plan-only")
        self.assertEqual(catalog["authorizationBoundary"], "central-fabric")
        self.assertEqual(
            [provider["id"] for provider in catalog["providers"]],
            [
                "account.provider",
                "backup.provider",
                "device.provider",
                "diagnostics.provider",
                "firewall.provider",
                "printer.provider",
                "process.provider",
                "recovery.provider",
                "schedule.provider",
                "service.provider",
                "storage.provider",
                "update.provider",
            ],
        )
        self.assertTrue(all(provider["realMutation"] is False for provider in catalog["providers"]))
        self.assertEqual(policy["restore"]["scope"], "system")
        self.assertTrue(policy["restore"]["preserveHome"])
        self.assertTrue(policy["restore"]["verifiedHealthyRequired"])
        self.assertTrue(policy["restore"]["verifiedReadOnlyRequired"])
        self.assertEqual(policy["backup"]["scope"], "home")
        self.assertTrue(policy["backup"]["verifiedSnapshotPathsRequired"])
        self.assertTrue(policy["update"]["privateJournalRequired"])
        self.assertTrue(policy["update"]["crossProcessLockRequired"])
        self.assertTrue(policy["diagnostics"]["structuredEvidenceOnly"])
        self.assertFalse(policy["diagnostics"]["upload"])

    def test_durable_update_journal_validates_directly_as_public_update_plan(self) -> None:
        schema = json.loads((ROOT / "default" / "fabric" / "schema" / "update-plan-v0.json").read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as directory:
            document = UpdateJournal(Path(directory) / "update.json").create("sha256." + "a" * 64, mode="apply", checkpoint_required=True)
        Draft202012Validator(schema).validate(document)

    def test_public_schemas_reject_semantically_inconsistent_safety_claims(self) -> None:
        directory = ROOT / "default" / "fabric" / "schema"
        update_schema = json.loads((directory / "update-plan-v0.json").read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as temporary:
            update_plan = UpdateJournal(Path(temporary) / "update.json").create("sha256." + "a" * 64, mode="check", checkpoint_required=False)
        update_plan["checkpoint"] = "created"
        with self.assertRaises(ValidationError):
            Draft202012Validator(update_schema).validate(update_plan)

        recovery_schema = json.loads((directory / "recovery-point-v0.json").read_text(encoding="utf-8"))
        recovery_point = {
            "schemaVersion": "v0",
            "id": "restore-point." + "a" * 24,
            "scope": "system",
            "source": "snapshot",
            "createdAt": "2026-08-27T00:00:00Z",
            "eligible": True,
            "health": "unknown",
            "readOnly": None,
            "revision": "sha256." + "b" * 64,
        }
        with self.assertRaises(ValidationError):
            Draft202012Validator(recovery_schema).validate(recovery_point)

        backup_schema = json.loads((directory / "backup-plan-v0.json").read_text(encoding="utf-8"))
        backup_plan = {
            "schemaVersion": "v0",
            "action": "restore",
            "scope": "home",
            "engine": "restic",
            "snapshotId": None,
            "relativePath": None,
            "retention": {"daily": 7, "weekly": 4, "monthly": 6},
            "threats": ["accidental-deletion", "disk-failure", "malware", "repository-loss"],
            "revision": "sha256." + "c" * 64,
        }
        with self.assertRaises(ValidationError):
            Draft202012Validator(backup_schema).validate(backup_plan)

        diagnostics_schema = json.loads((directory / "diagnostics-bundle-v0.json").read_text(encoding="utf-8"))
        diagnostics_bundle = {
            "schemaVersion": "v0",
            "sources": ["service-failures"],
            "maximumBytes": 1024,
            "estimatedBytes": 0,
            "redacted": True,
            "entries": [],
            "revision": "sha256." + "d" * 64,
        }
        with self.assertRaises(ValidationError):
            Draft202012Validator(diagnostics_schema).validate(diagnostics_bundle)

if __name__ == "__main__":
    unittest.main()
