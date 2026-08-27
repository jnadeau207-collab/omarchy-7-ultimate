from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "default" / "fabric"))

from omarchy_fabric.security.errors import SecurityValidationError
from omarchy_fabric.security.normalize import binding_digest, normalize_json
from omarchy_fabric.security.redaction import REDACTED, redact, redact_text, scan_for_secrets
from omarchy_fabric.security.system_executor import validate_system_executor_request


class ExecutorAndRedactionTests(unittest.TestCase):
    def request(self):
        return {
            "schemaVersion": "v0",
            "requestId": "10000000-0000-0000-0000-000000000001",
            "operationId": "20000000-0000-0000-0000-000000000002",
            "action": "storage.format",
            "arguments": {
                "device_id": "wwn.0x5000",
                "filesystem": "btrfs",
                "label": "BACKUP",
                "confirmation": "ERASE BACKUP",
            },
            "providerVersion": "storage.v0",
            "stateRevision": "state.42",
            "approvalBinding": "a" * 64,
            "consentNonce": "30000000-0000-0000-0000-000000000003",
        }

    def test_fixed_executor_request_maps_to_dedicated_polkit_action(self) -> None:
        request = validate_system_executor_request(self.request())
        self.assertEqual(request.action, "storage.format")
        self.assertEqual(request.polkit_action, "org.omarchy.fabric.storage.format")
        self.assertNotIn("command", request.arguments)

    def test_nonce_is_correlation_data_not_authorization(self) -> None:
        first = self.request()
        second = self.request()
        second["consentNonce"] = "40000000-0000-0000-0000-000000000004"
        self.assertEqual(
            validate_system_executor_request(first).polkit_action,
            validate_system_executor_request(second).polkit_action,
        )

    def test_executor_rejects_arbitrary_verbs_commands_paths_argv_and_env(self) -> None:
        mutations = []
        unknown = self.request()
        unknown["action"] = "command.run"
        mutations.append(unknown)
        for key, value in (
            ("command", "rm -rf /"),
            ("executable_path", "/tmp/helper"),
            ("argv", ["sh", "-c", "id"]),
            ("env", {"LD_PRELOAD": "/tmp/pwn.so"}),
        ):
            candidate = self.request()
            candidate["arguments"][key] = value
            mutations.append(candidate)
        path_target = self.request()
        path_target["arguments"]["device_id"] = "/dev/sda"
        mutations.append(path_target)
        for candidate in mutations:
            with self.subTest(candidate=candidate):
                with self.assertRaises(SecurityValidationError):
                    validate_system_executor_request(candidate)

    def test_executor_rejects_malformed_contracts_without_coercion(self) -> None:
        candidates = []
        missing = self.request()
        del missing["stateRevision"]
        candidates.append(missing)
        extra = self.request()
        extra["authorized"] = True
        candidates.append(extra)
        bad_uuid = self.request()
        bad_uuid["requestId"] = "not-a-uuid"
        candidates.append(bad_uuid)
        bad_version = self.request()
        bad_version["schemaVersion"] = "v99"
        candidates.append(bad_version)
        wrong_type = self.request()
        wrong_type["arguments"]["label"] = 7
        candidates.append(wrong_type)
        unhashable_action = self.request()
        unhashable_action["action"] = ["storage.format"]
        candidates.append(unhashable_action)
        invalid_choice = self.request()
        invalid_choice["action"] = "system.update"
        invalid_choice["arguments"] = {"channel": ["stable"], "allow_without_restore_point": False}
        candidates.append(invalid_choice)
        for candidate in candidates:
            with self.subTest(candidate=candidate):
                with self.assertRaises(SecurityValidationError):
                    validate_system_executor_request(candidate)

    def test_normalization_is_canonical_bounded_and_cross_language_safe(self) -> None:
        maximum = 2**53 - 1
        self.assertEqual(normalize_json({"value": maximum})["value"], maximum)
        self.assertEqual(normalize_json({"value": -maximum})["value"], -maximum)
        for value in (
            {1: "not-json"},
            {"value": 1.5},
            {"value": "x" * 65537},
            {"value": maximum + 1},
            {"value": -maximum - 1},
        ):
            with self.subTest(value_type=type(value)):
                with self.assertRaises(SecurityValidationError):
                    normalize_json(value)
        self.assertEqual(binding_digest({"name": "e\u0301"}), binding_digest({"name": "é"}))

    def test_nested_secret_redaction_and_scans_never_echo_values(self) -> None:
        private_key = "-----BEGIN PRIVATE KEY-----\nvery-secret-material\n-----END PRIVATE KEY-----"
        payload = {
            "password": "hunter2",
            "refreshToken": "camel-case-secret",
            "nested": {
                "note": "Authorization: Bearer abcdefghijklmnopqrstuvwxyz",
                "private": private_key,
                "safe": "display.primary",
            },
            "items": [{"api_key": "top-secret-api-key"}],
        }
        output = redact(payload)
        self.assertEqual(output["password"], REDACTED)
        self.assertEqual(output["refreshToken"], REDACTED)
        self.assertEqual(output["items"][0]["api_key"], REDACTED)
        self.assertEqual(output["nested"]["safe"], "display.primary")
        serialized = repr(output)
        for secret in ("hunter2", "camel-case-secret", "abcdefghijklmnopqrstuvwxyz", "very-secret-material", "top-secret-api-key"):
            self.assertNotIn(secret, serialized)
        findings = scan_for_secrets(payload)
        self.assertGreaterEqual(len(findings), 4)
        finding_text = repr(findings)
        self.assertNotIn("hunter2", finding_text)
        self.assertNotIn("very-secret-material", finding_text)

    def test_text_and_explicit_path_redaction(self) -> None:
        text = "password=swordfish https://alice:secret@example.com token=abcdef1234567890"
        cleaned = redact_text(text)
        self.assertNotIn("swordfish", cleaned)
        self.assertNotIn("alice:secret", cleaned)
        self.assertNotIn("abcdef1234567890", cleaned)
        explicit = redact({"context": {"selection": "private.txt"}}, explicit_paths={"/context/selection"})
        self.assertEqual(explicit["context"]["selection"], REDACTED)


if __name__ == "__main__":
    unittest.main()
