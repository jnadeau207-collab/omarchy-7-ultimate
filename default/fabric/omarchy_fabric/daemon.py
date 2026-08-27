"""Provisional owner-scoped Fabric daemon."""

from __future__ import annotations

import argparse
import asyncio
import copy
import json
import logging
import os
import re
import signal
import socket
import stat
import struct
import sys
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence

from .db import FabricDatabase, request_fingerprint
from .events import EventBroker, EventSubscription
from .health import daemon_health
from .models import (
    CURRENT_DATABASE_SCHEMA,
    DEFAULT_EVENT_RETENTION,
    MAX_EVENT_REPLAY,
    MAX_FRAME_BYTES,
    MAX_PROTOCOL_VERSION,
    MIN_PROTOCOL_VERSION,
    PROTOCOL_NAME,
    PROTOCOL_VERSION,
    FabricError,
    RpcRequest,
    default_socket_path,
    default_state_directory,
)
from .protocol import (
    ProtocolViolation,
    encode_frame,
    error_response,
    event_message,
    read_frame,
    success_response,
    validate_request,
)

LOGGER = logging.getLogger("omarchy-fabricd")
STABLE_ID = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$")
SCHEMA_VERSION = re.compile(r"^v[0-9]+(?:\.[0-9]+){0,2}$")
MAX_CONNECTION_REQUEST_IDS = 8192
MAX_CONNECTION_SUBSCRIPTIONS = 32


def _require_exact_fields(
    value: Mapping[str, Any],
    *,
    required: Sequence[str],
    optional: Sequence[str] = (),
    context: str = "request",
) -> None:
    missing = sorted(set(required) - set(value))
    extras = sorted(set(value) - set(required) - set(optional))
    if missing or extras:
        parts = []
        if missing:
            parts.append(f"missing: {', '.join(missing)}")
        if extras:
            parts.append(f"unknown: {', '.join(extras)}")
        raise FabricError(
            "rpc.invalid-params",
            "Fabric request parameters are invalid",
            f"The {context} parameters do not match the typed contract.",
            detail="; ".join(parts),
        )


def _stable_id(value: Any, label: str, *, maximum: int = 160) -> str:
    if (
        not isinstance(value, str)
        or not value
        or len(value) > maximum
        or STABLE_ID.fullmatch(value) is None
    ):
        raise FabricError(
            "rpc.invalid-params",
            "Fabric request parameters are invalid",
            f"{label} must be a stable lowercase identifier.",
        )
    return value


def _json_copy(value: Any) -> Any:
    try:
        return json.loads(
            json.dumps(
                value,
                ensure_ascii=False,
                allow_nan=False,
                separators=(",", ":"),
                sort_keys=True,
            )
        )
    except (TypeError, ValueError) as error:
        raise FabricError(
            "rpc.invalid-params",
            "Fabric request parameters are invalid",
            "The value must be finite JSON.",
            detail=str(error),
        ) from error


@dataclass
class FakeProvider:
    provider_id: str
    version: str
    actions: dict[str, dict[str, Any]]

    def __post_init__(self) -> None:
        self._counters: dict[str, int] = {}

    async def invoke(self, action: str, arguments: Mapping[str, Any]) -> Any:
        behavior = self.actions.get(action)
        if behavior is None:
            raise FabricError(
                "provider.action-unavailable",
                "Fabric provider action is unavailable",
                "The registered fake provider does not expose this action.",
                detail=f"{self.provider_id}.{action}",
            )
        kind = behavior["kind"]
        if kind == "echo":
            return {"arguments": _json_copy(arguments)}
        if kind == "constant":
            return _json_copy(behavior["value"])
        if kind == "counter":
            current = self._counters.get(action, 0) + 1
            self._counters[action] = current
            return {"count": current, "arguments": _json_copy(arguments)}
        if kind == "delay-echo":
            await asyncio.sleep(behavior["milliseconds"] / 1000)
            return {"arguments": _json_copy(arguments)}
        if kind == "error":
            raise FabricError(
                behavior["code"],
                behavior["title"],
                behavior["explanation"],
                retryable=behavior.get("retryable", False),
            )
        raise FabricError(
            "provider.invalid-definition",
            "Fabric provider definition is invalid",
            "The stored provider behavior is not supported by this daemon.",
            detail=str(kind),
        )


