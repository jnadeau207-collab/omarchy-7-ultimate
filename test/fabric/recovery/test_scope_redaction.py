from __future__ import annotations

import copy
import json
import unittest

from helper import backup_resource, diagnostics_resource, principal, recovery_resource

from omarchy_fabric.models import FabricError
from omarchy_fabric.providers.backup import provider as backup
from omarchy_fabric.providers.diagnostics import provider as diagnostics
from omarchy_fabric.providers.recovery import provider as recovery

class RecoveryScopeTests(unittest.IsolatedAsyncioTestCase):
    async def test_recovery_inventory_and_preflight_are_system_only(self) -> None:
        resource = recovery_resource()
        recovery.require_system_only([resource])
        wrong = copy.deepcopy(resource)
        wrong["scope"] = "home"
        with self.assertRaises(ValueError):
            recovery.require_system_only([wrong])
        with self.assertRaises(ValueError):
            recovery.build_fake_provider([wrong])
        provider = recovery.build_fake_provider([resource])
        arguments = {"resourceId": resource["id"], "scope": "system", "preserveHome": True, "confirmation": f"RESTORE:{resource['id']}"}
        plan = await provider.preflight(recovery.OPERATION_ACTION, arguments, principal())
        self.assertTrue(plan["proposedState"]["value"]["pendingPlan"]["preservesHome"])
        self.assertEqual(plan["proposedState"]["value"]["pendingPlan"]["scope"], "system")
        self.assertEqual(provider.backend.write_count, 0)

    async def test_unverified_snapper_rows_cannot_be_planned_and_current_row_is_not_a_restore_point(self) -> None:
        resources = recovery.parse_restore_points(
            json.dumps(
                {
                    "data": [
                        {"number": 0, "date": "", "description": "current"},
                        {"number": 8, "date": "2026-08-27T01:00:00Z", "description": "token=restore-secret"},
                    ]
                }
            )
        )
        self.assertEqual(len(resources), 1)
        self.assertFalse(resources[0]["state"]["eligible"])
        self.assertIsNone(resources[0]["state"]["readOnly"])
        self.assertNotIn("restore-secret", str(resources[0]))
        provider = recovery.build_fake_provider(resources)
        arguments = {"resourceId": resources[0]["id"], "scope": "system", "preserveHome": True, "confirmation": f"RESTORE:{resources[0]['id']}"}
        with self.assertRaises(FabricError) as unverified:
            await provider.preflight(recovery.OPERATION_ACTION, arguments, principal())
        self.assertEqual(unverified.exception.code, "recovery.precondition-failed")
        with self.assertRaises(ValueError):
            recovery.parse_restore_points(json.dumps({"data": [{"number": 9, "date": "2026-08-27T01:00:00", "description": "naive"}]}))

    async def test_backup_restore_scope_rejects_traversal_absolute_paths_and_shell_tokens(self) -> None:
        for value in ("../etc/shadow", "/etc/shadow", "Documents/../../etc", "Documents/./report.txt", "Documents//report.txt", "Documents\\secret", "$(id)"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                backup.validate_home_relative_path(value)
        resource = backup_resource()
        provider = backup.build_fake_provider([resource])
        valid = {"resourceId": backup.RESOURCE_ID, "action": "restore", "scope": "home", "snapshotId": "abcdef1234567890", "relativePath": "Documents/report.txt", "retention": dict(backup.DEFAULT_RETENTION)}
        plan = await provider.preflight(backup.OPERATION_ACTION, valid, principal())
        self.assertEqual(plan["proposedState"]["value"]["pendingPlan"]["scope"], "home")
        self.assertEqual(provider.backend.write_count, 0)

        with self.assertRaises(FabricError) as absent:
            await provider.preflight(backup.OPERATION_ACTION, {**valid, "snapshotId": "00000000"}, principal())
        self.assertEqual(absent.exception.code, "backup.precondition-failed")

    def test_backup_inventory_proves_home_scope_identity_and_time(self) -> None:
        valid = [{"id": "abcdef1234567890", "time": "2026-08-27T00:00:00Z", "paths": ["/home/jesse", "/home/jesse/Documents"]}]
        resource = backup.parse_snapshots(json.dumps(valid), home_root="/home/jesse")[0]
        self.assertEqual(resource["state"]["snapshotIds"], ["abcdef1234567890"])
        for mutation in (
            [{"id": "abcdef1234567890", "time": "2026-08-27T00:00:00Z"}],
            [{"id": "abcdef1234567890", "time": "2026-08-27T00:00:00Z", "paths": ["/etc"]}],
            [{"id": "ABCDEF1234567890", "time": "2026-08-27T00:00:00Z", "paths": ["/home/jesse"]}],
            [{"id": "abcdef1234567890", "time": "2026-08-27T00:00:00", "paths": ["/home/jesse"]}],
        ):
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                backup.parse_snapshots(json.dumps(mutation), home_root="/home/jesse")

class DiagnosticRedactionTests(unittest.IsolatedAsyncioTestCase):
    def test_support_redaction_removes_credentials_identity_paths_and_network_addresses(self) -> None:
        secret = 'Bearer abcdefghijklmnop token=top-secret {"api_key":"json-secret"} https://user:pass@example.test /home/jesse jesse@example.test 192.0.2.1'
        redacted, count = diagnostics.redact_support_text(secret)
        self.assertGreaterEqual(count, 6)
        for forbidden in ("abcdefghijklmnop", "top-secret", "json-secret", "user:pass", "/home/jesse", "jesse@example.test", "192.0.2.1"):
            self.assertNotIn(forbidden, redacted)
        self.assertIn("$HOME", redacted)

    def test_support_redaction_covers_prefixed_secrets_jwts_macs_and_private_keys(self) -> None:
        secret = (
            "AWS_SECRET_ACCESS_KEY=abcd1234 clientSecret='shh-value' "
            "abcdefgh.ijklmnop.qrstuvwx aa:bb:cc:dd:ee:ff "
            "-----BEGIN PRIVATE KEY-----\nvery-secret\n-----END PRIVATE KEY-----"
        )
        redacted, count = diagnostics.redact_support_text(secret)
        self.assertGreaterEqual(count, 5)
        for forbidden in ("abcd1234", "shh-value", "abcdefgh.ijklmnop.qrstuvwx", "aa:bb:cc:dd:ee:ff", "very-secret"):
            self.assertNotIn(forbidden, redacted)

    def test_preview_is_allowlisted_bounded_and_utf8_safe(self) -> None:
        preview = diagnostics.preview_support_bundle({"service-failures": "é" * 5000}, 1024)
        self.assertEqual(preview[0]["bytes"], 1024)
        preview[0]["excerpt"].encode("utf-8")
        with self.assertRaises(ValueError):
            diagnostics.preview_support_bundle({"/etc/shadow": "secret"}, 1024)
        with self.assertRaises(ValueError):
            diagnostics.preview_support_bundle({"service-failures": "x" * (diagnostics.MAXIMUM_SOURCE_BYTES + 1)}, diagnostics.MAXIMUM_BUNDLE_BYTES)
        large = diagnostics.preview_support_bundle({"service-failures": "x" * 100000}, diagnostics.MAXIMUM_BUNDLE_BYTES)
        self.assertEqual(large[0]["bytes"], 100000)

    async def test_bundle_plan_uses_only_existing_redacted_preview(self) -> None:
        resource = diagnostics_resource()
        provider = diagnostics.build_fake_provider([resource])
        arguments = {"resourceId": diagnostics.RESOURCE_ID, "sources": ["service-failures"], "maximumBytes": 4096}
        plan = await provider.preflight(diagnostics.OPERATION_ACTION, arguments, principal())
        pending = plan["proposedState"]["value"]["pendingPlan"]
        self.assertTrue(pending["redacted"])
        self.assertLessEqual(pending["estimatedBytes"], pending["maximumBytes"])
        self.assertNotIn("secret-value", str(plan))

        limited = diagnostics_resource()
        limited["state"]["supportPreview"] = [item for item in limited["state"]["supportPreview"] if item["source"] == "service-failures"]
        limited_provider = diagnostics.build_fake_provider([limited])
        with self.assertRaises(FabricError) as unavailable:
            await limited_provider.preflight(
                diagnostics.OPERATION_ACTION,
                {"resourceId": diagnostics.RESOURCE_ID, "sources": ["journal-usage"], "maximumBytes": 4096},
                principal(),
            )
        self.assertEqual(unavailable.exception.code, "diagnostics.precondition-failed")

    def test_diagnostic_parsers_reject_success_shaped_garbage(self) -> None:
        with self.assertRaises(ValueError):
            diagnostics._journal_check("garbage")
        with self.assertRaises(ValueError):
            diagnostics._filesystem_check("garbage")
        with self.assertRaises(ValueError):
            diagnostics._filesystem_check("Filesystem Use% Mounted on\n")

if __name__ == "__main__":
    unittest.main()
