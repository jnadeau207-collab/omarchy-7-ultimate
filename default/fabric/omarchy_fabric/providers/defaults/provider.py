"""Typed default application, MIME, and protocol provider."""

from __future__ import annotations

import asyncio
import json
import os
import stat
import unicodedata
from copy import deepcopy
from pathlib import Path
from typing import Any, Mapping

from jsonschema import Draft202012Validator

from omarchy_fabric.models import FabricError, FixedArgvCommand

from .._engine import canonical_json, state_revision
from .._identity import stable_resource_id
from .._immutable import freeze, thaw
from .._probe import ProbeRunner, invoke_probe, probe_error, run_probe
from ..files._engine import (
    FakeStateBackend,
    OperationSpec,
    StateDomainProvider,
    StateSnapshot,
    availability_payload,
    directory_writable_no_follow,
    open_directory_path_no_follow,
    read_regular_file_no_follow,
)

DOMAIN = "defaults"
PROVIDER_ID = "defaults.provider"
RESOURCE_KIND = "defaults.database"
RESOURCE_ID = "defaults.database.primary"
STATE_CONTRACT_ID = "urn:omarchy:fabric:provider:defaults:operation-state:v0"
MAX_CONFIG_BYTES = 32 * 1024
MAX_DESKTOP_BYTES = 64 * 1024
MAX_DESKTOP_FILES = 128
MAX_REAL_STATE_BYTES = 36 * 1024

MIME_TYPES = (
    "application/json",
    "application/pdf",
    "image/jpeg",
    "image/png",
    "text/html",
    "text/plain",
    "video/mp4",
)
PROTOCOLS = ("http", "https", "mailto")
QUERY_COMMANDS = {
    **{
        ("mime", key): FixedArgvCommand("/usr/bin/xdg-mime", ("query", "default", key))
        for key in MIME_TYPES
    },
    **{
        ("protocol", key): FixedArgvCommand(
            "/usr/bin/xdg-mime",
            ("query", "default", f"x-scheme-handler/{key}"),
        )
        for key in PROTOCOLS
    },
}

SCHEMA_FILES = (
    "defaults-empty-arguments-v0.json",
    "defaults-mime-query-arguments-v0.json",
    "defaults-protocol-query-arguments-v0.json",
    "defaults-mime-set-arguments-v0.json",
    "defaults-protocol-set-arguments-v0.json",
    "defaults-clear-arguments-v0.json",
    "defaults-inventory-result-v0.json",
    "defaults-query-result-v0.json",
    "defaults-operation-state-v0.json",
    "defaults-operation-preflight-v0.json",
    "defaults-operation-result-v0.json",
)

def _load_json(path: Path, maximum: int = MAX_CONFIG_BYTES) -> dict[str, Any]:
    raw = read_regular_file_no_follow(Path(path), maximum)

    def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate key: {key[:80]}")
            result[key] = value
        return result

    def reject_constant(value: str) -> Any:
        raise ValueError(f"non-finite number: {value}")

    document = json.loads(raw, object_pairs_hook=unique_object, parse_constant=reject_constant)
    if not isinstance(document, dict):
        raise ValueError("JSON document must be an object")
    return document

def _schema_directory() -> Path:
    return Path(__file__).resolve().parents[3] / "schema"

def _load_schemas() -> dict[str, Mapping[str, Any]]:
    documents = [_load_json(_schema_directory() / name, 128 * 1024) for name in SCHEMA_FILES]
    return {document["$id"]: document for document in documents}

SCHEMAS = _load_schemas()
STATE_SCHEMA = SCHEMAS[STATE_CONTRACT_ID]
STATE_VALIDATOR = Draft202012Validator(STATE_SCHEMA)

def _validate_database_schema(state: Mapping[str, Any]) -> None:
    wrapper = {"resourceId": RESOURCE_ID, "revision": state_revision(state), "value": thaw(state)}
    error = next(iter(STATE_VALIDATOR.iter_errors(wrapper)), None)
    if error is not None:
        path = ".".join(str(part) for part in error.absolute_path)
        raise ValueError(f"default database schema invalid at {path or '<root>'}")

