from __future__ import annotations

import asyncio
import unittest
from typing import Any, Mapping

from helper import Harness, fake_intents

from omarchy_fabric.models import FabricError, FixedArgvCommand
from omarchy_fabric.security.normalize import binding_digest
from omarchy_fabric.operations.session_executor import (
    SessionCommandExecutor,
    SessionCommandResult,
)

class RecordingRunner:
    def __init__(self, values: dict[str, Any], *, returncode: int = 0, stderr: str = "") -> None:
        self.values = values
        self.returncode = returncode
        self.stderr = stderr
        self.calls: list[tuple[tuple[str, ...], str]] = []

    async def __call__(self, command: FixedArgvCommand, payload: str) -> SessionCommandResult:
        import json

        self.calls.append(((command.executable, *command.arguments), payload))
        if self.returncode == 0:
            decoded = json.loads(payload)
            self.values[decoded["resourceId"]] = decoded["desired"]
        return SessionCommandResult(self.returncode, "applied", self.stderr)

def reader_for(values: Mapping[str, Any]):
    async def read(resource_id: str) -> Mapping[str, Any]:
        return {"resourceId": resource_id, "value": values.get(resource_id)}

    return read

class SynchronousStateView:
    def __init__(self, values: Mapping[str, Any]) -> None:
        self.values = values

    @staticmethod
    def _revision(value: Any) -> str:
        return "state." + binding_digest(value)

    def state(self, resource_id: str) -> dict[str, Any]:
        value = self.values.get(resource_id)
        return {"resourceId": resource_id, "revision": self._revision(value), "value": value}

class SessionExecutorTests(unittest.TestCase):
    def _harness(self, *, returncode: int = 0, stderr: str = "") -> tuple[Harness, RecordingRunner, dict[str, Any]]:
        harness = Harness()
        values: dict[str, Any] = {"setting.primary": False, "setting.secondary": False}
        runner = RecordingRunner(values, returncode=returncode, stderr=stderr)
        executor = SessionCommandExecutor(fake_intents(), reader_for(values), runner=runner)
        harness.executor = executor
        harness.gateway.executor = SynchronousStateView(values)
        harness.coordinator = harness.make_coordinator(executor=executor)
        return harness, runner, values

    def test_apply_runs_code_owned_argv_and_records_the_new_state(self) -> None:
        harness, runner, values = self._harness()
        self.addCleanup(harness.close)
        self.addCleanup(harness.temp.cleanup)

        async def scenario() -> None:
            operation_id = await harness.preflight()
            await harness.start(operation_id)
            for _ in range(400):
                state = harness.coordinator.get(harness.principal, operation_id)
                if state["status"] in {"succeeded", "failed", "cancelled", "recovered"}:
                    self.assertEqual(state["status"], "succeeded", state)
                    return
                await asyncio.sleep(0.01)
            self.fail("operation never reached a terminal status")

        asyncio.run(scenario())

        self.assertTrue(values["setting.primary"], values)
        self.assertEqual(len(runner.calls), 1)
        argv, payload = runner.calls[0]
        self.assertTrue(argv[0].startswith("/"), argv)
        self.assertIn("setting.primary", payload)

    def test_executor_is_available_and_reports_state(self) -> None:
        values = {"setting.primary": False}
        runner = RecordingRunner(values)
        executor = SessionCommandExecutor(fake_intents(), reader_for(values), runner=runner)
        self.assertTrue(executor.available)
        state = asyncio.run(executor.state("setting.primary"))
        self.assertEqual(state["resourceId"], "setting.primary")
        self.assertEqual(state["value"], False)
        self.assertTrue(state["revision"].startswith("state."))

    def test_absent_reader_state_is_a_typed_executor_error(self) -> None:
        async def read(resource_id: str):
            return None

        executor = SessionCommandExecutor(fake_intents(), read)
        with self.assertRaises(FabricError) as caught:
            asyncio.run(executor.state("setting.primary"))
        self.assertEqual(caught.exception.code, "executor.resource-unavailable")

    def test_invalid_deadline_is_rejected(self) -> None:
        with self.assertRaises(FabricError) as caught:
            SessionCommandExecutor(fake_intents(), reader_for({}), timeout_seconds=0.0)
        self.assertEqual(caught.exception.code, "executor.invalid-definition")

if __name__ == "__main__":
    unittest.main()
