"""Durable update-run journal for cancellation and restart reconciliation."""

from __future__ import annotations

import json
import os
import re
import stat
import threading
import time
import uuid
from copy import deepcopy
from pathlib import Path
from types import TracebackType
from typing import Any, Mapping

import fcntl

from omarchy_fabric.models import FabricError

from .._engine import canonical_json, state_revision

MAX_JOURNAL_BYTES = 128 * 1024
LOCK_TIMEOUT_SECONDS = 5.0
STATUSES = {
    "proposed",
    "checking",
    "downloading",
    "staged",
    "applying",
    "waiting-reboot",
    "succeeded",
    "failed",
    "cancelled",
    "interrupted",
    "reconciling",
    "needs-attention",
}
CANCELLABLE = {"proposed", "checking", "downloading", "staged"}
TRANSITIONS = {
    "proposed": {"checking", "downloading", "staged", "applying", "cancelled", "failed"},
    "checking": {"downloading", "staged", "succeeded", "cancelled", "failed", "interrupted"},
    "downloading": {"staged", "cancelled", "failed", "interrupted"},
    "staged": {"applying", "succeeded", "cancelled", "failed", "interrupted"},
    "applying": {"waiting-reboot", "succeeded", "failed", "interrupted"},
    "waiting-reboot": {"succeeded", "failed", "interrupted"},
    "interrupted": {"reconciling"},
    "reconciling": {"waiting-reboot", "succeeded", "failed", "needs-attention"},
}
MODE_STATUSES = {
    "check": {"proposed", "checking", "succeeded", "failed", "cancelled", "interrupted", "reconciling", "needs-attention"},
    "download": {"proposed", "checking", "downloading", "staged", "succeeded", "failed", "cancelled", "interrupted", "reconciling", "needs-attention"},
    "apply": set(STATUSES),
    "reboot": {"proposed", "applying", "succeeded", "failed", "cancelled", "interrupted", "reconciling", "needs-attention"},
}
_SENSITIVE_DETAIL_PATTERNS = (
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)\b(bearer\s+)[A-Za-z0-9._~+/-]{8,}"),
    re.compile(r"(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}(?![A-Za-z0-9_-])"),
    re.compile(
        r"(?i)(?<![A-Za-z0-9_-])[\"']?([a-z0-9_-]{0,64}(?:password|passwd|token|secret|api[_-]?key|access[_-]?key|private[_-]?key|authorization)[a-z0-9_-]{0,64})[\"']?\s*[:=]\s*(?:\"[^\"\r\n]*\"|'[^'\r\n]*'|[^\s,;]+)"
    ),
    re.compile(r"(?i)\b([a-z][a-z0-9+.-]{0,31}://)[^/@\s]{1,512}@"),
)


def _safe_detail(value: object) -> str:
    if not isinstance(value, str):
        raise FabricError("update.detail-invalid", "Update detail is invalid", "Journal detail must be trusted text.")
    cleaned = "".join(character for character in value if character.isprintable() and character not in "\r\n\x00")[:1000]
    for pattern in _SENSITIVE_DETAIL_PATTERNS:
        if pattern.search(cleaned):
            return "Sensitive update detail was redacted."
    return cleaned