def _association_id(kind: str, key: str) -> str:
    return stable_resource_id(DOMAIN, "association", f"{kind}\0{key}")

def _application_id(desktop_id: str) -> str:
    return stable_resource_id(DOMAIN, "app", desktop_id)

def _association_identity(association: Mapping[str, Any]) -> str:
    return state_revision({
        "kind": association["kind"],
        "key": association["key"],
        "defaultAppId": association["defaultAppId"],
        "candidateAppIds": association["candidateAppIds"],
        "source": association["source"],
        "status": association["status"],
    })

def validate_database(state: Mapping[str, Any]) -> None:
    _validate_database_schema(state)
    applications = state["applications"]
    associations = state["associations"]
    app_ids = [app["id"] for app in applications]
    desktop_ids = [app["desktopId"] for app in applications]
    association_ids = [association["id"] for association in associations]
    if len(app_ids) != len(set(app_ids)) or len(desktop_ids) != len(set(desktop_ids)):
        raise ValueError("application identities must be unique")
    if len(association_ids) != len(set(association_ids)):
        raise ValueError("association identities must be unique")
    app_by_id = {app["id"]: app for app in applications}
    for app in applications:
        if app["id"] != _application_id(app["desktopId"]):
            raise ValueError("application identity is not deterministic")
        if app["mimeTypes"] != sorted(app["mimeTypes"]) or app["protocols"] != sorted(app["protocols"]):
            raise ValueError("application capabilities must be sorted")
        if app["state"] == "available" and app["reason"] is not None:
            raise ValueError("available application carries an unavailable reason")
        if app["state"] == "unavailable" and app["reason"] is None:
            raise ValueError("unavailable application has no typed reason")
    for association in associations:
        if association["id"] != _association_id(association["kind"], association["key"]):
            raise ValueError("association identity is not deterministic")
        if association["candidateAppIds"] != sorted(association["candidateAppIds"]):
            raise ValueError("association candidates must be sorted")
        if association["kind"] == "mime" and association["key"] not in MIME_TYPES:
            raise ValueError("MIME association is outside the code-owned catalog")
        if association["kind"] == "protocol" and association["key"] not in PROTOCOLS:
            raise ValueError("protocol association is outside the code-owned catalog")
        if any(candidate not in app_by_id for candidate in association["candidateAppIds"]):
            raise ValueError("association candidate is unknown")
        for candidate in association["candidateAppIds"]:
            app = app_by_id[candidate]
            supported = app["mimeTypes"] if association["kind"] == "mime" else app["protocols"]
            if association["key"] not in supported:
                raise ValueError("association candidate does not declare support")
        default_id = association["defaultAppId"]
        if association["status"] == "configured":
            if default_id not in app_by_id or default_id not in association["candidateAppIds"]:
                raise ValueError("configured association default is unavailable")
            if association["source"] not in {"system", "user"}:
                raise ValueError("configured association has no authoritative source")
        elif association["status"] == "unconfigured":
            if default_id is not None or association["source"] != "none":
                raise ValueError("unconfigured association carries a default")
        elif association["status"] == "dangling":
            if default_id is None or (default_id in app_by_id and default_id in association["candidateAppIds"]):
                raise ValueError("dangling association resolves to a supported application")
            if association["source"] not in {"system", "user"}:
                raise ValueError("dangling association has no authoritative source")
        if association["identity"] != _association_identity(association):
            raise ValueError("association revision is inconsistent")

def canonicalize_database(state: Mapping[str, Any]) -> dict[str, Any]:
    normalized = deepcopy(dict(state))
    for app in normalized["applications"]:
        app["mimeTypes"] = sorted(app["mimeTypes"])
        app["protocols"] = sorted(app["protocols"])
    for association in normalized["associations"]:
        association["candidateAppIds"] = sorted(association["candidateAppIds"])
    normalized["applications"] = sorted(normalized["applications"], key=lambda item: item["id"])
    normalized["associations"] = sorted(normalized["associations"], key=lambda item: item["id"])
    validate_database(normalized)
    return normalized