class FakeProviderRegistry:
    def __init__(self, database: FabricDatabase) -> None:
        self.database = database
        self.providers: dict[str, FakeProvider] = {}

    def load(self) -> None:
        for record in self.database.load_providers():
            provider = self._parse_definition(
                record["provider"],
                record["version"],
                record["definition"],
            )
            self.providers[provider.provider_id] = provider

    def register(
        self,
        provider_id: Any,
        version: Any,
        actions: Any,
    ) -> tuple[FakeProvider, str]:
        provider_id = _stable_id(provider_id, "provider")
        if not (provider_id.startswith("fake.") or provider_id.startswith("test.")):
            raise FabricError(
                "provider.provisional-only",
                "Only fake providers can be registered",
                "The provisional registry accepts only fake.* and test.* provider IDs.",
            )
        if not isinstance(version, str) or SCHEMA_VERSION.fullmatch(version) is None:
            raise FabricError(
                "rpc.invalid-params",
                "Fabric provider version is invalid",
                "Provider version must use the vN or vN.N form.",
            )
        definition = {"actions": _json_copy(actions)}
        provider = self._parse_definition(provider_id, version, definition)
        disposition = self.database.register_provider(provider_id, version, definition)
        if disposition == "registered":
            self.providers[provider_id] = provider
        else:
            provider = self.providers.get(provider_id, provider)
        return provider, disposition

    def _parse_definition(
        self,
        provider_id: Any,
        version: Any,
        definition: Any,
    ) -> FakeProvider:
        provider_id = _stable_id(provider_id, "provider")
        if not (provider_id.startswith("fake.") or provider_id.startswith("test.")):
            raise FabricError(
                "provider.invalid-definition",
                "Fabric provider definition is invalid",
                "The provisional database may contain only fake.* or test.* providers.",
                detail=provider_id,
            )
        if not isinstance(version, str) or SCHEMA_VERSION.fullmatch(version) is None:
            raise FabricError(
                "provider.invalid-definition",
                "Fabric provider definition is invalid",
                "The stored provider version is invalid.",
                detail=provider_id,
            )
        if not isinstance(definition, dict) or set(definition) != {"actions"}:
            raise FabricError(
                "provider.invalid-definition",
                "Fabric provider definition is invalid",
                "A fake provider definition must contain exactly one actions object.",
                detail=provider_id,
            )
        actions = definition["actions"]
        if not isinstance(actions, dict) or not actions or len(actions) > 64:
            raise FabricError(
                "provider.invalid-definition",
                "Fabric provider definition is invalid",
                "A fake provider must define between one and 64 actions.",
                detail=provider_id,
            )
        parsed: dict[str, dict[str, Any]] = {}
        for action_name, raw_behavior in actions.items():
            action_name = _stable_id(action_name, "action")
            if not isinstance(raw_behavior, dict):
                raise FabricError(
                    "provider.invalid-definition",
                    "Fabric provider definition is invalid",
                    "Every fake action must contain a behavior object.",
                    detail=f"{provider_id}.{action_name}",
                )
            behavior = _json_copy(raw_behavior)
            kind = behavior.get("kind")
            if kind in {"echo", "counter"}:
                expected = {"kind"}
            elif kind == "constant":
                expected = {"kind", "value"}
            elif kind == "delay-echo":
                expected = {"kind", "milliseconds"}
                milliseconds = behavior.get("milliseconds")
                if (
                    isinstance(milliseconds, bool)
                    or not isinstance(milliseconds, int)
                    or not 1 <= milliseconds <= 1000
                ):
                    raise FabricError(
                        "provider.invalid-definition",
                        "Fabric provider definition is invalid",
                        "delay-echo milliseconds must be an integer from 1 through 1000.",
                        detail=f"{provider_id}.{action_name}",
                    )
            elif kind == "error":
                expected = {"kind", "code", "title", "explanation", "retryable"}
                if set(behavior) - expected or not {"kind", "code", "title", "explanation"} <= set(behavior):
                    raise FabricError(
                        "provider.invalid-definition",
                        "Fabric provider definition is invalid",
                        "The fake error behavior has unknown or missing fields.",
                        detail=f"{provider_id}.{action_name}",
                    )
                _stable_id(behavior["code"], "error code")
                if not isinstance(behavior["title"], str) or not 1 <= len(behavior["title"]) <= 160:
                    raise FabricError(
                        "provider.invalid-definition",
                        "Fabric provider definition is invalid",
                        "The fake error title is invalid.",
                    )
                if not isinstance(behavior["explanation"], str) or not 1 <= len(behavior["explanation"]) <= 2000:
                    raise FabricError(
                        "provider.invalid-definition",
                        "Fabric provider definition is invalid",
                        "The fake error explanation is invalid.",
                    )
                if "retryable" in behavior and not isinstance(behavior["retryable"], bool):
                    raise FabricError(
                        "provider.invalid-definition",
                        "Fabric provider definition is invalid",
                        "The fake error retryable field must be boolean.",
                    )
                parsed[action_name] = behavior
                continue
            else:
                raise FabricError(
                    "provider.invalid-definition",
                    "Fabric provider definition is invalid",
                    "Fake providers may use only echo, constant, counter, delay-echo, or error.",
                    detail=f"{provider_id}.{action_name}",
                )
            if set(behavior) != expected:
                raise FabricError(
                    "provider.invalid-definition",
                    "Fabric provider definition is invalid",
                    "The fake behavior has unknown or missing fields.",
                    detail=f"{provider_id}.{action_name}",
                )
            parsed[action_name] = behavior
        return FakeProvider(provider_id=provider_id, version=version, actions=parsed)

    def get(self, provider_id: str) -> FakeProvider:
        provider = self.providers.get(provider_id)
        if provider is None:
            raise FabricError(
                "provider.unavailable",
                "Fabric provider is unavailable",
                "No provider is registered with this ID.",
                detail=provider_id,
                retryable=True,
                recovery_actions=("provider.reconnect",),
            )
        return provider

    def list(self) -> list[dict[str, Any]]:
        return [
            {
                "provider": provider.provider_id,
                "version": provider.version,
                "actions": sorted(provider.actions),
                "kind": "fake",
            }
            for provider in sorted(self.providers.values(), key=lambda item: item.provider_id)
        ]


