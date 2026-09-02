"""Typed Files, This PC, Desktop, Trash, mount, recent, and search provider."""

from __future__ import annotations

import asyncio
import hashlib
import json
import mimetypes
import os
import stat
import unicodedata
import xml.etree.ElementTree as ET
from copy import deepcopy
from pathlib import Path
from typing import Any, Mapping
from urllib.parse import unquote, urlparse

from jsonschema import Draft202012Validator

from omarchy_fabric.models import FabricError

from .._engine import canonical_json, state_revision
from .._identity import stable_resource_id
from .._immutable import freeze, thaw
from ._engine import (
    FakeStateBackend,
    OperationSpec,
    StateDomainProvider,
    StateSnapshot,
    availability_payload,
    directory_writable_no_follow,
    open_directory_path_no_follow,
    read_regular_file_no_follow,
)

DOMAIN = "files"
PROVIDER_ID = "files.provider"
RESOURCE_KIND = "files.workspace"
RESOURCE_ID = "files.workspace.primary"
STATE_CONTRACT_ID = "urn:omarchy:fabric:provider:files:operation-state:v0"
MAX_CONFIG_BYTES = 32 * 1024
MAX_MOUNTINFO_BYTES = 256 * 1024
MAX_RECENT_BYTES = 1024 * 1024
MAX_REAL_STATE_BYTES = 36 * 1024

LOCATION_CATALOG = {
    "this-pc": ("this-pc", "virtual", True),
    "home": ("home", "home", True),
    "desktop": ("desktop", "xdg-desktop", False),
    "documents": ("documents", "xdg-documents", False),
    "downloads": ("downloads", "xdg-download", False),
    "pictures": ("pictures", "xdg-pictures", False),
    "trash": ("trash", "freedesktop-trash", False),
}

SCAN_PRIORITY = {
    "this-pc": 0,
    "pictures": 1,
    "desktop": 2,
    "documents": 3,
    "downloads": 4,
    "trash": 5,
    "home": 6,
}
HOME_LOCATION_ID = "files.location.home"
PLACE_LOCATION_IDS = frozenset({
    HOME_LOCATION_ID,
    "files.location.desktop",
    "files.location.documents",
    "files.location.downloads",
    "files.location.pictures",
})
LOCATION_ENTRY_FLOOR = 8
READ_COMPLETENESS_CODES = frozenset({
    "files.inventory-truncated",
    "files.mount-inventory-truncated",
})