class RealDefaultsBackend:
    """No-follow desktop inventory plus code-owned fixed-argv xdg-mime reads."""

    def __init__(self, home: Path, config_path: Path, runner: ProbeRunner) -> None:
        self.home = Path(home)
        config_path = Path(config_path)
        if not self.home.is_absolute() or not config_path.is_absolute():
            raise ValueError("defaults provider paths must be absolute")
        try:
            config_stat = os.lstat(config_path)
        except OSError as error:
            raise ValueError("default association config is unavailable") from error
        if stat.S_ISLNK(config_stat.st_mode) or not stat.S_ISREG(config_stat.st_mode):
            raise ValueError("default association config must be a real file")
        try:
            self.config = self._validate_config(_load_json(config_path))
        except OSError as error:
            raise ValueError("default association config cannot be opened through the no-follow boundary") from error
        self.runner = runner

    @staticmethod
    def _validate_config(document: Mapping[str, Any]) -> dict[str, Any]:
        if set(document) != {"schemaVersion", "mimeTypes", "protocols"} or document["schemaVersion"] != "v0":
            raise ValueError("default association config envelope is invalid")
        if tuple(document["mimeTypes"]) != MIME_TYPES or tuple(document["protocols"]) != PROTOCOLS:
            raise ValueError("default association config does not match the code-owned command catalog")
        return deepcopy(dict(document))

    async def snapshot(self) -> StateSnapshot:
        applications_task = asyncio.to_thread(self._applications)
        probe_tasks = [invoke_probe(command, self.runner) for command in QUERY_COMMANDS.values()]
        applications_result, *probe_results = await asyncio.gather(
            applications_task,
            *probe_tasks,
            return_exceptions=True,
        )
        reasons: list[FabricError] = []
        if isinstance(applications_result, Exception):
            return StateSnapshot(
                "unavailable",
                False,
                None,
                (_reason(
                    "defaults.desktop-inventory-unavailable",
                    "Application inventory is unavailable",
                    "The no-follow desktop application inventory could not be constructed.",
                    detail=type(applications_result).__name__,
                ),),
            )
        applications, inventory_reasons = applications_result
        reasons.extend(inventory_reasons)
        home_safe = _directory_is_safe(self.home)
        home_writable = home_safe and directory_writable_no_follow(self.home)
        if not home_safe:
            reasons.append(_reason(
                "defaults.home-unsafe",
                "Default application writes are unavailable",
                "The configured home root is not a real no-follow directory.",
                detail="home",
                retryable=False,
            ))
        by_desktop_id = {app["desktopId"]: app for app in applications}
        associations: list[dict[str, Any]] = []
        for ((kind, key), command), result in zip(QUERY_COMMANDS.items(), probe_results, strict=True):
            desktop_id = ""
            if isinstance(result, Exception):
                normalized = result if isinstance(result, FabricError) else _sanitized_probe_error(result)
                reasons.append(normalized)
            else:
                lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
                if len(lines) > 1 or (lines and not _valid_desktop_id(lines[0])):
                    reasons.append(_reason(
                        "defaults.probe-invalid",
                        "Default application query is invalid",
                        "The fixed xdg-mime query returned an invalid desktop identity.",
                        detail=f"{kind}:{key}",
                    ))
                elif lines:
                    desktop_id = lines[0]
            candidate_ids = sorted(
                app["id"]
                for app in applications
                if key in (app["mimeTypes"] if kind == "mime" else app["protocols"])
            )
            default_id = _application_id(desktop_id) if desktop_id else None
            if default_id is None:
                status = "unconfigured"
                source = "none"
            elif desktop_id in by_desktop_id and default_id in candidate_ids:
                status = "configured"
                source = "system"
            else:
                status = "dangling"
                source = "system"
            association = {
                "id": _association_id(kind, key),
                "kind": kind,
                "key": key,
                "defaultAppId": default_id,
                "candidateAppIds": candidate_ids,
                "writable": home_writable,
                "source": source,
                "status": status,
                "identity": "",
            }
            association["identity"] = _association_identity(association)
            associations.append(association)
        state = {
            "schemaVersion": "v0",
            "databaseId": RESOURCE_ID,
            "applications": sorted(applications, key=lambda item: item["id"]),
            "associations": sorted(associations, key=lambda item: item["id"]),
        }
        truncated = False
        while len(canonical_json(state).encode("utf-8")) > MAX_REAL_STATE_BYTES and state["applications"]:
            removed = state["applications"].pop()
            for association in state["associations"]:
                association["candidateAppIds"] = [candidate for candidate in association["candidateAppIds"] if candidate != removed["id"]]
                if association["defaultAppId"] == removed["id"]:
                    association["status"] = "dangling"
                association["identity"] = _association_identity(association)
            truncated = True
        if truncated:
            reasons.append(_reason(
                "defaults.application-inventory-truncated",
                "Application inventory is truncated",
                "The application inventory reached the Fabric value-size limit.",
                retryable=False,
                recovery=("defaults.query",),
            ))
        validate_database(state)
        reasons.append(_reason(
            "defaults.operation-read-only",
            "Default application changes require durable integration",
            "The real provider intentionally exposes inventory and change planning only.",
            recovery=("operation.integration-required",),
        ))
        return StateSnapshot("degraded", False, freeze(state), tuple(reasons))

    async def compare_and_swap(self, expected_revision: str, proposed_state: Mapping[str, Any]) -> StateSnapshot:
        raise FabricError(
            "defaults.operation-unavailable",
            "Default application operation is unavailable",
            "The real Defaults backend never changes MIME or protocol associations.",
            retryable=True,
            recovery_actions=("operation.integration-required",),
        )

    def _applications(self) -> tuple[list[dict[str, Any]], list[FabricError]]:
        roots = self._application_roots()
        applications: dict[str, dict[str, Any]] = {}
        masked: set[str] = set()
        reasons: list[FabricError] = []
        examined = 0
        truncated = False
        for source, root in roots:
            if examined >= MAX_DESKTOP_FILES:
                truncated = True
                break
            try:
                if os.name == "posix":
                    directory_fd = open_directory_path_no_follow(root)
                else:
                    root_lstat = os.lstat(root)
                    if stat.S_ISLNK(root_lstat.st_mode) or not stat.S_ISDIR(root_lstat.st_mode):
                        raise OSError("unsafe application directory")
                    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
                    directory_fd = os.open(root, flags)
                opened = os.fstat(directory_fd)
                if not stat.S_ISDIR(opened.st_mode):
                    os.close(directory_fd)
                    raise OSError("application directory identity changed")
            except FileNotFoundError:
                continue
            except OSError:
                reasons.append(_reason(
                    "defaults.application-root-unsafe",
                    "Application inventory is degraded",
                    "An application directory is not a real no-follow directory.",
                    detail=source,
                    retryable=False,
                ))
                continue
            try:
                try:
                    names = sorted(os.listdir(directory_fd))
                except OSError:
                    reasons.append(_reason(
                        "defaults.application-root-unreadable",
                        "Application inventory is degraded",
                        "An application directory could not be enumerated after its no-follow identity was established.",
                        detail=source,
                    ))
                    continue
                for name in names:
                    if examined >= MAX_DESKTOP_FILES:
                        truncated = True
                        break
                    if not _valid_desktop_id(name):
                        continue
                    if name in masked or name in applications:
                        continue
                    examined += 1
                    try:
                        descriptor = os.open(name, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0), dir_fd=directory_fd)
                        try:
                            file_stat = os.fstat(descriptor)
                            if not stat.S_ISREG(file_stat.st_mode) or file_stat.st_size > MAX_DESKTOP_BYTES:
                                continue
                            raw = _read_bounded(descriptor, MAX_DESKTOP_BYTES)
                            after = os.fstat(descriptor)
                            if (
                                file_stat.st_dev,
                                file_stat.st_ino,
                                file_stat.st_mode,
                                file_stat.st_size,
                                file_stat.st_mtime_ns,
                                file_stat.st_ctime_ns,
                            ) != (
                                after.st_dev,
                                after.st_ino,
                                after.st_mode,
                                after.st_size,
                                after.st_mtime_ns,
                                after.st_ctime_ns,
                            ):
                                raise ValueError("desktop file changed while it was read")
                        finally:
                            os.close(descriptor)
                        parsed = _parse_desktop(raw, name, source, file_stat)
                    except (OSError, UnicodeError, ValueError):
                        continue
                    if parsed == {"hidden": True}:
                        applications.pop(name, None)
                        masked.add(name)
                    elif parsed is not None:
                        applications[name] = parsed
            finally:
                os.close(directory_fd)
            if truncated:
                break
        if truncated:
            reasons.append(_reason(
                "defaults.application-inventory-truncated",
                "Application inventory is truncated",
                "The bounded desktop-file inventory reached its configured limit.",
                retryable=False,
                recovery=("defaults.query",),
            ))
        return list(applications.values()), reasons

    def _application_roots(self) -> tuple[tuple[str, Path], ...]:
        return (
            ("user", self.home / ".local" / "share" / "applications"),
            ("local", Path("/usr/local/share/applications")),
            ("system", Path("/usr/share/applications")),
        )

