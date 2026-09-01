"""Shared closed state-domain mechanics for Files and default-app providers.

The central Fabric registry owns admission and durable operation routing.  This
module gives graph-shaped domains the same preflight/execute/validate/undo
semantics as the simple leaf providers without exposing a live mutation path.
"""

from __future__ import annotations

import asyncio
import json
import os
import stat
import threading
import uuid
from contextlib import contextmanager
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterator, Mapping, Protocol

from jsonschema import Draft202012Validator, FormatChecker, ValidationError
from referencing import Registry, Resource

from omarchy_fabric.models import FabricError
from omarchy_fabric.security.principal import EndpointPrincipal

from .._engine import canonical_json, state_revision
from .._immutable import freeze, thaw

MAX_FAKE_STATE_BYTES = 12 * 1024
MAX_FAKE_DOCUMENT_BYTES = 16 * 1024

_STATE_LOCKS: dict[str, threading.RLock] = {}
_STATE_LOCKS_GUARD = threading.Lock()

def _directory_flags() -> int:
    return (
        os.O_RDONLY
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_CLOEXEC", 0)
    )

def _file_flags() -> int:
    return os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)

def open_directory_path_no_follow(path: Path) -> int:
    """Open every component of an absolute POSIX directory path without links."""

    candidate = Path(path)
    if os.name != "posix":
        raise NotImplementedError("component-wise directory opens require POSIX openat")
    if not candidate.is_absolute():
        raise ValueError("no-follow directory paths must be absolute")
    parts = candidate.parts
    if not parts or parts[0] != os.path.sep:
        raise ValueError("no-follow directory path has no filesystem anchor")
    descriptor = os.open(os.path.sep, _directory_flags())
    try:
        for component in parts[1:]:
            if component in {"", ".", ".."} or "/" in component or "\x00" in component:
                raise ValueError("no-follow directory path contains an unsafe component")
            child = os.open(component, _directory_flags(), dir_fd=descriptor)
            opened = os.fstat(child)
            if not stat.S_ISDIR(opened.st_mode):
                os.close(child)
                raise OSError("path component is not a directory")
            os.close(descriptor)
            descriptor = child
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise

def _read_bounded_descriptor(descriptor: int, maximum: int) -> bytes:
    before = os.fstat(descriptor)
    if not stat.S_ISREG(before.st_mode) or before.st_size > maximum:
        raise ValueError("bounded input must be a regular file within its byte limit")
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = os.read(descriptor, min(16384, maximum + 1 - total))
        if not chunk:
            break
        chunks.append(chunk)
        total += len(chunk)
        if total > maximum:
            raise ValueError("bounded input exceeds its byte limit")
    after = os.fstat(descriptor)
    before_identity = (
        before.st_dev,
        before.st_ino,
        before.st_mode,
        before.st_size,
        before.st_mtime_ns,
        before.st_ctime_ns,
    )
    after_identity = (
        after.st_dev,
        after.st_ino,
        after.st_mode,
        after.st_size,
        after.st_mtime_ns,
        after.st_ctime_ns,
    )
    if before_identity != after_identity or total != after.st_size:
        raise ValueError("bounded input changed while it was read")
    return b"".join(chunks)

