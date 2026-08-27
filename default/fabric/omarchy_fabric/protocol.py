"""Bounded newline-framed JSON transport for provisional Fabric RPC."""

from __future__ import annotations

import asyncio
import json
import math
import re
import uuid
from pathlib import Path
from typing import Any, Iterable, Mapping

from .models import (
    MAX_FRAME_BYTES,
    MAX_PROTOCOL_VERSION,
    MAX_REQUEST_ID_BYTES,
    MAX_SUBSCRIBER_BACKLOG,
    MIN_PROTOCOL_VERSION,
    PROTOCOL_NAME,
    PROTOCOL_VERSION,
    FabricError,
    RpcRequest,
)


STABLE_ID = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$")
UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
CHANGE_STATES = {"none", "partial", "complete", "unknown"}


class ProtocolViolation(Exception):
    def __init__(
        self,
        error: FabricError,
        *,
        request_id: str | None = None,
        fatal: bool = False,
    ) -> None:
        super().__init__(str(error))
        self.error = error
        self.request_id = request_id
        self.fatal = fatal


def _object_without_duplicates(pairs: Iterable[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f"duplicate object key: {key}")
        value[key] = item
    return value


def _reject_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON number: {value}")


def decode_frame(frame: bytes) -> dict[str, Any]:
    if len(frame) > MAX_FRAME_BYTES:
        raise ProtocolViolation(
            FabricError(
                "rpc.frame-too-large",
                "Fabric request is too large",
                f"A Fabric frame may contain at most {MAX_FRAME_BYTES} bytes.",
            ),
            fatal=True,
        )
    try:
        text = frame.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise ProtocolViolation(
            FabricError(
                "rpc.invalid-encoding",
                "Fabric request encoding is invalid",
                "Fabric frames must contain valid UTF-8 JSON.",
                detail=str(error),
            )
        ) from error

    try:
        value = json.loads(
            text,
            object_pairs_hook=_object_without_duplicates,
            parse_constant=_reject_constant,
        )
    except (json.JSONDecodeError, ValueError) as error:
        raise ProtocolViolation(
            FabricError(
                "rpc.invalid-json",
                "Fabric request JSON is invalid",
                "Fabric could not parse the newline-delimited JSON request.",
                detail=str(error),
            )
        ) from error

    if not isinstance(value, dict):
        raise ProtocolViolation(
            FabricError(
                "rpc.invalid-envelope",
                "Fabric request envelope is invalid",
                "Each Fabric frame must contain one JSON object.",
            )
        )
    return value


def encode_frame(message: Mapping[str, Any]) -> bytes:
    try:
        encoded = json.dumps(
            message,
            ensure_ascii=False,
            allow_nan=False,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
    except (TypeError, ValueError) as error:
        raise FabricError(
            "rpc.invalid-response",
            "Fabric response cannot be encoded",
            "The provider returned a value that is not finite JSON.",
            detail=str(error),
            change_state="unknown",
        ) from error
    if len(encoded) > MAX_FRAME_BYTES:
        raise FabricError(
            "rpc.response-too-large",
            "Fabric response is too large",
            f"A Fabric frame may contain at most {MAX_FRAME_BYTES} bytes.",
            change_state="unknown",
        )
    return encoded + b"\n"


async def read_frame(reader: asyncio.StreamReader) -> dict[str, Any] | None:
    try:
        frame = await reader.readuntil(b"\n")
    except asyncio.IncompleteReadError as error:
        if not error.partial:
            return None
        raise ProtocolViolation(
            FabricError(
                "rpc.truncated-frame",
                "Fabric request was truncated",
                "The connection closed before the request's newline terminator.",
            ),
            fatal=True,
        ) from error
    except asyncio.LimitOverrunError as error:
        raise ProtocolViolation(
            FabricError(
                "rpc.frame-too-large",
                "Fabric request is too large",
                f"A Fabric frame may contain at most {MAX_FRAME_BYTES} bytes.",
            ),
            fatal=True,
        ) from error

    return decode_frame(frame[:-1])


def validate_request(message: Mapping[str, Any]) -> RpcRequest:
    request_id = message.get("id")
    if not isinstance(request_id, str) or not request_id:
        raise ProtocolViolation(
            FabricError(
                "rpc.invalid-id",
                "Fabric request ID is invalid",
                "Every request must carry a non-empty string ID.",
            )
        )
    if len(request_id.encode("utf-8")) > MAX_REQUEST_ID_BYTES:
        raise ProtocolViolation(
            FabricError(
                "rpc.invalid-id",
                "Fabric request ID is invalid",
                f"Request IDs may contain at most {MAX_REQUEST_ID_BYTES} UTF-8 bytes.",
            ),
            request_id=request_id,
        )
    if message.get("protocol") != PROTOCOL_NAME:
        raise ProtocolViolation(
            FabricError(
                "rpc.incompatible-protocol",
                "Fabric protocol version is incompatible",
                f"This daemon accepts only {PROTOCOL_NAME}.",
                recovery_actions=("system.update",),
            ),
            request_id=request_id,
        )
    method = message.get("method")
    if not isinstance(method, str) or not method:
        raise ProtocolViolation(
            FabricError(
                "rpc.invalid-method",
                "Fabric method is invalid",
                "Every request must name a Fabric method.",
            ),
            request_id=request_id,
        )
    if "params" not in message:
        raise ProtocolViolation(
            FabricError(
                "rpc.invalid-envelope",
                "Fabric request envelope is invalid",
                "Every request must contain a params object.",
            ),
            request_id=request_id,
        )
    params = message["params"]
    if not isinstance(params, dict):
        raise ProtocolViolation(
            FabricError(
                "rpc.invalid-params",
                "Fabric request parameters are invalid",
                "The params field must be a JSON object.",
            ),
            request_id=request_id,
        )
    allowed = {"protocol", "id", "method", "params"}
    extras = sorted(set(message) - allowed)
    if extras:
        raise ProtocolViolation(
            FabricError(
                "rpc.invalid-envelope",
                "Fabric request envelope is invalid",
                "Unknown request fields are not accepted.",
                detail=", ".join(extras),
            ),
            request_id=request_id,
        )
    return RpcRequest(request_id=request_id, method=method, params=params)


def success_response(request_id: str, result: Mapping[str, Any] | list[Any]) -> dict[str, Any]:
    return {"protocol": PROTOCOL_NAME, "id": request_id, "result": result}


def error_response(request_id: str | None, error: FabricError) -> dict[str, Any]:
    return {"protocol": PROTOCOL_NAME, "id": request_id, "error": error.to_dict()}


def event_message(event: Mapping[str, Any]) -> dict[str, Any]:
    return {"protocol": PROTOCOL_NAME, "event": event}


def _invalid_server_message(explanation: str, *, detail: str = "") -> ProtocolViolation:
    return ProtocolViolation(
        FabricError(
            "rpc.invalid-response",
            "Fabric response is invalid",
            explanation,
            detail=detail,
        ),
        fatal=True,
    )


def _valid_stable_id(value: Any) -> bool:
    return (
        isinstance(value, str)
        and 1 <= len(value) <= 160
        and STABLE_ID.fullmatch(value) is not None
    )


def _validate_event(event: Any) -> dict[str, Any]:
    if not isinstance(event, dict) or set(event) != {
        "sequence",
        "id",
        "topic",
        "payload",
        "createdAt",
    }:
        raise _invalid_server_message("The daemon returned an invalid event envelope.")
    sequence = event["sequence"]
    created_at = event["createdAt"]
    if isinstance(sequence, bool) or not isinstance(sequence, int) or sequence < 1:
        raise _invalid_server_message("The daemon returned an invalid event sequence.")
    if not isinstance(event["id"], str) or UUID.fullmatch(event["id"]) is None:
        raise _invalid_server_message("The daemon returned an invalid event ID.")
    if not _valid_stable_id(event["topic"]):
        raise _invalid_server_message("The daemon returned an invalid event topic.")
    if not isinstance(event["payload"], dict):
        raise _invalid_server_message("The daemon returned an invalid event payload.")
    if (
        isinstance(created_at, bool)
        or not isinstance(created_at, (int, float))
        or (isinstance(created_at, float) and not math.isfinite(created_at))
        or created_at < 0
    ):
        raise _invalid_server_message("The daemon returned an invalid event timestamp.")
    return event


def _validate_remote_error(raw_error: Any) -> FabricError:
    required = {"code", "title", "explanation", "detail", "retryable", "changeState"}
    optional = {"recoveryActions"}
    if not isinstance(raw_error, dict) or not required <= set(raw_error) or set(raw_error) - required - optional:
        raise _invalid_server_message("The daemon returned an invalid error envelope.")
    actions = raw_error.get("recoveryActions", [])
    if (
        not _valid_stable_id(raw_error["code"])
        or not isinstance(raw_error["title"], str)
        or not 1 <= len(raw_error["title"]) <= 160
        or not isinstance(raw_error["explanation"], str)
        or not 1 <= len(raw_error["explanation"]) <= 2000
        or not isinstance(raw_error["detail"], str)
        or len(raw_error["detail"]) > 16000
        or not isinstance(raw_error["retryable"], bool)
        or not isinstance(raw_error["changeState"], str)
        or raw_error["changeState"] not in CHANGE_STATES
        or not isinstance(actions, list)
        or any(not _valid_stable_id(action) for action in actions)
        or len(set(actions)) != len(actions)
    ):
        raise _invalid_server_message("The daemon returned an invalid error envelope.")
    return FabricError(
        raw_error["code"],
        raw_error["title"],
        raw_error["explanation"],
        detail=raw_error["detail"],
        retryable=raw_error["retryable"],
        change_state=raw_error["changeState"],
        recovery_actions=tuple(actions),
    )


def validate_server_message(message: Mapping[str, Any]) -> tuple[str, str | None, Any]:
    """Validate one daemon envelope without trusting coercible JSON values."""

    if message.get("protocol") != PROTOCOL_NAME:
        raise ProtocolViolation(
            FabricError(
                "rpc.incompatible-protocol",
                "Fabric response protocol is incompatible",
                "The daemon replied with an unsupported protocol.",
            ),
            fatal=True,
        )
    keys = set(message)
    if keys == {"protocol", "event"}:
        return "event", None, _validate_event(message["event"])
    if keys == {"protocol", "id", "result"}:
        response_id = message["id"]
        if (
            not isinstance(response_id, str)
            or not response_id
            or len(response_id.encode("utf-8")) > MAX_REQUEST_ID_BYTES
        ):
            raise _invalid_server_message("The daemon returned an invalid response ID.")
        return "result", response_id, message["result"]
    if keys == {"protocol", "id", "error"}:
        response_id = message["id"]
        if (
            not isinstance(response_id, str)
            or not response_id
            or len(response_id.encode("utf-8")) > MAX_REQUEST_ID_BYTES
        ):
            raise _invalid_server_message("The daemon returned an invalid response ID.")
        return "error", response_id, _validate_remote_error(message["error"])
    raise _invalid_server_message(
        "The daemon response does not match exactly one result, error, or event envelope."
    )


class FabricClient:
    """Small reconnectable async client used by diagnostics and provider tests."""

    def __init__(
        self,
        socket_path: Path,
        *,
        client_name: str = "omarchy-fabric-client",
        request_timeout: float = 5.0,
        event_backlog: int = MAX_SUBSCRIBER_BACKLOG,
    ) -> None:
        if isinstance(event_backlog, bool) or not isinstance(event_backlog, int) or event_backlog < 1:
            raise ValueError("event backlog must be a positive integer")
        self.socket_path = Path(socket_path)
        self.client_name = client_name
        self.request_timeout = request_timeout
        self._event_backlog = event_backlog
        self._reader: asyncio.StreamReader | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._reader_task: asyncio.Task[None] | None = None
        self._pending: dict[str, asyncio.Future[Any]] = {}
        self._events: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=event_backlog)
        self._write_lock = asyncio.Lock()
        self._closed_error: Exception | None = None

    @property
    def connected(self) -> bool:
        return self._writer is not None and not self._writer.is_closing()

    async def connect(self) -> Mapping[str, Any]:
        await self.close()
        self._closed_error = None
        self._events = asyncio.Queue(maxsize=self._event_backlog)
        try:
            reader, writer = await asyncio.open_unix_connection(
                path=str(self.socket_path),
                limit=MAX_FRAME_BYTES + 1,
            )
        except OSError as error:
            raise FabricError(
                "daemon.unavailable",
                "Fabric is unavailable",
                "The Fabric user daemon is not accepting connections.",
                detail=str(error),
                retryable=True,
                recovery_actions=("fabric.restart",),
            ) from error
        self._reader = reader
        self._writer = writer
        self._reader_task = asyncio.create_task(self._read_loop())
        try:
            return await self.request(
                "hello",
                {
                    "client": self.client_name,
                    "minVersion": MIN_PROTOCOL_VERSION,
                    "maxVersion": MAX_PROTOCOL_VERSION,
                },
            )
        except Exception:
            await self.close()
            raise

    async def reconnect(self) -> Mapping[str, Any]:
        return await self.connect()

    async def close(self) -> None:
        reader_task = self._reader_task
        self._reader_task = None
        writer = self._writer
        self._reader = None
        self._writer = None
        if writer is not None:
            writer.close()
            try:
                await writer.wait_closed()
            except OSError:
                pass
        if reader_task is not None and reader_task is not asyncio.current_task():
            reader_task.cancel()
            try:
                await reader_task
            except (asyncio.CancelledError, OSError):
                pass
        self._fail_pending(
            FabricError(
                "daemon.disconnected",
                "Fabric connection closed",
                "The Fabric connection closed before the request completed.",
                retryable=True,
                change_state="unknown",
                recovery_actions=("fabric.reconnect",),
            )
        )

    async def request(
        self,
        method: str,
        params: Mapping[str, Any] | None = None,
        *,
        request_id: str | None = None,
    ) -> Any:
        if not self.connected or self._writer is None:
            raise FabricError(
                "daemon.disconnected",
                "Fabric is disconnected",
                "Connect to the Fabric daemon before sending a request.",
                retryable=True,
                recovery_actions=("fabric.reconnect",),
            )
        request_id = request_id or str(uuid.uuid4())
        if request_id in self._pending:
            raise FabricError(
                "rpc.duplicate-id",
                "Fabric request ID is already pending",
                "A client cannot reuse a request ID while that request is pending.",
            )
        loop = asyncio.get_running_loop()
        future: asyncio.Future[Any] = loop.create_future()
        self._pending[request_id] = future
        message = {
            "protocol": PROTOCOL_NAME,
            "id": request_id,
            "method": method,
            "params": dict(params or {}),
        }
        try:
            async with self._write_lock:
                if self._writer is None:
                    raise ConnectionError("connection closed")
                self._writer.write(encode_frame(message))
                await self._writer.drain()
            return await asyncio.wait_for(future, timeout=self.request_timeout)
        except asyncio.TimeoutError as error:
            if not future.done():
                future.cancel()
            raise FabricError(
                "rpc.timeout",
                "Fabric request timed out",
                "The daemon did not finish the request before the client deadline.",
                retryable=True,
                change_state="unknown",
                recovery_actions=("fabric.reconnect",),
            ) from error
        except (ConnectionError, OSError) as error:
            raise FabricError(
                "daemon.disconnected",
                "Fabric connection closed",
                "The Fabric connection closed while sending the request.",
                detail=str(error),
                retryable=True,
                change_state="unknown",
                recovery_actions=("fabric.reconnect",),
            ) from error
        finally:
            self._pending.pop(request_id, None)

    async def next_event(self, *, timeout: float = 5.0) -> Mapping[str, Any]:
        try:
            return await asyncio.wait_for(self._events.get(), timeout=timeout)
        except asyncio.TimeoutError as error:
            raise FabricError(
                "events.timeout",
                "No Fabric event arrived",
                "The subscription produced no event before the client deadline.",
                retryable=True,
            ) from error

    async def _read_loop(self) -> None:
        assert self._reader is not None
        disconnect_error: Exception = FabricError(
            "daemon.disconnected",
            "Fabric connection closed",
            "The Fabric daemon closed the connection.",
            retryable=True,
            change_state="unknown",
            recovery_actions=("fabric.reconnect",),
        )
        try:
            while True:
                message = await read_frame(self._reader)
                if message is None:
                    break
                kind, response_id, payload = validate_server_message(message)
                if kind == "event":
                    try:
                        self._events.put_nowait(payload)
                    except asyncio.QueueFull as error:
                        raise ProtocolViolation(
                            FabricError(
                                "events.client-overflow",
                                "Fabric client event backlog overflowed",
                                "The client did not consume Fabric events before its bounded backlog filled.",
                                retryable=True,
                                change_state="unknown",
                                recovery_actions=("events.reconnect-and-replay",),
                            ),
                            fatal=True,
                        ) from error
                    continue
                assert response_id is not None
                future = self._pending.get(response_id)
                if future is None or future.done():
                    continue
                if kind == "error":
                    future.set_exception(payload)
                else:
                    future.set_result(payload)
        except asyncio.CancelledError:
            return
        except (OSError, ProtocolViolation, FabricError) as error:
            disconnect_error = error.error if isinstance(error, ProtocolViolation) else error
        finally:
            self._closed_error = disconnect_error
            self._fail_pending(disconnect_error)
            writer = self._writer
            self._reader = None
            self._writer = None
            if writer is not None:
                writer.close()

    def _fail_pending(self, error: Exception) -> None:
        for future in list(self._pending.values()):
            if not future.done():
                future.set_exception(error)