def _read_bounded(descriptor: int, maximum: int) -> bytes:
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = os.read(descriptor, min(16384, maximum + 1 - total))
        if not chunk:
            break
        chunks.append(chunk)
        total += len(chunk)
        if total > maximum:
            raise ValueError("desktop file exceeds bound")
    return b"".join(chunks)

def _valid_desktop_id(value: str) -> bool:
    return (
        isinstance(value, str)
        and value.isascii()
        and 9 <= len(value) <= 255
        and value.endswith(".desktop")
        and all(character.isalnum() or character in "_.+-" for character in value)
        and "/" not in value
        and "\\" not in value
    )

def _parse_desktop(raw: bytes, desktop_id: str, source: str, file_stat: os.stat_result) -> dict[str, Any] | None:
    text = raw.decode("utf-8", errors="strict")
    in_desktop = False
    values: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            in_desktop = line == "[Desktop Entry]"
            continue
        if not in_desktop or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key in {"Type", "Name", "Icon", "MimeType", "Hidden"}:
            if key in values:
                raise ValueError("duplicate desktop key")
            values[key] = value.strip()
    if values.get("Hidden", "false").lower() == "true":
        return {"hidden": True}
    if values.get("Type") != "Application" or not values.get("Name"):
        return None
    name = _safe_display_field(values["Name"], 160)
    icon = values.get("Icon", "")
    if icon and ("/" in icon or "\\" in icon):
        icon = ""
    elif icon:
        icon = _safe_display_field(icon, 255)
    declared = sorted({item for item in values.get("MimeType", "").split(";") if item})
    mime_types = sorted(item for item in declared if item in MIME_TYPES)
    protocols = sorted(item.removeprefix("x-scheme-handler/") for item in declared if item.startswith("x-scheme-handler/") and item.removeprefix("x-scheme-handler/") in PROTOCOLS)
    identity = state_revision({
        "desktopId": desktop_id,
        "source": source,
        "device": file_stat.st_dev,
        "inode": file_stat.st_ino,
        "ctimeNs": file_stat.st_ctime_ns,
        "content": state_revision(text),
    })
    return {
        "id": _application_id(desktop_id),
        "desktopId": desktop_id,
        "name": name,
        "state": "available",
        "icon": icon or None,
        "mimeTypes": mime_types,
        "protocols": protocols,
        "source": source,
        "identity": identity,
        "reason": None,
    }