def read_regular_file_no_follow(path: Path, maximum: int) -> bytes:
    """Read one stable regular file without following it or a POSIX ancestor."""

    candidate = Path(path)
    if not candidate.is_absolute():
        raise ValueError("bounded input path must be absolute")
    if maximum < 0:
        raise ValueError("bounded input limit must be non-negative")
    if os.name == "posix":
        parent_fd = open_directory_path_no_follow(candidate.parent)
        try:
            before = os.stat(candidate.name, dir_fd=parent_fd, follow_symlinks=False)
            if stat.S_ISLNK(before.st_mode) or not stat.S_ISREG(before.st_mode):
                raise ValueError("bounded input must be a real file")
            descriptor = os.open(candidate.name, _file_flags(), dir_fd=parent_fd)
        finally:
            os.close(parent_fd)
    else:
        before = os.lstat(candidate)
        if stat.S_ISLNK(before.st_mode) or not stat.S_ISREG(before.st_mode):
            raise ValueError("bounded input must be a real file")
        descriptor = os.open(candidate, _file_flags())
    try:
        opened = os.fstat(descriptor)
        if (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
            raise ValueError("bounded input identity changed before open")
        return _read_bounded_descriptor(descriptor, maximum)
    finally:
        os.close(descriptor)

def directory_writable_no_follow(path: Path) -> bool:
    """Report writability only after proving the directory path has no link hop."""

    candidate = Path(path)
    try:
        if os.name == "posix":
            descriptor = open_directory_path_no_follow(candidate)
            try:
                try:
                    return os.access(
                        ".",
                        os.W_OK,
                        dir_fd=descriptor,
                        effective_ids=True,
                        follow_symlinks=False,
                    )
                except (NotImplementedError, TypeError):
                    opened = os.fstat(descriptor)
            finally:
                os.close(descriptor)
        else:
            opened = os.lstat(candidate)
            if stat.S_ISLNK(opened.st_mode) or not stat.S_ISDIR(opened.st_mode):
                return False
            return os.access(candidate, os.W_OK)
    except (OSError, ValueError):
        return False
    return bool(opened.st_mode & (stat.S_IWUSR | stat.S_IWGRP | stat.S_IWOTH))

def _state_lock(path: Path) -> threading.RLock:
    key = os.path.normcase(os.path.abspath(os.fspath(path)))
    with _STATE_LOCKS_GUARD:
        return _STATE_LOCKS.setdefault(key, threading.RLock())

def _strict_json(raw: bytes) -> Any:
    def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("fake provider state contains a duplicate key")
            result[key] = value
        return result

    def reject_constant(value: str) -> Any:
        raise ValueError(f"non-finite number: {value}")

    return json.loads(raw, object_pairs_hook=unique_object, parse_constant=reject_constant)

@dataclass(frozen=True)
class StateSnapshot:
    availability: str
    operation_available: bool
    state: Mapping[str, Any] | None
    reasons: tuple[FabricError, ...] = ()

class StateBackend(Protocol):
    async def snapshot(self) -> StateSnapshot: ...

    async def compare_and_swap(
        self,
        expected_revision: str,
        proposed_state: Mapping[str, Any],
    ) -> StateSnapshot: ...

Normalize = Callable[[Mapping[str, Any]], dict[str, Any]]
Propose = Callable[[Mapping[str, Any], Mapping[str, Any]], dict[str, Any]]
Summarize = Callable[[Mapping[str, Any], Mapping[str, Any], Mapping[str, Any]], str]
Guard = Callable[[Mapping[str, Any], Mapping[str, Any]], dict[str, Any]]
ReadHandler = Callable[[Mapping[str, Any], StateSnapshot], dict[str, Any]]

@dataclass(frozen=True)
class OperationSpec:
    action: str
    normalize: Normalize
    propose: Propose
    summarize: Summarize
    guards: Guard
    scope: Any = None

class FakeStateBackend:
    """Atomic, restartable state backend used only by hermetic lifecycle tests."""

    def __init__(
        self,
        domain: str,
        initial_state: Mapping[str, Any],
        validate_state: Callable[[Mapping[str, Any]], None],
        *,
        state_path: Path | None = None,
        fail_on: frozenset[str] = frozenset(),
    ) -> None:
        if fail_on - {"snapshot", "execute"}:
            raise ValueError("fake backend failure points are snapshot or execute")
        self.domain = domain
        self.state_path = Path(state_path) if state_path is not None else None
        if self.state_path is not None:
            if not self.state_path.is_absolute():
                raise ValueError("fake provider state path must be absolute")
            if not self.state_path.name or self.state_path.name in {".", ".."}:
                raise ValueError("fake provider state path is invalid")
            if not self.state_path.parent.exists():
                raise ValueError("fake provider state parent must already exist")
        self.fail_on = fail_on
        self.write_count = 0
        self._validate_state = validate_state
        self._lock = asyncio.Lock()
        self._state = deepcopy(dict(initial_state))
        self._state_file_seen = False
        self._validate_state(self._state)
        self._ensure_state_bound(self._state)
        if self.state_path is not None:
            with self._state_file_guard():
                loaded = self._load_if_present()
                if loaded is not None:
                    self._state = loaded
                    self._state_file_seen = True

    def _load(self) -> dict[str, Any]:
        assert self.state_path is not None
        raw = read_regular_file_no_follow(self.state_path, MAX_FAKE_DOCUMENT_BYTES)
        document = _strict_json(raw)
        if (
            not isinstance(document, dict)
            or set(document) != {"schemaVersion", "domain", "state"}
            or document["schemaVersion"] != "v0"
            or document["domain"] != self.domain
            or not isinstance(document["state"], dict)
        ):
            raise ValueError("fake provider state envelope is invalid")
        self._validate_state(document["state"])
        self._ensure_state_bound(document["state"])
        return deepcopy(document["state"])

    def _load_if_present(self) -> dict[str, Any] | None:
        try:
            return self._load()
        except FileNotFoundError:
            return None

    @contextmanager
    def _state_file_guard(self) -> Iterator[int | None]:
        if self.state_path is None:
            yield None
            return
        process_lock = _state_lock(self.state_path)
        with process_lock:
            if os.name != "posix":
                parent_lstat = os.lstat(self.state_path.parent)
                if stat.S_ISLNK(parent_lstat.st_mode) or not stat.S_ISDIR(parent_lstat.st_mode):
                    raise ValueError("fake provider state parent must be a real directory")
                yield None
                return
            parent_fd = open_directory_path_no_follow(self.state_path.parent)
            lock_name = f".{self.state_path.name}.lock"
            lock_fd = os.open(
                lock_name,
                os.O_RDWR
                | os.O_CREAT
                | getattr(os, "O_NOFOLLOW", 0)
                | getattr(os, "O_CLOEXEC", 0),
                0o600,
                dir_fd=parent_fd,
            )
            try:
                lock_stat = os.fstat(lock_fd)
                if (
                    not stat.S_ISREG(lock_stat.st_mode)
                    or lock_stat.st_nlink != 1
                    or lock_stat.st_uid != os.geteuid()
                    or lock_stat.st_mode & 0o077
                ):
                    raise ValueError("fake provider state lock is unsafe")
                import fcntl

                fcntl.flock(lock_fd, fcntl.LOCK_EX)
                try:
                    yield parent_fd
                finally:
                    fcntl.flock(lock_fd, fcntl.LOCK_UN)
            finally:
                os.close(lock_fd)
                os.close(parent_fd)

    def _persist(self, state: Mapping[str, Any], parent_fd: int | None) -> None:
        if self.state_path is None:
            return
        payload = canonical_json(
            {"schemaVersion": "v0", "domain": self.domain, "state": thaw(state)}
        ).encode("utf-8")
        if len(payload) > MAX_FAKE_DOCUMENT_BYTES:
            raise ValueError("fake provider document exceeds 16 KiB")
        temporary_name = f".{self.state_path.name}.{uuid.uuid4().hex}.tmp"
        temporary_path = self.state_path.with_name(temporary_name)
        descriptor = None
        try:
            flags = (
                os.O_WRONLY
                | os.O_CREAT
                | os.O_EXCL
                | getattr(os, "O_NOFOLLOW", 0)
                | getattr(os, "O_CLOEXEC", 0)
            )
            if parent_fd is not None:
                descriptor = os.open(temporary_name, flags, 0o600, dir_fd=parent_fd)
            else:
                descriptor = os.open(temporary_path, flags, 0o600)
            with os.fdopen(descriptor, "wb") as stream:
                descriptor = None
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
            if parent_fd is not None:
                os.replace(
                    temporary_name,
                    self.state_path.name,
                    src_dir_fd=parent_fd,
                    dst_dir_fd=parent_fd,
                )
                os.fsync(parent_fd)
            else:
                os.replace(temporary_path, self.state_path)
        finally:
            if descriptor is not None:
                os.close(descriptor)
            try:
                if parent_fd is not None:
                    os.unlink(temporary_name, dir_fd=parent_fd)
                else:
                    temporary_path.unlink()
            except FileNotFoundError:
                pass

    def _refresh_from_disk(self) -> None:
        if self.state_path is None:
            return
        loaded = self._load_if_present()
        if loaded is None:
            if self._state_file_seen:
                raise ValueError("fake provider state disappeared after persistence")
            return
        self._state = loaded
        self._state_file_seen = True

    async def snapshot(self) -> StateSnapshot:
        if "snapshot" in self.fail_on:
            raise FabricError(
                f"{self.domain}.fake-snapshot-failed",
                f"{self.domain.title()} fake inventory failed",
                "The hermetic backend produced its requested deterministic read failure.",
                retryable=True,
            )
        async with self._lock:
            with self._state_file_guard():
                self._refresh_from_disk()
            return StateSnapshot("available", True, freeze(deepcopy(self._state)))

    async def compare_and_swap(
        self,
        expected_revision: str,
        proposed_state: Mapping[str, Any],
    ) -> StateSnapshot:
        if "execute" in self.fail_on:
            raise FabricError(
                f"{self.domain}.fake-execute-failed",
                f"{self.domain.title()} fake operation failed",
                "The hermetic backend produced its requested deterministic execute failure.",
                retryable=True,
            )
        async with self._lock:
            revision_changed = False
            with self._state_file_guard() as parent_fd:
                self._refresh_from_disk()
                if state_revision(self._state) != expected_revision:
                    revision_changed = True
                else:
                    replacement = deepcopy(dict(thaw(proposed_state)))
                    self._validate_state(replacement)
                    self._ensure_state_bound(replacement)
                    self._persist(replacement, parent_fd)
                    self._state = replacement
                    self._state_file_seen = self.state_path is not None or self._state_file_seen
                    self.write_count += 1
            if revision_changed:
                raise stale_state(self.domain)
            return StateSnapshot("available", True, freeze(deepcopy(self._state)))

    async def force_state(self, state: Mapping[str, Any]) -> None:
        async with self._lock:
            replacement = deepcopy(dict(state))
            self._validate_state(replacement)
            self._ensure_state_bound(replacement)
            with self._state_file_guard() as parent_fd:
                self._persist(replacement, parent_fd)
                self._state = replacement
                self._state_file_seen = self.state_path is not None or self._state_file_seen

    @staticmethod
    def _ensure_state_bound(state: Mapping[str, Any]) -> None:
        if len(canonical_json(thaw(state)).encode("utf-8")) > MAX_FAKE_STATE_BYTES:
            raise ValueError("fake operation state exceeds 12 KiB")

class StateDomainProvider:
    def __init__(
        self,
        *,
        domain: str,
        provider_id: str,
        resource_kind: str,
        resource_id: str,
        manifest: Mapping[str, Any],
        schemas: Mapping[str, Mapping[str, Any]],
        backend: StateBackend,
        state_contract_id: str,
        state_validator: Callable[[Mapping[str, Any]], None],
        read_handlers: Mapping[str, ReadHandler],
        operations: Mapping[str, OperationSpec],
    ) -> None:
        self.domain = domain
        self.provider_id = provider_id
        self.resource_kind = resource_kind
        self.resource_id = resource_id
        self.manifest = freeze(thaw(manifest))
        self.schemas = freeze(thaw(schemas))
        self.backend = backend
        self.state_contract_id = state_contract_id
        self.state_validator = state_validator
        self.read_handlers = dict(read_handlers)
        self.operations = dict(operations)
        self._validators: dict[str, Draft202012Validator] = {}
        resources = Registry().with_resources(
            (schema_id, Resource.from_contents(thaw(schema)))
            for schema_id, schema in schemas.items()
        )
        for schema_id, schema in schemas.items():
            document = thaw(schema)
            Draft202012Validator.check_schema(document)
            self._validators[schema_id] = Draft202012Validator(
                document,
                registry=resources,
                format_checker=FormatChecker(),
            )

    def validate_state_value(self, state: Mapping[str, Any]) -> None:
        wrapper = {
            "resourceId": self.resource_id,
            "revision": state_revision(thaw(state)),
            "value": thaw(state),
        }
        self._validate({"id": self.state_contract_id}, wrapper, "state")
        self.state_validator(thaw(state))

    def _action(self, action: str, mode: str) -> Mapping[str, Any]:
        definition = self.manifest["actions"].get(action) if isinstance(action, str) else None
        if definition is None:
            raise FabricError(
                f"{self.domain}.action-unavailable",
                f"{self.domain.title()} action is unavailable",
                "The provider does not expose the requested typed action.",
                detail=str(action)[:160],
            )
        if definition["mode"] != mode:
            raise FabricError(
                f"{self.domain}.action-mode-invalid",
                f"{self.domain.title()} action mode is invalid",
                f"The action cannot be used through the {mode} provider seam.",
                detail=action,
            )
        return definition

    def _validate(self, reference: Mapping[str, Any], value: Any, label: str) -> None:
        validator = self._validators.get(reference["id"])
        if validator is None:
            raise FabricError(
                f"{self.domain}.contract-missing",
                f"{self.domain.title()} contract is missing",
                "The provider refuses to run without its exact versioned contract.",
            )
        try:
            validator.validate(thaw(value))
        except ValidationError as error:
            path = ".".join(str(part) for part in error.absolute_path)
            raise FabricError(
                f"{self.domain}.contract-invalid",
                f"{self.domain.title()} {label} is invalid",
                "The typed value does not satisfy the closed state-domain contract.",
                detail=f"{label}{'.' + path if path else ''}",
            ) from error

    async def read(self, action: str, arguments: Mapping[str, Any]) -> Mapping[str, Any]:
        definition = self._action(action, "read")
        self._validate(definition["arguments"], arguments, "arguments")
        handler = self.read_handlers.get(action)
        if handler is None:
            raise FabricError(
                f"{self.domain}.adapter-invalid",
                f"{self.domain.title()} read adapter is invalid",
                "The manifest action has no code-owned read handler.",
                detail=action,
            )
        snapshot = await self._snapshot()
        try:
            result = handler(thaw(arguments), snapshot)
        except FabricError:
            raise
        except (KeyError, TypeError, ValueError) as error:
            raise FabricError(
                f"{self.domain}.read-invalid",
                f"{self.domain.title()} read failed",
                "The bounded read handler could not construct trusted typed state.",
                detail=type(error).__name__,
            ) from error
        self._validate(result_reference or definition["result"], result, "result")
        return result

    def _workspace_result_reference(self) -> Mapping[str, Any] | None:
        for name, candidate in self.operations.items():
            if candidate.scope is None:
                return self._action(name, "operation")["result"]
        return None

    async def preflight(
        self,
        action: str,
        arguments: Mapping[str, Any],
        principal: EndpointPrincipal,
    ) -> Mapping[str, Any]:
        if not isinstance(principal, EndpointPrincipal):
            raise FabricError(
                "principal.required",
                "An authenticated Fabric principal is required",
                "Provider preflight accepts only a daemon-issued endpoint principal.",
            )
        definition = self._action(action, "operation")
        spec = self._operation(action)
        normalized = self._normalized(definition, spec, arguments)
        snapshot = await self._available_snapshot(operation=True)
        assert snapshot.state is not None
        current = thaw(snapshot.state)
        proposed = self._proposed(spec, current, normalized)
        if spec.scope is None:
            resource_binding = {"kind": self.resource_kind, "id": self.resource_id}
            current_state = self._state(current)
            proposed_state = self._state(proposed)
        else:
            scoped_current = spec.scope(current, normalized)
            scoped_proposed = spec.scope(proposed, normalized)
            if scoped_current["id"] != scoped_proposed["id"]:
                raise FabricError(
                    f"{self.domain}.scope-unstable",
                    f"{self.domain.title()} operation scope is unstable",
                    "The scoped resource identity changed across the proposal.",
                )
            resource_binding = {"kind": scoped_current["kind"], "id": scoped_current["id"]}
            current_state = self._scoped_state(scoped_current["id"], scoped_current["value"])
            proposed_state = self._scoped_state(scoped_proposed["id"], scoped_proposed["value"])
        guards = dict(spec.guards(current, normalized))
        if spec.scope is not None:
            guards["snapshotRevision"] = current_state["revision"]
        recovery_state = {
            **deepcopy(self._state(current)),
            "recoveryFromRevision": state_revision(proposed),
            "recoveryAction": action,
        }
        result = {
            "schemaVersion": "v0",
            "provider": self.provider_id,
            "providerVersion": "v0",
            "action": action,
            "capability": definition["capability"],
            "resource": resource_binding,
            "normalizedArguments": normalized,
            "stateRevision": current_state["revision"],
            "currentState": current_state,
            "proposedState": proposed_state,
            "changed": current != proposed,
            "summary": spec.summarize(current, proposed, normalized),
            "risk": definition["risk"],
            "effects": list(definition["effects"]),
            "guards": guards,
            "recovery": {"mode": "undo", "priorState": recovery_state},
        }
        self._validate(definition["preflight"], result, "preflight")
        return result

    async def execute(
        self,
        action: str,
        normalized_arguments: Mapping[str, Any],
        expected_revision: str,
    ) -> Mapping[str, Any]:
        definition = self._action(action, "operation")
        spec = self._operation(action)
        normalized = self._normalized(definition, spec, normalized_arguments)
        snapshot = await self._available_snapshot(operation=True)
        assert snapshot.state is not None
        current = thaw(snapshot.state)
        if self._plan_state(spec, current, normalized)["revision"] != expected_revision:
            raise stale_state(self.domain)
        proposed = self._proposed(spec, current, normalized)
        if current == proposed:
            return self._result(definition, action, current, changed=False, plan_state=self._plan_scope(spec, current, normalized))
        updated = await self._swap(state_revision(current), proposed)
        assert updated.state is not None
        actual = thaw(updated.state)
        if actual != proposed:
            raise FabricError(
                f"{self.domain}.validation-failed",
                f"{self.domain.title()} operation could not be validated",
                "The backend did not expose the exact requested state after execute.",
                retryable=True,
                change_state="unknown",
                recovery_actions=(f"{self.domain}.undo",),
            )
        return self._result(definition, action, actual, changed=True, plan_state=self._plan_scope(spec, actual, normalized))

    async def apply(
        self,
        action: str,
        normalized_arguments: Mapping[str, Any],
        expected_revision: str,
    ) -> Mapping[str, Any]:
        return await self.execute(action, normalized_arguments, expected_revision)

    async def validate(
        self,
        action: str,
        normalized_arguments: Mapping[str, Any],
        expected_state: Mapping[str, Any],
    ) -> Mapping[str, Any]:
        definition = self._action(action, "operation")
        spec = self._operation(action)
        self._normalized(definition, spec, normalized_arguments)
        expected_value, _ = self._validated_supplied_state(
            definition,
            expected_state,
            "expectedState",
            scoped=spec.scope is not None,
        )
        snapshot = await self._available_snapshot(operation=False)
        assert snapshot.state is not None
        actual = self._plan_state(spec, thaw(snapshot.state), self._normalized(definition, spec, normalized_arguments))
        if spec.scope is None:
            expected_document = self._state(expected_value)
        else:
            expected_document = self._scoped_state(actual["resourceId"], expected_value)
        if actual != expected_document:
            raise FabricError(
                f"{self.domain}.validation-failed",
                f"{self.domain.title()} operation state drifted",
                "The current state does not match the exact expected revision and value.",
                retryable=True,
                change_state="unknown",
                recovery_actions=(f"{self.domain}.undo",),
            )
        return self._result(definition, action, actual["value"], changed=False, plan_state=actual if spec.scope is not None else None)

    async def undo(
        self,
        action: str,
        prior_state: Mapping[str, Any],
        expected_revision: str,
    ) -> Mapping[str, Any]:
        definition = self._action(action, "operation")
        if not definition["supportsRollback"]:
            raise FabricError(
                f"{self.domain}.undo-unavailable",
                f"{self.domain.title()} undo is unavailable",
                "The action contract does not permit undo.",
            )
        target, recovery_revision = self._validated_supplied_state(
            definition,
            prior_state,
            "priorState",
            recovery_action=action,
            state_reference={"id": self.state_contract_id},
        )
        assert recovery_revision is not None
        snapshot = await self._available_snapshot(operation=True)
        assert snapshot.state is not None
        current = thaw(snapshot.state)
        if current == target:
            return self._result(
                definition,
                action,
                current,
                changed=False,
                result_reference=self._workspace_result_reference() if self._operation(action).scope is not None else None,
            )
        current_revision = state_revision(current)
        scoped = self._operation(action).scope is not None
        if current_revision != recovery_revision:
            raise stale_state(self.domain)
        if not scoped and current_revision != expected_revision:
            raise stale_state(self.domain)
        updated = await self._swap(current_revision, target)
        assert updated.state is not None
        actual = self._state(thaw(updated.state))
        if actual != self._state(target):
            raise FabricError(
                f"{self.domain}.undo-failed",
                f"{self.domain.title()} undo could not be validated",
                "The backend did not restore the exact prior state fingerprint.",
                retryable=True,
                change_state="unknown",
                recovery_actions=(f"{self.domain}.reconcile",),
            )
        return self._result(
            definition,
            action,
            actual["value"],
            changed=True,
            result_reference=self._workspace_result_reference() if scoped else None,
        )

    async def rollback(
        self,
        action: str,
        prior_state: Mapping[str, Any],
        expected_revision: str,
    ) -> Mapping[str, Any]:
        return await self.undo(action, prior_state, expected_revision)

    def _operation(self, action: str) -> OperationSpec:
        spec = self.operations.get(action)
        if spec is None or spec.action != action:
            raise FabricError(
                f"{self.domain}.adapter-invalid",
                f"{self.domain.title()} operation adapter is invalid",
                "The manifest action has no code-owned operation specification.",
                detail=action,
            )
        return spec

    def _validated_supplied_state(
        self,
        definition: Mapping[str, Any],
        supplied: Mapping[str, Any],
        label: str,
        *,
        recovery_action: str | None = None,
        scoped: bool = False,
        state_reference: Mapping[str, Any] | None = None,
    ) -> tuple[dict[str, Any], str | None]:
        self._validate(state_reference or definition["state"], supplied, label)
        if not scoped and supplied["resourceId"] != self.resource_id:
            raise FabricError(
                f"{self.domain}.resource-mismatch",
                f"{self.domain.title()} resource identity changed",
                f"{label} belongs to a different stable resource.",
            )
        value = deepcopy(dict(thaw(supplied["value"])))
        if not scoped:
            try:
                self.validate_state_value(value)
            except (FabricError, KeyError, TypeError, ValueError) as error:
                raise self._state_corrupt(label, type(error).__name__) from error
        if supplied["revision"] != state_revision(value):
            raise self._state_corrupt(label, "revision")
        recovery_revision = supplied.get("recoveryFromRevision")
        supplied_action = supplied.get("recoveryAction")
        if recovery_action is not None and (
            recovery_revision is None or supplied_action != recovery_action
        ):
            raise self._state_corrupt(label, "recovery-guard")
        return value, recovery_revision

    def _state_corrupt(self, label: str, detail: str) -> FabricError:
        return FabricError(
            f"{self.domain}.state-corrupt",
            f"{self.domain.title()} operation state is corrupt",
            "The supplied state fingerprint or recovery ownership guard is inconsistent.",
            detail=f"{label}:{detail}"[:160],
            retryable=False,
            recovery_actions=(f"{self.domain}.preflight",),
        )

    def _normalized(
        self,
        definition: Mapping[str, Any],
        spec: OperationSpec,
        arguments: Mapping[str, Any],
    ) -> dict[str, Any]:
        self._validate(definition["arguments"], arguments, "arguments")
        try:
            normalized = spec.normalize(thaw(arguments))
        except FabricError:
            raise
        except (KeyError, TypeError, ValueError) as error:
            raise FabricError(
                f"{self.domain}.arguments-invalid",
                f"{self.domain.title()} arguments are invalid",
                "The provider could not normalize the closed typed arguments.",
                detail=type(error).__name__,
            ) from error
        self._validate(definition["arguments"], normalized, "normalizedArguments")
        return normalized

    def _proposed(
        self,
        spec: OperationSpec,
        current: Mapping[str, Any],
        normalized: Mapping[str, Any],
    ) -> dict[str, Any]:
        try:
            proposed = spec.propose(deepcopy(dict(current)), thaw(normalized))
            self.validate_state_value(proposed)
            return proposed
        except FabricError:
            raise
        except (KeyError, TypeError, ValueError) as error:
            raise FabricError(
                f"{self.domain}.precondition-failed",
                f"{self.domain.title()} operation cannot run",
                "Current state does not satisfy the action's closed preconditions.",
                detail=type(error).__name__,
                retryable=True,
                recovery_actions=(f"{self.domain}.inspect",),
            ) from error

    async def _snapshot(self) -> StateSnapshot:
        try:
            snapshot = await self.backend.snapshot()
        except FabricError:
            raise
        except Exception as error:
            raise FabricError(
                f"{self.domain}.backend-failed",
                f"{self.domain.title()} backend failed",
                "The provider backend failed without a trusted typed result.",
                detail=type(error).__name__,
                retryable=True,
            ) from error
        if not isinstance(snapshot, StateSnapshot):
            raise self._backend_invalid("The backend did not return a StateSnapshot.")
        if snapshot.availability not in {"available", "degraded", "unavailable"}:
            raise self._backend_invalid("The backend availability vocabulary is invalid.")
        if snapshot.availability == "unavailable":
            if snapshot.operation_available or snapshot.state is not None or not snapshot.reasons:
                raise self._backend_invalid("Unavailable state must contain only typed reasons.")
        else:
            if snapshot.state is None:
                raise self._backend_invalid("Readable state requires a typed value.")
            if snapshot.availability == "available" and snapshot.reasons:
                raise self._backend_invalid("Available state cannot carry degradation reasons.")
            if snapshot.availability == "degraded" and not snapshot.reasons:
                raise self._backend_invalid("Degraded state requires at least one typed reason.")
            try:
                self.validate_state_value(snapshot.state)
            except (FabricError, TypeError, ValueError) as error:
                raise self._backend_invalid(
                    f"The backend state violates the closed semantic contract ({type(error).__name__})."
                ) from error
        if snapshot.operation_available and snapshot.availability != "available":
            raise self._backend_invalid("Mutations require a fully available snapshot.")
        return StateSnapshot(
            snapshot.availability,
            snapshot.operation_available,
            freeze(thaw(snapshot.state)) if snapshot.state is not None else None,
            tuple(snapshot.reasons),
        )

    async def _available_snapshot(self, *, operation: bool) -> StateSnapshot:
        snapshot = await self._snapshot()
        if snapshot.state is None or (operation and not snapshot.operation_available):
            reason = snapshot.reasons[0] if snapshot.reasons else None
            raise FabricError(
                f"{self.domain}.operation-unavailable" if operation else f"{self.domain}.inventory-unavailable",
                f"{self.domain.title()} operation is unavailable" if operation else f"{self.domain.title()} inventory is unavailable",
                "The real provider exposes trusted read state only until a durable typed executor is integrated."
                if operation and snapshot.state is not None
                else "The provider cannot establish trusted current state.",
                detail=reason.code if reason is not None else "",
                retryable=True,
                recovery_actions=("operation.integration-required",) if operation else ("provider.retry",),
            )
        return snapshot

    async def _swap(self, expected_revision: str, proposed: Mapping[str, Any]) -> StateSnapshot:
        try:
            snapshot = await self.backend.compare_and_swap(expected_revision, proposed)
        except FabricError:
            raise
        except Exception as error:
            raise FabricError(
                f"{self.domain}.backend-failed",
                f"{self.domain.title()} backend failed during execute",
                "The backend did not return trusted typed state after the transition.",
                detail=type(error).__name__,
                retryable=True,
                change_state="unknown",
                recovery_actions=(f"{self.domain}.reconcile",),
            ) from error
        normalized = await self._normalize_returned_snapshot(snapshot)
        return normalized

    async def _normalize_returned_snapshot(self, snapshot: StateSnapshot) -> StateSnapshot:
        if not isinstance(snapshot, StateSnapshot):
            raise FabricError(
                f"{self.domain}.backend-invalid",
                f"{self.domain.title()} backend result is invalid after execute",
                "The backend changed state but did not return a typed snapshot.",
                change_state="unknown",
                recovery_actions=(f"{self.domain}.reconcile",),
            )
        if snapshot.availability != "available" or not snapshot.operation_available or snapshot.state is None or snapshot.reasons:
            raise FabricError(
                f"{self.domain}.backend-invalid",
                f"{self.domain.title()} backend result is invalid after execute",
                "The backend changed state but did not return fully available typed state.",
                change_state="unknown",
                recovery_actions=(f"{self.domain}.reconcile",),
            )
        try:
            self.validate_state_value(snapshot.state)
        except (FabricError, TypeError, ValueError) as error:
            raise FabricError(
                f"{self.domain}.backend-invalid",
                f"{self.domain.title()} backend result is invalid after execute",
                "The changed state violates the closed semantic contract.",
                detail=type(error).__name__,
                change_state="unknown",
                recovery_actions=(f"{self.domain}.reconcile",),
            ) from error
        return StateSnapshot("available", True, freeze(thaw(snapshot.state)))

    def _plan_scope(self, spec: Any, state: Mapping[str, Any], normalized: Mapping[str, Any]) -> dict[str, Any] | None:
        if spec.scope is None:
            return None
        return self._plan_state(spec, state, normalized)

    def _plan_state(self, spec: Any, state: Mapping[str, Any], normalized: Mapping[str, Any]) -> dict[str, Any]:
        if spec.scope is None:
            return self._state(state)
        scoped = spec.scope(state, normalized)
        return self._scoped_state(scoped["id"], scoped["value"])

    def _scoped_state(self, resource_id: str, value: Mapping[str, Any]) -> dict[str, Any]:
        normalized = thaw(value)
        return {
            "resourceId": resource_id,
            "revision": state_revision(normalized),
            "value": normalized,
        }

    def _state(self, value: Mapping[str, Any]) -> dict[str, Any]:
        normalized = thaw(value)
        return {
            "resourceId": self.resource_id,
            "revision": state_revision(normalized),
            "value": normalized,
        }

    def _result(
        self,
        definition: Mapping[str, Any],
        action: str,
        state: Mapping[str, Any],
        *,
        changed: bool,
        plan_state: Mapping[str, Any] | None = None,
        result_reference: Mapping[str, Any] | None = None,
    ) -> Mapping[str, Any]:
        operation_state = self._state(state) if plan_state is None else dict(plan_state)
        resource = {"kind": self.resource_kind, "id": self.resource_id}
        if plan_state is not None:
            resource = {"kind": "files.directory", "id": operation_state["resourceId"]}
        result = {
            "schemaVersion": "v0",
            "provider": self.provider_id,
            "providerVersion": "v0",
            "action": action,
            "capability": definition["capability"],
            "resource": resource,
            "changed": changed,
            "changeState": "complete" if changed else "none",
            "stateRevision": operation_state["revision"],
            "state": operation_state,
            "error": None,
        }
        self._validate(definition["result"], result, "result")
        return result

    def _backend_invalid(self, explanation: str) -> FabricError:
        return FabricError(
            f"{self.domain}.backend-invalid",
            f"{self.domain.title()} backend result is invalid",
            explanation,
        )

def availability_payload(snapshot: StateSnapshot) -> dict[str, Any]:
    return {
        "state": snapshot.availability,
        "read": snapshot.state is not None,
        "operation": snapshot.operation_available,
        "reasons": [reason.to_dict() for reason in snapshot.reasons],
    }

def stale_state(domain: str) -> FabricError:
    return FabricError(
        f"{domain}.state-stale",
        f"{domain.title()} state changed",
        "The state fingerprint changed after preflight; request a new preflight.",
        retryable=True,
        recovery_actions=(f"{domain}.preflight",),
    )
