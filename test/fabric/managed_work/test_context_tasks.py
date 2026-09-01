from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from helper import (
    ACTOR,
    OTHER_ACTOR,
    OTHER_SESSION,
    ManagedWorkPlane,
    budget,
    create_context,
    create_task,
    inspect_intent,
    manifest,
)
from omarchy_fabric.managed_work import ManagedWorkError

class ContextTaskTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.plane = ManagedWorkPlane(Path(self.temporary.name) / "managed-work.db").open()

    def tearDown(self) -> None:
        self.plane.close()
        self.temporary.cleanup()

    def assert_code(self, code: str, call) -> ManagedWorkError:
        with self.assertRaises(ManagedWorkError) as caught:
            call()
        self.assertEqual(code, caught.exception.code)
        return caught.exception

    def test_context_is_immutable_redacted_hashed_and_idempotent(self) -> None:
        result = self.plane.capture_context(
            ACTOR,
            source="notification-history",
            access_scope="principal",
            content={
                "account": {"token": "never-store-me"},
                "session": {"accessToken": "also-never-store-me"},
                "notification": {"private": True, "title": "Doctor", "body": "private"},
                "safe": "visible",
            },
            sensitivity="private",
            ttl_seconds=600,
            idempotency_key="context.redaction",
            redact_keys=("custom-secret",),
            now=1_000,
        )
        self.assertEqual("[REDACTED]", result["content"]["account"]["token"])
        self.assertEqual("[REDACTED]", result["content"]["session"]["accessToken"])
        self.assertEqual("[private notification excluded]", result["content"]["notification"]["body"])
        self.assertIn("/account/token", result["redaction"]["paths"])
        self.assertEqual(64, len(result["contentHash"]))

        replay = self.plane.capture_context(
            ACTOR,
            source="notification-history",
            access_scope="principal",
            content={
                "account": {"token": "never-store-me"},
                "session": {"accessToken": "also-never-store-me"},
                "notification": {"private": True, "title": "Doctor", "body": "private"},
                "safe": "visible",
            },
            sensitivity="private",
            ttl_seconds=600,
            idempotency_key="context.redaction",
            redact_keys=("custom-secret",),
            now=1_100,
        )
        self.assertEqual(result, replay)
        self.assert_code(
            "idempotency.conflict",
            lambda: self.plane.capture_context(
                ACTOR,
                source="notification-history",
                access_scope="principal",
                content={"safe": "changed"},
                sensitivity="private",
                ttl_seconds=600,
                idempotency_key="context.redaction",
                now=1_100,
            ),
        )

    def test_common_free_text_tokens_are_redacted_without_value_leakage(self) -> None:
        tokens = {
            "openai": "sk-proj-" + "A" * 48,
            "slack": "xoxb-" + "1" * 12 + "-" + "B" * 24,
            "slack-app": "xapp-1-" + "H" * 30,
            "gitlab": "glpat-" + "C" * 32,
            "npm": "npm_" + "D" * 36,
            "jwt": "eyJ" + "E" * 12 + "." + "F" * 20 + "." + "G" * 32,
        }
        result = self.plane.capture_context(
            ACTOR,
            source="focused-application",
            access_scope="principal",
            content={"nested": [{"value": value} for value in tokens.values()]},
            sensitivity="private",
            ttl_seconds=600,
            idempotency_key="context.token-families",
            now=1_000,
        )
        self.assertEqual(
            ["[REDACTED]"] * len(tokens),
            [item["value"] for item in result["content"]["nested"]],
        )
        durable = self.plane.store.require_connection().execute(
            "SELECT content_json FROM contexts WHERE context_id = ?",
            (result["contextId"],),
        ).fetchone()[0]
        for token in tokens.values():
            self.assertNotIn(token, durable)

        error = self.assert_code(
            "validation.secret-field",
            lambda: self.plane.create_task(
                ACTOR,
                title="Token test",
                intent={"note": tokens["openai"]},
                context_ids=[],
                budget=budget(),
                idempotency_key="task.token-family",
                now=1_001,
            ),
        )
        self.assertIn("openai-token", error.detail)
        self.assertNotIn(tokens["openai"], error.detail)

        safe = self.plane.capture_context(
            ACTOR,
            source="focused-application",
            access_scope="principal",
            content={
                "tokenizer": "cl100k_base",
                "words": ["sketch-project-roadmap", "npm package", "jwt documentation"],
            },
            sensitivity="public",
            ttl_seconds=600,
            idempotency_key="context.token-false-positive",
            now=1_002,
        )
        self.assertEqual(
            ["sketch-project-roadmap", "npm package", "jwt documentation"],
            safe["content"]["words"],
        )
        self.assertEqual("cl100k_base", safe["content"]["tokenizer"])
        safe_task = self.plane.create_task(
            ACTOR,
            title="Tokenizer configuration",
            intent=inspect_intent(tokenizer="cl100k_base"),
            context_ids=[],
            budget=budget(),
            idempotency_key="task.tokenizer-safe",
            now=1_002,
        )
        self.assertEqual("cl100k_base", safe_task["intent"]["tokenizer"])
        key_error = self.assert_code(
            "validation.secret-field",
            lambda: self.plane.capture_context(
                ACTOR,
                source="focused-application",
                access_scope="principal",
                content={tokens["openai"]: "value"},
                sensitivity="private",
                ttl_seconds=600,
                idempotency_key="context.token-key",
                now=1_003,
            ),
        )
        self.assertIn("key-openai-token", key_error.detail)
        self.assertNotIn(tokens["openai"], key_error.detail)
        malformed_key_error = self.assert_code(
            "validation.json-number",
            lambda: self.plane.capture_context(
                ACTOR,
                source="focused-application",
                access_scope="principal",
                content={"nested": {tokens["openai"]: 2**60}},
                sensitivity="private",
                ttl_seconds=600,
                idempotency_key="context.token-key-invalid-child",
                now=1_003,
            ),
        )
        self.assertNotIn(tokens["openai"], malformed_key_error.explanation)
        self.assertNotIn(tokens["openai"], malformed_key_error.detail)
        before = self.plane.store.require_connection().execute(
            "SELECT COUNT(*) FROM contexts"
        ).fetchone()[0]
        self.assert_code(
            "validation.json-string",
            lambda: self.plane.capture_context(
                ACTOR,
                source="focused-application",
                access_scope="principal",
                content={"value": "sk-proj-" + "Z" * 16_385},
                sensitivity="private",
                ttl_seconds=600,
                idempotency_key="context.token-oversized",
                now=1_003,
            ),
        )
        connection = self.plane.store.require_connection()
        self.assertEqual(before, connection.execute("SELECT COUNT(*) FROM contexts").fetchone()[0])
        self.assertEqual(
            0,
            connection.execute(
                "SELECT COUNT(*) FROM idempotency WHERE idempotency_key = 'context.token-oversized'"
            ).fetchone()[0],
        )

    def test_excluded_sources_session_scope_expiry_and_revocation_fail_closed(self) -> None:
        self.assert_code(
            "context.source-excluded",
            lambda: self.plane.capture_context(
                ACTOR,
                source="password-field",
                access_scope="session",
                content={"value": "secret"},
                sensitivity="restricted",
                ttl_seconds=60,
                idempotency_key="excluded",
                now=1_000,
            ),
        )
        context = create_context(self.plane, scope="session")
        self.assert_code(
            "access.session-denied",
            lambda: self.plane.get_context(OTHER_SESSION, context["contextId"], now=1_010),
        )
        self.assert_code(
            "access.denied",
            lambda: self.plane.get_context(OTHER_ACTOR, context["contextId"], now=1_010),
        )
        self.assert_code(
            "context.expired",
            lambda: self.plane.get_context(ACTOR, context["contextId"], now=100_000),
        )
        revoked = self.plane.revoke_context(ACTOR, context["contextId"], expected_revision=1, now=1_020)
        self.assertEqual(2, revoked["revision"])
        self.assertEqual(1_020, revoked["revokedAt"])
        self.assert_code(
            "revision.stale",
            lambda: self.plane.revoke_context(ACTOR, context["contextId"], expected_revision=1, now=1_021),
        )

    def test_session_context_cannot_attach_to_durable_task_and_cleanup_releases_identity(self) -> None:
        session_context = create_context(self.plane, key="context.session-cleanup", scope="session")
        self.assert_code(
            "task.context-scope",
            lambda: create_task(
                self.plane,
                context_ids=[session_context["contextId"]],
                key="task.session-context",
            ),
        )
        connection = self.plane.store.require_connection()
        self.assertEqual(1, connection.execute("SELECT COUNT(*) FROM contexts").fetchone()[0])
        self.assertEqual(1, self.plane.release_session_contexts(ACTOR))
        self.assertEqual(0, connection.execute("SELECT COUNT(*) FROM contexts").fetchone()[0])
        self.assertEqual(
            0,
            connection.execute(
                "SELECT COUNT(*) FROM idempotency WHERE action = 'context.capture'"
            ).fetchone()[0],
        )
        replacement = create_context(self.plane, key="context.session-cleanup", scope="session", now=1_010)
        self.assertNotEqual(session_context["contextId"], replacement["contextId"])

    def test_task_state_machine_stale_revision_and_execution_refusal(self) -> None:
        context = create_context(self.plane)
        task = create_task(self.plane, context_ids=[context["contextId"]])
        status = ManagedWorkPlane.execution_status()
        self.assertEqual(status["available"], task["execution"]["available"])
        self.assertEqual(status["code"], task["execution"]["code"])
        awaiting = self.plane.transition_task(
            ACTOR,
            task["taskId"],
            expected_revision=1,
            target="awaiting-approval",
            now=1_002,
        )
        self.assertEqual("awaiting-approval", awaiting["state"])
        self.assert_code(
            "revision.stale",
            lambda: self.plane.transition_task(
                ACTOR,
                task["taskId"],
                expected_revision=1,
                target="queued",
                now=1_003,
            ),
        )
        queued = self.plane.transition_task(
            ACTOR,
            task["taskId"],
            expected_revision=2,
            target="queued",
            now=1_003,
        )
        self.assertEqual("queued", queued["state"])
        self.assert_code(
            "managed-execution.unavailable",
            lambda: self.plane.transition_task(
                ACTOR,
                task["taskId"],
                expected_revision=3,
                target="running",
                now=1_004,
            ),
        )
        failed = self.plane.transition_task(
            ACTOR,
            task["taskId"],
            expected_revision=3,
            target="failed",
            now=1_005,
        )
        self.assertEqual("failed", failed["state"])
        retried = self.plane.transition_task(
            ACTOR,
            task["taskId"],
            expected_revision=4,
            target="retrying",
            now=1_006,
        )
        self.assertEqual("retrying", retried["state"])
        self.assert_code(
            "access.denied",
            lambda: self.plane.get_task(OTHER_ACTOR, task["taskId"]),
        )

    def test_run_plan_steps_failure_retry_and_no_executor_spoof(self) -> None:
        context = create_context(self.plane)
        task = create_task(self.plane, context_ids=[context["contextId"]])
        queued = self.plane.transition_task(ACTOR, task["taskId"], expected_revision=1, target="queued", now=1_002)
        self.assertEqual("queued", queued["state"])
        run = self.plane.create_run_plan(
            ACTOR,
            task["taskId"],
            manifest=manifest([context["contextId"]]),
            idempotency_key="run.first",
            now=1_003,
        )
        self.assertEqual("queued", run["state"])
        self.assertEqual(2, len(run["steps"]))
        expected_step = "planned" if ManagedWorkPlane.execution_status()["available"] else "blocked-unavailable"
        self.assertTrue(all(step["state"] == expected_step for step in run["steps"]))
        self.assert_code(
            "managed-execution.unavailable",
            lambda: self.plane.transition_run(
                ACTOR,
                run["runId"],
                expected_revision=1,
                target="running",
                detail={},
                now=1_004,
            ),
        )
        failed = self.plane.transition_run(
            ACTOR,
            run["runId"],
            expected_revision=1,
            target="failed",
            detail={"code": "sandbox.unavailable"},
            now=1_004,
        )
        self.assertEqual("failed", failed["state"])
        retry = self.plane.retry_run(
            ACTOR,
            run["runId"],
            expected_revision=2,
            idempotency_key="run.retry",
            now=1_005,
        )
        self.assertEqual(run["runId"], retry["parentRunId"])
        self.assertEqual("queued", retry["state"])
        self.assertEqual(1, self.plane.get_task(ACTOR, task["taskId"])["retryCount"])

    def test_task_scoped_context_captured_after_task_is_available_only_to_that_task(self) -> None:
        first_task = create_task(self.plane, key="task.context-owner")
        second_task = create_task(self.plane, key="task.context-other", now=1_002)
        context = self.plane.capture_context(
            ACTOR,
            source="explicit-file-selection",
            access_scope="task",
            task_id=first_task["taskId"],
            content={"fileHandle": "selection.one"},
            sensitivity="private",
            ttl_seconds=600,
            idempotency_key="context.task-owned",
            now=1_003,
        )
        self.plane.transition_task(
            ACTOR,
            first_task["taskId"],
            expected_revision=1,
            target="queued",
            now=1_004,
        )
        run = self.plane.create_run_plan(
            ACTOR,
            first_task["taskId"],
            manifest=manifest([context["contextId"]]),
            idempotency_key="run.task-context",
            now=1_005,
        )
        self.assertEqual([context["contextId"]], run["manifest"]["contextIds"])
        self.plane.transition_task(
            ACTOR,
            second_task["taskId"],
            expected_revision=1,
            target="queued",
            now=1_004,
        )
        self.assert_code(
            "run.context-scope",
            lambda: self.plane.create_run_plan(
                ACTOR,
                second_task["taskId"],
                manifest=manifest([context["contextId"]]),
                idempotency_key="run.wrong-task-context",
                now=1_005,
            ),
        )

    def test_run_rejects_context_escape_network_without_grant_and_command_fields(self) -> None:
        context = create_context(self.plane)
        other = create_context(self.plane, actor=OTHER_ACTOR, key="context.other")
        task = create_task(self.plane, context_ids=[context["contextId"]])
        self.plane.transition_task(ACTOR, task["taskId"], expected_revision=1, target="queued", now=1_002)
        escaped = manifest([other["contextId"]])
        self.assert_code(
            "access.denied",
            lambda: self.plane.create_run_plan(
                ACTOR,
                task["taskId"],
                manifest=escaped,
                idempotency_key="run.escape",
                now=1_003,
            ),
        )
        networked = manifest([context["contextId"]])
        networked["networkGranted"] = True
        networked["budgets"] = budget(network=True)
        self.assert_code(
            "run.network-denied",
            lambda: self.plane.create_run_plan(
                ACTOR,
                task["taskId"],
                manifest=networked,
                idempotency_key="run.network",
                now=1_003,
            ),
        )
        injected = manifest([context["contextId"]])
        injected["command"] = "rm -rf /"
        self.assert_code(
            "validation.unknown-field",
            lambda: self.plane.create_run_plan(
                ACTOR,
                task["taskId"],
                manifest=injected,
                idempotency_key="run.command",
                now=1_003,
            ),
        )

if __name__ == "__main__":
    unittest.main()
