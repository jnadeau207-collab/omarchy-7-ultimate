from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

from helper import ACTOR, ManagedWorkPlane


SCHEMA_DIRECTORY = Path(__file__).resolve().parents[3] / "default" / "fabric" / "schema"


class ManagedWorkRpcSchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        documents = {
            name: json.loads((SCHEMA_DIRECTORY / name).read_text(encoding="utf-8"))
            for name in (
                "common-v0.json",
                "managed-work-v0.json",
                "reference-operation-v0.json",
                "rpc-v0.json",
            )
        }
        resources: list[tuple[str, Resource]] = []
        for name, document in documents.items():
            resource = Resource.from_contents(document)
            resources.extend(((name, resource), (document["$id"], resource)))
        registry = Registry().with_resources(resources)
        cls.rpc_schema = documents["rpc-v0.json"]
        cls.managed_schema = documents["managed-work-v0.json"]
        Draft202012Validator.check_schema(cls.rpc_schema)
        Draft202012Validator.check_schema(cls.managed_schema)
        root_validator = Draft202012Validator(cls.rpc_schema, registry=registry)
        cls.request_validator = root_validator.evolve(schema=cls.rpc_schema["$defs"]["request"])
        cls.result_validator = root_validator.evolve(
            schema=cls.rpc_schema["$defs"]["managedWorkMethodResultContract"]
        )

    @staticmethod
    def request(params: dict[str, object]) -> dict[str, object]:
        return {
            "protocol": "omarchy.fabric.rpc/v0",
            "id": "request.one",
            "method": "managed-work.query",
            "params": params,
        }

    def assert_request_valid(self, params: dict[str, object]) -> None:
        self.assertEqual([], list(self.request_validator.iter_errors(self.request(params))))

    def assert_request_invalid(self, params: dict[str, object]) -> None:
        self.assertNotEqual([], list(self.request_validator.iter_errors(self.request(params))))

    def test_query_params_are_closed_paired_and_view_constrained(self) -> None:
        for view in ManagedWorkPlane.QUERY_VIEWS:
            self.assert_request_valid({"version": "v0", "view": view, "limit": 100})
        self.assert_request_valid(
            {
                "version": "v0",
                "view": "agent.tasks",
                "entityType": "task",
                "entityId": "task.one",
            }
        )
        self.assert_request_valid(
            {
                "version": "v0",
                "view": "agent.activity",
                "entityType": "operation",
                "entityId": "11111111-2222-3333-4444-555555555555",
            }
        )
        invalid = (
            {"version": "v1", "view": "agent.tasks"},
            {"version": "v0", "view": "agent.unknown"},
            {"version": "v0", "view": "agent.tasks", "owner": "account.uid.0"},
            {"version": "v0", "view": "agent.tasks", "argv": ["sh"]},
            {"version": "v0", "view": "agent.tasks", "env": {"TOKEN": "x"}},
            {"version": "v0", "view": "agent.tasks", "cursor": None},
            {"version": "v0", "view": "agent.tasks", "entityType": None, "entityId": None},
            {"version": "v0", "view": "agent.tasks", "entityType": "task"},
            {"version": "v0", "view": "agent.tasks", "entityId": "task.one"},
            {
                "version": "v0",
                "view": "agent.tasks",
                "entityType": "task",
                "entityId": "task.one",
                "cursor": "opaque",
            },
            {
                "version": "v0",
                "view": "agent.providers",
                "entityType": "operation",
                "entityId": "operation.one",
            },
            {
                "version": "v0",
                "view": "agent.approvals",
                "entityType": "task",
                "entityId": "task.one",
            },
            {"version": "v0", "view": "agent.overview", "cursor": "opaque"},
        )
        for params in invalid:
            with self.subTest(params=params):
                self.assert_request_invalid(params)

    def test_all_twelve_runtime_results_bind_to_the_method_and_view(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            plane = ManagedWorkPlane(Path(temporary) / "managed-work.db").open()
            try:
                results = {
                    view: plane.query(ACTOR, view, now=1_000)
                    for view in ManagedWorkPlane.QUERY_VIEWS
                }
            finally:
                plane.close()
        for view, result in results.items():
            with self.subTest(view=view):
                contract = {"method": "managed-work.query", "result": result}
                self.assertEqual([], list(self.result_validator.iter_errors(contract)))

        wrong_method = {"method": "provider.read", "result": results["agent.overview"]}
        self.assertNotEqual([], list(self.result_validator.iter_errors(wrong_method)))

        swapped = copy.deepcopy(results["agent.tasks"])
        swapped["items"] = results["agent.troubleshooting"]["items"]
        self.assertNotEqual(
            [],
            list(
                self.result_validator.iter_errors(
                    {"method": "managed-work.query", "result": swapped}
                )
            ),
        )
        swapped_summary = copy.deepcopy(results["agent.tasks"])
        swapped_summary["summary"] = results["agent.usage"]["summary"]
        self.assertNotEqual(
            [],
            list(
                self.result_validator.iter_errors(
                    {"method": "managed-work.query", "result": swapped_summary}
                )
            ),
        )

    def test_rpc_contract_remains_well_below_one_frame(self) -> None:
        encoded = json.dumps(
            self.rpc_schema,
            ensure_ascii=False,
            allow_nan=False,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
        self.assertLess(len(encoded), 64 * 1024)


if __name__ == "__main__":
    unittest.main()