def _safe_display_field(value: str, maximum: int) -> str:
    if not value or len(value) > maximum:
        raise ValueError("desktop display field is outside its bound")
    if any(unicodedata.category(character).startswith("C") for character in value):
        raise ValueError("desktop display field contains a control character")
    return value

def _directory_is_safe(path: Path) -> bool:
    try:
        if os.name == "posix":
            descriptor = open_directory_path_no_follow(path)
            os.close(descriptor)
            return True
        opened = os.lstat(path)
        return stat.S_ISDIR(opened.st_mode) and not stat.S_ISLNK(opened.st_mode)
    except (OSError, ValueError):
        return False

def _sanitized_probe_error(error: Exception) -> FabricError:
    normalized = probe_error(DOMAIN, error)
    if normalized.code == "provider.dependency-missing":
        detail = "/usr/bin/xdg-mime"
    elif normalized.code == "provider.probe-failed":
        detail = normalized.detail
    else:
        detail = type(error).__name__
    return FabricError(
        normalized.code,
        normalized.title,
        normalized.explanation,
        detail=detail,
        retryable=normalized.retryable,
        change_state=normalized.change_state,
        recovery_actions=normalized.recovery_actions,
    )

def _reason(
    code: str,
    title: str,
    explanation: str,
    *,
    detail: str = "",
    retryable: bool = True,
    recovery: tuple[str, ...] = ("provider.retry",),
) -> FabricError:
    return FabricError(code, title, explanation, detail=detail, retryable=retryable, recovery_actions=recovery)

