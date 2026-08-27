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
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping, Sequence

try:
    import fcntl
except ImportError:  # pragma: no cover - exercised by import-only non-Linux tooling
    fcntl = None  # type: ignore[assignment]

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
from .managed_work import (
    Actor,
    DaemonProjectionBridge,
    ManagedWorkError,
    ManagedWorkPlane,
    StableOwnerSessionStore,
)
from .provider_builtins import build_builtin_providers
from .provider_registry import ProviderRegistry, TypedProvider
from .reference_operation import ReferenceOperationManager
from .security import EndpointAdmission, EndpointPrincipal, PrincipalKind
from .security.errors import SecurityValidationError

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
    typed_providers: tuple[TypedProvider, ...] = field(default_factory=build_builtin_providers)
    managed_work_database_path: Path | None = None

    @property
    def managed_work_path(self) -> Path:
        return self.managed_work_database_path or self.database_path.with_name("managed-work.db")


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
        self.principal: EndpointPrincipal | None = None
        self.peer_uid: int | None = None

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
        self.peer_uid = None
        peer_socket = self.writer.get_extra_info("socket")
        if peer_socket is None or not hasattr(socket, "SO_PEERCRED"):
            return False
        try:
            credential_size = struct.calcsize("iII")
            credentials = peer_socket.getsockopt(
                socket.SOL_SOCKET,
                socket.SO_PEERCRED,
                credential_size,
            )
            _pid, uid, _gid = struct.unpack("iII", credentials)
            if uid != self.daemon.daemon_uid:
                return False
            self.peer_uid = uid
            return True
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
        if self.principal is not None:
            try:
                self.daemon.managed_work.release_session_contexts(
                    Actor(self.principal.principal_id, self.principal.session_id)
                )
            except ManagedWorkError as error:
                LOGGER.error("managed-work session cleanup refused: %s", error.code)
            self.daemon.session_bindings.release(self.principal.session_id)
            self.principal = None
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
        self.daemon_uid = os.getuid() if hasattr(os, "getuid") else 0
        self.database = FabricDatabase(config.database_path)
        self.events = EventBroker(self.database, retention=config.event_retention)
        self.providers = FakeProviderRegistry(self.database)
        self.typed_providers = ProviderRegistry(event_sink=self.events.publish)
        self.session_bindings = StableOwnerSessionStore(self.daemon_uid)
        self.reference_operations = ReferenceOperationManager(
            self.database,
            self.events,
            session_is_active=self.session_bindings.is_active,
        )
        self.managed_work = ManagedWorkPlane(config.managed_work_path)
        self.managed_projections = DaemonProjectionBridge(
            self.managed_work,
            self.reference_operations,
        )
        self.server: asyncio.AbstractServer | None = None
        self.connections: set[ClientConnection] = set()
        self.run_id = ""
        self.started_monotonic = 0.0
        self._socket_identity: tuple[int, int] | None = None
        self._instance_lock_fds: list[int] = []
        self._database_lease_fds: list[tuple[Path, int, tuple[int, int]]] = []
        self._stopped = False

    async def start(self) -> None:
        self._secure_directory(self.config.database_path.parent)
        self._secure_directory(self.config.managed_work_path.parent)
        self._secure_directory(self.config.socket_path.parent)
        bound_socket: socket.socket | None = None
        try:
            self._prepare_socket_path()
            old_umask = os.umask(0o077)
            try:
                bound_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                bound_socket.setblocking(False)
                bound_socket.bind(str(self.config.socket_path))
                socket_stat = self.config.socket_path.lstat()
                if (
                    not stat.S_ISSOCK(socket_stat.st_mode)
                    or socket_stat.st_uid != self.daemon_uid
                ):
                    raise FabricError(
                        "socket.unsafe-path",
                        "Fabric socket ownership could not be verified",
                        "Fabric refuses to retain an unverified bound endpoint.",
                    )
                self._socket_identity = (socket_stat.st_dev, socket_stat.st_ino)
                bound_socket.listen(socket.SOMAXCONN)
                os.chmod(self.config.socket_path, 0o600)
                socket_stat = self.config.socket_path.lstat()
                descriptor_stat = os.fstat(bound_socket.fileno())
                if (
                    not stat.S_ISSOCK(socket_stat.st_mode)
                    or socket_stat.st_uid != self.daemon_uid
                    or not stat.S_ISSOCK(descriptor_stat.st_mode)
                    or descriptor_stat.st_uid != self.daemon_uid
                ):
                    raise FabricError(
                        "socket.unsafe-path",
                        "Fabric socket ownership could not be verified",
                        "Fabric refuses to publish an unverified local endpoint.",
                    )
                if (socket_stat.st_dev, socket_stat.st_ino) != self._socket_identity:
                    raise FabricError(
                        "socket.unsafe-path",
                        "Fabric socket changed during endpoint setup",
                        "Fabric refuses to publish an endpoint whose identity changed.",
                    )
            finally:
                os.umask(old_umask)

            self._acquire_instance_locks()
            self.database.open(
                database_lease_descriptor=self._database_lease_descriptor(
                    self.config.database_path
                )
            )
            self._verify_sqlite_database_inode(
                database_path=self.config.database_path,
                connection=self.database.connection,
                lease_descriptor=self._database_lease_descriptor(self.config.database_path),
            )
            try:
                self.managed_work.open(
                    database_lease_descriptor=self._database_lease_descriptor(
                        self.config.managed_work_path
                    )
                )
            except ManagedWorkError as error:
                raise FabricError(
                    error.code,
                    "Managed-work database was refused",
                    error.explanation,
                    detail=error.detail,
                    retryable=error.retryable,
                    change_state="none",
                    recovery_actions=error.recovery_actions,
                ) from error
            self._verify_database_leases()
            self.reference_operations.recover_startup()
            self.providers.load()
            for provider in self.config.typed_providers:
                self.typed_providers.register(provider)
            self.started_monotonic = time.monotonic()
            self.run_id = self.database.start_daemon_run(os.getpid())
            self.server = await asyncio.start_unix_server(
                self._accept,
                sock=bound_socket,
                limit=MAX_FRAME_BYTES + 1,
                start_serving=False,
            )
            bound_socket = None
            self._verify_owned_socket_identity()
            await self.server.start_serving()
        except Exception:
            if bound_socket is not None:
                try:
                    bound_socket.close()
                except Exception as error:  # pragma: no cover - exceptional OS cleanup
                    LOGGER.error("startup socket cleanup failed: %s", type(error).__name__)
            if self.server is not None:
                try:
                    self.server.close()
                    await self.server.wait_closed()
                except Exception as error:  # pragma: no cover - exceptional OS cleanup
                    LOGGER.error("startup server cleanup failed: %s", type(error).__name__)
                self.server = None
            try:
                self._remove_owned_socket()
            except Exception as error:  # pragma: no cover - exceptional OS cleanup
                LOGGER.error("startup socket-path cleanup failed: %s", type(error).__name__)
            try:
                self.managed_work.close()
            except Exception as error:  # pragma: no cover - exceptional SQLite cleanup
                LOGGER.error("startup managed-work cleanup failed: %s", type(error).__name__)
            try:
                self.database.close()
            except Exception as error:  # pragma: no cover - exceptional SQLite cleanup
                LOGGER.error("startup Fabric database cleanup failed: %s", type(error).__name__)
            try:
                self._release_instance_locks()
            except Exception as error:  # pragma: no cover - exceptional OS cleanup
                LOGGER.error("startup database lease cleanup failed: %s", type(error).__name__)
            raise

    async def stop(self, reason: str = "requested") -> None:
        if self._stopped:
            return
        self._stopped = True
        first_error: BaseException | None = None

        def remember(error: BaseException) -> None:
            nonlocal first_error
            if first_error is None:
                first_error = error

        server = self.server
        self.server = None
        if server is not None:
            try:
                server.close()
            except Exception as error:  # pragma: no cover - exceptional OS cleanup
                remember(error)
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
            try:
                await server.wait_closed()
            except Exception as error:  # pragma: no cover - exceptional OS cleanup
                remember(error)
        try:
            await self.reference_operations.shutdown()
        except Exception as error:
            remember(error)
        try:
            self.events.close()
        except Exception as error:
            remember(error)
        if self.run_id:
            try:
                self.database.finish_daemon_run(self.run_id, reason)
            except Exception as error:
                remember(error)
        for cleanup in (
            self.managed_work.close,
            self.database.close,
            self._remove_owned_socket,
            self._release_instance_locks,
        ):
            try:
                cleanup()
            except Exception as error:  # pragma: no cover - exceptional cleanup path
                remember(error)
        if first_error is not None:
            raise first_error

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
            try:
                current = path.lstat()
            except FileNotFoundError:
                return
            if (
                not stat.S_ISSOCK(current.st_mode)
                or current.st_uid != self.daemon_uid
                or (current.st_dev, current.st_ino) != (metadata.st_dev, metadata.st_ino)
            ):
                raise FabricError(
                    "socket.unsafe-path",
                    "Fabric socket changed during stale-endpoint recovery",
                    "Fabric will not unlink an endpoint whose identity changed while it was probed.",
                    detail=str(path),
                )
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

    @staticmethod
    def _instance_lock_path(database_path: Path) -> Path:
        return database_path.with_name(f"{database_path.name}.daemon.lock")

    @staticmethod
    def _absolute_database_path(database_path: Path) -> Path:
        return Path(os.path.abspath(os.fspath(database_path)))

    def _acquire_one_instance_lock(self, path: Path) -> int:
        if fcntl is None:
            raise FabricError(
                "daemon.lock-unavailable",
                "Fabric daemon ownership locking is unavailable",
                "The production daemon requires Linux flock support before opening durable state.",
                change_state="none",
            )
        flags = os.O_RDWR | os.O_CREAT
        if hasattr(os, "O_CLOEXEC"):
            flags |= os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        try:
            descriptor = os.open(path, flags, 0o600)
        except OSError as error:
            raise FabricError(
                "daemon.lock-unsafe",
                "Fabric daemon ownership lock is unsafe",
                "Fabric could not safely open its owner-only instance lock.",
                detail=type(error).__name__,
            ) from error
        try:
            metadata = os.fstat(descriptor)
            path_metadata = path.lstat()
            if (
                not stat.S_ISREG(metadata.st_mode)
                or metadata.st_uid != self.daemon_uid
                or metadata.st_nlink != 1
                or (metadata.st_dev, metadata.st_ino)
                != (path_metadata.st_dev, path_metadata.st_ino)
            ):
                raise FabricError(
                    "daemon.lock-unsafe",
                    "Fabric daemon ownership lock is unsafe",
                    "The instance lock must be a stable regular file owned by the daemon account.",
                )
            os.fchmod(descriptor, 0o600)
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise FabricError(
                    "daemon.already-running",
                    "Fabric is already running",
                    "Another Fabric daemon owns this account's durable state lease.",
                ) from error
            path_metadata = path.lstat()
            if (metadata.st_dev, metadata.st_ino) != (
                path_metadata.st_dev,
                path_metadata.st_ino,
            ):
                raise FabricError(
                    "daemon.lock-unsafe",
                    "Fabric daemon ownership lock changed",
                    "Fabric refused an instance lock path that changed during acquisition.",
                )
            return descriptor
        except Exception:
            os.close(descriptor)
            raise

    def _acquire_database_lease(self, path: Path) -> tuple[int, tuple[int, int]]:
        if fcntl is None:
            raise FabricError(
                "daemon.lock-unavailable",
                "Fabric daemon ownership locking is unavailable",
                "The production daemon requires Linux flock support before opening durable state.",
                change_state="none",
            )
        flags = os.O_RDWR | os.O_CREAT
        if hasattr(os, "O_CLOEXEC"):
            flags |= os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        try:
            descriptor = os.open(path, flags, 0o600)
        except OSError as error:
            raise FabricError(
                "daemon.database-unsafe",
                "Fabric durable state could not be leased",
                "Fabric could not safely open an owner-only durable database inode.",
                detail=type(error).__name__,
            ) from error
        try:
            metadata = os.fstat(descriptor)
            path_metadata = path.lstat()
            identity = (metadata.st_dev, metadata.st_ino)
            if (
                not stat.S_ISREG(metadata.st_mode)
                or metadata.st_uid != self.daemon_uid
                or metadata.st_nlink != 1
                or not stat.S_ISREG(path_metadata.st_mode)
                or identity != (path_metadata.st_dev, path_metadata.st_ino)
            ):
                raise FabricError(
                    "daemon.database-unsafe",
                    "Fabric durable state is unsafe",
                    "Each durable database must be one stable regular inode owned only by the daemon account.",
                )
            os.fchmod(descriptor, 0o600)
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise FabricError(
                    "daemon.already-running",
                    "Fabric is already running",
                    "Another Fabric daemon owns one of this account's durable database inodes.",
                ) from error
            path_metadata = path.lstat()
            if (
                not stat.S_ISREG(path_metadata.st_mode)
                or (path_metadata.st_dev, path_metadata.st_ino) != identity
            ):
                raise FabricError(
                    "daemon.database-unsafe",
                    "Fabric durable state changed during lease acquisition",
                    "Fabric refused a durable database path that changed before startup.",
                )
            return descriptor, identity
        except Exception:
            os.close(descriptor)
            raise

    def _acquire_instance_locks(self) -> None:
        paths = sorted(
            (
                self._absolute_database_path(self.config.database_path),
                self._absolute_database_path(self.config.managed_work_path),
            ),
            key=lambda value: os.fspath(value),
        )
        if paths[0] == paths[1]:
            raise FabricError(
                "daemon.database-alias",
                "Fabric databases must be distinct",
                "The Fabric and managed-work schemas cannot share one database path.",
            )
        acquired_locks: list[int] = []
        acquired_leases: list[tuple[Path, int, tuple[int, int]]] = []
        seen_inodes: set[tuple[int, int]] = set()
        try:
            for path in paths:
                acquired_locks.append(self._acquire_one_instance_lock(self._instance_lock_path(path)))
            for path in paths:
                descriptor, identity = self._acquire_database_lease(path)
                if identity in seen_inodes:
                    os.close(descriptor)
                    raise FabricError(
                        "daemon.database-alias",
                        "Fabric databases resolve to the same inode",
                        "The Fabric and managed-work schemas require distinct durable database inodes.",
                    )
                seen_inodes.add(identity)
                acquired_leases.append((path, descriptor, identity))
        except Exception:
            for _path, descriptor, _identity in reversed(acquired_leases):
                try:
                    if fcntl is not None:
                        fcntl.flock(descriptor, fcntl.LOCK_UN)
                except OSError:
                    pass
                try:
                    os.close(descriptor)
                except OSError:
                    pass
            for descriptor in reversed(acquired_locks):
                try:
                    if fcntl is not None:
                        fcntl.flock(descriptor, fcntl.LOCK_UN)
                except OSError:
                    pass
                try:
                    os.close(descriptor)
                except OSError:
                    pass
            raise
        self._instance_lock_fds = acquired_locks
        self._database_lease_fds = acquired_leases

    def _verify_database_leases(self) -> None:
        for path, descriptor, identity in self._database_lease_fds:
            try:
                metadata = os.fstat(descriptor)
                path_metadata = path.lstat()
            except OSError as error:
                raise FabricError(
                    "daemon.database-unsafe",
                    "Fabric durable state identity could not be verified",
                    "Fabric refuses to publish after a durable database path changes.",
                    detail=type(error).__name__,
                ) from error
            if (
                not stat.S_ISREG(metadata.st_mode)
                or metadata.st_uid != self.daemon_uid
                or metadata.st_nlink != 1
                or not stat.S_ISREG(path_metadata.st_mode)
                or (metadata.st_dev, metadata.st_ino) != identity
                or (path_metadata.st_dev, path_metadata.st_ino) != identity
            ):
                raise FabricError(
                    "daemon.database-unsafe",
                    "Fabric durable state identity changed",
                    "Fabric refuses to publish after a durable database inode changes.",
                )

    def _database_lease_descriptor(self, database_path: Path) -> int:
        expected = self._absolute_database_path(database_path)
        for path, descriptor, _identity in self._database_lease_fds:
            if path == expected:
                return descriptor
        raise FabricError(
            "daemon.database-unsafe",
            "Fabric durable state lease is missing",
            "Fabric refuses to open durable state without its lifetime inode lease.",
        )

    def _verify_sqlite_database_inode(
        self,
        *,
        database_path: Path,
        connection: Any,
        lease_descriptor: int,
    ) -> None:
        if connection is None:
            raise FabricError(
                "daemon.database-unsafe",
                "Fabric durable state connection is missing",
                "Fabric refuses to publish without an opened durable database.",
            )
        lease_metadata = os.fstat(lease_descriptor)
        identity = (lease_metadata.st_dev, lease_metadata.st_ino)
        expected_path = self._absolute_database_path(database_path).resolve(strict=True)
        rows = connection.execute("PRAGMA database_list").fetchall()
        main_rows = [row for row in rows if str(row[1]) == "main"]
        if len(main_rows) != 1:
            raise FabricError(
                "daemon.database-unsafe",
                "Fabric durable state connection is ambiguous",
                "Fabric could not verify the opened main SQLite database.",
            )
        try:
            opened_path = Path(str(main_rows[0][2])).resolve(strict=True)
        except (OSError, RuntimeError) as error:
            raise FabricError(
                "daemon.database-unsafe",
                "Fabric durable state path could not be resolved",
                "Fabric could not verify the opened main SQLite database path.",
                detail=type(error).__name__,
            ) from error
        if opened_path != expected_path:
            raise FabricError(
                "daemon.database-unsafe",
                "Fabric opened an unexpected durable state path",
                "Fabric refuses a SQLite connection whose path differs from its lifetime lease.",
            )
        descriptor_directory = Path("/proc/self/fd")
        if not descriptor_directory.is_dir():
            raise FabricError(
                "daemon.database-unsafe",
                "Fabric cannot prove its opened durable state inode",
                "The production daemon requires Linux descriptor identity evidence.",
            )
        try:
            descriptors = [
                int(entry.name)
                for entry in descriptor_directory.iterdir()
                if entry.name.isdigit()
            ]
        except OSError as error:
            raise FabricError(
                "daemon.database-unsafe",
                "Fabric could not enumerate its opened durable state descriptors",
                "The production daemon requires Linux descriptor identity evidence.",
                detail=type(error).__name__,
            ) from error
        matches = []
        for descriptor in descriptors:
            if descriptor == lease_descriptor:
                continue
            try:
                metadata = os.fstat(descriptor)
            except OSError:
                continue
            if stat.S_ISREG(metadata.st_mode) and (metadata.st_dev, metadata.st_ino) == identity:
                matches.append(descriptor)
        if len(matches) != 1:
            raise FabricError(
                "daemon.database-unsafe",
                "Fabric could not prove its opened durable state inode",
                "The SQLite connection must hold exactly one descriptor for the leased database inode.",
                detail=f"matching descriptors: {len(matches)}",
            )

    def _verify_owned_socket_identity(self) -> None:
        if self._socket_identity is None:
            raise FabricError(
                "socket.unsafe-path",
                "Fabric socket ownership evidence is missing",
                "Fabric refuses to publish an endpoint without its bound inode identity.",
            )
        try:
            metadata = self.config.socket_path.lstat()
        except OSError as error:
            raise FabricError(
                "socket.unsafe-path",
                "Fabric socket disappeared before publication",
                "Fabric refuses to publish an endpoint whose path cannot be verified.",
                detail=type(error).__name__,
            ) from error
        if (
            not stat.S_ISSOCK(metadata.st_mode)
            or metadata.st_uid != self.daemon_uid
            or (metadata.st_dev, metadata.st_ino) != self._socket_identity
        ):
            raise FabricError(
                "socket.unsafe-path",
                "Fabric socket changed before publication",
                "Fabric refuses to publish an endpoint whose bound inode identity changed.",
            )

    def _release_instance_locks(self) -> None:
        leases = self._database_lease_fds
        self._database_lease_fds = []
        descriptors = self._instance_lock_fds
        self._instance_lock_fds = []
        first_error: OSError | None = None
        for _path, descriptor, _identity in reversed(leases):
            try:
                if fcntl is not None:
                    fcntl.flock(descriptor, fcntl.LOCK_UN)
            except OSError as error:
                first_error = first_error or error
            try:
                os.close(descriptor)
            except OSError as error:
                first_error = first_error or error
        for descriptor in reversed(descriptors):
            try:
                if fcntl is not None:
                    fcntl.flock(descriptor, fcntl.LOCK_UN)
            except OSError as error:
                first_error = first_error or error
            try:
                os.close(descriptor)
            except OSError as error:
                first_error = first_error or error
        if first_error is not None:
            raise first_error

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
        principal = self._principal(connection)
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
                provider_count=len(self.providers.providers) + self.typed_providers.provider_count,
                fake_provider_count=len(self.providers.providers),
                typed_provider_count=self.typed_providers.provider_count,
                available_typed_provider_count=self.typed_providers.available_count,
                degraded_typed_provider_count=self.typed_providers.degraded_count,
                usable_typed_provider_count=self.typed_providers.usable_count,
                subscription_count=self.events.subscription_count,
            )
        if request.method == "provider.register":
            return self._register_provider(request.params)
        if request.method == "provider.list":
            _require_exact_fields(request.params, required=())
            return {"providers": self.providers.list()}
        if request.method == "provider.catalog":
            _require_exact_fields(request.params, required=())
            return {"providers": self.typed_providers.catalog()}
        if request.method == "managed-work.query":
            return self._managed_work_query(principal, request.params)
        if request.method == "provider.read":
            return await self._read_typed_provider(request.params)
        if request.method == "provider.invoke":
            return await self._invoke_provider(request, request.params)
        if request.method == "reference.operation.preflight":
            return self.reference_operations.preflight(principal, request.params)
        if request.method == "reference.operation.approve":
            return self.reference_operations.approve(principal, request.params)
        if request.method == "reference.operation.start":
            return self.reference_operations.start(principal, request.params)
        if request.method == "reference.operation.get":
            return self.reference_operations.get(principal, request.params)
        if request.method == "reference.operation.cancel":
            return self.reference_operations.cancel(principal, request.params)
        if request.method == "reference.operation.reconcile":
            return self.reference_operations.reconcile(principal, request.params)
        if request.method == "reference.operation.ledger":
            return self.reference_operations.ledger(principal, request.params)
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

    def _principal(self, connection: ClientConnection) -> EndpointPrincipal:
        if connection.principal is None:
            raise FabricError(
                "principal.unavailable",
                "Fabric endpoint principal is unavailable",
                "The connection did not receive its daemon-bound endpoint identity.",
                change_state="none",
            )
        try:
            return self.session_bindings.require_active(connection.principal)
        except SecurityValidationError as error:
            raise FabricError(
                error.code,
                "Fabric endpoint session is inactive",
                error.explanation,
                change_state="none",
                recovery_actions=("fabric.reconnect",),
            ) from error

    def _managed_work_query(
        self,
        principal: EndpointPrincipal,
        params: Mapping[str, Any],
    ) -> Mapping[str, Any]:
        _require_exact_fields(
            params,
            required=("version", "view"),
            optional=("limit", "cursor", "entityType", "entityId"),
            context="managed-work query",
        )
        if params["version"] != "v0":
            raise FabricError(
                "managed-work.version-unsupported",
                "Managed-work query version is unsupported",
                "This daemon exposes only the closed v0 Agent Center query contract.",
                change_state="none",
                recovery_actions=("system.update",),
            )
        actor = Actor(principal.principal_id, principal.session_id)
        try:
            normalized = self.managed_work.normalize_query_arguments(
                actor,
                params["view"],
                limit=params.get("limit", 50),
                cursor=params.get("cursor"),
                entity_type=params.get("entityType"),
                entity_id=params.get("entityId"),
                present_fields=frozenset(params),
            )
            view = normalized.view
            if view in {"agent.providers", "agent.troubleshooting"}:
                self.managed_projections.refresh_providers(actor, self.typed_providers.catalog())
            if view in {"agent.activity", "agent.troubleshooting"}:
                self.managed_projections.refresh_reference_operations(actor)
            return self.managed_work.query_normalized(
                actor,
                normalized,
            )
        except ManagedWorkError as error:
            raise FabricError(
                error.code,
                "Managed-work query was refused",
                error.explanation,
                detail=error.detail,
                retryable=error.retryable,
                change_state="none",
                recovery_actions=error.recovery_actions,
            ) from error

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
        if (
            not isinstance(client, str)
            or not 1 <= len(client.encode("utf-8")) <= 160
            or "\x00" in client
        ):
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
        try:
            if connection.peer_uid is None:
                raise SecurityValidationError(
                    "principal.peer-credentials",
                    "The connection has no authenticated Unix peer UID.",
                )
            principal, _credential = self.session_bindings.issue(
                connection.peer_uid,
                EndpointAdmission(endpoint_id="fabric.owner-rpc", kind=PrincipalKind.SHELL),
            )
        except SecurityValidationError as error:
            raise FabricError(
                error.code,
                "Fabric endpoint session could not be issued",
                error.explanation,
                change_state="none",
                recovery_actions=("fabric.reconnect",),
            ) from error
        connection.principal = principal
        connection.hello_complete = True
        return {
            "connectionId": connection.connection_id,
            "client": client,
            "protocol": PROTOCOL_NAME,
            "version": PROTOCOL_VERSION,
            "databaseSchema": CURRENT_DATABASE_SCHEMA,
            "principal": {
                "id": principal.principal_id,
                "ownerId": principal.principal_id,
                "sessionId": principal.session_id,
                "endpoint": principal.endpoint_id,
                "kind": principal.kind.value,
            },
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

    async def _read_typed_provider(self, params: Mapping[str, Any]) -> Mapping[str, Any]:
        _require_exact_fields(params, required=("provider", "action", "arguments"))
        provider_id = _stable_id(params["provider"], "provider")
        action = _stable_id(params["action"], "action")
        arguments = params["arguments"]
        if not isinstance(arguments, dict):
            raise FabricError(
                "rpc.invalid-params",
                "Fabric provider arguments are invalid",
                "Typed provider read arguments must be a JSON object.",
            )
        return await self.typed_providers.read(provider_id, action, arguments)

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
        # A typed startup refusal is persistent configuration/state failure.
        # systemd must not spin on it, while an unexpected Python exception is
        # deliberately left uncaught so the service can restart exit status 1.
        return os.EX_CONFIG


if __name__ == "__main__":
    raise SystemExit(main())