@dataclass(frozen=True)
class DaemonConfig:
    socket_path: Path
    database_path: Path
    event_retention: int = DEFAULT_EVENT_RETENTION


class ClientConnection:
    def __init__(
        self,
        daemon: "FabricDaemon",
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        self.daemon = daemon
        self.reader = reader
        self.writer = writer
        self.connection_id = str(uuid.uuid4())
        self.hello_complete = False
        self.seen_request_ids: set[str] = set()
        self.write_lock = asyncio.Lock()
        self.subscriptions: dict[str, tuple[EventSubscription, asyncio.Task[None]]] = {}
        self.closed = False
        self.finished = asyncio.Event()
        self.run_task: asyncio.Task[None] | None = None

    async def run(self) -> None:
        self.run_task = asyncio.current_task()
        if not self._peer_is_owner():
            await self.close()
            self.finished.set()
            return
        try:
            while not self.closed:
                try:
                    message = await read_frame(self.reader)
                except ProtocolViolation as violation:
                    await self.send(error_response(violation.request_id, violation.error))
                    if violation.fatal:
                        break
                    continue
                if message is None:
                    break
                try:
                    request = validate_request(message)
                    if request.request_id in self.seen_request_ids:
                        raise FabricError(
                            "rpc.duplicate-id",
                            "Fabric request ID was reused",
                            "Request IDs must be unique for the lifetime of a connection.",
                        )
                    if len(self.seen_request_ids) >= MAX_CONNECTION_REQUEST_IDS:
                        raise FabricError(
                            "rpc.connection-request-limit",
                            "Fabric connection request limit reached",
                            "Reconnect before sending more requests on this connection.",
                            retryable=True,
                            recovery_actions=("fabric.reconnect",),
                        )
                    self.seen_request_ids.add(request.request_id)
                    result = await self.daemon.dispatch(self, request)
                    await self.send(success_response(request.request_id, result))
                except ProtocolViolation as violation:
                    await self.send(error_response(violation.request_id, violation.error))
                    if violation.fatal:
                        break
                except FabricError as error:
                    request_id = message.get("id")
                    await self.send(
                        error_response(request_id if isinstance(request_id, str) else None, error)
                    )
                except Exception as error:
                    LOGGER.exception("unhandled Fabric request failure")
                    request_id = message.get("id")
                    await self.send(
                        error_response(
                            request_id if isinstance(request_id, str) else None,
                            FabricError(
                                "daemon.internal-error",
                                "Fabric request failed internally",
                                "The daemon could not complete the request.",
                                detail=type(error).__name__,
                                retryable=True,
                                change_state="unknown",
                                recovery_actions=("fabric.restart",),
                            ),
                        )
                    )
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            await self.close()
            self.finished.set()

    def _peer_is_owner(self) -> bool:
        peer_socket = self.writer.get_extra_info("socket")
        if peer_socket is None or not hasattr(socket, "SO_PEERCRED"):
            return False
        try:
            credentials = peer_socket.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
            _pid, uid, _gid = struct.unpack("3i", credentials)
            return uid == os.getuid()
        except (AttributeError, OSError, struct.error):
            return False

    async def send(self, message: Mapping[str, Any]) -> None:
        if self.closed:
            return
        encoded = encode_frame(message)
        async with self.write_lock:
            self.writer.write(encoded)
            await self.writer.drain()

    def add_subscription(self, subscription: EventSubscription) -> None:
        task = asyncio.create_task(self._pump_subscription(subscription))
        self.subscriptions[subscription.subscription_id] = (subscription, task)

    def remove_subscription(self, subscription_id: str) -> bool:
        record = self.subscriptions.pop(subscription_id, None)
        if record is None:
            return False
        self.daemon.events.unsubscribe(subscription_id)
        record[1].cancel()
        return True

    async def _pump_subscription(self, subscription: EventSubscription) -> None:
        try:
            while not self.closed:
                event = await subscription.queue.get()
                await self.send(event_message(event))
                if event.get("topic") == "fabric.subscription-overflow":
                    break
        except (asyncio.CancelledError, BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            self.daemon.events.unsubscribe(subscription.subscription_id)
            self.subscriptions.pop(subscription.subscription_id, None)

    async def close(self) -> None:
        if self.closed:
            return
        self.closed = True
        for subscription_id, (_subscription, task) in list(self.subscriptions.items()):
            self.daemon.events.unsubscribe(subscription_id)
            task.cancel()
        self.subscriptions.clear()
        self.writer.close()
        try:
            await self.writer.wait_closed()
        except OSError:
            pass
        self.daemon.connections.discard(self)


class FabricDaemon:
    def __init__(self, config: DaemonConfig) -> None:
        self.config = config
        self.database = FabricDatabase(config.database_path)
        self.events = EventBroker(self.database, retention=config.event_retention)
        self.providers = FakeProviderRegistry(self.database)
        self.server: asyncio.AbstractServer | None = None
        self.connections: set[ClientConnection] = set()
        self.run_id = ""
        self.started_monotonic = 0.0
        self._socket_identity: tuple[int, int] | None = None
        self._stopped = False

    async def start(self) -> None:
        self._secure_directory(self.config.database_path.parent)
        self._secure_directory(self.config.socket_path.parent)
        self.database.open()
        try:
            self.providers.load()
            self._prepare_socket_path()
            old_umask = os.umask(0o077)
            try:
                self.server = await asyncio.start_unix_server(
                    self._accept,
                    path=str(self.config.socket_path),
                    limit=MAX_FRAME_BYTES + 1,
                )
            finally:
                os.umask(old_umask)
            os.chmod(self.config.socket_path, 0o600)
            socket_stat = self.config.socket_path.stat()
            self._socket_identity = (socket_stat.st_dev, socket_stat.st_ino)
            self.started_monotonic = time.monotonic()
            self.run_id = self.database.start_daemon_run(os.getpid())
        except Exception:
            if self.server is not None:
                self.server.close()
                await self.server.wait_closed()
                self.server = None
            self._remove_owned_socket()
            self.database.close()
            raise

    async def stop(self, reason: str = "requested") -> None:
        if self._stopped:
            return
        self._stopped = True
        server = self.server
        self.server = None
        if server is not None:
            server.close()
        active_connections = list(self.connections)
        if active_connections:
            await asyncio.gather(
                *(connection.close() for connection in active_connections),
                return_exceptions=True,
            )
            try:
                await asyncio.wait_for(
                    asyncio.gather(
                        *(connection.finished.wait() for connection in active_connections)
                    ),
                    timeout=3.0,
                )
            except asyncio.TimeoutError:
                tasks = [
                    connection.run_task
                    for connection in active_connections
                    if connection.run_task is not None and not connection.run_task.done()
                ]
                for task in tasks:
                    task.cancel()
                if tasks:
                    await asyncio.gather(*tasks, return_exceptions=True)
        if server is not None:
            await server.wait_closed()
        self.events.close()
        try:
            if self.run_id:
                self.database.finish_daemon_run(self.run_id, reason)
        finally:
            try:
                self.database.close()
            finally:
                self._remove_owned_socket()

    async def _accept(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        connection = ClientConnection(self, reader, writer)
        self.connections.add(connection)
        await connection.run()

    @staticmethod
    def _secure_directory(path: Path) -> None:
        if path.exists() and path.is_symlink():
            raise FabricError(
                "path.unsafe",
                "Fabric directory path is unsafe",
                "Fabric refuses to store state or sockets through a symbolic link.",
                detail=str(path),
            )
        old_umask = os.umask(0o077)
        try:
            path.mkdir(mode=0o700, parents=True, exist_ok=True)
        finally:
            os.umask(old_umask)
        metadata = path.stat()
        if metadata.st_uid != os.getuid():
            raise FabricError(
                "path.wrong-owner",
                "Fabric directory has the wrong owner",
                "Fabric directories must be owned by the current user.",
                detail=str(path),
            )
        os.chmod(path, 0o700)

    def _prepare_socket_path(self) -> None:
        path = self.config.socket_path
        try:
            metadata = path.lstat()
        except FileNotFoundError:
            return
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISSOCK(metadata.st_mode):
            raise FabricError(
                "socket.unsafe-path",
                "Fabric socket path is unsafe",
                "Fabric will not replace a symbolic link or non-socket path.",
                detail=str(path),
            )
        if metadata.st_uid != os.getuid():
            raise FabricError(
                "socket.wrong-owner",
                "Fabric socket has the wrong owner",
                "Fabric will not replace another user's socket.",
                detail=str(path),
            )
        probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            probe.settimeout(0.2)
            probe.connect(str(path))
        except (ConnectionRefusedError, FileNotFoundError):
            path.unlink()
            return
        except OSError as error:
            raise FabricError(
                "socket.probe-failed",
                "Fabric socket state is unknown",
                "Fabric could not safely determine whether the existing socket is live.",
                detail=str(error),
            ) from error
        finally:
            probe.close()
        raise FabricError(
            "daemon.already-running",
            "Fabric is already running",
            "Another Fabric daemon is accepting connections on this socket.",
        )

    def _remove_owned_socket(self) -> None:
        if self._socket_identity is None:
            return
        try:
            metadata = self.config.socket_path.lstat()
        except FileNotFoundError:
            self._socket_identity = None
            return
        identity = (metadata.st_dev, metadata.st_ino)
        if (
            identity == self._socket_identity
            and stat.S_ISSOCK(metadata.st_mode)
            and metadata.st_uid == os.getuid()
        ):
            self.config.socket_path.unlink()
        self._socket_identity = None

    async def dispatch(
        self,
        connection: ClientConnection,
        request: RpcRequest,
    ) -> Mapping[str, Any] | list[Any]:
        if not connection.hello_complete and request.method != "hello":
            raise FabricError(
                "rpc.hello-required",
                "Fabric handshake is required",
                "The first request on every connection must be hello.",
            )
        if request.method == "hello":
            return self._hello(connection, request.params)
        if request.method == "version":
            _require_exact_fields(request.params, required=())
            return self._version()
        if request.method == "health":
            _require_exact_fields(request.params, required=())
            return daemon_health(
                database=self.database,
                socket_path=self.config.socket_path,
                started_monotonic=self.started_monotonic,
                run_id=self.run_id,
                provider_count=len(self.providers.providers),
                subscription_count=self.events.subscription_count,
            )
        if request.method == "provider.register":
            return self._register_provider(request.params)
        if request.method == "provider.list":
            _require_exact_fields(request.params, required=())
            return {"providers": self.providers.list()}
        if request.method == "provider.invoke":
            return await self._invoke_provider(request, request.params)
        if request.method == "events.subscribe":
            return self._subscribe(connection, request.request_id, request.params)
        if request.method == "events.unsubscribe":
            return self._unsubscribe(connection, request.params)
        raise FabricError(
            "rpc.method-not-found",
            "Fabric method is unavailable",
            "The requested method is not part of the provisional RPC contract.",
            detail=request.method,
        )

    def _hello(
        self,
        connection: ClientConnection,
        params: Mapping[str, Any],
    ) -> Mapping[str, Any]:
        if connection.hello_complete:
            raise FabricError(
                "rpc.hello-already-complete",
                "Fabric handshake is already complete",
                "Reconnect to negotiate a new Fabric session.",
            )
        _require_exact_fields(
            params,
            required=("client", "minVersion", "maxVersion"),
            context="hello",
        )
        client = params["client"]
        minimum = params["minVersion"]
        maximum = params["maxVersion"]
        if not isinstance(client, str) or not 1 <= len(client) <= 160:
            raise FabricError(
                "rpc.invalid-params",
                "Fabric client identity is invalid",
                "The hello client label must contain between one and 160 characters.",
            )
        if (
            isinstance(minimum, bool)
            or isinstance(maximum, bool)
            or not isinstance(minimum, int)
            or not isinstance(maximum, int)
            or minimum > maximum
        ):
            raise FabricError(
                "rpc.invalid-params",
                "Fabric version range is invalid",
                "The hello version range must contain ordered integer bounds.",
            )
        if maximum < MIN_PROTOCOL_VERSION or minimum > MAX_PROTOCOL_VERSION:
            raise FabricError(
                "rpc.incompatible-version",
                "Fabric client and daemon versions are incompatible",
                f"The daemon supports versions {MIN_PROTOCOL_VERSION} through {MAX_PROTOCOL_VERSION}.",
                recovery_actions=("system.update",),
            )
        connection.hello_complete = True
        return {
            "connectionId": connection.connection_id,
            "client": client,
            "protocol": PROTOCOL_NAME,
            "version": PROTOCOL_VERSION,
            "databaseSchema": CURRENT_DATABASE_SCHEMA,
        }

    @staticmethod
    def _version() -> Mapping[str, Any]:
        return {
            "protocol": PROTOCOL_NAME,
            "version": PROTOCOL_VERSION,
            "minimum": MIN_PROTOCOL_VERSION,
            "maximum": MAX_PROTOCOL_VERSION,
            "databaseSchema": CURRENT_DATABASE_SCHEMA,
        }

    def _register_provider(self, params: Mapping[str, Any]) -> Mapping[str, Any]:
        _require_exact_fields(params, required=("provider", "version", "actions"))
        provider, disposition = self.providers.register(
            params["provider"],
            params["version"],
            params["actions"],
        )
        return {
            "provider": provider.provider_id,
            "version": provider.version,
            "actions": sorted(provider.actions),
            "disposition": disposition,
        }

    async def _invoke_provider(
        self,
        request: RpcRequest,
        params: Mapping[str, Any],
    ) -> Mapping[str, Any]:
        _require_exact_fields(
            params,
            required=("provider", "action", "arguments", "idempotencyKey"),
        )
        provider_id = _stable_id(params["provider"], "provider")
        action = _stable_id(params["action"], "action")
        arguments = params["arguments"]
        if not isinstance(arguments, dict):
            raise FabricError(
                "rpc.invalid-params",
                "Fabric invocation arguments are invalid",
                "Provider invocation arguments must be a JSON object.",
            )
        arguments = _json_copy(arguments)
        idempotency_key = params["idempotencyKey"]
        if not isinstance(idempotency_key, str) or not 1 <= len(idempotency_key) <= 256:
            raise FabricError(
                "rpc.invalid-params",
                "Fabric idempotency key is invalid",
                "Provider invocation requires an idempotency key of 1 through 256 characters.",
            )
        provider = self.providers.get(provider_id)
        fingerprint = request_fingerprint(
            {
                "provider": provider_id,
                "providerVersion": provider.version,
                "action": action,
                "arguments": arguments,
            }
        )
        disposition, stored = self.database.claim_idempotency(
            provider_id=provider_id,
            action=action,
            idempotency_key=idempotency_key,
            fingerprint=fingerprint,
            request_id=request.request_id,
        )
        if disposition == "conflict":
            raise FabricError(
                "operation.idempotency-conflict",
                "Fabric idempotency key conflicts",
                "This idempotency key was already bound to different normalized arguments.",
                change_state="unknown",
                recovery_actions=("operation.inspect",),
            )
        if disposition == "pending":
            raise FabricError(
                "operation.in-progress",
                "Fabric operation is already running",
                "An invocation with this idempotency key is still in progress.",
                retryable=True,
                change_state="unknown",
                recovery_actions=("operation.inspect",),
            )
        if disposition == "interrupted":
            raise FabricError(
                "operation.interrupted",
                "Fabric operation was interrupted",
                "The daemon restarted before this idempotent invocation reached a durable result.",
                change_state="unknown",
                recovery_actions=("operation.reconcile",),
            )
        if disposition == "complete" and stored is not None:
            return self._invocation_response(
                provider,
                action,
                idempotency_key,
                stored["value"],
                replayed=True,
            )
        if disposition == "failed" and stored is not None:
            raw_error = stored["error"]
            raise FabricError(
                raw_error["code"],
                raw_error["title"],
                raw_error["explanation"],
                detail=raw_error.get("detail", ""),
                retryable=raw_error.get("retryable", False),
                change_state=raw_error.get("changeState", "unknown"),
                recovery_actions=tuple(raw_error.get("recoveryActions", ())),
            )
        try:
            value = await provider.invoke(action, arguments)
            value = _json_copy(value)
        except FabricError as error:
            event = self.database.finish_idempotency(
                provider_id=provider_id,
                action=action,
                idempotency_key=idempotency_key,
                succeeded=False,
                response={"error": error.to_dict()},
                event_topic="provider.invocation-finished",
                event_payload={
                    "provider": provider_id,
                    "providerVersion": provider.version,
                    "action": action,
                    "idempotencyKey": idempotency_key,
                    "status": "failed",
                    "errorCode": error.code,
                    "changeState": error.change_state,
                },
                event_retention=self.events.retention,
            )
            assert event is not None
            self.events.deliver(event)
            raise
        except Exception as error:
            wrapped = FabricError(
                "provider.failed",
                "Fabric provider invocation failed",
                "The provider failed without a structured error.",
                detail=type(error).__name__,
                change_state="unknown",
            )
            event = self.database.finish_idempotency(
                provider_id=provider_id,
                action=action,
                idempotency_key=idempotency_key,
                succeeded=False,
                response={"error": wrapped.to_dict()},
                event_topic="provider.invocation-finished",
                event_payload={
                    "provider": provider_id,
                    "providerVersion": provider.version,
                    "action": action,
                    "idempotencyKey": idempotency_key,
                    "status": "failed",
                    "errorCode": wrapped.code,
                    "changeState": wrapped.change_state,
                },
                event_retention=self.events.retention,
            )
            assert event is not None
            self.events.deliver(event)
            raise wrapped from error
        event = self.database.finish_idempotency(
            provider_id=provider_id,
            action=action,
            idempotency_key=idempotency_key,
            succeeded=True,
            response={"value": value},
            event_topic="provider.invocation-finished",
            event_payload={
                "provider": provider_id,
                "providerVersion": provider.version,
                "action": action,
                "idempotencyKey": idempotency_key,
                "status": "succeeded",
                "changeState": "none",
            },
            event_retention=self.events.retention,
        )
        assert event is not None
        self.events.deliver(event)
        return self._invocation_response(
            provider,
            action,
            idempotency_key,
            value,
            replayed=False,
        )

    @staticmethod
    def _invocation_response(
        provider: FakeProvider,
        action: str,
        idempotency_key: str,
        value: Any,
        *,
        replayed: bool,
    ) -> Mapping[str, Any]:
        return {
            "provider": provider.provider_id,
            "providerVersion": provider.version,
            "action": action,
            "value": value,
            "idempotency": {"key": idempotency_key, "replayed": replayed},
        }

    def _subscribe(
        self,
        connection: ClientConnection,
        request_id: str,
        params: Mapping[str, Any],
    ) -> Mapping[str, Any]:
        if len(connection.subscriptions) >= MAX_CONNECTION_SUBSCRIPTIONS:
            raise FabricError(
                "events.subscription-limit",
                "Fabric connection subscription limit reached",
                f"A connection may own at most {MAX_CONNECTION_SUBSCRIPTIONS} live subscriptions.",
                retryable=True,
                recovery_actions=("events.unsubscribe",),
            )
        _require_exact_fields(params, required=("topics",), optional=("after", "limit"))
        topics = params["topics"]
        if (
            not isinstance(topics, list)
            or not 1 <= len(topics) <= 32
            or any(not isinstance(topic, str) for topic in topics)
        ):
            raise FabricError(
                "rpc.invalid-params",
                "Fabric event topics are invalid",
                "A subscription must contain between one and 32 topic strings.",
            )
        normalized_topics: list[str] = []
        for topic in topics:
            if topic == "*":
                normalized_topics.append(topic)
            else:
                normalized_topics.append(_stable_id(topic, "event topic"))
        if len(set(normalized_topics)) != len(normalized_topics):
            raise FabricError(
                "rpc.invalid-params",
                "Fabric event topics are invalid",
                "A subscription cannot contain duplicate topics.",
            )
        limit = params.get("limit", MAX_EVENT_REPLAY)
        if isinstance(limit, bool) or not isinstance(limit, int) or not 1 <= limit <= MAX_EVENT_REPLAY:
            raise FabricError(
                "rpc.invalid-params",
                "Fabric event replay limit is invalid",
                f"Replay limit must be an integer from 1 through {MAX_EVENT_REPLAY}.",
            )
        after = params.get("after")
        if after is not None and (
            isinstance(after, bool) or not isinstance(after, int) or after < 0
        ):
            raise FabricError(
                "rpc.invalid-params",
                "Fabric event cursor is invalid",
                "The after cursor must be a non-negative integer or null.",
            )
        subscription = self.events.subscribe(normalized_topics)
        through = self.database.latest_event_sequence()
        effective_after = through if after is None else after
        try:
            if effective_after > through:
                raise FabricError(
                    "events.cursor-ahead",
                    "Fabric event cursor is ahead of the daemon",
                    "The requested cursor is newer than the latest durable Fabric event.",
                    detail=f"latest sequence {through}",
                    retryable=True,
                    recovery_actions=("events.refresh-state",),
                )
            replay = self.database.replay_events(
                after=effective_after,
                through=through,
                topics=normalized_topics,
                limit=limit,
            )
        except Exception:
            self.events.unsubscribe(subscription.subscription_id)
            raise
        result = {
            "subscriptionId": subscription.subscription_id,
            "topics": normalized_topics,
            "cursor": through,
            "replay": replay,
        }
        try:
            encode_frame(success_response(request_id, result))
        except FabricError:
            self.events.unsubscribe(subscription.subscription_id)
            raise
        connection.add_subscription(subscription)
        return result

    def _unsubscribe(
        self,
        connection: ClientConnection,
        params: Mapping[str, Any],
    ) -> Mapping[str, Any]:
        _require_exact_fields(params, required=("subscriptionId",))
        subscription_id = params["subscriptionId"]
        try:
            uuid.UUID(subscription_id)
        except (ValueError, TypeError, AttributeError) as error:
            raise FabricError(
                "rpc.invalid-params",
                "Fabric subscription ID is invalid",
                "Subscription ID must be a UUID returned by events.subscribe.",
            ) from error
        return {
            "subscriptionId": subscription_id,
            "removed": connection.remove_subscription(subscription_id),
        }


async def run_daemon(config: DaemonConfig) -> None:
    daemon = FabricDaemon(config)
    stop_event = asyncio.Event()
    stop_reason = "requested"

    def request_stop(reason: str) -> None:
        nonlocal stop_reason
        stop_reason = reason
        stop_event.set()

    loop = asyncio.get_running_loop()
    for signum in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(signum, request_stop, signal.Signals(signum).name.lower())
        except NotImplementedError:
            pass

    await daemon.start()
    LOGGER.info("Fabric listening on %s", config.socket_path)
    try:
        await stop_event.wait()
    finally:
        await daemon.stop(stop_reason)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the provisional Omarchy Fabric user daemon")
    parser.add_argument("--socket", type=Path, help="override the owner-only Unix socket path")
    parser.add_argument("--database", type=Path, help="override the SQLite state database path")
    parser.add_argument(
        "--event-retention",
        type=int,
        default=DEFAULT_EVENT_RETENTION,
        help="number of durable events to retain",
    )
    parser.add_argument(
        "--log-level",
        choices=("DEBUG", "INFO", "WARNING", "ERROR"),
        default="WARNING",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(levelname)s %(name)s: %(message)s",
    )
    if args.event_retention < 1:
        _parser().error("--event-retention must be positive")
    try:
        socket_path = args.socket or default_socket_path()
        database_path = args.database or (default_state_directory() / "fabric.db")
        asyncio.run(
            run_daemon(
                DaemonConfig(
                    socket_path=socket_path,
                    database_path=database_path,
                    event_retention=args.event_retention,
                )
            )
        )
        return 0
    except KeyboardInterrupt:
        return 130
    except FabricError as error:
        print(json.dumps({"error": error.to_dict()}, sort_keys=True), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