SCHEMA_FILES = (
    "files-empty-arguments-v0.json",
    "files-browse-arguments-v0.json",
    "files-search-arguments-v0.json",
    "files-recent-arguments-v0.json",
    "files-create-directory-arguments-v0.json",
    "files-rename-arguments-v0.json",
    "files-entry-arguments-v0.json",
    "files-mount-arguments-v0.json",
    "files-inventory-result-v0.json",
    "files-query-result-v0.json",
    "files-operation-state-v0.json",
    "files-operation-preflight-v0.json",
    "files-operation-result-v0.json",
    "files-directory-state-v1.json",
    "files-directory-preflight-v1.json",
    "files-directory-result-v1.json",
    "files-directory-read-v1.json",
    "files-directory-arguments-v1.json",
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

def _validate_workspace_schema(state: Mapping[str, Any]) -> None:
    wrapper = {"resourceId": RESOURCE_ID, "revision": state_revision(state), "value": thaw(state)}
    error = next(iter(STATE_VALIDATOR.iter_errors(wrapper)), None)
    if error is not None:
        path = ".".join(str(part) for part in error.absolute_path)
        raise ValueError(f"workspace schema invalid at {path or '<root>'}")

def normalize_relative_path(value: str, *, allow_empty: bool) -> str:
    if not isinstance(value, str):
        raise ValueError("relative path must be a string")
    normalized = unicodedata.normalize("NFC", value)
    if not normalized and allow_empty:
        return ""
    if not normalized or len(normalized) > 1024:
        raise ValueError("relative path length is invalid")
    if normalized.startswith("/") or normalized.endswith("/") or "\\" in normalized or "\x00" in normalized:
        raise ValueError("path must be a canonical location-relative path")
    parts = normalized.split("/")
    if any(
        not part
        or part in {".", ".."}
        or len(part) > 255
        or any(
            ord(character) < 32
            or ord(character) == 127
            or unicodedata.category(character) in {"Cc", "Cf", "Cs"}
            for character in part
        )
        for part in parts
    ):
        raise ValueError("path contains a forbidden segment")
    return normalized

def normalize_name(value: str) -> str:
    normalized = normalize_relative_path(value, allow_empty=False)
    if "/" in normalized:
        raise ValueError("name must contain exactly one path segment")
    return normalized

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

def validate_workspace(state: Mapping[str, Any]) -> None:
    _validate_workspace_schema(state)
    locations = state["locations"]
    entries = state["entries"]
    mounts = state["mounts"]
    recent = state["recent"]
    for collection, label in ((locations, "location"), (entries, "entry"), (mounts, "mount")):
        identifiers = [item["id"] for item in collection]
        if len(identifiers) != len(set(identifiers)):
            raise ValueError(f"duplicate {label} identity")
    location_by_id = {location["id"]: location for location in locations}
    for location in locations:
        if location["state"] == "available" and location["reason"] is not None:
            raise ValueError("available location carries a degradation reason")
        if location["state"] != "available" and location["reason"] is None:
            raise ValueError("degraded location has no typed reason")
        if location["state"] == "unavailable" and location["writable"]:
            raise ValueError("unavailable location is falsely writable")
    entry_by_id = {entry["id"]: entry for entry in entries}
    path_keys: set[tuple[str, str]] = set()
    for entry in entries:
        if entry["locationId"] not in location_by_id:
            raise ValueError("entry references an unknown location")
        if normalize_relative_path(entry["relativePath"], allow_empty=False) != entry["relativePath"]:
            raise ValueError("entry path is not canonical")
        if normalize_name(entry["name"]) != entry["name"]:
            raise ValueError("entry name is not canonical")
        if entry["relativePath"].rsplit("/", 1)[-1] != entry["name"]:
            raise ValueError("entry name does not match its path")
        key = (entry["locationId"], entry["relativePath"])
        if key in path_keys:
            raise ValueError("duplicate entry path")
        path_keys.add(key)
        parent_id = entry["parentId"]
        if parent_id is None and "/" in entry["relativePath"]:
            raise ValueError("descendant entry is missing its parent identity")
        if parent_id is not None:
            parent = entry_by_id.get(parent_id)
            if parent is None or parent["kind"] != "directory" or parent["locationId"] != entry["locationId"]:
                raise ValueError("entry parent is unavailable or unsafe")
            if entry["relativePath"].rsplit("/", 1)[0] != parent["relativePath"]:
                raise ValueError("entry parent path is inconsistent")
        if entry["kind"] == "symlink" and any(candidate["parentId"] == entry["id"] for candidate in entries):
            raise ValueError("symlink cannot anchor descendants")
        if entry["kind"] == "symlink":
            if entry["symlinkTargetState"] is None or entry["writable"]:
                raise ValueError("symlink entry is falsely writable or lacks target state")
        elif entry["symlinkTargetState"] is not None:
            raise ValueError("non-symlink entry carries symlink target state")
        if entry["kind"] != "file" and entry["sizeBytes"] is not None:
            raise ValueError("non-file entry carries a file size")
        trash = entry["trash"]
        if trash is not None:
            if location_by_id[entry["locationId"]]["kind"] != "trash":
                raise ValueError("Trash metadata appears outside the Trash location")
            if trash["originalLocationId"] not in location_by_id or location_by_id[trash["originalLocationId"]]["kind"] == "trash":
                raise ValueError("Trash metadata has no safe original location")
            if normalize_relative_path(trash["originalRelativePath"], allow_empty=False) != trash["originalRelativePath"]:
                raise ValueError("Trash recovery path is not canonical")
            original_parent_id = trash["originalParentId"]
            if original_parent_id is None and "/" in trash["originalRelativePath"]:
                raise ValueError("Trash recovery path is orphaned")
            if original_parent_id is not None:
                original_parent = entry_by_id.get(original_parent_id)
                if original_parent is None or original_parent["kind"] != "directory":
                    raise ValueError("Trash recovery parent is unavailable")
        seen: set[str] = set()
        cursor = entry
        while cursor["parentId"] is not None:
            if cursor["id"] in seen:
                raise ValueError("entry parent graph contains a cycle")
            seen.add(cursor["id"])
            cursor = entry_by_id[cursor["parentId"]]
    for mount in mounts:
        if mount["locationId"] is not None and mount["locationId"] not in location_by_id:
            raise ValueError("mount references an unknown location")
        source = mount["source"]
        if mount["kind"] == "system":
            if mount["locationId"] is not None or source["scheme"] != "system" or source["host"] is not None or source["share"] is not None:
                raise ValueError("system mount authority is inconsistent")
        elif mount["kind"] == "removable":
            if mount["locationId"] is None or source["scheme"] != "device" or source["host"] is not None or source["share"] is not None:
                raise ValueError("removable mount authority is inconsistent")
        elif mount["kind"] == "smb":
            if mount["locationId"] is None or source["scheme"] != "smb" or source["host"] is None or source["share"] is None:
                raise ValueError("SMB mount authority is inconsistent")
        if mount["locationId"] is not None:
            location = location_by_id[mount["locationId"]]
            expected_kind = "network" if mount["kind"] == "smb" else "mount"
            if location["kind"] != expected_kind:
                raise ValueError("mount location kind is inconsistent")
            if mount["state"] == "unmounted" and (location["state"] != "unavailable" or location["writable"]):
                raise ValueError("unmounted location remains falsely available")
    if len({item["rank"] for item in recent}) != len(recent):
        raise ValueError("recent ranks must be unique")
    if any(item["entryId"] not in entry_by_id for item in recent):
        raise ValueError("recent item references an unknown entry")

def canonicalize_workspace(state: Mapping[str, Any]) -> dict[str, Any]:
    normalized = deepcopy(dict(state))
    normalized["locations"] = sorted(normalized["locations"], key=lambda item: item["id"])
    normalized["entries"] = sorted(normalized["entries"], key=lambda item: item["id"])
    normalized["mounts"] = sorted(normalized["mounts"], key=lambda item: item["id"])
    normalized["recent"] = sorted(normalized["recent"], key=lambda item: (item["rank"], item["entryId"]))
    validate_workspace(normalized)
    return normalized

class RealFilesBackend:
    """Bounded no-follow host inventory; this adapter never mutates the host."""

    def __init__(self, home: Path, config_path: Path, *, session_operable: bool = False) -> None:
        self.session_operable = session_operable
        self.home = Path(home)
        self.config_path = Path(config_path)
        if not self.home.is_absolute() or not self.config_path.is_absolute():
            raise ValueError("files provider paths must be absolute")
        try:
            config_stat = os.lstat(self.config_path)
        except OSError as error:
            raise ValueError("files location config is unavailable") from error
        if stat.S_ISLNK(config_stat.st_mode) or not stat.S_ISREG(config_stat.st_mode):
            raise ValueError("files location config must be a real file")
        try:
            self.config = self._validate_config(_load_json(self.config_path))
        except OSError as error:
            raise ValueError("files location config cannot be opened through the no-follow boundary") from error

    @staticmethod
    def _validate_config(document: Mapping[str, Any]) -> dict[str, Any]:
        if set(document) != {"schemaVersion", "locations", "limits"} or document["schemaVersion"] != "v0":
            raise ValueError("files location config envelope is invalid")
        if not isinstance(document["locations"], list) or not isinstance(document["limits"], dict):
            raise ValueError("files location config shape is invalid")
        if set(document["limits"]) != {"entries", "mounts", "recent", "depth"}:
            raise ValueError("files location limits are invalid")
        limits = document["limits"]
        if not (
            isinstance(limits["entries"], int) and not isinstance(limits["entries"], bool) and 1 <= limits["entries"] <= 256
            and isinstance(limits["mounts"], int) and not isinstance(limits["mounts"], bool) and 1 <= limits["mounts"] <= 64
            and isinstance(limits["recent"], int) and not isinstance(limits["recent"], bool) and 1 <= limits["recent"] <= 128
            and isinstance(limits["depth"], int) and not isinstance(limits["depth"], bool) and 1 <= limits["depth"] <= 3
        ):
            raise ValueError("files location limits are out of bounds")
        keys: set[str] = set()
        for location in document["locations"]:
            if not isinstance(location, dict) or set(location) != {"key", "kind", "label", "source", "required"}:
                raise ValueError("files location definition is invalid")
            if not all(isinstance(location[key], str) and location[key] for key in ("key", "kind", "label", "source")):
                raise ValueError("files location identity is invalid")
            if location["key"] in keys:
                raise ValueError("files location identity is invalid")
            if not isinstance(location["required"], bool):
                raise ValueError("files location required flag is invalid")
            expected = LOCATION_CATALOG.get(location["key"])
            if expected != (location["kind"], location["source"], location["required"]):
                raise ValueError("files location authority does not match the code-owned catalog")
            if len(location["label"]) > 160 or any(unicodedata.category(character).startswith("C") for character in location["label"]):
                raise ValueError("files location label is invalid")
            keys.add(location["key"])
        if keys != set(LOCATION_CATALOG):
            raise ValueError("files location catalog is incomplete")
        return deepcopy(dict(document))

    async def snapshot(self) -> StateSnapshot:
        return await asyncio.to_thread(self._snapshot_sync)

    async def compare_and_swap(self, expected_revision: str, proposed_state: Mapping[str, Any]) -> StateSnapshot:
        raise FabricError(
            "files.operation-unavailable",
            "Files operation is unavailable",
            "The real Files backend is a no-follow read adapter and never mutates host state.",
            retryable=True,
            recovery_actions=("operation.integration-required",),
        )

    def _snapshot_sync(self) -> StateSnapshot:
        reasons: list[FabricError] = []
        try:
            if os.name == "posix":
                home_fd = open_directory_path_no_follow(self.home)
                try:
                    home_stat = os.fstat(home_fd)
                finally:
                    os.close(home_fd)
            else:
                home_stat = os.lstat(self.home)
        except FileNotFoundError:
            return StateSnapshot(
                "unavailable",
                False,
                None,
                    (_reason("files.home-unavailable", "Home is unavailable", "The user home directory cannot be inspected without following links.", detail="home"),),
            )
        except (OSError, ValueError):
            return StateSnapshot(
                "unavailable",
                False,
                None,
                    (_reason("files.home-unsafe", "Home is unsafe to inspect", "The configured home root is not a real directory.", detail="home", retryable=False),),
            )
        if stat.S_ISLNK(home_stat.st_mode) or not stat.S_ISDIR(home_stat.st_mode):
            return StateSnapshot(
                "unavailable",
                False,
                None,
                (_reason("files.home-unsafe", "Home is unsafe to inspect", "The configured home root is not a real directory.", detail="home", retryable=False),),
            )
        user_dirs = self._user_dirs(reasons)
        roots = self._root_paths(user_dirs)
        locations: list[dict[str, Any]] = []
        entries: list[dict[str, Any]] = []
        path_to_entry: dict[str, str] = {}
        limits = self.config["limits"]
        truncated = False
        scan_order = sorted(
            self.config["locations"],
            key=lambda item: (SCAN_PRIORITY.get(item["key"], 50), item["key"]),
        )
        remaining_place_scans = sum(
            1 for item in scan_order if f"files.location.{item['key']}" in PLACE_LOCATION_IDS
        )
        for definition in scan_order:
            location_id = f"files.location.{definition['key']}"
            if definition["source"] == "virtual":
                locations.append({
                    "id": location_id,
                    "kind": definition["kind"],
                    "label": definition["label"],
                    "state": "available",
                    "writable": False,
                    "rootDigest": state_revision({"virtual": definition["key"], "version": "v0"}),
                    "reason": None,
                })
                continue
            reserved = 0
            if location_id in PLACE_LOCATION_IDS:
                remaining_place_scans -= 1
                reserved = LOCATION_ENTRY_FLOOR * remaining_place_scans
            root = roots.get(definition["source"])
            location, scanned, mapping, was_truncated = self._scan_location(
                location_id,
                definition,
                root,
                maximum=max(
                    LOCATION_ENTRY_FLOOR if location_id in PLACE_LOCATION_IDS else 0,
                    limits["entries"] - len(entries) - reserved,
                ),
                depth=limits["depth"],
            )
            locations.append(location)
            entries.extend(scanned)
            path_to_entry.update(mapping)
            truncated = truncated or was_truncated
            if location["reason"] is not None and location["reason"]["code"] != "files.location-absent":
                reasons.append(FabricError(**_fabric_error_kwargs(location["reason"])))
        if truncated:
            reasons.append(_reason(
                "files.inventory-truncated",
                "Files inventory is truncated",
                "The bounded inventory reached its configured entry limit.",
                retryable=False,
                recovery=("files.search.narrow",),
            ))
        mounts, mount_locations, mount_reasons = self._mounts(limits["mounts"])
        locations.extend(mount_locations)
        reasons.extend(mount_reasons)
        recent, recent_reasons = self._recent(path_to_entry, limits["recent"])
        reasons.extend(recent_reasons)
        state = {
            "schemaVersion": "v0",
            "workspaceId": RESOURCE_ID,
            "locations": sorted(locations, key=lambda item: item["id"]),
            "entries": sorted(entries, key=lambda item: item["id"]),
            "mounts": sorted(mounts, key=lambda item: item["id"]),
            "recent": recent,
        }
        while len(canonical_json(state).encode("utf-8")) > MAX_REAL_STATE_BYTES and state["entries"]:
            parent_ids = {entry["parentId"] for entry in state["entries"] if entry["parentId"] is not None}
            removable_index = _evictable_leaf_index(state["entries"], parent_ids)
            removed = state["entries"].pop(removable_index)
            state["recent"] = [item for item in state["recent"] if item["entryId"] != removed["id"]]
            truncated = True
        mount_state_truncated = False
        while len(canonical_json(state).encode("utf-8")) > MAX_REAL_STATE_BYTES and state["mounts"]:
            removed_mount = state["mounts"].pop()
            removed_location_id = removed_mount["locationId"]
            if removed_location_id is not None:
                state["locations"] = [location for location in state["locations"] if location["id"] != removed_location_id]
                removed_entry_ids = {
                    entry["id"]
                    for entry in state["entries"]
                    if entry["locationId"] == removed_location_id
                }
                state["entries"] = [entry for entry in state["entries"] if entry["locationId"] != removed_location_id]
                state["recent"] = [item for item in state["recent"] if item["entryId"] not in removed_entry_ids]
            mount_state_truncated = True
        if mount_state_truncated and not any(reason.code == "files.mount-inventory-truncated" for reason in reasons):
            reasons.append(_reason(
                "files.mount-inventory-truncated",
                "Mount inventory is truncated",
                "Mount records were trimmed to preserve the Fabric value-size bound.",
                retryable=False,
            ))
        for rank, item in enumerate(sorted(state["recent"], key=lambda value: value["rank"])):
            item["rank"] = rank
        if truncated and not any(reason.code == "files.inventory-truncated" for reason in reasons):
            reasons.append(_reason(
                "files.inventory-truncated",
                "Files inventory is truncated",
                "The bounded inventory reached the Fabric value-size limit.",
                retryable=False,
                recovery=("files.search.narrow",),
            ))
        if len(canonical_json(state).encode("utf-8")) > MAX_REAL_STATE_BYTES:
            return StateSnapshot(
                "unavailable",
                False,
                None,
                (_reason(
                    "files.inventory-overflow",
                    "Files inventory exceeds its safe bound",
                    "Required workspace metadata alone exceeds the Fabric value-size limit.",
                    retryable=False,
                    recovery=("files.config.repair",),
                ),),
            )
        validate_workspace(state)
        if not self.session_operable:
            reasons.append(_reason(
                "files.operation-read-only",
                "Files mutations require durable integration",
                "The real provider intentionally exposes inventory only.",
                recovery=("operation.integration-required",),
            ))
        if self.session_operable and not reasons:
            return StateSnapshot("available", True, freeze(state), ())
        operable = self.session_operable and all(
            reason.code in READ_COMPLETENESS_CODES for reason in reasons
        )
        return StateSnapshot(
            "degraded",
            operable,
            freeze(state),
            tuple(reasons),
        )

    def _user_dirs(self, reasons: list[FabricError]) -> dict[str, Path]:
        path = self.home / ".config" / "user-dirs.dirs"
        try:
            raw = read_regular_file_no_follow(path, 64 * 1024)
            result: dict[str, Path] = {}
            for line in raw.decode("utf-8", errors="strict").splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, raw_value = line.split("=", 1)
                if key not in {"XDG_DESKTOP_DIR", "XDG_DOCUMENTS_DIR", "XDG_DOWNLOAD_DIR", "XDG_PICTURES_DIR"}:
                    continue
                if len(raw_value) < 2 or raw_value[0] != '"' or raw_value[-1] != '"':
                    raise ValueError("user dirs value is not a quoted literal")
                value = _unescape_xdg_value(raw_value[1:-1])
                if value in {"$HOME", "$HOME/"}:
                    candidate = self.home
                elif value.startswith("$HOME/"):
                    relative = normalize_relative_path(value[6:], allow_empty=False)
                    candidate = self.home.joinpath(*relative.split("/"))
                elif value.startswith("/"):
                    relative = normalize_relative_path(value[1:], allow_empty=True)
                    candidate = Path("/") if not relative else Path("/").joinpath(*relative.split("/"))
                else:
                    raise ValueError("user dirs value is outside the supported literal forms")
                result[key] = candidate
            return result
        except FileNotFoundError:
            return {}
        except (OSError, UnicodeError, ValueError):
            reasons.append(_reason(
                "files.user-dirs-invalid",
                "User folders are degraded",
                "The XDG user-directory file is malformed or outside the bounded contract.",
                detail="user-dirs.dirs",
                retryable=False,
                recovery=("files.user-dirs.repair",),
            ))
            return {}

    def directory_listing(self, location_id: str, parent: str) -> list[str] | None:
        key = location_id.rsplit(".", 1)[-1]
        definition = LOCATION_CATALOG.get(key)
        if definition is None or not definition[2] and key not in {"desktop", "documents", "downloads", "pictures"}:
            return None
        reasons: list[FabricError] = []
        root = self._root_paths(self._user_dirs(reasons)).get(definition[1])
        if root is None:
            return None
        target = root
        if parent:
            for segment in parent.split("/"):
                if segment in {"", ".", ".."}:
                    return None
                target = target / segment
        try:
            with os.scandir(target) as scan:
                names = sorted(item.name for item in scan)
        except OSError:
            return None
        if len(names) > 4096:
            return None
        return names

    def _root_paths(self, user_dirs: Mapping[str, Path]) -> dict[str, Path]:
        return {
            "home": self.home,
            "xdg-desktop": user_dirs.get("XDG_DESKTOP_DIR", self.home / "Desktop"),
            "xdg-documents": user_dirs.get("XDG_DOCUMENTS_DIR", self.home / "Documents"),
            "xdg-download": user_dirs.get("XDG_DOWNLOAD_DIR", self.home / "Downloads"),
            "xdg-pictures": user_dirs.get("XDG_PICTURES_DIR", self.home / "Pictures"),
            "freedesktop-trash": self.home / ".local" / "share" / "Trash" / "files",
        }

    def _scan_location(
        self,
        location_id: str,
        definition: Mapping[str, Any],
        root: Path | None,
        *,
        maximum: int,
        depth: int,
    ) -> tuple[dict[str, Any], list[dict[str, Any]], dict[str, str], bool]:
        unavailable = _reason(
            "files.location-unavailable",
            f"{definition['label']} is unavailable",
            "The location root cannot be opened as a real no-follow directory.",
            detail=location_id,
        )
        if root is None:
            return _location_unavailable(location_id, definition, unavailable), [], {}, False
        try:
            if os.name != "posix":
                root_lstat = os.lstat(root)
                if stat.S_ISLNK(root_lstat.st_mode) or not stat.S_ISDIR(root_lstat.st_mode):
                    raise OSError("unsafe root")
                flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
                root_fd = os.open(root, flags)
            else:
                root_fd = open_directory_path_no_follow(root)
            opened = os.fstat(root_fd)
        except FileNotFoundError:
            absent = _reason(
                "files.location-absent" if not definition["required"] else "files.location-unavailable",
                f"{definition['label']} is unavailable",
                (
                    f"{definition['label']} has not been created on this host."
                    if not definition["required"]
                    else "The location root cannot be opened as a real no-follow directory."
                ),
                detail=location_id,
                retryable=False,
            )
            return _location_unavailable(location_id, definition, absent), [], {}, False
        except (OSError, ValueError):
            return _location_unavailable(location_id, definition, unavailable), [], {}, False
        root_identity = state_revision({"device": opened.st_dev, "inode": opened.st_ino, "ctimeNs": opened.st_ctime_ns})
        location = {
            "id": location_id,
            "kind": definition["kind"],
            "label": definition["label"],
            "state": "available",
            "writable": directory_writable_no_follow(root),
            "rootDigest": root_identity,
            "reason": None,
        }
        entries: list[dict[str, Any]] = []
        mapping: dict[str, str] = {}
        truncated = False
        scan_degraded = False

        def scan(fd: int, relative_parent: str, parent_id: str | None, remaining_depth: int) -> None:
            nonlocal scan_degraded, truncated
            if remaining_depth <= 0 or truncated:
                return
            try:
                names = sorted(os.listdir(fd))
            except OSError:
                scan_degraded = True
                return
            for name in names:
                if len(entries) >= maximum:
                    truncated = True
                    return
                try:
                    canonical_name = normalize_name(name)
                    relative = canonical_name if not relative_parent else f"{relative_parent}/{canonical_name}"
                    entry_lstat = os.stat(name, dir_fd=fd, follow_symlinks=False)
                except (OSError, ValueError, UnicodeError):
                    scan_degraded = True
                    continue
                if stat.S_ISDIR(entry_lstat.st_mode):
                    kind = "directory"
                elif stat.S_ISREG(entry_lstat.st_mode):
                    kind = "file"
                elif stat.S_ISLNK(entry_lstat.st_mode):
                    kind = "symlink"
                else:
                    continue
                entry_id = stable_resource_id(DOMAIN, "entry", f"{location_id}\0{entry_lstat.st_dev}\0{entry_lstat.st_ino}\0{relative}")
                identity = state_revision({
                    "device": entry_lstat.st_dev,
                    "inode": entry_lstat.st_ino,
                    "mode": stat.S_IFMT(entry_lstat.st_mode),
                    "ctimeNs": entry_lstat.st_ctime_ns,
                })
                mime_type = mimetypes.guess_type(canonical_name, strict=False)[0] if kind == "file" else None
                entries.append({
                    "id": entry_id,
                    "locationId": location_id,
                    "parentId": parent_id,
                    "name": canonical_name,
                    "relativePath": relative,
                    "kind": kind,
                    "sizeBytes": min(entry_lstat.st_size, 9007199254740991) if kind == "file" else None,
                    "modifiedMs": min(entry_lstat.st_mtime_ns // 1000000, 9007199254740991),
                    "mimeType": mime_type.lower() if mime_type else None,
                    "hidden": canonical_name.startswith("."),
                    "writable": kind != "symlink" and bool(entry_lstat.st_mode & stat.S_IWUSR),
                    "identity": identity,
                    "symlinkTargetState": "unknown" if kind == "symlink" else None,
                    "trash": None,
                })
                mapping[os.fspath(root / Path(*relative.split("/")))] = entry_id
                if kind == "directory" and remaining_depth > 1:
                    child_fd = None
                    try:
                        flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
                        child_fd = os.open(name, flags, dir_fd=fd)
                        child_stat = os.fstat(child_fd)
                        if (child_stat.st_dev, child_stat.st_ino) != (entry_lstat.st_dev, entry_lstat.st_ino):
                            raise OSError("directory identity changed")
                        scan(child_fd, relative, entry_id, remaining_depth - 1)
                    except OSError:
                        scan_degraded = True
                    finally:
                        if child_fd is not None:
                            os.close(child_fd)

        try:
            scan(root_fd, "", None, depth)
        finally:
            os.close(root_fd)
        if scan_degraded:
            partial = _reason(
                "files.location-partial",
                f"{definition['label']} inventory is partial",
                "One or more entries changed identity or could not be opened through the no-follow directory boundary.",
                detail=location_id,
                retryable=True,
            )
            location["state"] = "degraded"
            location["writable"] = False
            location["reason"] = partial.to_dict()
        return location, entries, mapping, truncated

    def _mounts(self, maximum: int) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[FabricError]]:
        mountinfo = Path("/proc/self/mountinfo")
        try:
            raw = mountinfo.read_bytes()
            if len(raw) > MAX_MOUNTINFO_BYTES:
                raise ValueError("mountinfo exceeds 256 KiB")
            lines = raw.decode("utf-8", errors="strict").splitlines()
        except (OSError, UnicodeError, ValueError):
            return [], [], [_reason("files.mount-inventory-unavailable", "Mount inventory is unavailable", "The bounded procfs mount inventory could not be read.")]
        mounts: list[dict[str, Any]] = []
        locations: list[dict[str, Any]] = []
        reasons: list[FabricError] = []
        browse_deferred = False
        invalid_smb = False
        for line in lines:
            fields = line.split()
            try:
                separator = fields.index("-")
                mount_point = _unescape_mount_field(fields[4])
                options = fields[5].split(",")
                filesystem = fields[separator + 1]
                source = _unescape_mount_field(fields[separator + 2])
            except (ValueError, IndexError):
                continue
            if (
                len(mount_point) > 4096
                or len(source) > 4096
                or len(filesystem) > 64
                or any(ord(character) < 32 or ord(character) == 127 for character in mount_point + source)
            ):
                continue
            home_text = os.fspath(self.home)
            username = self.home.name
            removable = mount_point.startswith(f"/run/media/{username}/") or mount_point.startswith(f"/media/{username}/")
            smb = filesystem in {"cifs", "smb3"}
            relevant = mount_point == "/" or mount_point == home_text or mount_point.startswith(f"{home_text}/") or mount_point.startswith("/mnt/") or removable or smb
            if not relevant:
                continue
            kind = "smb" if smb else "removable" if removable else "system"
            host = None
            share = None
            scheme = "smb" if smb else "device" if removable else "system"
            display = "Removable device" if removable else "System mount"
            identity_source = source
            if smb:
                parsed_source = _safe_smb_source(source)
                if parsed_source is None:
                    invalid_smb = True
                    continue
                host, share = parsed_source
                display = f"//{host}/{share}"
                identity_source = display
            if len(mounts) >= maximum:
                reasons.append(_reason("files.mount-inventory-truncated", "Mount inventory is truncated", "The mount inventory reached its configured bound.", retryable=False))
                break
            mount_id = stable_resource_id(DOMAIN, "mount", f"{identity_source}\0{mount_point}")
            location_id = stable_resource_id(DOMAIN, "location", f"mount\0{identity_source}\0{mount_point}") if kind != "system" else None
            mounts.append({
                "id": mount_id,
                "kind": kind,
                "label": _safe_mount_label(mount_point, kind),
                "state": "mounted",
                "writable": "rw" in options,
                "locationId": location_id,
                "source": {"scheme": scheme, "display": display[:320], "host": host, "share": share},
                "reason": None,
            })
            if location_id is not None:
                browse_reason = _reason(
                    "files.mount-browse-deferred",
                    "Mounted location browsing is deferred",
                    "The bounded startup inventory does not traverse removable or network roots.",
                    detail=mount_id,
                    retryable=False,
                    recovery=("files.browse",),
                )
                locations.append({
                    "id": location_id,
                    "kind": "network" if smb else "mount",
                    "label": _safe_mount_label(mount_point, kind),
                    "state": "degraded",
                    "writable": "rw" in options,
                    "rootDigest": state_revision({"mountId": mount_id, "mountPoint": mount_point}),
                    "reason": browse_reason.to_dict(),
                })
                browse_deferred = True
        if invalid_smb:
            reasons.append(_reason(
                "files.mount-source-invalid",
                "Network mount authority is invalid",
                "At least one kernel-reported SMB mount has no safe host and share identity.",
                retryable=False,
            ))
        if browse_deferred:
            reasons.append(_reason(
                "files.mount-browse-deferred",
                "Mounted location browsing is deferred",
                "Bounded startup inventory does not traverse removable or network roots.",
                retryable=False,
                recovery=("files.browse",),
            ))
        return mounts, locations, reasons

    def _recent(self, path_to_entry: Mapping[str, str], maximum: int) -> tuple[list[dict[str, Any]], list[FabricError]]:
        path = self.home / ".local" / "share" / "recently-used.xbel"
        try:
            raw = read_regular_file_no_follow(path, MAX_RECENT_BYTES)
            if b"<!DOCTYPE" in raw.upper() or b"<!ENTITY" in raw.upper():
                raise ValueError("recent document violates the bounded XML contract")
            root = ET.fromstring(raw)
            entry_ids: list[str] = []
            for bookmark in root.iter():
                if not bookmark.tag.endswith("bookmark"):
                    continue
                href = bookmark.attrib.get("href", "")
                parsed = urlparse(href)
                if parsed.scheme != "file" or parsed.netloc not in {"", "localhost"}:
                    continue
                candidate = unquote(parsed.path)
                entry_id = path_to_entry.get(candidate)
                if entry_id is not None and entry_id not in entry_ids:
                    entry_ids.append(entry_id)
                if len(entry_ids) >= maximum:
                    break
            return [{"entryId": entry_id, "rank": rank} for rank, entry_id in enumerate(entry_ids)], []
        except FileNotFoundError:
            return [], []
        except (OSError, UnicodeError, ValueError, ET.ParseError):
            return [], [_reason(
                "files.recent-invalid",
                "Recent files are degraded",
                "The recent-files document is malformed or exceeds its bounded XML contract.",
                detail="recently-used.xbel",
                retryable=False,
                recovery=("files.recent.clear",),
            )]

def _fabric_error_kwargs(document: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "code": document["code"],
        "title": document["title"],
        "explanation": document["explanation"],
        "detail": document["detail"],
        "retryable": document["retryable"],
        "change_state": document["changeState"],
        "recovery_actions": tuple(document.get("recoveryActions", ())),
    }

def _location_unavailable(
    location_id: str,
    definition: Mapping[str, Any],
    reason: FabricError,
) -> dict[str, Any]:
    return {
        "id": location_id,
        "kind": definition["kind"],
        "label": definition["label"],
        "state": "unavailable",
        "writable": False,
        "rootDigest": state_revision({"unavailable": location_id, "version": "v0"}),
        "reason": reason.to_dict(),
    }

def _unescape_mount_field(value: str) -> str:
    return value.replace("\\040", " ").replace("\\011", "\t").replace("\\012", "\n").replace("\\134", "\\")

def _safe_smb_source(source: str) -> tuple[str, str] | None:
    if not source.startswith("//"):
        return None
    parts = source[2:].split("/")
    if len(parts) < 2 or not parts[0] or not parts[1]:
        return None
    authority = parts[0].rsplit("@", 1)[-1]
    share = parts[1]
    if not (
        1 <= len(authority) <= 253
        and 1 <= len(share) <= 255
        and all(character.isascii() and (character.isalnum() or character in ".:-[]_") for character in authority)
        and all(not unicodedata.category(character).startswith("C") and character not in "/\\" for character in share)
    ):
        return None
    return authority, share

def _safe_mount_label(mount_point: str, kind: str) -> str:
    candidate = Path(mount_point).name
    if candidate and len(candidate) <= 160 and not any(unicodedata.category(character).startswith("C") for character in candidate):
        return candidate
    return "Network mount" if kind == "smb" else "Removable device" if kind == "removable" else "System"

def _unescape_xdg_value(value: str) -> str:
    result: list[str] = []
    index = 0
    while index < len(value):
        character = value[index]
        if character != "\\":
            result.append(character)
            index += 1
            continue
        index += 1
        if index >= len(value):
            raise ValueError("user dirs value has a dangling escape")
        if value[index] == "$":
            raise ValueError("user dirs value cannot disguise a variable prefix")
        result.append(value[index])
        index += 1
    normalized = "".join(result)
    if "\x00" in normalized or any(unicodedata.category(character) in {"Cc", "Cf", "Cs"} for character in normalized):
        raise ValueError("user dirs value contains a control character")
    return normalized

def _counts_by_location(entries: list[Mapping[str, Any]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for entry in entries:
        location_id = entry["locationId"]
        counts[location_id] = counts.get(location_id, 0) + 1
    return counts

def _location_surplus(entry: Mapping[str, Any], counts: Mapping[str, int]) -> int:
    location_id = entry["locationId"]
    floor = LOCATION_ENTRY_FLOOR if location_id in PLACE_LOCATION_IDS else 0
    return counts[location_id] - floor

def _evictable_leaf_index(entries: list[Mapping[str, Any]], parent_ids: set[str]) -> int:
    leaves = [index for index, entry in enumerate(entries) if entry["id"] not in parent_ids]
    if not leaves:
        raise ValueError("files inventory has no leaf entries to evict")
    counts = _counts_by_location(entries)
    above_floor = [index for index in leaves if _location_surplus(entries[index], counts) > 0]
    keep_last = [index for index in leaves if counts[entries[index]["locationId"]] > 1]
    candidates = above_floor or keep_last or leaves
    return max(
        candidates,
        key=lambda index: (
            _location_surplus(entries[index], counts) if above_floor else counts[entries[index]["locationId"]],
            index,
        ),
    )

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

def _location_query_availability(snapshot: StateSnapshot, location_id: str) -> dict[str, Any]:
    if snapshot.state is None:
        return availability_payload(snapshot)
    matches = [location for location in snapshot.state["locations"] if location["id"] == location_id]
    if len(matches) != 1:
        missing = _reason(
            "files.location-unavailable",
            "Location is unavailable",
            "The selected location is not present in the current workspace.",
            detail=location_id,
        )
        return {"state": "unavailable", "read": False, "operation": False, "reasons": [missing.to_dict()]}
    location = matches[0]
    if location["state"] == "available":
        return {"state": "available", "read": True, "operation": False, "reasons": []}
    reason = location["reason"]
    copied = None
    if reason is not None:
        copied = {key: value for key, value in dict(reason).items()}
        if "recoveryActions" in copied:
            copied["recoveryActions"] = list(copied["recoveryActions"])
    return {
        "state": location["state"] if location["state"] in {"degraded", "unavailable"} else "unavailable",
        "read": location["state"] != "unavailable",
        "operation": False,
        "reasons": [copied] if copied else [],
    }

def _browse(arguments: Mapping[str, Any], snapshot: StateSnapshot) -> dict[str, Any]:
    relative = normalize_relative_path(arguments["relativePath"], allow_empty=True)
    entries: list[dict[str, Any]] = []
    if snapshot.state is not None:
        for entry in snapshot.state["entries"]:
            parent = entry["relativePath"].rsplit("/", 1)[0] if "/" in entry["relativePath"] else ""
            if entry["locationId"] == arguments["locationId"] and parent == relative and (arguments["includeHidden"] or not entry["hidden"]):
                entries.append(thaw(entry))
    entries.sort(key=lambda item: (item["kind"] != "directory", item["name"].casefold(), item["id"]))
    limit = arguments["limit"]
    metadata = _metadata("browse", snapshot)
    metadata["availability"] = _location_query_availability(snapshot, arguments["locationId"])
    return {**metadata, "entries": entries[:limit], "truncated": len(entries) > limit}

def _search(arguments: Mapping[str, Any], snapshot: StateSnapshot) -> dict[str, Any]:
    query = unicodedata.normalize("NFC", arguments["query"]).casefold()
    scopes = set(arguments["locationIds"])
    entries: list[dict[str, Any]] = []
    if snapshot.state is not None:
        for entry in snapshot.state["entries"]:
            if scopes and entry["locationId"] not in scopes:
                continue
            if not arguments["includeHidden"] and entry["hidden"]:
                continue
            if query in entry["name"].casefold() or query in entry["relativePath"].casefold():
                entries.append(thaw(entry))
    entries.sort(key=lambda item: (item["name"].casefold(), item["relativePath"], item["id"]))
    limit = arguments["limit"]
    return {**_metadata("search", snapshot), "entries": entries[:limit], "truncated": len(entries) > limit}

def _recent(arguments: Mapping[str, Any], snapshot: StateSnapshot) -> dict[str, Any]:
    entries: list[dict[str, Any]] = []
    total = 0
    if snapshot.state is not None:
        by_id = {entry["id"]: entry for entry in snapshot.state["entries"]}
        ordered = sorted(snapshot.state["recent"], key=lambda item: item["rank"])
        total = len(ordered)
        entries = [thaw(by_id[item["entryId"]]) for item in ordered[: arguments["limit"]]]
    return {**_metadata("recent", snapshot), "entries": entries, "truncated": total > arguments["limit"]}

def _location(state: Mapping[str, Any], location_id: str, *, writable: bool = False) -> Mapping[str, Any]:
    matches = [location for location in state["locations"] if location["id"] == location_id]
    if len(matches) != 1:
        raise _precondition("The selected location is not present in the current workspace.", location_id)
    location = matches[0]
    if location["state"] != "available" or (writable and not location["writable"]):
        raise _precondition("The selected location is not available for this operation.", location_id)
    return location

def _entry(state: Mapping[str, Any], entry_id: str, *, safe_path: bool = True) -> Mapping[str, Any]:
    matches = [entry for entry in state["entries"] if entry["id"] == entry_id]
    if len(matches) != 1:
        raise _precondition("The selected entry is not present in the current workspace.", entry_id)
    entry = matches[0]
    if safe_path:
        if entry["kind"] == "symlink":
            raise _precondition("Symlink entries cannot be mutation anchors.", entry_id)
        by_id = {candidate["id"]: candidate for candidate in state["entries"]}
        cursor = entry
        while cursor["parentId"] is not None:
            cursor = by_id[cursor["parentId"]]
            if cursor["kind"] == "symlink":
                raise _precondition("A symlink appears in the selected entry ancestry.", cursor["id"])
    return entry

def _precondition(explanation: str, detail: str) -> FabricError:
    return FabricError(
        "files.precondition-failed",
        "Files operation cannot run",
        explanation,
        detail=detail[:160],
        retryable=True,
        recovery_actions=("files.inspect",),
    )

def _normalize_create(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "locationId": arguments["locationId"],
        "parentRelativePath": normalize_relative_path(arguments["parentRelativePath"], allow_empty=True),
        "name": normalize_name(arguments["name"]),
    }

def _normalize_rename(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"entryId": arguments["entryId"], "newName": normalize_name(arguments["newName"])}

def _normalize_entry(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"entryId": arguments["entryId"]}

def _normalize_mount(arguments: Mapping[str, Any]) -> dict[str, Any]:
    return {"mountId": arguments["mountId"]}

def _directory_names_from_state(state: Mapping[str, Any], location_id: str, parent: str) -> list[str]:
    prefix = f"{parent}/" if parent else ""
    names = []
    for entry in state["entries"]:
        if entry["locationId"] != location_id:
            continue
        relative = entry["relativePath"]
        if not relative.startswith(prefix):
            continue
        remainder = relative[len(prefix):]
        if remainder and "/" not in remainder:
            names.append(remainder)
    return sorted(names)

def _directory_scope(current: Mapping[str, Any], proposed: Mapping[str, Any], arguments: Mapping[str, Any], backend: Any) -> dict[str, Any]:
    location_id = arguments["locationId"]
    parent = arguments["parentRelativePath"]
    listing = None
    if backend is not None and hasattr(backend, "directory_listing"):
        listing = backend.directory_listing(location_id, parent)
    if listing is None:
        current_names = _directory_names_from_state(current, location_id, parent)
        proposed_names = _directory_names_from_state(proposed, location_id, parent)
    else:
        current_names = sorted(listing)
        proposed_names = sorted(set(listing) | {arguments["name"]})
    digest = hashlib.sha256(f"files.directory\0{location_id}\0{parent}".encode("utf-8")).hexdigest()

    def document(names: list[str]) -> dict[str, Any]:
        return {"locationId": location_id, "parentRelativePath": parent, "names": names}

    return {
        "kind": "files.directory",
        "id": f"files.directory.{digest}",
        "current": document(current_names),
        "proposed": document(proposed_names),
    }

def _entry_directory_scope(current: Mapping[str, Any], arguments: Mapping[str, Any], backend: Any, *, restoring: bool) -> dict[str, Any]:
    selected = _entry(current, arguments["entryId"])
    record = selected["trash"] if selected["trash"] is not None else None
    location_id = record["originalLocationId"] if record else selected["locationId"]
    relative = record["originalRelativePath"] if record else selected["relativePath"]
    parent = relative.rsplit("/", 1)[0] if "/" in relative else ""
    name = relative.rsplit("/", 1)[-1]
    listing = None
    if backend is not None and hasattr(backend, "directory_listing"):
        listing = backend.directory_listing(location_id, parent)
    current_names = sorted(listing) if listing is not None else _directory_names_from_state(current, location_id, parent)
    if restoring:
        proposed_names = sorted(set(current_names) | {name})
    else:
        proposed_names = sorted(candidate for candidate in current_names if candidate != name)
    digest = hashlib.sha256(f"files.directory\0{location_id}\0{parent}".encode("utf-8")).hexdigest()

    def document(names: list[str]) -> dict[str, Any]:
        return {"locationId": location_id, "parentRelativePath": parent, "names": names}

    return {
        "kind": "files.directory",
        "id": f"files.directory.{digest}",
        "current": document(current_names),
        "proposed": document(proposed_names),
    }

def _entry_trash_scope(current: Mapping[str, Any], proposed: Mapping[str, Any], arguments: Mapping[str, Any], backend: Any) -> dict[str, Any]:
    return _entry_directory_scope(current, arguments, backend, restoring=False)


def _trash_restore_scope(current: Mapping[str, Any], proposed: Mapping[str, Any], arguments: Mapping[str, Any], backend: Any) -> dict[str, Any]:
    return _entry_directory_scope(current, arguments, backend, restoring=True)

def _create_directory(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    state = deepcopy(dict(current))
    location = _location(state, arguments["locationId"], writable=True)
    parent_id = None
    parent_identity = location["rootDigest"]
    if arguments["parentRelativePath"]:
        parents = [entry for entry in state["entries"] if entry["locationId"] == location["id"] and entry["relativePath"] == arguments["parentRelativePath"]]
        if len(parents) != 1 or parents[0]["kind"] != "directory":
            raise _precondition("The destination parent is not a real directory.", arguments["parentRelativePath"])
        parent = _entry(state, parents[0]["id"])
        parent_id = parent["id"]
        parent_identity = parent["identity"]
    relative = arguments["name"] if not arguments["parentRelativePath"] else f"{arguments['parentRelativePath']}/{arguments['name']}"
    if any(entry["locationId"] == location["id"] and entry["relativePath"] == relative for entry in state["entries"]):
        raise _precondition("An entry already exists at the destination.", relative)
    entry_id = stable_resource_id(DOMAIN, "entry", f"created\0{location['id']}\0{parent_identity}\0{relative}")
    state["entries"].append({
        "id": entry_id,
        "locationId": location["id"],
        "parentId": parent_id,
        "name": arguments["name"],
        "relativePath": relative,
        "kind": "directory",
        "sizeBytes": None,
        "modifiedMs": None,
        "mimeType": None,
        "hidden": arguments["name"].startswith("."),
        "writable": True,
        "identity": state_revision({"created": entry_id, "parent": parent_identity}),
        "symlinkTargetState": None,
        "trash": None,
    })
    state["entries"].sort(key=lambda item: item["id"])
    return state

def _rename_entry(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    state = deepcopy(dict(current))
    selected = _entry(state, arguments["entryId"])
    _location(state, selected["locationId"], writable=True)
    if not selected["writable"]:
        raise _precondition("The selected entry is not writable.", selected["id"])
    old_path = selected["relativePath"]
    parent_path = old_path.rsplit("/", 1)[0] if "/" in old_path else ""
    new_path = arguments["newName"] if not parent_path else f"{parent_path}/{arguments['newName']}"
    if old_path == new_path:
        return state
    if any(entry["id"] != selected["id"] and entry["locationId"] == selected["locationId"] and entry["relativePath"] == new_path for entry in state["entries"]):
        raise _precondition("An entry already exists at the rename destination.", new_path)
    prefix = f"{old_path}/"
    for entry in state["entries"]:
        if entry["id"] == selected["id"]:
            entry["name"] = arguments["newName"]
            entry["relativePath"] = new_path
            entry["hidden"] = arguments["newName"].startswith(".")
        elif entry["locationId"] == selected["locationId"] and entry["relativePath"].startswith(prefix):
            entry["relativePath"] = f"{new_path}/{entry['relativePath'][len(prefix):]}"
    return state

def _trash_entry(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    state = deepcopy(dict(current))
    selected = _entry(state, arguments["entryId"])
    source_location = _location(state, selected["locationId"], writable=True)
    if selected["trash"] is not None or source_location["kind"] == "trash":
        raise _precondition("The selected entry is already in Trash.", selected["id"])
    trash_locations = [location for location in state["locations"] if location["kind"] == "trash"]
    if len(trash_locations) != 1:
        raise _precondition("A unique Trash location is unavailable.", selected["id"])
    trash = _location(state, trash_locations[0]["id"], writable=True)
    original_path = selected["relativePath"]
    original_parent_id = selected["parentId"]
    candidate = selected["name"]
    if any(entry["locationId"] == trash["id"] and entry["relativePath"] == candidate for entry in state["entries"]):
        suffix = f".{selected['id'][-8:]}"
        candidate = f"{selected['name'][:255 - len(suffix)]}{suffix}"
        if any(entry["locationId"] == trash["id"] and entry["relativePath"] == candidate for entry in state["entries"]):
            raise _precondition("No collision-free bounded Trash name is available.", selected["id"])
    prefix = f"{original_path}/"
    moved_ids: set[str] = set()
    for entry in state["entries"]:
        if entry["id"] == selected["id"]:
            moved_ids.add(entry["id"])
            entry["locationId"] = trash["id"]
            entry["parentId"] = None
            entry["name"] = candidate
            entry["relativePath"] = candidate
            entry["trash"] = {
                "originalLocationId": source_location["id"],
                "originalParentId": original_parent_id,
                "originalRelativePath": original_path,
            }
        elif entry["locationId"] == source_location["id"] and entry["relativePath"].startswith(prefix):
            moved_ids.add(entry["id"])
            entry["locationId"] = trash["id"]
            entry["relativePath"] = f"{candidate}/{entry['relativePath'][len(prefix):]}"
    state["recent"] = [item for item in state["recent"] if item["entryId"] not in moved_ids]
    for rank, item in enumerate(sorted(state["recent"], key=lambda value: value["rank"])):
        item["rank"] = rank
    return state

def _restore_entry(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    state = deepcopy(dict(current))
    selected = _entry(state, arguments["entryId"])
    metadata = selected["trash"]
    if metadata is None:
        raise _precondition("The selected entry has no typed Trash recovery metadata.", selected["id"])
    target_location = _location(state, metadata["originalLocationId"], writable=True)
    target_path = metadata["originalRelativePath"]
    if any(entry["id"] != selected["id"] and entry["locationId"] == target_location["id"] and entry["relativePath"] == target_path for entry in state["entries"]):
        raise _precondition("The original restore destination is occupied.", target_path)
    if metadata["originalParentId"] is not None:
        parent = _entry(state, metadata["originalParentId"])
        if parent["kind"] != "directory" or parent["locationId"] != target_location["id"]:
            raise _precondition("The original restore parent is unavailable.", metadata["originalParentId"])
    trash_path = selected["relativePath"]
    trash_location_id = selected["locationId"]
    prefix = f"{trash_path}/"
    for entry in state["entries"]:
        if entry["id"] == selected["id"]:
            entry["locationId"] = target_location["id"]
            entry["parentId"] = metadata["originalParentId"]
            entry["name"] = target_path.rsplit("/", 1)[-1]
            entry["relativePath"] = target_path
            entry["trash"] = None
        elif entry["locationId"] == trash_location_id and entry["relativePath"].startswith(prefix):
            entry["locationId"] = target_location["id"]
            entry["relativePath"] = f"{target_path}/{entry['relativePath'][len(prefix):]}"
    return state

def _mount_state(current: Mapping[str, Any], arguments: Mapping[str, Any], target: str) -> dict[str, Any]:
    state = deepcopy(dict(current))
    matches = [mount for mount in state["mounts"] if mount["id"] == arguments["mountId"]]
    if len(matches) != 1:
        raise _precondition("The selected mount is unavailable.", arguments["mountId"])
    mount = matches[0]
    if mount["kind"] == "system":
        raise _precondition("System mounts cannot be changed through the Files provider.", mount["id"])
    if mount["state"] == target:
        return state
    expected = "unmounted" if target == "mounted" else "mounted"
    if mount["state"] != expected or mount["locationId"] is None:
        raise _precondition("The selected mount is not in the required transition state.", mount["id"])
    mount["state"] = target
    locations = [location for location in state["locations"] if location["id"] == mount["locationId"]]
    if len(locations) != 1:
        raise _precondition("The selected mount location is unavailable.", mount["id"])
    location = locations[0]
    location["state"] = "available" if target == "mounted" else "unavailable"
    location["writable"] = mount["writable"] if target == "mounted" else False
    location["reason"] = None if target == "mounted" else _reason(
        "files.mount-disconnected",
        "Mount is disconnected",
        "The removable or network location is not currently mounted.",
        detail=mount["id"],
    ).to_dict()
    return state

def _connect(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    return _mount_state(current, arguments, "mounted")

def _disconnect(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    return _mount_state(current, arguments, "unmounted")

def _anchors(current: Mapping[str, Any], arguments: Mapping[str, Any]) -> dict[str, Any]:
    anchors: list[dict[str, Any]] = []
    if "entryId" in arguments:
        entry = _entry(current, arguments["entryId"])
        anchors.append({"resourceId": entry["id"], "identity": entry["identity"]})
        location = _location(current, entry["locationId"])
        anchors.append({"resourceId": location["id"], "identity": location["rootDigest"]})
    elif "locationId" in arguments:
        location = _location(current, arguments["locationId"])
        anchors.append({"resourceId": location["id"], "identity": location["rootDigest"]})
        parent_path = arguments.get("parentRelativePath", "")
        if parent_path:
            parent = next(entry for entry in current["entries"] if entry["locationId"] == location["id"] and entry["relativePath"] == parent_path)
            anchors.append({"resourceId": parent["id"], "identity": parent["identity"]})
    else:
        mount = next((candidate for candidate in current["mounts"] if candidate["id"] == arguments["mountId"]), None)
        if mount is None:
            raise _precondition("The selected mount is unavailable.", arguments["mountId"])
        anchors.append({"resourceId": mount["id"], "identity": state_revision(mount)})
    return {
        "snapshotRevision": state_revision(current),
        "pathPolicy": "location-relative-v0",
        "noFollow": True,
        "anchors": anchors,
    }

def _summary(noun: str):
    def summarize(current: Mapping[str, Any], proposed: Mapping[str, Any], _arguments: Mapping[str, Any]) -> str:
        if current == proposed:
            return f"The requested {noun} state already matches; no change will be made."
        return f"Apply the typed {noun} transition after rechecking the frozen no-follow identities."

    return summarize

OPERATIONS = {
    "directory.create": OperationSpec("directory.create", _normalize_create, _create_directory, _summary("directory"), _anchors, _directory_scope),
    "entry.rename": OperationSpec("entry.rename", _normalize_rename, _rename_entry, _summary("rename"), _anchors),
    "entry.trash": OperationSpec("entry.trash", _normalize_entry, _trash_entry, _summary("Trash"), _anchors, _entry_trash_scope),
    "trash.restore": OperationSpec("trash.restore", _normalize_entry, _restore_entry, _summary("restore"), _anchors, _trash_restore_scope),
    "mount.connect": OperationSpec("mount.connect", _normalize_mount, _connect, _summary("mount connection"), _anchors),
    "mount.disconnect": OperationSpec("mount.disconnect", _normalize_mount, _disconnect, _summary("mount disconnection"), _anchors),
}

READ_HANDLERS = {"inspect": _inspect, "browse": _browse, "search": _search, "recent": _recent}

def _directory_inspect_handler(backend: Any):
    def handler(arguments: Mapping[str, Any], snapshot: StateSnapshot) -> dict[str, Any]:
        location_id = arguments["locationId"]
        parent = arguments["parentRelativePath"]
        names = None
        if hasattr(backend, "directory_listing"):
            names = backend.directory_listing(location_id, parent)
        if names is None and snapshot.state is not None:
            names = _directory_names_from_state(thaw(snapshot.state), location_id, parent)
        state = None
        if names is not None:
            state = {"locationId": location_id, "parentRelativePath": parent, "names": sorted(names)}
        metadata = _metadata("directory.inspect", snapshot)
        metadata["revision"] = state_revision(state) if state is not None else None
        return {**metadata, "state": state}

    return handler

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
        state_validator=validate_workspace,
        read_handlers={**READ_HANDLERS, "directory.inspect": _directory_inspect_handler(backend)},
        read_completeness_codes=READ_COMPLETENESS_CODES,
        operations=OPERATIONS,
        scoped_resource_kind="files.directory",
    )

def build_provider(*, home: Path | None = None, config_path: Path | None = None, session_operable: bool = False) -> StateDomainProvider:
    if home is None:
        home = Path.home()
    if config_path is None:
        omarchy_path = os.environ.get("OMARCHY_PATH")
        if not omarchy_path:
            raise FabricError(
                "files.config-unavailable",
                "Files provider configuration is unavailable",
                "OMARCHY_PATH is not present in the user session environment.",
                recovery_actions=("session.restart",),
            )
        config_path = Path(omarchy_path) / "default" / "ultimate" / "files" / "locations-v0.json"
    return _provider(RealFilesBackend(home, config_path, session_operable=session_operable))

def build_fake_provider(
    state: Mapping[str, Any],
    *,
    state_path: Path | None = None,
    fail_on: frozenset[str] = frozenset(),
) -> StateDomainProvider:
    normalized = canonicalize_workspace(state)
    backend = FakeStateBackend(
        DOMAIN,
        normalized,
        validate_workspace,
        state_path=state_path,
        fail_on=fail_on,
    )
    return _provider(backend)