def _metadata(action: str, snapshot: StateSnapshot) -> dict[str, Any]:
    return {
        "schemaVersion": "v0",
        "provider": PROVIDER_ID,
        "providerVersion": "v0",
        "action": action,
        "availability": availability_payload(snapshot),
        "revision": state_revision(thaw(snapshot.state)) if snapshot.state is not None else None,
    }

def _inspect(_arguments: Mapping[str, Any], snapshot: StateSnapshot) -> dict[str, Any]:
    return {**_metadata("inspect", snapshot), "state": thaw(snapshot.state) if snapshot.state is not None else None}

def _query(kind: str, key: str, action: str, snapshot: StateSnapshot) -> dict[str, Any]:
    association = None
    application = None
    if snapshot.state is not None:
        association = next((thaw(item) for item in snapshot.state["associations"] if item["kind"] == kind and item["key"] == key), None)
        if association is not None and association["defaultAppId"] is not None:
            application = next((thaw(app) for app in snapshot.state["applications"] if app["id"] == association["defaultAppId"]), None)
    return {**_metadata(action, snapshot), "association": association, "application": application}

def _mime_query(arguments: Mapping[str, Any], snapshot: StateSnapshot) -> dict[str, Any]:
    return _query("mime", arguments["mimeType"], "mime.query", snapshot)

def _protocol_query(arguments: Mapping[str, Any], snapshot: StateSnapshot) -> dict[str, Any]:
    return _query("protocol", arguments["scheme"], "protocol.query", snapshot)

def _association(state: Mapping[str, Any], *, kind: str | None = None, key: str | None = None, association_id: str | None = None) -> Mapping[str, Any]:
    matches = [
        item for item in state["associations"]
        if (association_id is not None and item["id"] == association_id)
        or (association_id is None and item["kind"] == kind and item["key"] == key)
    ]
    if len(matches) != 1:
        raise _precondition("The selected default association is unavailable.", association_id or f"{kind}:{key}")
    if not matches[0]["writable"]:
        raise _precondition("The selected default association is read-only.", matches[0]["id"])
    return matches[0]

def _application(state: Mapping[str, Any], app_id: str) -> Mapping[str, Any]:
    matches = [app for app in state["applications"] if app["id"] == app_id]
    if len(matches) != 1 or matches[0]["state"] != "available":
        raise _precondition("The selected application is unavailable.", app_id)
    return matches[0]

def _precondition(explanation: str, detail: str) -> FabricError:
    return FabricError(
        "defaults.precondition-failed",
        "Default application change cannot run",
        explanation,
        detail=detail[:160],
        retryable=True,
        recovery_actions=("defaults.inspect",),
    )

def _normalize_mime(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"mimeType": arguments["mimeType"].lower(), "appId": arguments["appId"]}

def _normalize_protocol(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"scheme": arguments["scheme"].lower(), "appId": arguments["appId"]}

def _normalize_clear(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"associationId": arguments["associationId"]}

