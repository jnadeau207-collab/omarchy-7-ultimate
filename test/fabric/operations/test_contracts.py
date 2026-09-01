from __future__ import annotations

import copy
import json
import unittest

from helper import ROOT, Harness

from jsonschema import Draft202012Validator, ValidationError

from omarchy_fabric.models import FabricError
from omarchy_fabric.operations.contracts import ExecutorIntent, OperationPlan

SCHEMA_ROOT = ROOT / "default" / "fabric" / "schema"

def schema(name: str):
    return json.loads((SCHEMA_ROOT / name).read_text(encoding="utf-8"))

def assert_closed_objects(test: unittest.TestCase, value, path="$", seen=None):
    seen = seen or set()
    if id(value) in seen:
        return
    seen.add(id(value))
    if isinstance(value, dict):
        if value.get("type") == "object":
            test.assertIs(value.get("additionalProperties"), False, path)
        for key, child in value.items():
            assert_closed_objects(test, child, f"{path}.{key}", seen)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            assert_closed_objects(test, child, f"{path}[{index}]", seen)

class OperationContractTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.harness = Harness()
        self.coordinator_schema = schema("operation-coordinator-v0.json")
        self.executor_schema = schema("operation-executor-v0.json")
        Draft202012Validator.check_schema(self.coordinator_schema)
        Draft202012Validator.check_schema(self.executor_schema)

    async def asyncTearDown(self) -> None:
        self.harness.close()

    async def test_state_ledger_and_intent_match_closed_schemas(self) -> None:
        preflight = await self.harness.coordinator.preflight(
            self.harness.principal,
            provider_id="test.settings",
            action="settings.set",
            arguments={"resourceId": "setting.primary", "desired": True},
            idempotency_key="schema.operation",
        )
        Draft202012Validator(self.coordinator_schema).validate(preflight)
        operation_id = preflight["operationId"]
        final = await self.harness.start(operation_id)
        Draft202012Validator(self.coordinator_schema).validate(final)
        ledger = self.harness.coordinator.ledger(self.harness.principal, operation_id)
        Draft202012Validator(self.coordinator_schema).validate(ledger)
        plan = self.harness.store.get(operation_id).plan
        Draft202012Validator(self.executor_schema).validate(plan.intent.as_dict())

    async def test_unknown_fields_fail_at_every_protocol_layer(self) -> None:
        operation_id = await self.harness.preflight()
        state = self.harness.coordinator.get(self.harness.principal, operation_id)
        validator = Draft202012Validator(self.coordinator_schema)
        unknown = copy.deepcopy(state)
        unknown["actor"] = "spoof"
        with self.assertRaises(ValidationError):
            validator.validate(unknown)
        unknown = copy.deepcopy(state)
        unknown["provider"]["argv"] = ["sh", "-c"]
        with self.assertRaises(ValidationError):
            validator.validate(unknown)
        intent = self.harness.store.get(operation_id).plan.intent.as_dict()
        intent["payload"]["environment"] = {"LD_PRELOAD": "evil"}
        with self.assertRaises(ValidationError):
            Draft202012Validator(self.executor_schema).validate(intent)
        ledger = self.harness.coordinator.ledger(self.harness.principal, operation_id)
        ledger["entries"][0]["payload"]["secret"] = "value"
        with self.assertRaises(ValidationError):
            validator.validate(ledger)

    async def test_schema_objects_are_recursively_closed(self) -> None:
        assert_closed_objects(self, self.coordinator_schema)
        assert_closed_objects(self, self.executor_schema)

    async def test_python_plan_and_intent_decoders_are_exact(self) -> None:
        operation_id = await self.harness.preflight()
        plan = self.harness.store.get(operation_id).plan
        document = plan.as_dict()
        document["owner"]["claimedBy"] = "caller"
        with self.assertRaises(FabricError):
            OperationPlan.from_dict(document)
        intent = plan.intent.as_dict()
        intent["argv"] = ["sh", "-c"]
        with self.assertRaises(FabricError):
            ExecutorIntent.from_dict(intent)

    async def test_schema_files_have_unique_ids_and_no_remote_runtime_refs(self) -> None:
        ids = {self.coordinator_schema["$id"], self.executor_schema["$id"]}
        self.assertEqual(len(ids), 2)
        for document in (self.coordinator_schema, self.executor_schema):
            encoded = json.dumps(document)
            self.assertNotIn("http://", encoded)
            self.assertNotIn("https://", encoded.replace(document["$schema"], ""))

if __name__ == "__main__":
    unittest.main()
