from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator

from helper import ACTOR, OTHER_ACTOR, ManagedWorkPlane, budget, create_context, create_task, manifest, policy, template
from omarchy_fabric.managed_work import ManagedWorkError


class ProjectionQueryTests(unittest.TestCase):
    OPERATION_ID = "11111111-2222-3333-4444-555555555555"
    @classmethod
    def setUpClass(cls) -> None:
        schema_path = Path(__file__).resolve().parents[3] / "default" / "fabric" / "schema" / "managed-work-v0.json"
        cls.schema = json.loads(schema_path.read_text(encoding="utf-8"))
        Draft202012Validator.check_schema(cls.schema)
        cls.validator = Draft202012Validator(cls.schema)

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.plane = ManagedWorkPlane(Path(self.temporary.name) / "managed-work.db").open()

    def tearDown(self) -> None:
        self.plane.close()
        self.temporary.cleanup()

    def assert_valid(self, result: dict[str, object]) -> None:
        errors = sorted(self.validator.iter_errors(result), key=lambda error: list(error.path))
        if errors:
            self.fail("\n".join(error.message for error in errors[:10]))

    def assert_code(self, code: str, call) -> None:
        with self.assertRaises(ManagedWorkError) as caught:
            call()
        self.assertEqual(code, caught.exception.code)

    @staticmethod
    def approval(revision: int = 1, state: str = "pending") -> dict[str, object]:
        return {
            "sourceRevision": revision,
            "approvalId": "approval.one",
            "operationId": ProjectionQueryTests.OPERATION_ID,
            "capability": "display.configure",
            "state": state,
            "risk": "consequential",
            "summary": "Change the display scale",
            "requestedAt": 1_000,
            "expiresAt": 2_000,
        }

    @staticmethod
    def permission(revision: int = 1, state: str = "active") -> dict[str, object]:
        return {
            "sourceRevision": revision,
            "grantId": "grant.network",
            "capability": "managed.network",
            "resource": "network.internet",
            "state": state,
            "riskCeiling": "consequential",
            "issuedAt": 1_000,
            "expiresAt": 2_000,
        }

    def test_projection_revisions_are_monotonic_and_cross_principal_isolated(self) -> None:
        first = self.plane.project_approval(ACTOR, self.approval(), now=1_001)
        self.assert_valid(first)
        replay = self.plane.project_approval(ACTOR, self.approval(), now=1_002)
        self.assertEqual(first, replay)
        updated = self.plane.project_approval(ACTOR, self.approval(2, "approved"), now=1_003)
        self.assertEqual("approved", updated["state"])
        self.assert_code(
            "projection.stale",
            lambda: self.plane.project_approval(ACTOR, self.approval(1), now=1_004),
        )
        conflicting = self.approval(2, "denied")
        self.assert_code(
            "projection.conflict",
            lambda: self.plane.project_approval(ACTOR, conflicting, now=1_004),
        )
        other = self.plane.project_approval(OTHER_ACTOR, self.approval(), now=1_001)
        self.assertEqual(OTHER_ACTOR.principal_id, other["owner"]["principalId"])
        self.assertEqual([], self.plane.query(ACTOR, "agent.approvals", now=1_100)["items"])
        self.assertEqual(1, len(self.plane.query(OTHER_ACTOR, "agent.approvals", now=1_100)["items"]))

    def test_token_shaped_scalar_and_identity_fields_reject_before_any_transaction(self) -> None:
        token = "sk-" + "a" * 30
        before = {
            table: self.plane.store.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            for table in (
                "contexts",
                "approval_projections",
                "operation_links",
                "permission_projections",
                "usage_records",
                "provider_projections",
                "managed_events",
                "idempotency",
            )
        }
        self.assert_code(
            "validation.secret-field",
            lambda: self.plane.capture_context(
                ACTOR,
                source=token,
                access_scope="principal",
                content={"safe": True},
                sensitivity="personal",
                ttl_seconds=600,
                idempotency_key="context.secret-source",
                now=1_000,
            ),
        )
        approval = self.approval()
        approval["capability"] = token
        self.assert_code(
            "validation.secret-field",
            lambda: self.plane.project_approval(ACTOR, approval, now=1_000),
        )
        self.assert_code(
            "validation.secret-field",
            lambda: self.plane.link_operation(
                ACTOR,
                {
                    "sourceRevision": 1,
                    "operationId": "55555555-5555-5555-5555-555555555555",
                    "taskId": None,
                    "runId": None,
                    "capability": token,
                    "status": "failed",
                    "changeState": "none",
                    "summary": "No change was attempted",
                    "recoveryEligible": False,
                    "artifactIds": [],
                    "createdAt": 1_000,
                    "updatedAt": 1_000,
                },
                now=1_000,
            ),
        )
        permission = self.permission()
        permission["resource"] = token
        self.assert_code(
            "validation.secret-field",
            lambda: self.plane.project_permission(ACTOR, permission, now=1_000),
        )
        self.assert_code(
            "validation.secret-field",
            lambda: self.plane.record_usage(
                ACTOR,
                {
                    "usageId": "usage.secret-provider",
                    "taskId": None,
                    "runId": None,
                    "provider": token,
                    "metric": "tokens.input",
                    "quantity": 1,
                    "unit": "token",
                    "costMicrounits": 0,
                    "recordedAt": 1_000,
                },
            ),
        )
        self.assert_code(
            "validation.secret-field",
            lambda: self.plane.project_provider_inventory(
                ACTOR,
                [
                    {
                        "manifest": {"provider": token, "providerVersion": "v0"},
                        "fingerprint": "a" * 64,
                        "generation": 1,
                        "registrationOrder": 0,
                        "state": "available",
                        "detail": "",
                        "registeredAt": 1_000,
                        "changedAt": 1_000,
                    }
                ],
                now=1_000,
            ),
        )
        after = {
            table: self.plane.store.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            for table in before
        }
        self.assertEqual(before, after)

    def test_permission_enables_network_manifest_without_authorizing_execution(self) -> None:
        permission = self.plane.project_permission(ACTOR, self.permission(), now=1_001)
        self.assert_valid(permission)
        context = create_context(self.plane)
        task = create_task(self.plane, context_ids=[context["contextId"]])
        self.plane.transition_task(ACTOR, task["taskId"], expected_revision=1, target="queued", now=1_002)
        run_manifest = manifest([context["contextId"]])
        run_manifest["networkGranted"] = True
        run_manifest["budgets"] = budget(network=True)
        run = self.plane.create_run_plan(
            ACTOR,
            task["taskId"],
            manifest=run_manifest,
            idempotency_key="run.network-granted",
            now=1_003,
        )
        self.assert_valid(run)
        self.assertFalse(run["execution"]["available"])
        self.assertTrue(run["manifest"]["networkGranted"])

    def test_network_permission_must_cover_the_internet_resource(self) -> None:
        projection = self.permission()
        projection["resource"] = "network.local"
        self.plane.project_permission(ACTOR, projection, now=1_001)
        task = create_task(self.plane)
        self.plane.transition_task(ACTOR, task["taskId"], expected_revision=1, target="queued", now=1_002)
        run_manifest = manifest()
        run_manifest["networkGranted"] = True
        run_manifest["budgets"] = budget(network=True)
        self.assert_code(
            "run.network-denied",
            lambda: self.plane.create_run_plan(
                ACTOR,
                task["taskId"],
                manifest=run_manifest,
                idempotency_key="run.wrong-network-resource",
                now=1_003,
            ),
        )

    def test_artifact_usage_and_operation_links_keep_owned_provenance(self) -> None:
        task = create_task(self.plane)
        self.plane.transition_task(ACTOR, task["taskId"], expected_revision=1, target="queued", now=1_002)
        run = self.plane.create_run_plan(
            ACTOR,
            task["taskId"],
            manifest=manifest(),
            idempotency_key="run.artifact",
            now=1_003,
        )
        artifact = self.plane.register_artifact(
            ACTOR,
            task_id=task["taskId"],
            run_id=run["runId"],
            handle="artifact.report",
            label="Inventory report",
            media_type="application/json",
            byte_length=128,
            content_hash="a" * 64,
            scope="task",
            idempotency_key="artifact.report",
            now=1_004,
        )
        self.assert_valid(artifact)
        usage = self.plane.record_usage(
            ACTOR,
            {
                "usageId": "usage.one",
                "taskId": task["taskId"],
                "runId": run["runId"],
                "provider": "provider.test",
                "metric": "tokens.input",
                "quantity": 42,
                "unit": "token",
                "costMicrounits": 120,
                "recordedAt": 1_005,
            },
        )
        self.assert_valid(usage)
        operation = self.plane.link_operation(
            ACTOR,
            {
                "sourceRevision": 1,
                "operationId": self.OPERATION_ID,
                "taskId": task["taskId"],
                "runId": run["runId"],
                "capability": "system.inspect",
                "status": "failed",
                "changeState": "none",
                "summary": "Sandbox prerequisite missing",
                "recoveryEligible": False,
                "artifactIds": [artifact["artifactId"]],
                "createdAt": 1_003,
                "updatedAt": 1_006,
            },
            now=1_006,
        )
        self.assert_valid(operation)
        recovery_projection = {
            "sourceRevision": 2,
            "operationId": self.OPERATION_ID,
            "taskId": task["taskId"],
            "runId": run["runId"],
            "capability": "system.inspect",
            "status": "recovering",
            "changeState": "unknown",
            "summary": "Reconciling the interrupted operation",
            "recoveryEligible": True,
            "artifactIds": [artifact["artifactId"]],
            "createdAt": 1_003,
            "updatedAt": 1_007,
        }
        recovering = self.plane.link_operation(ACTOR, recovery_projection, now=1_007)
        self.assert_valid(recovering)
        self.assertEqual("recovering", recovering["status"])
        activity = self.plane.query(
            ACTOR,
            "agent.activity",
            entity_type="operation",
            entity_id=self.OPERATION_ID,
            now=1_007,
        )
        self.assert_valid(activity)
        self.assertEqual([artifact["artifactId"]], activity["items"][0]["artifactIds"])
        usage_query = self.plane.query(ACTOR, "agent.usage", now=1_007)
        self.assertEqual(120, usage_query["summary"]["costMicrounits"])

    def test_operation_inventory_is_an_exact_owner_scoped_source_snapshot(self) -> None:
        capability = "reference.setting.apply"

        def projection(operation_id: str, revision: int = 1) -> dict[str, object]:
            return {
                "sourceRevision": revision,
                "legacyOwner": False,
                "operationId": operation_id,
                "taskId": None,
                "runId": None,
                "capability": capability,
                "status": "failed",
                "changeState": "none",
                "summary": "Reference update failed safely",
                "recoveryEligible": False,
                "artifactIds": [],
                "createdAt": 1_000,
                "updatedAt": 1_001,
            }

        first_id = "11111111-1111-1111-1111-111111111111"
        second_id = "22222222-2222-2222-2222-222222222222"
        unrelated_id = "33333333-3333-3333-3333-333333333333"
        other_owner_id = "44444444-4444-4444-4444-444444444444"
        unrelated = projection(unrelated_id)
        unrelated["capability"] = "system.inspect"
        self.plane.link_operation(ACTOR, unrelated, now=1_001)
        self.plane.project_operation_inventory(
            ACTOR,
            [(ACTOR, projection(first_id)), (ACTOR, projection(second_id))],
            source_capability=capability,
            now=1_002,
        )
        self.plane.project_operation_inventory(
            OTHER_ACTOR,
            [(OTHER_ACTOR, projection(other_owner_id))],
            source_capability=capability,
            now=1_002,
        )

        self.plane.project_operation_inventory(
            ACTOR,
            [(ACTOR, projection(second_id))],
            source_capability=capability,
            now=1_003,
        )
        owned_ids = {
            item["operationId"]
            for item in self.plane.query(ACTOR, "agent.activity", now=1_004)["items"]
        }
        self.assertEqual({second_id, unrelated_id}, owned_ids)

        self.plane.project_operation_inventory(
            ACTOR,
            [],
            source_capability=capability,
            now=1_005,
        )
        owned_ids = {
            item["operationId"]
            for item in self.plane.query(ACTOR, "agent.activity", now=1_006)["items"]
        }
        self.assertEqual({unrelated_id}, owned_ids)
        other_ids = {
            item["operationId"]
            for item in self.plane.query(OTHER_ACTOR, "agent.activity", now=1_006)["items"]
        }
        self.assertEqual({other_owner_id}, other_ids)

        self.assert_code(
            "operation.inventory-owner",
            lambda: self.plane.project_operation_inventory(
                ACTOR,
                [(OTHER_ACTOR, projection(first_id))],
                source_capability=capability,
                now=1_007,
            ),
        )
        self.assertEqual(
            {unrelated_id},
            {
                item["operationId"]
                for item in self.plane.query(ACTOR, "agent.activity", now=1_008)["items"]
            },
        )
        conflicting = projection(unrelated_id, revision=2)
        self.assert_code(
            "operation.inventory-source-conflict",
            lambda: self.plane.project_operation_inventory(
                ACTOR,
                [(ACTOR, conflicting)],
                source_capability=capability,
                now=1_009,
            ),
        )
        preserved = self.plane.query(
            ACTOR,
            "agent.activity",
            entity_type="operation",
            entity_id=unrelated_id,
            now=1_010,
        )["items"][0]
        self.assertEqual("system.inspect", preserved["capability"])
        self.assertEqual(1, preserved["sourceRevision"])

    def test_every_agent_center_destination_has_a_closed_honest_query(self) -> None:
        context = create_context(self.plane)
        task = create_task(self.plane, context_ids=[context["contextId"]])
        self.plane.project_approval(ACTOR, self.approval(), now=1_003)
        self.plane.project_permission(ACTOR, self.permission(), now=1_003)
        self.plane.create_automation(
            ACTOR,
            name="Event automation",
            task_template=template([context["contextId"]]),
            trigger={"kind": "event", "topic": "provider.changed"},
            policy=policy(),
            idempotency_key="automation.query",
            now=1_003,
        )
        for view in sorted(self.plane.QUERY_VIEWS):
            result = self.plane.query(ACTOR, view, limit=10, now=1_010)
            self.assertEqual(view, result["view"])
            self.assertFalse(result["availability"]["executionAvailable"])
            self.assert_valid(result)
        providers = self.plane.query(ACTOR, "agent.providers", now=1_010)
        self.assertTrue(providers["availability"]["available"])
        self.assertEqual([], providers["items"])
        task_entity = self.plane.query(
            ACTOR,
            "agent.tasks",
            entity_type="task",
            entity_id=task["taskId"],
            now=1_010,
        )
        self.assert_valid(task_entity)

    def test_pagination_is_bounded_and_cursor_is_view_and_principal_bound(self) -> None:
        for index in range(5):
            create_task(self.plane, key=f"task.page-{index}", now=1_000 + index)
        first = self.plane.query(ACTOR, "agent.tasks", limit=2, now=1_100)
        self.assertEqual(2, len(first["items"]))
        self.assertIsNotNone(first["nextCursor"])
        second = self.plane.query(
            ACTOR,
            "agent.tasks",
            limit=2,
            cursor=first["nextCursor"],
            now=1_100,
        )
        first_ids = {item["task"]["taskId"] for item in first["items"]}
        second_ids = {item["task"]["taskId"] for item in second["items"]}
        self.assertTrue(first_ids.isdisjoint(second_ids))
        self.assert_code(
            "query.cursor",
            lambda: self.plane.query(OTHER_ACTOR, "agent.tasks", cursor=first["nextCursor"], now=1_100),
        )
        self.assert_code(
            "query.cursor",
            lambda: self.plane.query(ACTOR, "agent.history", cursor=first["nextCursor"], now=1_100),
        )
        self.assert_code(
            "validation.integer",
            lambda: self.plane.query(ACTOR, "agent.tasks", limit=101, now=1_100),
        )

    def test_schema_rejects_open_result_envelopes(self) -> None:
        task = create_task(self.plane)
        self.assert_valid(task)
        opened = dict(task)
        opened["unexpected"] = True
        self.assertTrue(list(self.validator.iter_errors(opened)))
        error = ManagedWorkError("test.failure", "Expected failure.", recovery_actions=("test.recover",)).as_dict()
        self.assert_valid(error)


if __name__ == "__main__":
    unittest.main()