def _set(kind: str, key_name: str):
    def propose(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
        state = deepcopy(dict(current))
        association = _association(state, kind=kind, key=arguments[key_name])
        app = _application(state, arguments["appId"])
        supported = app["mimeTypes"] if kind == "mime" else app["protocols"]
        if arguments[key_name] not in supported or app["id"] not in association["candidateAppIds"]:
            raise _precondition("The selected application does not declare support for this association.", app["id"])
        association["defaultAppId"] = app["id"]
        association["source"] = "user"
        association["status"] = "configured"
        association["identity"] = _association_identity(association)
        return state

    return propose

def _clear(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    state = deepcopy(dict(current))
    association = _association(state, association_id=arguments["associationId"])
    association["defaultAppId"] = None
    association["source"] = "none"
    association["status"] = "unconfigured"
    association["identity"] = _association_identity(association)
    return state

def _guard_target(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> tuple[Mapping[str, Any], Mapping[str, Any] | None]:
    if "mimeType" in arguments:
        association = _association(current, kind="mime", key=arguments["mimeType"])
    elif "scheme" in arguments:
        association = _association(current, kind="protocol", key=arguments["scheme"])
    else:
        association = _association(current, association_id=arguments["associationId"])
    app = _application(current, arguments["appId"]) if "appId" in arguments else None
    return association, app

def _guards(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    association, app = _guard_target(current, arguments)
    return {
        "snapshotRevision": state_revision(current),
        "associationId": association["id"],
        "associationRevision": association["identity"],
        "applicationRevision": app["identity"] if app is not None else None,
        "executor": {"mode": "typed-helper", "commandId": "defaults.apply-v0", "shell": False},
    }

def _summary(label: str):
    def summarize(current: Mapping[str, Any], proposed: Mapping[str, Any], _arguments: Mapping[str, Any]) -> str:
        if current == proposed:
            return f"The requested {label} association already matches; no change will be made."
        return f"Apply the typed {label} association after rechecking application and association revisions."

    return summarize

OPERATIONS = {
    "mime.set": OperationSpec("mime.set", _normalize_mime, _set("mime", "mimeType"), _summary("MIME"), _guards),
    "protocol.set": OperationSpec("protocol.set", _normalize_protocol, _set("protocol", "scheme"), _summary("protocol"), _guards),
    "association.clear": OperationSpec("association.clear", _normalize_clear, _clear, _summary("default"), _guards),
}

READ_HANDLERS = {"inspect": _inspect, "mime.query": _mime_query, "protocol.query": _protocol_query}

def _manifest() -> Mapping[str, Any]:
    return _load_json(Path(__file__).with_name("manifest-v0.json"), 128 * 1024)

def _provider(backend: Any) -> StateDomainProvider:
    return StateDomainProvider(
        domain=DOMAIN,
        provider_id=PROVIDER_ID,
        resource_kind=RESOURCE_KIND,
        resource_id=RESOURCE_ID,
        manifest=_manifest(),
        schemas=SCHEMAS,
        backend=backend,
        state_contract_id=STATE_CONTRACT_ID,
        state_validator=validate_database,
        read_handlers=READ_HANDLERS,
        operations=OPERATIONS,
    )

def build_provider(
    *,
    home: Path | None = None,
    config_path: Path | None = None,
    runner: ProbeRunner = run_probe,
) -> StateDomainProvider:
    if home is None:
        home = Path.home()
    if config_path is None:
        omarchy_path = os.environ.get("OMARCHY_PATH")
        if not omarchy_path:
            raise FabricError(
                "defaults.config-unavailable",
                "Default application configuration is unavailable",
                "OMARCHY_PATH is not present in the user session environment.",
                recovery_actions=("session.restart",),
            )
        config_path = Path(omarchy_path) / "default" / "ultimate" / "files" / "default-associations-v0.json"
    return _provider(RealDefaultsBackend(home, config_path, runner))

def build_fake_provider(
    state: Mapping[str, Any],
    *,
    state_path: Path | None = None,
    fail_on: frozenset[str] = frozenset(),
) -> StateDomainProvider:
    normalized = canonicalize_database(state)
    backend = FakeStateBackend(
        DOMAIN,
        normalized,
        validate_database,
        state_path=state_path,
        fail_on=fail_on,
    )
    return _provider(backend)
