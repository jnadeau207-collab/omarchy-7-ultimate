from __future__ import annotations

import asyncio
import subprocess
import unittest
import uuid
from unittest import mock

from helper import FABRIC_ROOT

from omarchy_fabric.models import (
    MAX_FRAME_BYTES,
    FixedArgvCommand,
    FabricError,
    run_fixed_argv,
)
from omarchy_fabric.protocol import (
    FabricClient,
    ProtocolViolation,
    decode_frame,
    encode_frame,
    validate_request,
    validate_server_message,
)

class ProtocolUnitTests(unittest.TestCase):
    def test_round_trip_preserves_finite_json(self) -> None:
        message = {
            "protocol": "omarchy.fabric.rpc/v0",
            "id": "one",
            "method": "health",
            "params": {},
        }
        encoded = encode_frame(message)
        self.assertEqual(decode_frame(encoded[:-1]), message)
        self.assertEqual(validate_request(message).request_id, "one")

    def test_malformed_duplicate_and_nonfinite_json_are_rejected(self) -> None:
        for frame in (b"{", b'{"a":1,"a":2}', b'{"value":NaN}'):
            with self.subTest(frame=frame):
                with self.assertRaises(ProtocolViolation) as caught:
                    decode_frame(frame)
                self.assertEqual(caught.exception.error.code, "rpc.invalid-json")

    def test_non_object_and_invalid_utf8_are_rejected(self) -> None:
        with self.assertRaises(ProtocolViolation) as caught:
            decode_frame(b"[]")
        self.assertEqual(caught.exception.error.code, "rpc.invalid-envelope")
        with self.assertRaises(ProtocolViolation) as caught:
            decode_frame(b'\xff')
        self.assertEqual(caught.exception.error.code, "rpc.invalid-encoding")

    def test_frame_bounds_apply_to_requests_and_responses(self) -> None:
        with self.assertRaises(ProtocolViolation) as caught:
            decode_frame(b"x" * (MAX_FRAME_BYTES + 1))
        self.assertEqual(caught.exception.error.code, "rpc.frame-too-large")
        self.assertTrue(caught.exception.fatal)
        with self.assertRaises(FabricError) as response_error:
            encode_frame({"value": "x" * MAX_FRAME_BYTES})
        self.assertEqual(response_error.exception.code, "rpc.response-too-large")

    def test_request_envelope_is_closed_and_ids_are_bounded(self) -> None:
        base = {
            "protocol": "omarchy.fabric.rpc/v0",
            "id": "one",
            "method": "health",
            "params": {},
        }
        with self.assertRaises(ProtocolViolation) as caught:
            validate_request({**base, "extra": True})
        self.assertEqual(caught.exception.error.code, "rpc.invalid-envelope")
        with self.assertRaises(ProtocolViolation) as caught:
            validate_request({**base, "id": "x" * 129})
        self.assertEqual(caught.exception.error.code, "rpc.invalid-id")
        without_params = dict(base)
        del without_params["params"]
        with self.assertRaises(ProtocolViolation) as caught:
            validate_request(without_params)
        self.assertEqual(caught.exception.error.code, "rpc.invalid-envelope")

    def test_server_envelopes_are_exact_and_error_types_are_not_coerced(self) -> None:
        valid_error = {
            "code": "provider.failed",
            "title": "Provider failed",
            "explanation": "The provider rejected the operation.",
            "detail": "",
            "retryable": False,
            "changeState": "none",
        }
        invalid_messages = (
            {"protocol": "omarchy.fabric.rpc/v0", "id": "one", "result": {}, "error": valid_error},
            {"protocol": "omarchy.fabric.rpc/v0", "event": {}, "id": "one"},
            {
                "protocol": "omarchy.fabric.rpc/v0",
                "id": "one",
                "error": {**valid_error, "retryable": "false"},
            },
            {
                "protocol": "omarchy.fabric.rpc/v0",
                "id": "one",
                "error": {**valid_error, "unexpected": True},
            },
            {
                "protocol": "omarchy.fabric.rpc/v0",
                "id": "one",
                "error": {**valid_error, "changeState": []},
            },
        )
        for message in invalid_messages:
            with self.subTest(message=message):
                with self.assertRaises(ProtocolViolation) as caught:
                    validate_server_message(message)
                self.assertTrue(caught.exception.fatal)
                self.assertEqual(caught.exception.error.code, "rpc.invalid-response")

    def test_server_event_contract_is_validated(self) -> None:
        event = {
            "sequence": 1,
            "id": str(uuid.uuid4()),
            "topic": "provider.changed",
            "payload": {},
            "createdAt": 1.0,
        }
        kind, response_id, parsed = validate_server_message(
            {"protocol": "omarchy.fabric.rpc/v0", "event": event}
        )
        self.assertEqual((kind, response_id, parsed), ("event", None, event))
        for changed in (
            {**event, "sequence": True},
            {**event, "topic": "Provider Changed"},
            {**event, "createdAt": float("inf")},
            {**event, "extra": True},
        ):
            with self.subTest(event=changed):
                with self.assertRaises(ProtocolViolation):
                    validate_server_message(
                        {"protocol": "omarchy.fabric.rpc/v0", "event": changed}
                    )

class FabricClientTests(unittest.IsolatedAsyncioTestCase):
    async def test_event_queue_is_bounded_and_overflow_closes_the_connection(self) -> None:
        client = FabricClient(FABRIC_ROOT / "unused.sock", event_backlog=1)
        reader = asyncio.StreamReader()
        client._reader = reader
        for sequence in (1, 2):
            reader.feed_data(
                encode_frame(
                    {
                        "protocol": "omarchy.fabric.rpc/v0",
                        "event": {
                            "sequence": sequence,
                            "id": str(uuid.uuid4()),
                            "topic": "provider.changed",
                            "payload": {},
                            "createdAt": float(sequence),
                        },
                    }
                )
            )
        reader.feed_eof()
        await client._read_loop()
        self.assertEqual(client._events.qsize(), 1)
        self.assertIsInstance(client._closed_error, FabricError)
        self.assertEqual(client._closed_error.code, "events.client-overflow")

    def test_event_queue_requires_a_positive_bound(self) -> None:
        for invalid in (0, -1, True):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    FabricClient(FABRIC_ROOT / "unused.sock", event_backlog=invalid)

class FixedArgvTests(unittest.TestCase):
    def test_fixed_argv_requires_absolute_immutable_vector(self) -> None:
        with self.assertRaises(ValueError):
            FixedArgvCommand("echo")
        with self.assertRaises(TypeError):
            FixedArgvCommand("/usr/bin/printf", ["%s"])
        command = FixedArgvCommand("/usr/bin/printf", ("%s", "fixed"))
        self.assertEqual(command.argv, ("/usr/bin/printf", "%s", "fixed"))

    @mock.patch("omarchy_fabric.models.subprocess.run")
    def test_fixed_argv_never_uses_a_shell_or_appends_payload(self, run: mock.Mock) -> None:
        run.return_value = subprocess.CompletedProcess([], 0, "", "")
        command = FixedArgvCommand("/usr/bin/provider-helper", ("--typed-stdin",))
        run_fixed_argv(command, stdin_payload={"hostile": "$(touch /tmp/nope); rm -rf /"})
        positional, keywords = run.call_args
        self.assertEqual(positional[0], ["/usr/bin/provider-helper", "--typed-stdin"])
        self.assertFalse(keywords["shell"])
        self.assertIn("$(touch /tmp/nope)", keywords["input"])

if __name__ == "__main__":
    unittest.main()