def _decode(raw: bytes) -> dict[str, Any]:
    if len(raw) > MAX_JOURNAL_BYTES:
        raise FabricError("update.journal-too-large", "Update journal is too large", "The update journal exceeds its bounded contract.")

    def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        document: dict[str, Any] = {}
        for key, value in pairs:
            if key in document:
                raise ValueError("duplicate key")
            document[key] = value
        return document

    try:
        document = json.loads(raw, object_pairs_hook=unique_object, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        raise FabricError("update.journal-corrupt", "Update journal is corrupt", "The journal is not finite canonical UTF-8 JSON.", detail=type(error).__name__) from error
    if not isinstance(document, dict):
        raise FabricError("update.journal-corrupt", "Update journal is corrupt", "The journal root must be an object.")
    return document


def _validate(document: Mapping[str, Any]) -> None:
    if set(document) != {"schemaVersion", "runId", "mode", "status", "catalogRevision", "checkpoint", "rebootRequired", "detail", "revision"}:
        raise FabricError("update.journal-corrupt", "Update journal is corrupt", "The journal shape is not the closed v0 contract.")
    if document["schemaVersion"] != "v0" or document["status"] not in STATUSES:
        raise FabricError("update.journal-corrupt", "Update journal is corrupt", "The journal version or state is invalid.")
    if not isinstance(document["runId"], str) or re.fullmatch(r"update-run\.[0-9a-f]{32}", document["runId"]) is None:
        raise FabricError("update.journal-corrupt", "Update journal is corrupt", "The run identity is invalid.")
    if document["mode"] not in {"check", "download", "apply", "reboot"}:
        raise FabricError("update.journal-corrupt", "Update journal is corrupt", "The update mode is invalid.")
    if document["status"] not in MODE_STATUSES[document["mode"]]:
        raise FabricError("update.journal-corrupt", "Update journal is corrupt", "The update mode and lifecycle state are inconsistent.")
    if not isinstance(document["catalogRevision"], str) or re.fullmatch(r"sha256\.[0-9a-f]{64}", document["catalogRevision"]) is None:
        raise FabricError("update.journal-corrupt", "Update journal is corrupt", "The catalog revision is invalid.")
    if document["checkpoint"] not in {"none", "required", "created", "failed"} or not isinstance(document["rebootRequired"], bool):
        raise FabricError("update.journal-corrupt", "Update journal is corrupt", "Checkpoint or reboot truth is invalid.")
    if not isinstance(document["detail"], str) or len(document["detail"]) > 1000 or _safe_detail(document["detail"]) != document["detail"]:
        raise FabricError("update.journal-corrupt", "Update journal is corrupt", "Journal detail is invalid.")
    if document["mode"] == "apply":
        if document["checkpoint"] == "none":
            raise FabricError("update.journal-corrupt", "Update journal is corrupt", "Apply lifecycle state lost its required checkpoint truth.")
        if document["status"] in {"applying", "waiting-reboot", "succeeded"} and document["checkpoint"] != "created":
            raise FabricError("update.journal-corrupt", "Update journal is corrupt", "Package application cannot precede a verified checkpoint.")
    elif document["checkpoint"] != "none":
        raise FabricError("update.journal-corrupt", "Update journal is corrupt", "Non-apply update modes cannot claim a checkpoint.")
    if document["status"] == "waiting-reboot" and not document["rebootRequired"]:
        raise FabricError("update.journal-corrupt", "Update journal is corrupt", "Waiting-reboot state requires observed reboot truth.")
    unsigned = dict(document)
    declared = unsigned.pop("revision")
    if declared != state_revision(unsigned):
        raise FabricError("update.journal-revision-invalid", "Update journal revision is invalid", "The journal contents do not match the declared revision.")


class _ExclusiveJournalLock:
    def __init__(self, journal: "UpdateJournal") -> None:
        self.journal = journal
        self.directory_fd = -1
        self.lock_fd = -1

    def __enter__(self) -> int:
        self.directory_fd, self.lock_fd = self.journal._acquire()
        return self.directory_fd

    def __exit__(self, _error_type: type[BaseException] | None, _error: BaseException | None, _traceback: TracebackType | None) -> bool:
        self.journal._release(self.directory_fd, self.lock_fd)
        self.directory_fd = -1
        self.lock_fd = -1
        return False


class UpdateJournal:
    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        if not self.path.is_absolute() or not self.path.name or len(self.path.name) > 128:
            raise ValueError("update journal path must be an absolute bounded file path")
        self._lock_name = f".{self.path.name}.lock"
        self._lock = threading.RLock()

    def create(self, catalog_revision: str, *, mode: str, checkpoint_required: bool) -> dict[str, Any]:
        with self._exclusive() as directory_fd:
            if self._entry_exists(directory_fd, self.path.name):
                raise FabricError("update.journal-exists", "Update journal already exists", "A run must be reconciled or removed before another is created.")
            if mode not in {"check", "download", "apply", "reboot"} or checkpoint_required is not (mode == "apply"):
                raise FabricError("update.plan-invalid", "Update plan is invalid", "Apply requires a checkpoint and other update modes must not claim one.")
            document = {
                "schemaVersion": "v0",
                "runId": f"update-run.{uuid.uuid4().hex}",
                "mode": mode,
                "status": "proposed",
                "catalogRevision": catalog_revision,
                "checkpoint": "required" if checkpoint_required else "none",
                "rebootRequired": False,
                "detail": "",
            }
            return self._write_unlocked(directory_fd, document)

    def load(self) -> dict[str, Any]:
        with self._exclusive() as directory_fd:
            return self._load_unlocked(directory_fd)

    def transition(self, expected_revision: str, status: str, *, checkpoint: str | None = None, reboot_required: bool | None = None, detail: str = "") -> dict[str, Any]:
        with self._exclusive() as directory_fd:
            current = self._load_unlocked(directory_fd)
            if current["revision"] != expected_revision:
                raise FabricError("update.state-stale", "Update state changed", "The journal revision changed; reconcile before continuing.", retryable=True)
            if status not in TRANSITIONS.get(current["status"], set()):
                raise FabricError("update.transition-invalid", "Update transition is invalid", "The requested state transition is not allowed.", detail=f"{current['status']}->{status}")
            next_document = {key: value for key, value in current.items() if key != "revision"}
            next_document["status"] = status
            next_document["detail"] = _safe_detail(detail)
            if checkpoint is not None:
                if checkpoint not in {"none", "required", "created", "failed"}:
                    raise FabricError("update.checkpoint-invalid", "Update checkpoint is invalid", "Checkpoint state must use the closed vocabulary.")
                next_document["checkpoint"] = checkpoint
            if reboot_required is not None:
                if not isinstance(reboot_required, bool):
                    raise FabricError("update.reboot-invalid", "Update reboot state is invalid", "Reboot truth must be boolean.")
                next_document["rebootRequired"] = reboot_required
            if status not in MODE_STATUSES[current["mode"]]:
                raise FabricError("update.transition-invalid", "Update transition is invalid", "The requested state is not valid for this update mode.", detail=f"{current['mode']}:{status}")
            if current["mode"] == "apply" and status in {"applying", "waiting-reboot", "succeeded"} and next_document["checkpoint"] != "created":
                raise FabricError("update.checkpoint-required", "Update checkpoint is required", "Package application cannot begin until checkpoint creation is observed.")
            if current["mode"] != "apply" and next_document["checkpoint"] != "none":
                raise FabricError("update.checkpoint-invalid", "Update checkpoint is invalid", "Only apply runs can record checkpoint state.")
            if status == "waiting-reboot" and not next_document["rebootRequired"]:
                raise FabricError("update.reboot-invalid", "Update reboot state is invalid", "Waiting-reboot requires observed reboot truth.")
            return self._write_unlocked(directory_fd, next_document)

    def cancel(self, expected_revision: str) -> dict[str, Any]:
        with self._exclusive() as directory_fd:
            current = self._load_unlocked(directory_fd)
            if current["revision"] != expected_revision:
                raise FabricError("update.state-stale", "Update state changed", "The journal revision changed; reconcile before continuing.", retryable=True)
            if current["status"] not in CANCELLABLE:
                raise FabricError("update.cancel-unsafe", "Update cannot be cancelled safely", "Cancellation is closed after package application begins.", detail=current["status"])
            next_document = {key: value for key, value in current.items() if key != "revision"}
            next_document["status"] = "cancelled"
            next_document["detail"] = "Cancelled before the irreversible apply boundary."
            return self._write_unlocked(directory_fd, next_document)

    def reconcile(self, expected_revision: str, actual: Mapping[str, Any]) -> dict[str, Any]:
        with self._exclusive() as directory_fd:
            current = self._load_unlocked(directory_fd)
            if current["revision"] != expected_revision:
                raise FabricError("update.state-stale", "Update state changed", "The journal revision changed; reconcile before continuing.", retryable=True)
            if current["status"] not in {"interrupted", "reconciling"} or set(actual) != {"catalogRevision", "checkpoint", "rebootRequired", "complete"}:
                raise FabricError("update.reconcile-invalid", "Update reconcile input is invalid", "Reconcile requires an interrupted run and closed observed state.")
            if (
                not isinstance(actual["catalogRevision"], str)
                or re.fullmatch(r"sha256\.[0-9a-f]{64}", actual["catalogRevision"]) is None
                or actual["checkpoint"] not in {"none", "required", "created", "failed"}
                or not isinstance(actual["rebootRequired"], bool)
                or not isinstance(actual["complete"], bool)
                or (current["mode"] != "apply" and actual["checkpoint"] != "none")
            ):
                raise FabricError("update.reconcile-invalid", "Update reconcile input is invalid", "Observed update truth does not satisfy the closed reconcile contract.")
            if current["status"] == "interrupted":
                next_document = {key: value for key, value in current.items() if key != "revision"}
                next_document["status"] = "reconciling"
                next_document["detail"] = "Comparing durable intent with actual package state."
                current = self._write_unlocked(directory_fd, next_document)
            if (
                actual["catalogRevision"] != current["catalogRevision"]
                or (current["mode"] == "apply" and actual["checkpoint"] != "created")
                or (current["mode"] != "apply" and actual["rebootRequired"])
            ):
                status = "needs-attention"
            elif actual["complete"] and actual["rebootRequired"] and current["mode"] == "apply":
                status = "waiting-reboot"
            elif actual["complete"]:
                status = "succeeded"
            else:
                status = "failed"
            next_document = {key: value for key, value in current.items() if key != "revision"}
            next_document.update(
                status=status,
                checkpoint=actual["checkpoint"],
                rebootRequired=actual["rebootRequired"],
                detail="Reconciled from observed package and checkpoint truth.",
            )
            return self._write_unlocked(directory_fd, next_document)

    def _exclusive(self) -> _ExclusiveJournalLock:
        return _ExclusiveJournalLock(self)

    def _acquire(self) -> tuple[int, int]:
        self._lock.acquire()
        directory_fd = -1
        lock_fd = -1
        try:
            if not self.path.parent.exists():
                raise FabricError("update.journal-path-unsafe", "Update journal path is unsafe", "The journal directory must be provisioned before use.")
            resolved_parent = self.path.parent.resolve(strict=True)
            if resolved_parent != self.path.parent.absolute():
                raise FabricError("update.journal-path-unsafe", "Update journal path is unsafe", "The journal directory cannot traverse a symbolic link.")
            try:
                directory_fd = os.open(self.path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            except OSError as error:
                raise FabricError("update.journal-path-unsafe", "Update journal path is unsafe", "The journal directory could not be opened without following symbolic links.", detail=type(error).__name__) from error
            try:
                directory_stat = os.fstat(directory_fd)
                if not stat.S_ISDIR(directory_stat.st_mode) or directory_stat.st_uid != os.geteuid() or directory_stat.st_mode & 0o022:
                    raise FabricError("update.journal-path-unsafe", "Update journal path is unsafe", "The journal directory must be owned by the caller and not writable by other users.")
                lock_fd = os.open(self._lock_name, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600, dir_fd=directory_fd)
                lock_stat = os.fstat(lock_fd)
                if not stat.S_ISREG(lock_stat.st_mode) or lock_stat.st_uid != os.geteuid() or lock_stat.st_mode & 0o077:
                    raise FabricError("update.journal-path-unsafe", "Update journal path is unsafe", "The journal lock must be a caller-owned regular file.")
                deadline = time.monotonic() + LOCK_TIMEOUT_SECONDS
                while True:
                    try:
                        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        break
                    except BlockingIOError as error:
                        if time.monotonic() >= deadline:
                            raise FabricError("update.journal-busy", "Update journal is busy", "Another update writer still owns the bounded journal lock.", retryable=True) from error
                        time.sleep(0.01)
            except OSError as error:
                raise FabricError("update.journal-path-unsafe", "Update journal path is unsafe", "The journal lock could not be opened without following symbolic links.", detail=type(error).__name__) from error
            return directory_fd, lock_fd
        except BaseException:
            if lock_fd >= 0:
                os.close(lock_fd)
            if directory_fd >= 0:
                os.close(directory_fd)
            self._lock.release()
            raise

    def _release(self, directory_fd: int, lock_fd: int) -> None:
        try:
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
            finally:
                os.close(lock_fd)
        finally:
            try:
                os.close(directory_fd)
            finally:
                self._lock.release()

    @staticmethod
    def _entry_exists(directory_fd: int, name: str) -> bool:
        try:
            os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        except FileNotFoundError:
            return False
        return True

    def _load_unlocked(self, directory_fd: int) -> dict[str, Any]:
        try:
            file_fd = os.open(self.path.name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory_fd)
        except FileNotFoundError as error:
            raise FabricError("update.journal-missing", "Update journal is missing", "No durable update run exists.") from error
        except OSError as error:
            raise FabricError("update.journal-path-unsafe", "Update journal path is unsafe", "The journal must not be a symbolic link.", detail=type(error).__name__) from error
        try:
            file_stat = os.fstat(file_fd)
            if not stat.S_ISREG(file_stat.st_mode) or file_stat.st_uid != os.geteuid() or file_stat.st_mode & 0o077:
                raise FabricError("update.journal-path-unsafe", "Update journal path is unsafe", "The journal must be a caller-owned regular file that other users cannot modify.")
            chunks: list[bytes] = []
            remaining = MAX_JOURNAL_BYTES + 1
            while remaining:
                chunk = os.read(file_fd, min(65536, remaining))
                if not chunk:
                    break
                chunks.append(chunk)
                remaining -= len(chunk)
            raw = b"".join(chunks)
            document = _decode(raw)
        finally:
            os.close(file_fd)
        _validate(document)
        if raw != canonical_json(document).encode("utf-8"):
            raise FabricError("update.journal-corrupt", "Update journal is corrupt", "The journal bytes are not canonical UTF-8 JSON.")
        return deepcopy(document)

    def _write_unlocked(self, directory_fd: int, document: Mapping[str, Any]) -> dict[str, Any]:
        unsigned = deepcopy(dict(document))
        unsigned.pop("revision", None)
        complete = {**unsigned, "revision": state_revision(unsigned)}
        _validate(complete)
        payload = canonical_json(complete).encode("utf-8")
        if len(payload) > MAX_JOURNAL_BYTES:
            raise FabricError("update.journal-too-large", "Update journal is too large", "The update journal exceeds its bounded contract.")
        temporary_name = f".{self.path.name}.{uuid.uuid4().hex}.tmp"
        temporary_fd = -1
        try:
            temporary_fd = os.open(temporary_name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory_fd)
            offset = 0
            while offset < len(payload):
                offset += os.write(temporary_fd, payload[offset:])
            os.fsync(temporary_fd)
            os.close(temporary_fd)
            temporary_fd = -1
            os.replace(temporary_name, self.path.name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
            os.fsync(directory_fd)
        finally:
            if temporary_fd >= 0:
                os.close(temporary_fd)
            try:
                os.unlink(temporary_name, dir_fd=directory_fd)
            except FileNotFoundError:
                pass
        return deepcopy(complete)
