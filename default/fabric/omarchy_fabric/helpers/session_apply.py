"""Code-owned session apply helper for user-scope operations."""

from __future__ import annotations

import datetime
import errno
import fcntl
import hashlib
import io
import json
import os
import pathlib
import re
import shutil
import signal
import stat
import subprocess
import sys
import urllib.parse
import zipfile
from typing import Any, Mapping

from .trash_info import parse_trash_info_path, trash_info_document

PACTL = "/usr/bin/pactl"
HYPRCTL = "/usr/bin/hyprctl"
NMCLI = "/usr/bin/nmcli"
XDG_MIME = "/usr/bin/xdg-mime"
XDG_OPEN = "/usr/bin/xdg-open"
WL_COPY = "/usr/bin/wl-copy"
WL_PASTE = "/usr/bin/wl-paste"
MAX_CLIPBOARD_URIS = 16
DEFAULTS_PROTOCOLS = frozenset({"http", "https", "mailto"})
MAX_MIME_LENGTH = 160
NETWORK_WIFI_ID = "network.radio.wifi"
BRIGHTNESS = "/usr/bin/omarchy-brightness-display"
POWERPROFILESCTL = "/usr/bin/powerprofilesctl"
POWER_RESOURCE_ID = "power.profile.current"
FILES_WORKSPACE_ID = "files.workspace.primary"
MAX_PAYLOAD_BYTES = 8192
OMARCHY_PKG_ADD = "/usr/bin/omarchy-pkg-add"
OMARCHY_PKG_DROP = "/usr/bin/omarchy-pkg-drop"
SOFTWARE_PACKAGE_ID = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$")
SOFTWARE_COMMAND_TIMEOUT_SECONDS = 900
OMARCHY_VERSION_CHANNEL = "/usr/bin/omarchy-version-channel"
OMARCHY_UPDATE = "/usr/bin/omarchy-update"
OMARCHY_UPDATE_AVAILABLE = "/usr/bin/omarchy-update-available"
OMARCHY_UPDATE_FREE_SPACE = "/usr/bin/omarchy-update-requires-free-space"
UPDATE_COMMAND_TIMEOUT_SECONDS = 900
UPDATE_CHANNELS = frozenset({"stable", "candidate", "rc", "edge"})
UPDATE_AUTH_MARKERS = (
    "sudo:",
    "a password is required",
    "authentication",
    "not authorized",
    "polkit",
    "authorization required",
    "incorrect password",
    "sorry, try again",
)

class ApplyError(Exception):
    def __init__(self, code: str, explanation: str) -> None:
        super().__init__(explanation)
        self.code = code
        self.explanation = explanation

def stable_sink_id(sink_name: str) -> str:
    digest = hashlib.sha256(f"audio\0{sink_name}".encode("utf-8")).hexdigest()
    return f"audio.sink.{digest}"

def stable_display_id(monitor_name: str) -> str:
    digest = hashlib.sha256(f"display\0{monitor_name}".encode("utf-8")).hexdigest()
    return f"display.output.{digest}"

def stable_keyboard_id(device_name: str) -> str:
    digest = hashlib.sha256(f"input\0{device_name}".encode("utf-8")).hexdigest()
    return f"input.keyboard.{digest}"

def read_payload(stream: Any) -> Mapping[str, Any]:
    raw = stream.read(MAX_PAYLOAD_BYTES + 1)
    if isinstance(raw, bytes):
        raw = raw.decode("utf-8", errors="strict")
    if len(raw) > MAX_PAYLOAD_BYTES:
        raise ApplyError("payload.too-large", "The apply payload exceeds its bound.")
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ApplyError("payload.invalid", "The apply payload is not valid JSON.") from error
    if not isinstance(payload, dict):
        raise ApplyError("payload.invalid", "The apply payload must be an object.")
    return payload

def require_resource_id(payload: Mapping[str, Any]) -> str:
    resource_id = payload.get("resourceId")
    if not isinstance(resource_id, str) or not resource_id.startswith("audio.sink."):
        raise ApplyError("payload.invalid", "The apply payload names no audio sink resource.")
    if len(resource_id) != len("audio.sink.") + 64:
        raise ApplyError("payload.invalid", "The audio sink identity is malformed.")
    return resource_id

def require_digest_resource_id(payload: Mapping[str, Any], prefix: str) -> str:
    resource_id = payload.get("resourceId")
    if not isinstance(resource_id, str) or not resource_id.startswith(prefix):
        raise ApplyError("payload.invalid", "The apply payload names no resource of the expected kind.")
    if len(resource_id) != len(prefix) + 64:
        raise ApplyError("payload.invalid", "The resource identity is malformed.")
    return resource_id

def require_percent(payload: Mapping[str, Any]) -> int:
    percent = payload.get("percent")
    if isinstance(percent, bool) or not isinstance(percent, int):
        raise ApplyError("payload.invalid", "The requested volume percent must be an integer.")
    if not 0 <= percent <= 100:
        raise ApplyError("payload.out-of-range", "The requested volume percent is outside its bound.")
    return percent

def list_sinks(run: Any = subprocess.run) -> list[Mapping[str, Any]]:
    completed = run(
        [PACTL, "--format=json", "list", "sinks"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    if completed.returncode != 0:
        raise ApplyError("probe.failed", "The audio inventory probe reported a failure status.")
    try:
        sinks = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise ApplyError("probe.invalid", "The audio inventory probe returned unreadable output.") from error
    if not isinstance(sinks, list):
        raise ApplyError("probe.invalid", "The audio inventory probe returned no sink list.")
    return sinks

def resolve_sink_name(resource_id: str, sinks: list[Mapping[str, Any]]) -> str:
    matches = []
    for sink in sinks:
        if not isinstance(sink, Mapping):
            continue
        name = sink.get("name")
        if isinstance(name, str) and name and stable_sink_id(name) == resource_id:
            matches.append(name)
    if len(matches) != 1:
        raise ApplyError("resource.unresolved", "The named audio sink is not present exactly once.")
    return matches[0]

def apply_volume(sink_name: str, percent: int, run: Any = subprocess.run) -> None:
    completed = run(
        [PACTL, "set-sink-volume", sink_name, f"{percent}%"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    if completed.returncode != 0:
        raise ApplyError("apply.failed", "Setting the audio output volume reported a failure status.")

def list_monitors(run: Any = subprocess.run) -> list[Mapping[str, Any]]:
    completed = run(
        [HYPRCTL, "-j", "monitors", "all"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    if completed.returncode != 0:
        raise ApplyError("probe.failed", "The display inventory probe reported a failure status.")
    try:
        monitors = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise ApplyError("probe.invalid", "The display inventory probe returned unreadable output.") from error
    if not isinstance(monitors, list):
        raise ApplyError("probe.invalid", "The display inventory probe returned no monitor list.")
    return monitors

def resolve_monitor_name(resource_id: str, monitors: list[Mapping[str, Any]]) -> str:
    matches = []
    for monitor in monitors:
        if not isinstance(monitor, Mapping):
            continue
        name = monitor.get("name")
        if isinstance(name, str) and name and stable_display_id(name) == resource_id:
            matches.append(name)
    if len(matches) != 1:
        raise ApplyError("resource.unresolved", "The named display is not present exactly once.")
    return matches[0]

def apply_brightness(monitor_name: str, percent: int, run: Any = subprocess.run) -> None:
    completed = run(
        [BRIGHTNESS, "--no-osd", "--monitor", monitor_name, f"{percent}%"],
        capture_output=True,
        text=True,
        timeout=15,
    )
    if completed.returncode != 0:
        raise ApplyError("apply.failed", "Setting the display brightness reported a failure status.")

def require_layout_index(payload: Mapping[str, Any]) -> int:
    index = payload.get("layoutIndex")
    if not isinstance(index, int) or isinstance(index, bool):
        raise ApplyError("payload.invalid", "The apply payload names no layout index.")
    if not 0 <= index <= 7:
        raise ApplyError("payload.out-of-range", "The requested layout index is outside its bound.")
    return index

def list_keyboards(run: Any = subprocess.run) -> list[Mapping[str, Any]]:
    completed = run(
        [HYPRCTL, "-j", "devices"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    if completed.returncode != 0:
        raise ApplyError("probe.failed", "The input inventory probe reported a failure status.")
    try:
        devices = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise ApplyError("probe.invalid", "The input inventory probe returned unreadable output.") from error
    keyboards = devices.get("keyboards") if isinstance(devices, Mapping) else None
    if not isinstance(keyboards, list):
        raise ApplyError("probe.invalid", "The input inventory probe returned no keyboard list.")
    return keyboards

def resolve_keyboard_name(resource_id: str, keyboards: list[Mapping[str, Any]]) -> str:
    matches = []
    for keyboard in keyboards:
        if not isinstance(keyboard, Mapping):
            continue
        name = keyboard.get("name")
        if isinstance(name, str) and name and stable_keyboard_id(name) == resource_id:
            matches.append(name)
    if len(matches) != 1:
        raise ApplyError("resource.unresolved", "The named keyboard is not present exactly once.")
    return matches[0]

def apply_keyboard_layout(device_name: str, index: int, run: Any = subprocess.run) -> None:
    completed = run(
        [HYPRCTL, "switchxkblayout", device_name, str(index)],
        capture_output=True,
        text=True,
        timeout=5,
    )
    if completed.returncode != 0:
        raise ApplyError("apply.failed", "Switching the keyboard layout reported a failure status.")

def require_enabled(payload: Mapping[str, Any]) -> bool:
    enabled = payload.get("enabled")
    if not isinstance(enabled, bool):
        raise ApplyError("payload.invalid", "The apply payload names no radio state.")
    return enabled

def apply_wifi_radio(enabled: bool, run: Any = subprocess.run) -> None:
    completed = run(
        [NMCLI, "radio", "wifi", "on" if enabled else "off"],
        capture_output=True,
        text=True,
        timeout=15,
    )
    if completed.returncode != 0:
        raise ApplyError("apply.failed", "Switching the Wi-Fi radio reported a failure status.")

def require_scheme(payload: Mapping[str, Any]) -> str:
    scheme = payload.get("scheme")
    if not isinstance(scheme, str) or scheme not in DEFAULTS_PROTOCOLS:
        raise ApplyError("payload.invalid", "The apply payload names no code-owned protocol.")
    return scheme

def stable_application_id(desktop_id: str) -> str:
    digest = hashlib.sha256(f"defaults\0{desktop_id}".encode("utf-8")).hexdigest()
    return f"defaults.app.{digest}"

def desktop_entry_roots() -> list[pathlib.Path]:
    roots = [pathlib.Path.home() / ".local" / "share" / "applications"]
    roots.extend(pathlib.Path(base) / "applications" for base in ("/usr/local/share", "/usr/share"))
    return roots

def resolve_application(payload: Mapping[str, Any]) -> str:
    app_id = payload.get("appId")
    if not isinstance(app_id, str) or not app_id.startswith("defaults.app."):
        raise ApplyError("payload.invalid", "The apply payload names no application identity.")
    matches = []
    for root in desktop_entry_roots():
        try:
            entries = sorted(root.iterdir())
        except OSError:
            continue
        for entry in entries:
            if entry.suffix != ".desktop" or not entry.is_file():
                continue
            if stable_application_id(entry.name) == app_id and entry.name not in matches:
                matches.append(entry.name)
    if len(matches) != 1:
        raise ApplyError("resource.unresolved", "The named application is not installed exactly once.")
    return matches[0]

def apply_default_protocol(scheme: str, desktop_id: str, run: Any = subprocess.run) -> None:
    completed = run(
        [XDG_MIME, "default", desktop_id, f"x-scheme-handler/{scheme}"],
        capture_output=True,
        text=True,
        timeout=15,
    )
    if completed.returncode != 0:
        raise ApplyError("apply.failed", "Setting the default application reported a failure status.")

FILES_XDG_KEYS = {
    "desktop": "XDG_DESKTOP_DIR",
    "documents": "XDG_DOCUMENTS_DIR",
    "downloads": "XDG_DOWNLOAD_DIR",
    "pictures": "XDG_PICTURES_DIR",
}
FILES_WRITABLE_KEYS = frozenset({"home", "desktop", "documents", "downloads", "pictures"})
MAX_NAME_LENGTH = 128
MAX_RELATIVE_DEPTH = 16
MAX_COPY_ENTRIES = 4096
MAX_ARCHIVE_SOURCES = 16
MAX_EXTRACT_BYTES = 256 * 1024 * 1024
MAX_PROPERTIES_PATH = 4096

def files_location_key(location_id: str) -> str:
    prefix = "files.location."
    if not isinstance(location_id, str) or not location_id.startswith(prefix):
        raise ApplyError("payload.invalid", "The apply payload names no files location.")
    key = location_id[len(prefix):]
    if key not in FILES_WRITABLE_KEYS:
        raise ApplyError("resource.unresolved", "The named files location is not writable.")
    return key

def read_user_dirs(home: pathlib.Path) -> dict[str, pathlib.Path]:
    path = home / ".config" / "user-dirs.dirs"
    try:
        raw = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return {}
    result: dict[str, pathlib.Path] = {}
    for line in raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key not in FILES_XDG_KEYS.values():
            continue
        if len(value) < 2 or value[0] != '"' or value[-1] != '"':
            continue
        literal = value[1:-1]
        if literal in {"$HOME", "$HOME/"}:
            result[key] = home
        elif literal.startswith("$HOME/"):
            result[key] = home / literal[6:]
        elif literal.startswith("/"):
            result[key] = pathlib.Path(literal)
    return result

def resolve_location_path(key: str, home: pathlib.Path) -> pathlib.Path:
    if key == "home":
        return home
    dirs = read_user_dirs(home)
    resolved = dirs.get(FILES_XDG_KEYS[key])
    if resolved is None:
        resolved = home / key.capitalize()
    return resolved

def require_relative(payload: Mapping[str, Any]) -> list[str]:
    relative = payload.get("parentRelativePath")
    if not isinstance(relative, str):
        raise ApplyError("payload.invalid", "The parent relative path must be a string.")
    if relative == "":
        return []
    if relative.startswith("/") or "\\" in relative:
        raise ApplyError("payload.invalid", "The parent relative path is not relative.")
    segments = relative.split("/")
    if len(segments) > MAX_RELATIVE_DEPTH:
        raise ApplyError("payload.out-of-range", "The parent relative path is too deep.")
    for segment in segments:
        if segment in {"", ".", ".."} or "\x00" in segment:
            raise ApplyError("payload.invalid", "The parent relative path holds an unsafe segment.")
    return segments

def require_name(payload: Mapping[str, Any]) -> str:
    name = payload.get("name")
    if not isinstance(name, str) or not name:
        raise ApplyError("payload.invalid", "The directory name is missing.")
    if len(name) > MAX_NAME_LENGTH:
        raise ApplyError("payload.out-of-range", "The directory name exceeds its bound.")
    if name in {".", ".."} or "/" in name or "\\" in name or "\x00" in name:
        raise ApplyError("payload.invalid", "The directory name holds an unsafe character.")
    if name != name.strip():
        raise ApplyError("payload.invalid", "The directory name is not trimmed.")
    return name

def create_directory(payload: Mapping[str, Any], home: pathlib.Path) -> pathlib.Path:
    key = files_location_key(payload.get("locationId"))
    segments = require_relative(payload)
    name = require_name(payload)
    base = resolve_location_path(key, home)
    try:
        root = base.resolve(strict=True)
    except OSError as error:
        raise ApplyError("resource.unresolved", "The files location is not present.") from error
    target = root.joinpath(*segments, name)
    try:
        parent = target.parent.resolve(strict=True)
    except OSError as error:
        raise ApplyError("resource.unresolved", "The parent directory is not present.") from error
    if parent != root and root not in parent.parents:
        raise ApplyError("payload.invalid", "The target escapes its files location.")
    if not parent.is_dir():
        raise ApplyError("resource.unresolved", "The parent path is not a directory.")
    final = parent / name
    try:
        final.mkdir()
    except FileExistsError as error:
        raise ApplyError("apply.exists", "A directory of that name already exists.") from error
    except OSError as error:
        raise ApplyError("apply.failed", "Creating the directory reported a failure status.") from error
    return final

def require_files_resource_id(payload: Mapping[str, Any]) -> str:
    resource_id = payload.get("resourceId")
    if not isinstance(resource_id, str) or not resource_id.startswith("files."):
        raise ApplyError("payload.invalid", "The apply payload names no files resource.")
    return resource_id


def bind_files_named_directory_resource(payload: Mapping[str, Any], expected: str) -> str:
    resource_id = payload.get("resourceId")
    if resource_id in (None, ""):
        return expected
    if not isinstance(resource_id, str) or not resource_id.startswith("files."):
        raise ApplyError("payload.invalid", "The apply payload names no files resource.")
    if resource_id != expected:
        raise ApplyError("payload.invalid", "The apply payload targets another directory than its resource.")
    return resource_id


def bind_files_directory_resource(payload: Mapping[str, Any], location_id: str, parent: str) -> str:
    expected = stable_directory_id(location_id, parent)
    resource_id = payload.get("resourceId")
    if resource_id in (None, ""):
        return expected
    if not isinstance(resource_id, str) or not resource_id.startswith("files."):
        raise ApplyError("payload.invalid", "The apply payload names no files resource.")
    if resource_id != expected:
        raise ApplyError("payload.invalid", "The apply payload targets another directory than its resource.")
    return resource_id

def stable_entry_id(location_id: str, device: int, inode: int, relative: str) -> str:
    material = f"files\0{location_id}\0{device}\0{inode}\0{relative}"
    digest = hashlib.sha256(material.encode("utf-8")).hexdigest()
    return f"files.entry.{digest}"


def require_entry_relative(payload: Mapping[str, Any]) -> list[str]:
    relative = payload.get("entryRelativePath")
    if not isinstance(relative, str) or not relative:
        raise ApplyError("payload.invalid", "The apply payload names no entry.")
    if relative.startswith("/") or "\\" in relative:
        raise ApplyError("payload.invalid", "The entry path is not relative.")
    segments = relative.split("/")
    if len(segments) > MAX_RELATIVE_DEPTH:
        raise ApplyError("payload.out-of-range", "The entry path is too deep.")
    for segment in segments:
        if segment in {"", ".", ".."} or "\x00" in segment:
            raise ApplyError("payload.invalid", "The entry path holds an unsafe segment.")
    return segments


def require_entry_id(payload: Mapping[str, Any]) -> str:
    entry_id = payload.get("entryId")
    if not isinstance(entry_id, str) or not entry_id.startswith("files.entry."):
        raise ApplyError("payload.invalid", "The apply payload names no entry identity.")
    return entry_id


def resolve_entry_slot(payload: Mapping[str, Any], home: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path, str]:
    key = files_location_key(payload.get("locationId"))
    segments = require_entry_relative(payload)
    base = resolve_location_path(key, home)
    try:
        root = base.resolve(strict=True)
    except OSError as error:
        raise ApplyError("resource.unresolved", "The files location is not present.") from error
    target = root.joinpath(*segments)
    try:
        resolved_parent = target.parent.resolve(strict=True)
    except OSError as error:
        raise ApplyError("resource.unresolved", "The entry parent is not present.") from error
    if resolved_parent != root and root not in resolved_parent.parents:
        raise ApplyError("payload.invalid", "The entry escapes its files location.")
    return root, resolved_parent / target.name, "/".join(segments)


def resolve_entry_path(payload: Mapping[str, Any], home: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path, str]:
    entry_id = require_entry_id(payload)
    root, final, relative = resolve_entry_slot(payload, home)
    try:
        info = final.lstat()
    except OSError as error:
        raise ApplyError("resource.unresolved", "The entry is not present.") from error
    observed = stable_entry_id(payload["locationId"], info.st_dev, info.st_ino, relative)
    if observed != entry_id:
        raise ApplyError("resource.drifted", "The entry on disk is not the entry the plan approved.")
    return root, final, relative


def trash_root(home: pathlib.Path) -> pathlib.Path:
    data_home = os.environ.get("XDG_DATA_HOME", "")
    base = pathlib.Path(data_home) if data_home.startswith("/") else home / ".local" / "share"
    return base / "Trash"


def trash_names(directory: pathlib.Path, name: str) -> str:
    candidate = name
    suffix = 1
    while (directory / "files" / candidate).exists() or (directory / "info" / f"{candidate}.trashinfo").exists():
        if suffix > 4096:
            raise ApplyError("apply.exists", "No collision-free Trash name is available.")
        stem, dot, extension = name.partition(".")
        candidate = f"{stem}.{suffix}{dot}{extension}" if dot else f"{name}.{suffix}"
        suffix += 1
    return candidate


def parse_trash_info(text: str) -> str:
    try:
        return parse_trash_info_path(text)
    except ValueError as error:
        raise ApplyError("apply.failed", "The Trash record does not name an absolute original path.") from error


def apply_files_entry_trash(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    home = pathlib.Path.home()
    _, final, relative = resolve_entry_path(payload, home)
    parent = "/".join(relative.split("/")[:-1])
    resource_id = bind_files_directory_resource(payload, payload["locationId"], parent)
    root = trash_root(home)
    try:
        (root / "files").mkdir(parents=True, exist_ok=True)
        (root / "info").mkdir(parents=True, exist_ok=True)
    except OSError as error:
        raise ApplyError("apply.failed", "The Trash directory is unavailable.") from error
    name = trash_names(root, final.name)
    deleted_at = datetime.datetime.now().replace(microsecond=0).isoformat()
    info_path = root / "info" / f"{name}.trashinfo"
    try:
        with open(info_path, "x", encoding="utf-8", newline="\n") as stream:
            stream.write(trash_info_document(final, deleted_at))
    except OSError as error:
        raise ApplyError("apply.failed", "The Trash record could not be written.") from error
    try:
        os.rename(final, root / "files" / name)
    except OSError as error:
        try:
            info_path.unlink()
        except OSError:
            pass
        raise ApplyError("apply.failed", "Moving the entry to Trash reported a failure status.") from error
    json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "trashName": name}, stdout)
    stdout.write("\n")
    return 0


def apply_files_trash_restore(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    entry_id = require_entry_id(payload)
    home = pathlib.Path.home()
    _, destination, relative = resolve_entry_slot(payload, home)
    parent = "/".join(relative.split("/")[:-1])
    resource_id = bind_files_directory_resource(payload, payload["locationId"], parent)
    root = trash_root(home)
    files_dir = root / "files"
    try:
        names = os.listdir(files_dir)
    except OSError as error:
        raise ApplyError("resource.unresolved", "The Trash directory is not present.") from error
    if len(names) > 4096:
        raise ApplyError("apply.failed", "The Trash directory exceeds its scan bound.")
    trash_file = None
    for name in names:
        try:
            info = (files_dir / name).lstat()
        except OSError:
            continue
        if stable_entry_id("files.location.trash", info.st_dev, info.st_ino, name) == entry_id:
            trash_file = files_dir / name
            break
    if trash_file is None:
        raise ApplyError("resource.unresolved", "The Trash record for this entry is missing.")
    info_path = root / "info" / f"{trash_file.name}.trashinfo"
    try:
        record = info_path.read_text(encoding="utf-8")
    except OSError as error:
        raise ApplyError("resource.unresolved", "The Trash record for this entry is missing.") from error
    original = pathlib.Path(parse_trash_info(record))
    if home.resolve() not in original.parents:
        raise ApplyError("payload.invalid", "The Trash record points outside this account's home.")
    if original != destination:
        raise ApplyError("payload.invalid", "The Trash record does not name this restore destination.")
    if destination.exists():
        raise ApplyError("apply.exists", "Something already occupies the original location.")
    try:
        os.rename(trash_file, destination)
    except OSError as error:
        raise ApplyError("apply.failed", "Restoring the entry reported a failure status.") from error
    try:
        info_path.unlink()
    except OSError:
        pass
    json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "restoredTo": str(destination)}, stdout)
    stdout.write("\n")
    return 0


def apply_files_trash_manage(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    if payload.get("locationId") != "files.location.trash":
        raise ApplyError("payload.invalid", "Only the Trash location can be emptied.")
    parent = payload.get("parentRelativePath")
    if parent not in (None, ""):
        raise ApplyError("payload.invalid", "Empty Bin only targets the Trash root.")
    resource_id = bind_files_directory_resource(payload, "files.location.trash", "")
    root = trash_root(pathlib.Path.home())
    files_dir = root / "files"
    info_dir = root / "info"
    try:
        names = os.listdir(files_dir)
    except FileNotFoundError:
        json.dump({"ok": True, "resourceId": resource_id, "emptied": False, "count": 0}, stdout)
        stdout.write("\n")
        return 0
    except OSError as error:
        raise ApplyError("resource.unresolved", "The Trash directory is not present.") from error
    if len(names) > 4096:
        raise ApplyError("apply.failed", "The Trash directory exceeds its scan bound.")
    targets: list[tuple[pathlib.Path, str]] = []
    for name in names:
        if name in {".", ".."} or "/" in name or "\\" in name or "\x00" in name:
            raise ApplyError("payload.invalid", "The Trash directory holds an unsafe name.")
        candidate = files_dir / name
        try:
            info = candidate.lstat()
        except OSError as error:
            raise ApplyError("resource.unresolved", "A Trash entry disappeared before Empty Bin could run.") from error
        if stat.S_ISLNK(info.st_mode):
            raise ApplyError("payload.invalid", "Symlink entries cannot be emptied from Trash.")
        if stat.S_ISREG(info.st_mode):
            targets.append((candidate, "file"))
            continue
        if not stat.S_ISDIR(info.st_mode):
            raise ApplyError("payload.invalid", "Only regular files and empty directories can be emptied from Trash.")
        try:
            children = list(candidate.iterdir())
        except OSError as error:
            raise ApplyError("apply.failed", "Emptying Trash reported a failure status.") from error
        if children:
            raise ApplyError("payload.invalid", "Only regular files and empty directories can be emptied from Trash.")
        targets.append((candidate, "directory"))
    removed = 0
    for candidate, kind in targets:
        try:
            if kind == "file":
                candidate.unlink()
            else:
                candidate.rmdir()
        except OSError as error:
            raise ApplyError("apply.failed", "Emptying Trash reported a failure status.") from error
        try:
            (info_dir / f"{candidate.name}.trashinfo").unlink()
        except OSError:
            pass
        removed += 1
    json.dump({"ok": True, "resourceId": resource_id, "emptied": removed > 0, "count": removed}, stdout)
    stdout.write("\n")
    return 0


def apply_open(path: pathlib.Path, run: Any = subprocess.run) -> None:
    completed = run(
        [XDG_OPEN, str(path)],
        capture_output=True,
        text=True,
        timeout=15,
    )
    if completed.returncode != 0:
        raise ApplyError("apply.failed", "Opening the entry with its default application reported a failure status.")


def apply_files_entry_open(stdin: Any, stdout: Any, run: Any = subprocess.run) -> int:
    payload = read_payload(stdin)
    resource_id = require_files_resource_id(payload)
    if "desired" in payload:
        json.dump({"ok": True, "resourceId": resource_id, "launched": False}, stdout)
        stdout.write("\n")
        return 0
    if payload.get("locationId") == "files.location.trash":
        raise ApplyError("payload.invalid", "Trash entries cannot be opened with the default handler.")
    home = pathlib.Path.home()
    _, final, relative = resolve_entry_path(payload, home)
    parent = "/".join(relative.split("/")[:-1])
    if resource_id != stable_directory_id(payload["locationId"], parent):
        raise ApplyError("payload.invalid", "The apply payload targets another directory than its resource.")
    try:
        info = final.lstat()
    except OSError as error:
        raise ApplyError("resource.unresolved", "The entry is not present.") from error
    if stat.S_ISLNK(info.st_mode):
        raise ApplyError("payload.invalid", "Symlink entries cannot be opened with the default handler.")
    if not stat.S_ISREG(info.st_mode):
        raise ApplyError("payload.invalid", "The selected entry is not a regular file.")
    apply_open(final, run)
    json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "launched": True}, stdout)
    stdout.write("\n")
    return 0


def stable_directory_id(location_id: str, parent: str) -> str:
    digest = hashlib.sha256(f"files.directory\0{location_id}\0{parent}".encode("utf-8")).hexdigest()
    return f"files.directory.{digest}"


def stable_rename_directory_id(location_id: str, parent: str, entry_id: str) -> str:
    digest = hashlib.sha256(f"files.directory\0{location_id}\0{parent}\0{entry_id}".encode("utf-8")).hexdigest()
    return f"files.directory.{digest}"


def stable_copy_directory_id(location_id: str, parent: str, entry_id: str) -> str:
    return stable_rename_directory_id(location_id, parent, entry_id)


def stable_move_directory_id(location_id: str, parent: str, entry_id: str) -> str:
    return stable_rename_directory_id(location_id, parent, entry_id)


def stable_delete_directory_id(location_id: str, parent: str, entry_id: str) -> str:
    return stable_rename_directory_id(location_id, parent, entry_id)


def require_destination_name(payload: Mapping[str, Any]) -> str:
    name = payload.get("destinationName")
    if not isinstance(name, str) or not name:
        raise ApplyError("payload.invalid", "The destination name is missing.")
    if len(name) > 255:
        raise ApplyError("payload.out-of-range", "The destination name exceeds its bound.")
    if name in {".", ".."} or "/" in name or "\\" in name or "\x00" in name:
        raise ApplyError("payload.invalid", "The destination name holds an unsafe character.")
    if name != name.strip():
        raise ApplyError("payload.invalid", "The destination name is not trimmed.")
    return name


def require_new_name(payload: Mapping[str, Any]) -> str:
    name = payload.get("newName")
    if not isinstance(name, str) or not name:
        raise ApplyError("payload.invalid", "The new name is missing.")
    if len(name) > 255:
        raise ApplyError("payload.out-of-range", "The new name exceeds its bound.")
    if name in {".", ".."} or "/" in name or "\\" in name or "\x00" in name:
        raise ApplyError("payload.invalid", "The new name holds an unsafe character.")
    if name != name.strip():
        raise ApplyError("payload.invalid", "The new name is not trimmed.")
    return name


def apply_files_entry_rename(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    resource_id = require_files_resource_id(payload)
    entry_id = require_entry_id(payload)
    new_name = require_new_name(payload)
    if payload.get("locationId") == "files.location.trash":
        raise ApplyError("payload.invalid", "Trash entries cannot be renamed.")
    home = pathlib.Path.home()
    parent_relative = "/".join(require_entry_relative(payload)[:-1])
    if resource_id != stable_rename_directory_id(payload["locationId"], parent_relative, entry_id):
        raise ApplyError("payload.invalid", "The apply payload targets another directory than its resource.")
    if "desired" in payload:
        _, original, relative = resolve_entry_slot(payload, home)
        renamed = original.parent / new_name
        if original.exists() and not renamed.exists():
            json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "newName": original.name, "renamed": False}, stdout)
            stdout.write("\n")
            return 0
        try:
            info = renamed.lstat()
        except OSError as error:
            raise ApplyError("resource.unresolved", "The renamed entry is not present.") from error
        if stat.S_ISLNK(info.st_mode):
            raise ApplyError("payload.invalid", "Symlink entries cannot be renamed.")
        observed = stable_entry_id(payload["locationId"], info.st_dev, info.st_ino, relative)
        if observed != entry_id:
            raise ApplyError("resource.drifted", "The entry on disk is not the entry the plan approved.")
        if original.exists():
            raise ApplyError("apply.exists", "Something already occupies the original name.")
        try:
            os.rename(renamed, original)
        except OSError as error:
            raise ApplyError("apply.failed", "Restoring the original name reported a failure status.") from error
        json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "newName": original.name, "renamed": True}, stdout)
        stdout.write("\n")
        return 0
    _, final, relative = resolve_entry_path(payload, home)
    try:
        info = final.lstat()
    except OSError as error:
        raise ApplyError("resource.unresolved", "The entry is not present.") from error
    if stat.S_ISLNK(info.st_mode):
        raise ApplyError("payload.invalid", "Symlink entries cannot be renamed.")
    destination = final.parent / new_name
    if destination == final:
        json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "newName": new_name, "renamed": False}, stdout)
        stdout.write("\n")
        return 0
    if destination.exists():
        raise ApplyError("apply.exists", "Something already occupies the new name.")
    try:
        os.rename(final, destination)
    except OSError as error:
        raise ApplyError("apply.failed", "Renaming the entry reported a failure status.") from error
    json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "newName": new_name, "renamed": True}, stdout)
    stdout.write("\n")
    return 0

def remove_replica(path: pathlib.Path) -> None:
    try:
        info = path.lstat()
    except FileNotFoundError:
        return
    except OSError as error:
        raise ApplyError("apply.failed", "Removing the copied entry reported a failure status.") from error
    if stat.S_ISLNK(info.st_mode) or stat.S_ISREG(info.st_mode):
        try:
            path.unlink()
        except OSError as error:
            raise ApplyError("apply.failed", "Removing the copied entry reported a failure status.") from error
        return
    if not stat.S_ISDIR(info.st_mode):
        raise ApplyError("apply.failed", "Removing the copied entry reported a failure status.")
    try:
        children = list(path.iterdir())
    except OSError as error:
        raise ApplyError("apply.failed", "Removing the copied entry reported a failure status.") from error
    for child in children:
        remove_replica(child)
    try:
        path.rmdir()
    except OSError as error:
        raise ApplyError("apply.failed", "Removing the copied entry reported a failure status.") from error


def copy_regular_file(source: pathlib.Path, destination: pathlib.Path) -> None:
    try:
        with source.open("rb") as incoming, destination.open("xb") as outgoing:
            shutil.copyfileobj(incoming, outgoing)
    except FileExistsError as error:
        raise ApplyError("apply.exists", "Something already occupies the destination name.") from error
    except OSError as error:
        if error.errno == errno.EXDEV:
            raise ApplyError("apply.failed", "The copy cannot cross devices.") from error
        raise ApplyError("apply.failed", "Copying the entry reported a failure status.") from error


def copy_entry_tree(
    source: pathlib.Path,
    destination: pathlib.Path,
    seen: set[tuple[int, int]],
    remaining_depth: int,
    remaining_entries: list[int],
    created_root: list[bool],
) -> None:
    if remaining_depth <= 0:
        raise ApplyError("payload.out-of-range", "The entry path is too deep.")
    try:
        info = source.lstat()
    except OSError as error:
        raise ApplyError("resource.unresolved", "The entry is not present.") from error
    if stat.S_ISLNK(info.st_mode):
        raise ApplyError("payload.invalid", "Symlink entries cannot be copied.")
    identity = (info.st_dev, info.st_ino)
    if identity in seen:
        raise ApplyError("payload.invalid", "A cyclic directory cannot be copied.")
    if remaining_entries[0] <= 0:
        raise ApplyError("payload.out-of-range", "The copy exceeds its entry bound.")
    remaining_entries[0] -= 1
    if stat.S_ISREG(info.st_mode):
        copy_regular_file(source, destination)
        created_root[0] = True
        return
    if not stat.S_ISDIR(info.st_mode):
        raise ApplyError("payload.invalid", "Only regular files and directories can be copied.")
    try:
        destination.mkdir(exist_ok=False)
    except FileExistsError as error:
        raise ApplyError("apply.exists", "Something already occupies the destination name.") from error
    except OSError as error:
        if error.errno == errno.EXDEV:
            raise ApplyError("apply.failed", "The copy cannot cross devices.") from error
        raise ApplyError("apply.failed", "Copying the entry reported a failure status.") from error
    created_root[0] = True
    seen.add(identity)
    try:
        children = sorted(source.iterdir(), key=lambda child: child.name)
    except OSError as error:
        raise ApplyError("apply.failed", "Copying the entry reported a failure status.") from error
    for child in children:
        copy_entry_tree(
            child,
            destination / child.name,
            seen,
            remaining_depth - 1,
            remaining_entries,
            created_root,
        )


def apply_files_entry_copy(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    resource_id = require_files_resource_id(payload)
    entry_id = require_entry_id(payload)
    dest_name = require_destination_name(payload)
    dest_location = payload.get("destinationLocationId")
    dest_parent = payload.get("destinationParentRelativePath")
    if payload.get("locationId") == "files.location.trash":
        raise ApplyError("payload.invalid", "Trash entries cannot be copied.")
    if dest_location == "files.location.trash":
        raise ApplyError("payload.invalid", "Trash is not a copy destination.")
    if not isinstance(dest_location, str) or not isinstance(dest_parent, str):
        raise ApplyError("payload.invalid", "The apply payload names no copy destination.")
    if resource_id != stable_copy_directory_id(dest_location, dest_parent, entry_id):
        raise ApplyError("payload.invalid", "The apply payload targets another directory than its resource.")
    _, source, relative = resolve_entry_path(payload, pathlib.Path.home())
    try:
        info = source.lstat()
    except OSError as error:
        raise ApplyError("resource.unresolved", "The entry is not present.") from error
    if stat.S_ISLNK(info.st_mode):
        raise ApplyError("payload.invalid", "Symlink entries cannot be copied.")
    if not stat.S_ISREG(info.st_mode) and not stat.S_ISDIR(info.st_mode):
        raise ApplyError("payload.invalid", "Only regular files and directories can be copied.")
    dest_payload = {
        "locationId": dest_location,
        "parentRelativePath": dest_parent,
        "name": dest_name,
    }
    dest_key = files_location_key(dest_location)
    dest_segments = require_relative(dest_payload)
    dest_base = resolve_location_path(dest_key, pathlib.Path.home())
    try:
        dest_root = dest_base.resolve(strict=True)
    except OSError as error:
        raise ApplyError("resource.unresolved", "The destination files location is not present.") from error
    dest_target = dest_root.joinpath(*dest_segments, dest_name)
    try:
        dest_parent_path = dest_target.parent.resolve(strict=True)
    except OSError as error:
        raise ApplyError("resource.unresolved", "The destination parent is not present.") from error
    if dest_parent_path != dest_root and dest_root not in dest_parent_path.parents:
        raise ApplyError("payload.invalid", "The destination escapes its files location.")
    if not dest_parent_path.is_dir():
        raise ApplyError("resource.unresolved", "The destination parent is not a directory.")
    destination = dest_parent_path / dest_name
    if stat.S_ISDIR(info.st_mode):
        try:
            destination.relative_to(source)
        except ValueError:
            pass
        else:
            raise ApplyError("payload.invalid", "A directory cannot be copied into itself.")
    if "desired" in payload:
        if destination.exists() and source.exists():
            remove_replica(destination)
            json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "destinationName": dest_name, "copied": False}, stdout)
            stdout.write("\n")
            return 0
        json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "destinationName": dest_name, "copied": False}, stdout)
        stdout.write("\n")
        return 0
    if destination.exists():
        raise ApplyError("apply.exists", "Something already occupies the destination name.")
    created_root = [False]
    try:
        copy_entry_tree(
            source,
            destination,
            set(),
            MAX_RELATIVE_DEPTH - len(dest_segments),
            [MAX_COPY_ENTRIES],
            created_root,
        )
    except ApplyError:
        if created_root[0] and destination.exists():
            try:
                remove_replica(destination)
            except ApplyError:
                pass
        raise
    json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "destinationName": dest_name, "copied": True}, stdout)
    stdout.write("\n")
    return 0


def path_as_file_uri(path: pathlib.Path) -> str:
    return path.absolute().as_uri()


def parse_file_uri_list(raw: str) -> list[pathlib.Path]:
    text = str(raw or "").replace("\r\n", "\n").replace("\r", "\n")
    lines = text.split("\n")
    if lines and lines[0].strip().lower() in {"copy", "cut"}:
        lines = lines[1:]
    paths: list[pathlib.Path] = []
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("file:"):
            parsed = urllib.parse.urlparse(line)
            if parsed.scheme != "file" or parsed.netloc not in {"", "localhost"}:
                raise ApplyError("payload.invalid", "The clipboard URI is not a local file.")
            candidate = pathlib.Path(urllib.parse.unquote(parsed.path))
        elif line.startswith("/"):
            candidate = pathlib.Path(line)
        else:
            raise ApplyError("payload.invalid", "The clipboard does not hold file URIs.")
        if not candidate.is_absolute() or ".." in candidate.parts or "\x00" in str(candidate):
            raise ApplyError("payload.invalid", "The clipboard path is not a safe absolute path.")
        paths.append(candidate)
    if not paths:
        raise ApplyError("resource.unresolved", "The clipboard does not hold files.")
    if len(paths) > MAX_CLIPBOARD_URIS:
        raise ApplyError("payload.out-of-range", "The clipboard holds too many files.")
    return paths


def apply_clipboard_uri_list(uris: list[str], run: Any = subprocess.run) -> None:
    body = "\r\n".join(uris) + "\r\n"
    argv = [WL_COPY, "--type", "text/uri-list"]
    if run is not subprocess.run:
        completed = run(argv, input=body, capture_output=True, text=True, timeout=5)
        if completed.returncode != 0:
            raise ApplyError("apply.failed", "Offering the files on the clipboard reported a failure status.")
        return
    process = subprocess.Popen(
        argv,
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        _, stderr = process.communicate(body, timeout=1)
    except subprocess.TimeoutExpired:
        return
    if process.returncode != 0:
        raise ApplyError("apply.failed", "Offering the files on the clipboard reported a failure status.")


def read_clipboard_files(run: Any = subprocess.run) -> str:
    last_error = "resource.unresolved"
    for mime in ("text/uri-list", "x-special/gnome-copied-files", "text/plain"):
        completed = run(
            [WL_PASTE, "--type", mime],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if completed.returncode == 0 and str(completed.stdout or "").strip():
            return completed.stdout
        last_error = "resource.unresolved"
    raise ApplyError(last_error, "The clipboard does not hold files.")


def next_copy_name(taken: set[str], source_name: str) -> str:
    lowered = {name.lower() for name in taken}
    if source_name.lower() not in lowered:
        return source_name
    stem, ext = source_name, ""
    dot = source_name.rfind(".")
    if dot > 0:
        stem, ext = source_name[:dot], source_name[dot:]
    for index in range(2, 512):
        candidate = f"{stem} ({index}){ext}"
        if candidate.lower() not in lowered:
            return candidate
    raise ApplyError("apply.exists", "No collision-free copy name is available.")


def map_absolute_path_to_entry(path: pathlib.Path, home: pathlib.Path) -> tuple[str, str, pathlib.Path]:
    try:
        parent = path.parent.resolve(strict=True)
    except OSError as error:
        raise ApplyError("resource.unresolved", "The clipboard file is not present.") from error
    final = parent / path.name
    trash = trash_root(home)
    try:
        trash_root_resolved = trash.resolve()
    except OSError:
        trash_root_resolved = trash
    try:
        located = final.resolve(strict=False)
    except OSError as error:
        raise ApplyError("resource.unresolved", "The clipboard file is not present.") from error
    if located == trash_root_resolved or trash_root_resolved in located.parents:
        raise ApplyError("payload.invalid", "Trash entries cannot be pasted.")
    matches: list[tuple[str, str, pathlib.Path]] = []
    for key in FILES_WRITABLE_KEYS:
        try:
            root = resolve_location_path(key, home).resolve(strict=True)
        except OSError:
            continue
        try:
            relative = located.relative_to(root)
        except ValueError:
            continue
        relative_text = "" if str(relative) == "." else str(relative).replace("\\", "/")
        if relative_text == "":
            raise ApplyError("payload.invalid", "A files location root cannot be pasted as an entry.")
        matches.append((f"files.location.{key}", relative_text, final))
    if not matches:
        raise ApplyError("payload.invalid", "The clipboard file is outside this account's Files locations.")
    matches.sort(key=lambda item: len(item[1]))
    return matches[0]


def destination_taken_names(dest_location: str, dest_parent: str, home: pathlib.Path) -> set[str]:
    key = files_location_key(dest_location)
    segments = require_relative({"parentRelativePath": dest_parent})
    base = resolve_location_path(key, home)
    try:
        root = base.resolve(strict=True)
    except OSError as error:
        raise ApplyError("resource.unresolved", "The destination files location is not present.") from error
    parent = root.joinpath(*segments)
    try:
        resolved_parent = parent.resolve(strict=True)
    except OSError as error:
        raise ApplyError("resource.unresolved", "The destination parent is not present.") from error
    if resolved_parent != root and root not in resolved_parent.parents:
        raise ApplyError("payload.invalid", "The destination escapes its files location.")
    try:
        names = [entry.name for entry in resolved_parent.iterdir()]
    except OSError as error:
        raise ApplyError("resource.unresolved", "The destination parent is not present.") from error
    return set(names)


def apply_files_clipboard_copy(stdin: Any, stdout: Any, run: Any = subprocess.run) -> int:
    payload = read_payload(stdin)
    require_entry_id(payload)
    if payload.get("locationId") == "files.location.trash":
        raise ApplyError("payload.invalid", "Trash entries cannot be copied to the clipboard.")
    home = pathlib.Path.home()
    _, final, relative = resolve_entry_path(payload, home)
    try:
        info = final.lstat()
    except OSError as error:
        raise ApplyError("resource.unresolved", "The entry is not present.") from error
    if stat.S_ISLNK(info.st_mode):
        raise ApplyError("payload.invalid", "Symlink entries cannot be copied to the clipboard.")
    if not stat.S_ISREG(info.st_mode) and not stat.S_ISDIR(info.st_mode):
        raise ApplyError("payload.invalid", "Only regular files and directories can be copied to the clipboard.")
    apply_clipboard_uri_list([path_as_file_uri(final)], run)
    json.dump({"ok": True, "entry": relative, "offered": True}, stdout)
    stdout.write("\n")
    return 0


def apply_files_clipboard_paste(stdin: Any, stdout: Any, run: Any = subprocess.run) -> int:
    payload = read_payload(stdin)
    dest_location = payload.get("destinationLocationId")
    dest_parent = payload.get("destinationParentRelativePath")
    if dest_location == "files.location.trash":
        raise ApplyError("payload.invalid", "Trash is not a paste destination.")
    files_location_key(dest_location)
    if not isinstance(dest_parent, str):
        raise ApplyError("payload.invalid", "The apply payload names no paste destination.")
    require_relative({"parentRelativePath": dest_parent})
    home = pathlib.Path.home()
    sources = parse_file_uri_list(read_clipboard_files(run))
    taken = destination_taken_names(dest_location, dest_parent, home)
    names: list[str] = []
    for source in sources:
        location_id, relative, final = map_absolute_path_to_entry(source, home)
        try:
            info = final.lstat()
        except OSError as error:
            raise ApplyError("resource.unresolved", "The clipboard file is not present.") from error
        if stat.S_ISLNK(info.st_mode):
            raise ApplyError("payload.invalid", "Symlink entries cannot be pasted.")
        if not stat.S_ISREG(info.st_mode) and not stat.S_ISDIR(info.st_mode):
            raise ApplyError("payload.invalid", "Only regular files and directories can be pasted.")
        entry_id = stable_entry_id(location_id, info.st_dev, info.st_ino, relative)
        dest_name = next_copy_name(taken, final.name)
        copy_payload = {
            "resourceId": stable_copy_directory_id(dest_location, dest_parent, entry_id),
            "locationId": location_id,
            "entryRelativePath": relative,
            "entryId": entry_id,
            "destinationLocationId": dest_location,
            "destinationParentRelativePath": dest_parent,
            "destinationName": dest_name,
        }
        apply_files_entry_copy(io.StringIO(json.dumps(copy_payload)), io.StringIO())
        names.append(dest_name)
        taken.add(dest_name)
    json.dump({"ok": True, "copied": True, "count": len(names), "names": names}, stdout)
    stdout.write("\n")
    return 0


def apply_files_entry_move(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    entry_id = require_entry_id(payload)
    dest_name = require_destination_name(payload)
    dest_location = payload.get("destinationLocationId")
    dest_parent = payload.get("destinationParentRelativePath")
    if payload.get("locationId") == "files.location.trash":
        raise ApplyError("payload.invalid", "Trash entries cannot be moved.")
    if dest_location == "files.location.trash":
        raise ApplyError("payload.invalid", "Trash is not a move destination.")
    if not isinstance(dest_location, str) or not isinstance(dest_parent, str):
        raise ApplyError("payload.invalid", "The apply payload names no move destination.")
    resource_id = bind_files_named_directory_resource(
        payload, stable_move_directory_id(dest_location, dest_parent, entry_id)
    )
    home = pathlib.Path.home()
    _, source, relative = resolve_entry_slot(payload, home)
    source_parent = "/".join(relative.split("/")[:-1])
    source_name = relative.rsplit("/", 1)[-1]
    if dest_location == payload.get("locationId") and dest_parent == source_parent and dest_name != source_name:
        raise ApplyError("payload.invalid", "Same-directory name changes use rename.")
    dest_payload = {
        "locationId": dest_location,
        "parentRelativePath": dest_parent,
        "name": dest_name,
    }
    dest_key = files_location_key(dest_location)
    dest_segments = require_relative(dest_payload)
    dest_base = resolve_location_path(dest_key, home)
    try:
        dest_root = dest_base.resolve(strict=True)
    except OSError as error:
        raise ApplyError("resource.unresolved", "The destination files location is not present.") from error
    dest_target = dest_root.joinpath(*dest_segments, dest_name)
    try:
        dest_parent_path = dest_target.parent.resolve(strict=True)
    except OSError as error:
        raise ApplyError("resource.unresolved", "The destination parent is not present.") from error
    if dest_parent_path != dest_root and dest_root not in dest_parent_path.parents:
        raise ApplyError("payload.invalid", "The destination escapes its files location.")
    if not dest_parent_path.is_dir():
        raise ApplyError("resource.unresolved", "The destination parent is not a directory.")
    destination = dest_parent_path / dest_name
    if dest_location == payload.get("locationId") and dest_parent == source_parent and dest_name == source_name:
        json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "destinationName": dest_name, "moved": False}, stdout)
        stdout.write("\n")
        return 0
    if "desired" in payload:
        if source.exists() and not destination.exists():
            json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "destinationName": dest_name, "moved": False}, stdout)
            stdout.write("\n")
            return 0
        try:
            info = destination.lstat()
        except OSError as error:
            raise ApplyError("resource.unresolved", "The moved entry is not present.") from error
        if stat.S_ISLNK(info.st_mode):
            raise ApplyError("payload.invalid", "Symlink entries cannot be moved.")
        observed = stable_entry_id(payload["locationId"], info.st_dev, info.st_ino, relative)
        if observed != entry_id:
            raise ApplyError("resource.drifted", "The entry on disk is not the entry the plan approved.")
        if source.exists():
            raise ApplyError("apply.exists", "Something already occupies the original location.")
        try:
            os.rename(destination, source)
        except OSError as error:
            raise ApplyError("apply.failed", "Restoring the moved entry reported a failure status.") from error
        json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "destinationName": dest_name, "moved": False}, stdout)
        stdout.write("\n")
        return 0
    try:
        info = source.lstat()
    except OSError as error:
        raise ApplyError("resource.unresolved", "The entry is not present.") from error
    observed = stable_entry_id(payload["locationId"], info.st_dev, info.st_ino, relative)
    if observed != entry_id:
        raise ApplyError("resource.drifted", "The entry on disk is not the entry the plan approved.")
    if stat.S_ISLNK(info.st_mode):
        raise ApplyError("payload.invalid", "Symlink entries cannot be moved.")
    if not stat.S_ISREG(info.st_mode):
        raise ApplyError("payload.invalid", "Only regular files can be moved.")
    if destination.exists():
        raise ApplyError("apply.exists", "Something already occupies the destination name.")
    try:
        os.rename(source, destination)
    except OSError as error:
        if error.errno == errno.EXDEV:
            raise ApplyError("apply.failed", "The move cannot cross devices.") from error
        raise ApplyError("apply.failed", "Moving the entry reported a failure status.") from error
    json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "destinationName": dest_name, "moved": True}, stdout)
    stdout.write("\n")
    return 0


def apply_files_entry_delete(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    entry_id = require_entry_id(payload)
    if payload.get("locationId") == "files.location.trash":
        raise ApplyError("payload.invalid", "Trash entries cannot be permanently deleted.")
    parent_relative = "/".join(require_entry_relative(payload)[:-1])
    resource_id = bind_files_named_directory_resource(
        payload, stable_delete_directory_id(payload["locationId"], parent_relative, entry_id)
    )
    _, final, relative = resolve_entry_path(payload, pathlib.Path.home())
    try:
        info = final.lstat()
    except OSError as error:
        raise ApplyError("resource.unresolved", "The entry is not present.") from error
    if stat.S_ISLNK(info.st_mode):
        raise ApplyError("payload.invalid", "Symlink entries cannot be permanently deleted.")
    if stat.S_ISREG(info.st_mode):
        try:
            final.unlink()
        except OSError as error:
            raise ApplyError("apply.failed", "Deleting the entry reported a failure status.") from error
        json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "deleted": True}, stdout)
        stdout.write("\n")
        return 0
    if not stat.S_ISDIR(info.st_mode):
        raise ApplyError("payload.invalid", "Only regular files and empty directories can be permanently deleted.")
    try:
        children = list(final.iterdir())
    except OSError as error:
        raise ApplyError("apply.failed", "Deleting the entry reported a failure status.") from error
    if children:
        raise ApplyError("payload.invalid", "Only empty directories can be permanently deleted.")
    try:
        final.rmdir()
    except OSError as error:
        raise ApplyError("apply.failed", "Deleting the entry reported a failure status.") from error
    json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "deleted": True}, stdout)
    stdout.write("\n")
    return 0


def require_archive_entries(payload: Mapping[str, Any]) -> list[Mapping[str, Any]]:
    raw = payload.get("entries")
    if raw is None:
        entry_id = payload.get("entryId")
        relative = payload.get("entryRelativePath")
        if not isinstance(entry_id, str) or not isinstance(relative, str) or not relative:
            raise ApplyError("payload.invalid", "The apply payload names no archive entries.")
        return [{"entryId": entry_id, "entryRelativePath": relative}]
    if not isinstance(raw, list) or not raw:
        raise ApplyError("payload.invalid", "The apply payload names no archive entries.")
    if len(raw) > MAX_ARCHIVE_SOURCES:
        raise ApplyError("payload.out-of-range", "The archive selection exceeds its bound.")
    entries: list[Mapping[str, Any]] = []
    for item in raw:
        if not isinstance(item, Mapping):
            raise ApplyError("payload.invalid", "The apply payload names no archive entries.")
        entry_id = item.get("entryId")
        relative = item.get("entryRelativePath")
        if not isinstance(entry_id, str) or not isinstance(relative, str) or not relative:
            raise ApplyError("payload.invalid", "The apply payload names no archive entries.")
        entries.append({"entryId": entry_id, "entryRelativePath": relative})
    return entries


def archive_stem(name: str, is_directory: bool) -> str:
    if is_directory:
        return name
    dot = name.rfind(".")
    if dot > 0:
        return name[:dot]
    return name


def open_nofollow(path: pathlib.Path, flags: int) -> int:
    return os.open(path, flags | getattr(os, "O_NOFOLLOW", 0))


def add_path_to_zip(
    zf: zipfile.ZipFile,
    source: pathlib.Path,
    arcname: str,
    remaining_depth: int,
    remaining_entries: list[int],
) -> None:
    if remaining_depth <= 0:
        raise ApplyError("payload.out-of-range", "The entry path is too deep.")
    if remaining_entries[0] <= 0:
        raise ApplyError("payload.out-of-range", "The archive exceeds its entry bound.")
    remaining_entries[0] -= 1
    try:
        preview = source.lstat()
    except OSError as error:
        raise ApplyError("resource.unresolved", "The entry is not present.") from error
    if stat.S_ISLNK(preview.st_mode):
        raise ApplyError("payload.invalid", "Symlink entries cannot be compressed.")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(source, flags)
    except OSError as error:
        if error.errno in {errno.ELOOP, errno.EEXIST} or error.errno == getattr(errno, "ENOTDIR", -1):
            raise ApplyError("payload.invalid", "Symlink entries cannot be compressed.") from error
        raise ApplyError("resource.unresolved", "The entry is not present.") from error
    owned = True
    try:
        info = os.fstat(descriptor)
        if stat.S_ISLNK(info.st_mode):
            raise ApplyError("payload.invalid", "Symlink entries cannot be compressed.")
        if stat.S_ISREG(info.st_mode):
            incoming = os.fdopen(descriptor, "rb")
            owned = False
            try:
                member = zipfile.ZipInfo(filename=arcname.replace("\\", "/"))
                member.compress_type = zipfile.ZIP_DEFLATED
                with zf.open(member, "w") as outgoing:
                    shutil.copyfileobj(incoming, outgoing)
            finally:
                incoming.close()
            return
        if not stat.S_ISDIR(info.st_mode):
            raise ApplyError("payload.invalid", "Only regular files and directories can be compressed.")
        try:
            names = os.listdir(descriptor)
        except OSError as error:
            raise ApplyError("apply.failed", "Reading a directory for the archive reported a failure status.") from error
    finally:
        if owned:
            os.close(descriptor)
    directory_name = arcname.replace("\\", "/").rstrip("/") + "/"
    if directory_name not in {"/", "./"}:
        zf.writestr(directory_name, b"")
    for name in sorted(names):
        if name in {".", ".."} or "/" in name or "\\" in name or "\x00" in name:
            raise ApplyError("payload.invalid", "The directory holds an unsafe name.")
        add_path_to_zip(
            zf,
            source / name,
            f"{arcname.rstrip('/')}/{name}",
            remaining_depth - 1,
            remaining_entries,
        )


def apply_files_archive_create(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    if payload.get("locationId") == "files.location.trash":
        raise ApplyError("payload.invalid", "Trash entries cannot be compressed.")
    location_id = payload.get("locationId")
    files_location_key(location_id)
    specs = require_archive_entries(payload)
    home = pathlib.Path.home()
    resolved: list[tuple[pathlib.Path, str, os.stat_result]] = []
    parents: set[str] = set()
    for spec in specs:
        entry_payload = {
            "locationId": location_id,
            "entryRelativePath": spec["entryRelativePath"],
            "entryId": spec["entryId"],
        }
        _, final, relative = resolve_entry_path(entry_payload, home)
        try:
            info = final.lstat()
        except OSError as error:
            raise ApplyError("resource.unresolved", "The entry is not present.") from error
        if stat.S_ISLNK(info.st_mode):
            raise ApplyError("payload.invalid", "Symlink entries cannot be compressed.")
        if not stat.S_ISREG(info.st_mode) and not stat.S_ISDIR(info.st_mode):
            raise ApplyError("payload.invalid", "Only regular files and directories can be compressed.")
        parents.add("/".join(relative.split("/")[:-1]))
        resolved.append((final, relative, info))
    if len(parents) != 1:
        raise ApplyError("payload.invalid", "Archive entries must share one parent directory.")
    parent_relative = next(iter(parents))
    resource_id = bind_files_named_directory_resource(
        payload, stable_directory_id(location_id, parent_relative)
    )
    dest_parent = resolved[0][0].parent
    try:
        dest_parent_fd = open_nofollow(
            dest_parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
        )
    except OSError as error:
        raise ApplyError("resource.unresolved", "The destination parent is not present.") from error
    try:
        dest_info = os.fstat(dest_parent_fd)
        if not stat.S_ISDIR(dest_info.st_mode):
            raise ApplyError("resource.unresolved", "The destination parent is not a directory.")
        taken = {name.lower() for name in os.listdir(dest_parent_fd)}
    except ApplyError:
        raise
    except OSError as error:
        raise ApplyError("resource.unresolved", "The destination parent is not present.") from error
    finally:
        os.close(dest_parent_fd)
    if len(resolved) == 1:
        proposed = f"{archive_stem(resolved[0][0].name, stat.S_ISDIR(resolved[0][2].st_mode))}.zip"
    else:
        proposed = "Archive.zip"
    dest_name = next_copy_name(taken, proposed)
    destination = dest_parent / dest_name
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    try:
        dest_fd = os.open(destination, flags, 0o644)
    except FileExistsError as error:
        raise ApplyError("apply.exists", "Something already occupies the archive name.") from error
    except OSError as error:
        raise ApplyError("apply.failed", "Creating the archive reported a failure status.") from error
    created = False
    try:
        with os.fdopen(dest_fd, "wb") as handle:
            with zipfile.ZipFile(handle, "w") as zf:
                remaining = [MAX_COPY_ENTRIES]
                for final, _relative, _info in resolved:
                    add_path_to_zip(
                        zf,
                        final,
                        final.name,
                        MAX_RELATIVE_DEPTH,
                        remaining,
                    )
        created = True
    except ApplyError:
        try:
            destination.unlink()
        except OSError:
            pass
        raise
    except OSError as error:
        try:
            destination.unlink()
        except OSError:
            pass
        raise ApplyError("apply.failed", "Creating the archive reported a failure status.") from error
    if not created:
        try:
            destination.unlink()
        except OSError:
            pass
        raise ApplyError("apply.failed", "Creating the archive reported a failure status.")
    json.dump(
        {
            "ok": True,
            "resourceId": resource_id,
            "archiveName": dest_name,
            "created": True,
            "count": len(resolved),
        },
        stdout,
    )
    stdout.write("\n")
    return 0


def zip_arcname_segments(name: str) -> tuple[list[str], bool]:
    if not isinstance(name, str) or not name or "\x00" in name:
        raise ApplyError("payload.invalid", "The archive holds an unsafe name.")
    if name.startswith("/") or name.startswith("\\") or "\\" in name:
        raise ApplyError("payload.invalid", "The archive path is not relative.")
    if len(name) >= 2 and name[1] == ":":
        raise ApplyError("payload.invalid", "The archive path is not relative.")
    is_directory = name.endswith("/")
    trimmed = name[:-1] if is_directory else name
    if trimmed == "":
        raise ApplyError("payload.invalid", "The archive holds an unsafe name.")
    segments = trimmed.split("/")
    if len(segments) > MAX_RELATIVE_DEPTH:
        raise ApplyError("payload.out-of-range", "The archive path is too deep.")
    for segment in segments:
        if segment in {"", ".", ".."} or "\x00" in segment:
            raise ApplyError("payload.invalid", "The archive path holds an unsafe segment.")
        if len(segment) > MAX_NAME_LENGTH:
            raise ApplyError("payload.out-of-range", "The archive name exceeds its bound.")
    return segments, is_directory


def zip_member_is_symlink(info: zipfile.ZipInfo) -> bool:
    mode = info.external_attr >> 16
    return bool(mode) and stat.S_ISLNK(mode)


def zip_member_is_directory(info: zipfile.ZipInfo, flagged_directory: bool) -> bool:
    if flagged_directory:
        return True
    mode = info.external_attr >> 16
    return bool(mode) and stat.S_ISDIR(mode)


def refuse_trash_destination(path: pathlib.Path, home: pathlib.Path) -> None:
    trash = trash_root(home)
    try:
        trash_resolved = trash.resolve()
    except OSError:
        trash_resolved = trash
    try:
        located = path.resolve(strict=False)
    except OSError as error:
        raise ApplyError("resource.unresolved", "The destination parent is not present.") from error
    if located == trash_resolved or trash_resolved in located.parents:
        raise ApplyError("payload.invalid", "Trash is not an extract destination.")


def ensure_extract_dir(parent_fd: int, name: str) -> int:
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        os.mkdir(name, 0o755, dir_fd=parent_fd)
    except FileExistsError:
        pass
    except OSError as error:
        raise ApplyError("apply.failed", "Extracting the archive reported a failure status.") from error
    try:
        return os.open(name, flags, dir_fd=parent_fd)
    except OSError as error:
        if error.errno in {errno.ELOOP, errno.EEXIST} or error.errno == getattr(errno, "ENOTDIR", -1):
            raise ApplyError("payload.invalid", "Symlink writes are refused.") from error
        raise ApplyError("apply.failed", "Extracting the archive reported a failure status.") from error


def apply_files_archive_extract(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    if payload.get("locationId") == "files.location.trash":
        raise ApplyError("payload.invalid", "Trash entries cannot be extracted.")
    location_id = payload.get("locationId")
    files_location_key(location_id)
    specs = require_archive_entries(payload)
    if len(specs) != 1:
        raise ApplyError("payload.invalid", "Extract one zip archive at a time.")
    home = pathlib.Path.home()
    spec = specs[0]
    entry_payload = {
        "locationId": location_id,
        "entryRelativePath": spec["entryRelativePath"],
        "entryId": spec["entryId"],
    }
    _, final, relative = resolve_entry_path(entry_payload, home)
    try:
        info = final.lstat()
    except OSError as error:
        raise ApplyError("resource.unresolved", "The entry is not present.") from error
    if stat.S_ISLNK(info.st_mode):
        raise ApplyError("payload.invalid", "Symlink entries cannot be extracted.")
    if not stat.S_ISREG(info.st_mode):
        raise ApplyError("payload.invalid", "Only a regular zip file can be extracted.")
    if not final.name.lower().endswith(".zip") or final.name.lower() == ".zip":
        raise ApplyError("payload.invalid", "Only a zip archive can be extracted.")
    dest_parent = final.parent
    refuse_trash_destination(dest_parent, home)
    parent_relative = "/".join(relative.split("/")[:-1])
    resource_id = bind_files_named_directory_resource(
        payload, stable_directory_id(location_id, parent_relative)
    )
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        zip_fd = os.open(final, flags)
    except OSError as error:
        if error.errno in {errno.ELOOP, errno.EEXIST}:
            raise ApplyError("payload.invalid", "Symlink entries cannot be extracted.") from error
        raise ApplyError("resource.unresolved", "The entry is not present.") from error
    created = False
    dest_dir: pathlib.Path | None = None
    dest_name = ""
    try:
        zip_info = os.fstat(zip_fd)
        if stat.S_ISLNK(zip_info.st_mode) or not stat.S_ISREG(zip_info.st_mode):
            raise ApplyError("payload.invalid", "Only a regular zip file can be extracted.")
        with os.fdopen(zip_fd, "rb") as handle:
            zip_fd = -1
            try:
                zf = zipfile.ZipFile(handle, "r")
            except zipfile.BadZipFile as error:
                raise ApplyError("payload.invalid", "The selected file is not a zip archive.") from error
            with zf:
                members = zf.infolist()
                if len(members) > MAX_COPY_ENTRIES:
                    raise ApplyError("payload.out-of-range", "The archive exceeds its entry bound.")
                remaining_bytes = MAX_EXTRACT_BYTES
                planned: list[tuple[zipfile.ZipInfo, list[str], bool]] = []
                for member in members:
                    if member.flag_bits & 0x1:
                        raise ApplyError("payload.invalid", "Encrypted archives cannot be extracted.")
                    if zip_member_is_symlink(member):
                        raise ApplyError("payload.invalid", "Symlink writes are refused.")
                    segments, flagged_directory = zip_arcname_segments(member.filename)
                    is_directory = zip_member_is_directory(member, flagged_directory)
                    if not is_directory:
                        remaining_bytes -= int(member.file_size)
                        if remaining_bytes < 0:
                            raise ApplyError(
                                "payload.out-of-range",
                                "The archive exceeds its uncompressed bound.",
                            )
                    planned.append((member, segments, is_directory))
                try:
                    dest_parent_fd = open_nofollow(
                        dest_parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
                    )
                except OSError as error:
                    raise ApplyError("resource.unresolved", "The destination parent is not present.") from error
                try:
                    dest_parent_info = os.fstat(dest_parent_fd)
                    if not stat.S_ISDIR(dest_parent_info.st_mode):
                        raise ApplyError("resource.unresolved", "The destination parent is not a directory.")
                    taken = {name.lower() for name in os.listdir(dest_parent_fd)}
                    stem = archive_stem(final.name, False)
                    if not stem or stem in {".", ".."} or "/" in stem or "\\" in stem:
                        raise ApplyError("payload.invalid", "The archive name is not extractable.")
                    dest_name = next_copy_name(taken, stem)
                    refuse_trash_destination(dest_parent / dest_name, home)
                    try:
                        os.mkdir(dest_name, 0o755, dir_fd=dest_parent_fd)
                    except FileExistsError as error:
                        raise ApplyError("apply.exists", "Something already occupies the extract folder.") from error
                    except OSError as error:
                        raise ApplyError("apply.failed", "Extracting the archive reported a failure status.") from error
                    dest_dir = dest_parent / dest_name
                    created = True
                    dest_root_fd = os.open(
                        dest_name,
                        os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
                        dir_fd=dest_parent_fd,
                    )
                finally:
                    os.close(dest_parent_fd)
                try:
                    remaining = [MAX_COPY_ENTRIES]
                    budget = [MAX_EXTRACT_BYTES]
                    for member, segments, is_directory in planned:
                        if remaining[0] <= 0:
                            raise ApplyError("payload.out-of-range", "The archive exceeds its entry bound.")
                        remaining[0] -= 1
                        current_fd = dest_root_fd
                        owned: list[int] = []
                        try:
                            for index, segment in enumerate(segments):
                                last = index == len(segments) - 1
                                if last and not is_directory:
                                    file_flags = (
                                        os.O_WRONLY
                                        | os.O_CREAT
                                        | os.O_EXCL
                                        | getattr(os, "O_NOFOLLOW", 0)
                                    )
                                    try:
                                        out_fd = os.open(segment, file_flags, 0o644, dir_fd=current_fd)
                                    except FileExistsError as error:
                                        raise ApplyError(
                                            "apply.exists",
                                            "Something already occupies an extracted name.",
                                        ) from error
                                    except OSError as error:
                                        if error.errno in {errno.ELOOP, errno.EEXIST}:
                                            raise ApplyError("payload.invalid", "Symlink writes are refused.") from error
                                        raise ApplyError(
                                            "apply.failed",
                                            "Extracting the archive reported a failure status.",
                                        ) from error
                                    try:
                                        with os.fdopen(out_fd, "wb") as outgoing:
                                            with zf.open(member, "r") as incoming:
                                                while True:
                                                    chunk = incoming.read(65536)
                                                    if not chunk:
                                                        break
                                                    budget[0] -= len(chunk)
                                                    if budget[0] < 0:
                                                        raise ApplyError(
                                                            "payload.out-of-range",
                                                            "The archive exceeds its uncompressed bound.",
                                                        )
                                                    outgoing.write(chunk)
                                    except ApplyError:
                                        raise
                                    except OSError as error:
                                        raise ApplyError(
                                            "apply.failed",
                                            "Extracting the archive reported a failure status.",
                                        ) from error
                                else:
                                    next_fd = ensure_extract_dir(current_fd, segment)
                                    owned.append(next_fd)
                                    current_fd = next_fd
                        finally:
                            for descriptor in reversed(owned):
                                os.close(descriptor)
                finally:
                    os.close(dest_root_fd)
    except ApplyError:
        if zip_fd >= 0:
            os.close(zip_fd)
        if created and dest_dir is not None:
            try:
                remove_replica(dest_dir)
            except ApplyError:
                pass
        raise
    except OSError as error:
        if zip_fd >= 0:
            os.close(zip_fd)
        if created and dest_dir is not None:
            try:
                remove_replica(dest_dir)
            except ApplyError:
                pass
        raise ApplyError("apply.failed", "Extracting the archive reported a failure status.") from error
    json.dump(
        {
            "ok": True,
            "resourceId": resource_id,
            "folderName": dest_name,
            "created": True,
            "count": 1,
        },
        stdout,
    )
    stdout.write("\n")
    return 0


def require_properties_entry(payload: Mapping[str, Any]) -> Mapping[str, Any]:
    raw = payload.get("entries")
    if raw is None:
        entry_id = payload.get("entryId")
        relative = payload.get("entryRelativePath")
        if not isinstance(entry_id, str) or not isinstance(relative, str) or not relative:
            raise ApplyError("payload.invalid", "The apply payload names no entry.")
        return {"entryId": entry_id, "entryRelativePath": relative}
    if not isinstance(raw, list) or len(raw) != 1:
        raise ApplyError("payload.invalid", "Read Properties for one entry at a time.")
    item = raw[0]
    if not isinstance(item, Mapping):
        raise ApplyError("payload.invalid", "The apply payload names no entry.")
    entry_id = item.get("entryId")
    relative = item.get("entryRelativePath")
    if not isinstance(entry_id, str) or not isinstance(relative, str) or not relative:
        raise ApplyError("payload.invalid", "The apply payload names no entry.")
    return {"entryId": entry_id, "entryRelativePath": relative}


def refuse_trash_read(path: pathlib.Path, home: pathlib.Path) -> None:
    trash = trash_root(home)
    try:
        trash_resolved = trash.resolve()
    except OSError:
        trash_resolved = trash
    try:
        located = path.resolve(strict=False)
    except OSError as error:
        raise ApplyError("resource.unresolved", "The entry is not present.") from error
    if located == trash_resolved or trash_resolved in located.parents:
        raise ApplyError("payload.invalid", "Trash entries cannot show session Properties.")


def apply_files_entry_properties(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    if payload.get("locationId") == "files.location.trash":
        raise ApplyError("payload.invalid", "Trash entries cannot show session Properties.")
    location_id = payload.get("locationId")
    files_location_key(location_id)
    spec = require_properties_entry(payload)
    home = pathlib.Path.home()
    entry_payload = {
        "locationId": location_id,
        "entryRelativePath": spec["entryRelativePath"],
        "entryId": spec["entryId"],
    }
    _, final, relative = resolve_entry_path(entry_payload, home)
    refuse_trash_read(final, home)
    try:
        preview = final.lstat()
    except OSError as error:
        raise ApplyError("resource.unresolved", "The entry is not present.") from error
    parent_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        parent_fd = os.open(final.parent, parent_flags)
    except OSError as error:
        if error.errno in {errno.ELOOP, errno.EEXIST}:
            raise ApplyError("payload.invalid", "Symlink follow is refused.") from error
        raise ApplyError("resource.unresolved", "The entry parent is not present.") from error
    fd = -1
    try:
        if stat.S_ISLNK(preview.st_mode):
            info = os.stat(final.name, dir_fd=parent_fd, follow_symlinks=False)
            if not stat.S_ISLNK(info.st_mode):
                raise ApplyError("payload.invalid", "Symlink follow is refused.")
            kind = "symlink"
            size_bytes = None
        elif stat.S_ISREG(preview.st_mode):
            flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
            try:
                fd = os.open(final.name, flags, dir_fd=parent_fd)
            except OSError as error:
                if error.errno in {errno.ELOOP, errno.EEXIST}:
                    raise ApplyError("payload.invalid", "Symlink follow is refused.") from error
                raise ApplyError("resource.unresolved", "The entry is not present.") from error
            info = os.fstat(fd)
            if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
                raise ApplyError("payload.invalid", "Symlink follow is refused.")
            kind = "file"
            size_bytes = int(info.st_size)
        elif stat.S_ISDIR(preview.st_mode):
            flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
            try:
                fd = os.open(final.name, flags, dir_fd=parent_fd)
            except OSError as error:
                if error.errno in {errno.ELOOP, errno.EEXIST}:
                    raise ApplyError("payload.invalid", "Symlink follow is refused.") from error
                raise ApplyError("resource.unresolved", "The entry is not present.") from error
            info = os.fstat(fd)
            if not stat.S_ISDIR(info.st_mode):
                raise ApplyError("payload.invalid", "Symlink follow is refused.")
            kind = "directory"
            size_bytes = None
        else:
            raise ApplyError("payload.invalid", "That entry kind cannot show session Properties.")
    finally:
        if fd >= 0:
            os.close(fd)
        os.close(parent_fd)
    location_path = str(final.parent)
    if len(location_path) > MAX_PROPERTIES_PATH:
        raise ApplyError("payload.out-of-range", "The location path exceeds its bound.")
    modified_ms = min(info.st_mtime_ns // 1_000_000, 9007199254740991)
    json.dump(
        {
            "ok": True,
            "name": final.name,
            "kind": kind,
            "sizeBytes": size_bytes,
            "modifiedMs": modified_ms,
            "locationPath": location_path,
            "entryRelativePath": relative,
            "locationId": location_id,
            "explanation": "Read Properties through this session.",
        },
        stdout,
    )
    stdout.write("\n")
    return 0

def apply_files_directory_create(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    resource_id = payload.get("resourceId")
    if not isinstance(resource_id, str):
        raise ApplyError("payload.invalid", "The apply payload names no files directory.")
    location_id = payload.get("locationId")
    parent = payload.get("parentRelativePath")
    if not isinstance(location_id, str) or not isinstance(parent, str):
        raise ApplyError("payload.invalid", "The apply payload names no scoped directory.")
    if resource_id != stable_directory_id(location_id, parent):
        raise ApplyError("payload.invalid", "The apply payload targets another directory than its resource.")
    created = create_directory(payload, pathlib.Path.home())
    json.dump({"ok": True, "resourceId": resource_id, "created": created.name}, stdout)
    stdout.write("\n")
    return 0

def require_mime_type(payload):
    value = payload.get("mimeType")
    if not isinstance(value, str) or not value or len(value) > MAX_MIME_LENGTH:
        raise ApplyError("payload.invalid", "The apply payload names no MIME type.")
    parts = value.split("/")
    if len(parts) != 2 or not parts[0] or not parts[1]:
        raise ApplyError("payload.invalid", "The MIME type is not a type/subtype pair.")
    for part in parts:
        for character in part:
            if not (character.isalnum() or character in "._-+"):
                raise ApplyError("payload.invalid", "The MIME type holds an unsafe character.")
    return value

def apply_default_mime(mime_type, desktop_id, run=subprocess.run):
    completed = run(
        [XDG_MIME, "default", desktop_id, mime_type],
        capture_output=True,
        text=True,
        timeout=15,
    )
    if completed.returncode != 0:
        raise ApplyError("apply.failed", "Setting the default application reported a failure status.")

def apply_defaults_mime_set(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    resource_id = payload.get("resourceId")
    if not isinstance(resource_id, str) or not resource_id.startswith("defaults.association."):
        raise ApplyError("payload.invalid", "The apply payload names no default association.")
    mime_type = require_mime_type(payload)
    desktop_id = resolve_application(payload)
    apply_default_mime(mime_type, desktop_id)
    json.dump({"ok": True, "resourceId": resource_id, "mimeType": mime_type, "desktopId": desktop_id}, stdout)
    stdout.write("\n")
    return 0

def apply_defaults_protocol_set(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    resource_id = payload.get("resourceId")
    if not isinstance(resource_id, str) or not resource_id.startswith("defaults.association."):
        raise ApplyError("payload.invalid", "The apply payload names no default association.")
    scheme = require_scheme(payload)
    desktop_id = resolve_application(payload)
    apply_default_protocol(scheme, desktop_id)
    json.dump({"ok": True, "resourceId": resource_id, "scheme": scheme, "desktopId": desktop_id}, stdout)
    stdout.write("\n")
    return 0

def apply_network_wifi_enabled(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    resource_id = payload.get("resourceId")
    if resource_id != NETWORK_WIFI_ID:
        raise ApplyError("resource.unresolved", "The apply payload names no code-owned radio.")
    enabled = require_enabled(payload)
    apply_wifi_radio(enabled)
    json.dump({"ok": True, "resourceId": resource_id, "enabled": enabled}, stdout)
    stdout.write("\n")
    return 0

def apply_input_keyboard_layout(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    resource_id = require_digest_resource_id(payload, "input.keyboard.")
    index = require_layout_index(payload)
    device_name = resolve_keyboard_name(resource_id, list_keyboards())
    apply_keyboard_layout(device_name, index)
    json.dump({"ok": True, "resourceId": resource_id, "layoutIndex": index}, stdout)
    stdout.write("\n")
    return 0

def apply_display_brightness(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    resource_id = require_digest_resource_id(payload, "display.output.")
    percent = require_percent(payload)
    monitor_name = resolve_monitor_name(resource_id, list_monitors())
    apply_brightness(monitor_name, percent)
    json.dump({"ok": True, "resourceId": resource_id, "percent": percent}, stdout)
    stdout.write("\n")
    return 0

def apply_audio_output_volume(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    resource_id = require_resource_id(payload)
    percent = require_percent(payload)
    sink_name = resolve_sink_name(resource_id, list_sinks())
    apply_volume(sink_name, percent)
    json.dump({"ok": True, "resourceId": resource_id, "percent": percent}, stdout)
    stdout.write("\n")
    return 0

def list_power_profiles(run: Any = subprocess.run) -> list[str]:
    completed = run([POWERPROFILESCTL, "list"], capture_output=True, text=True, timeout=5)
    if completed.returncode != 0:
        raise ApplyError("probe.failed", "The power profile probe reported a failure status.")
    profiles = []
    for line in completed.stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("*"):
            stripped = stripped[1:].strip()
        if stripped.endswith(":") and " " not in stripped[:-1]:
            name = stripped[:-1]
            if name and name not in profiles:
                profiles.append(name)
    if not profiles:
        raise ApplyError("probe.invalid", "The power profile probe returned no profiles.")
    return profiles

def resolve_profile(payload: Mapping[str, Any], profiles: list[str]) -> str:
    profile = payload.get("profile")
    if not isinstance(profile, str) or not profile:
        raise ApplyError("payload.invalid", "The apply payload names no power profile.")
    if profile not in profiles:
        raise ApplyError("resource.unresolved", "The named power profile is not offered by this host.")
    return profile

def apply_power_profile(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    if payload.get("resourceId") != POWER_RESOURCE_ID:
        raise ApplyError("payload.invalid", "The apply payload names no power profile resource.")
    profile = resolve_profile(payload, list_power_profiles())
    completed = subprocess.run([POWERPROFILESCTL, "set", profile], capture_output=True, text=True, timeout=5)
    if completed.returncode != 0:
        raise ApplyError("apply.failed", "Setting the power profile reported a failure status.")
    json.dump({"ok": True, "resourceId": POWER_RESOURCE_ID, "profile": profile}, stdout)
    stdout.write("\n")
    return 0

BOOT_ID_PATH = "/proc/sys/kernel/random/boot_id"

def process_start_token(pid: int) -> str | None:
    try:
        with open(BOOT_ID_PATH, "r", encoding="utf-8") as handle:
            boot_id = handle.read(128).strip()
        with open(f"/proc/{pid}/stat", "r", encoding="utf-8") as handle:
            stat_line = handle.read(4096)
    except OSError:
        return None
    close = stat_line.rfind(")")
    if close < 0:
        return None
    fields = stat_line[close + 2:].split()
    if len(fields) < 20:
        return None
    try:
        start_ticks = int(fields[19])
    except ValueError:
        return None
    return hashlib.sha256(f"{boot_id}:{pid}:{start_ticks}".encode("utf-8")).hexdigest()[:16]

def process_owner(pid: int) -> int | None:
    try:
        return os.stat(f"/proc/{pid}").st_uid
    except OSError:
        return None

def stable_termination_id(pid: int, token: str) -> str:
    digest = hashlib.sha256(f"process.termination\0process.{pid}.{token}".encode("utf-8")).hexdigest()
    return f"process.termination.{digest}"

def apply_process_terminate(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    resource_id = payload.get("resourceId")
    pid = payload.get("pid")
    if not isinstance(resource_id, str) or not resource_id.startswith("process.termination."):
        raise ApplyError("payload.invalid", "The apply payload names no process termination resource.")
    if isinstance(pid, bool) or not isinstance(pid, int) or pid <= 1:
        raise ApplyError("payload.invalid", "The apply payload names no terminable process id.")
    token = process_start_token(pid)
    if token is None:
        raise ApplyError("resource.unresolved", "The named process is not present.")
    if stable_termination_id(pid, token) != resource_id:
        raise ApplyError("resource.unresolved", "The live process identity does not match the approved resource.")
    if process_owner(pid) != os.getuid():
        raise ApplyError("payload.invalid", "The named process is not owned by this account.")
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError as error:
        raise ApplyError("apply.failed", "Signalling the process reported a failure status.") from error
    json.dump({"ok": True, "resourceId": resource_id, "pid": pid}, stdout)
    stdout.write("\n")
    return 0

def require_software_package_id(payload: Mapping[str, Any]) -> str:
    package_id = payload.get("packageId")
    if not isinstance(package_id, str) or not SOFTWARE_PACKAGE_ID.fullmatch(package_id):
        raise ApplyError("payload.invalid", "The apply payload names no admitted software catalog identity.")
    return package_id

def resolve_session_package_ref(package_id: str) -> str:
    catalog_path = pathlib.Path(__file__).resolve().parents[3] / "ultimate" / "software" / "catalog-v0.json"
    try:
        document = json.loads(catalog_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ApplyError("package.catalog-unreadable", "The code-owned software catalog could not be read.") from error
    entries = document.get("entries") if isinstance(document, dict) else None
    if not isinstance(entries, list):
        raise ApplyError("package.catalog-invalid", "The code-owned software catalog has no entry list.")
    for entry in entries:
        if not isinstance(entry, Mapping):
            continue
        if entry.get("id") != package_id:
            continue
        source_type = entry.get("sourceType")
        package_ref = entry.get("packageRef")
        if source_type not in ("curated", "signed-repo"):
            raise ApplyError("package.source-unsupported", "This source channel has no code-owned root install path yet.")
        if not isinstance(package_ref, str) or not package_ref:
            raise ApplyError("package.unknown", "A requested package is not admitted by the code-owned catalog.")
        return package_ref
    raise ApplyError("package.unknown", "A requested package is not admitted by the code-owned catalog.")

def run_software_helper(helper: str, package_ref: str, run: Any) -> None:
    completed = run(
        [helper, package_ref],
        capture_output=True,
        text=True,
        timeout=SOFTWARE_COMMAND_TIMEOUT_SECONDS,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or "").strip()[:480]
        raise ApplyError("command.failed", detail or "The session package helper reported a failure.")

def apply_software_mutation(stdin: Any, stdout: Any, helper: str, explanation: str, run: Any) -> int:
    try:
        payload = read_payload(stdin)
        package_id = require_software_package_id(payload)
        package_ref = resolve_session_package_ref(package_id)
        run_software_helper(helper, package_ref, run)
    except ApplyError as error:
        json.dump({"ok": False, "code": error.code, "explanation": error.explanation}, stdout)
        stdout.write("\n")
        return 1
    json.dump(
        {
            "ok": True,
            "packageId": package_id,
            "packageRef": package_ref,
            "explanation": explanation.format(package_ref=package_ref),
        },
        stdout,
    )
    stdout.write("\n")
    return 0

def apply_software_install(stdin: Any, stdout: Any, run: Any = subprocess.run) -> int:
    return apply_software_mutation(stdin, stdout, OMARCHY_PKG_ADD, "Installed {package_ref}.", run)

def apply_software_remove(stdin: Any, stdout: Any, run: Any = subprocess.run) -> int:
    return apply_software_mutation(stdin, stdout, OMARCHY_PKG_DROP, "Removed {package_ref}.", run)

def update_lock_path() -> pathlib.Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    return pathlib.Path(runtime) / "omarchy-update.lock"

def default_update_lock_held() -> bool:
    try:
        fd = os.open(update_lock_path(), os.O_RDWR)
    except FileNotFoundError:
        return False
    except OSError:
        return False
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(fd, fcntl.LOCK_UN)
        return False
    except OSError:
        return True
    finally:
        os.close(fd)

def run_update_helper(argv: list[str], run: Any, timeout: int) -> Any:
    try:
        return run(argv, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError as error:
        raise ApplyError("command.unavailable", "The code-owned system command is not installed.") from error

def probe_update_channel(run: Any) -> str:
    completed = run_update_helper([OMARCHY_VERSION_CHANNEL], run, 30)
    if completed.returncode != 0:
        raise ApplyError("command.failed", "The channel probe reported a failure status.")
    for line in completed.stdout.splitlines():
        token = line.strip().lower()
        if token:
            return token
    raise ApplyError("command.failed", "The channel probe named no channel.")

def require_update_channel(payload: Mapping[str, Any]) -> str:
    channel = payload.get("channel")
    if not isinstance(channel, str) or not channel.strip():
        raise ApplyError("payload.invalid", "The apply payload names no update channel.")
    token = channel.strip().lower()
    if token not in UPDATE_CHANNELS:
        raise ApplyError("payload.invalid", "The requested channel is not a code-owned update channel.")
    return token

def refuse_channel_mismatch(requested: str, active: str) -> None:
    if requested != active:
        raise ApplyError(
            "update.channel-mismatch",
            "The requested channel is not the channel this machine tracks.",
        )

def probe_update_available(run: Any) -> tuple[bool, list[str]]:
    completed = run_update_helper([OMARCHY_UPDATE_AVAILABLE], run, 60)
    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    if completed.returncode == 0:
        return True, lines
    return False, lines

def probe_update_disk(run: Any) -> tuple[bool, str]:
    completed = run_update_helper([OMARCHY_UPDATE_FREE_SPACE], run, 15)
    if completed.returncode == 0:
        return True, ""
    detail = (completed.stdout or completed.stderr or "").strip()[:480]
    return False, detail or "This machine does not have enough free disk space to update safely."

def update_history_log_path() -> pathlib.Path:
    override = os.environ.get("OMARCHY_UPDATE_LOG")
    if override:
        return pathlib.Path(override)
    return pathlib.Path("/tmp/omarchy-update.log")


def update_history_state_dir() -> pathlib.Path:
    xdg = os.environ.get("XDG_STATE_HOME")
    if xdg:
        return pathlib.Path(xdg) / "omarchy"
    return pathlib.Path.home() / ".local" / "state" / "omarchy"


def iso_from_mtime(path: pathlib.Path) -> str:
    stamp = datetime.datetime.fromtimestamp(path.stat().st_mtime, datetime.timezone.utc)
    return stamp.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def analyze_update_history_text(text: str) -> list[dict[str, str]]:
    failures: list[dict[str, str]] = []
    if "Updating linux initcpios" in text and "Initcpio image generation successful" not in text:
        failures.append(
            {
                "code": "update.history.initramfs",
                "title": "Initramfs generation may have failed",
                "detail": "The update transcript started initramfs generation but did not record success. Review the log before restart.",
            }
        )
    if "Something went wrong during the update" in text:
        failures.append(
            {
                "code": "update.history.failed",
                "title": "The update did not finish",
                "detail": "The update transcript recorded a failure. Review the log and retry the update.",
            }
        )
    if "already running" in text.lower():
        failures.append(
            {
                "code": "update.history.lock-held",
                "title": "An Omarchy update was already running",
                "detail": "The transcript records a held update lock.",
            }
        )
    lowered = text.lower()
    if "10 gib" in lowered or "free to safely update" in lowered:
        failures.append(
            {
                "code": "update.history.disk-space",
                "title": "The update stopped for disk space",
                "detail": "The transcript records a free-space refusal.",
            }
        )
    return failures


def inspect_update_restart_markers(state_dir: pathlib.Path) -> tuple[bool, list[str]]:
    reboot_required = (state_dir / "reboot-required").is_file()
    restart_required: list[str] = []
    if state_dir.is_dir():
        for marker in sorted(state_dir.glob("restart-*-required")):
            name = marker.name[len("restart-") : -len("-required")]
            if name:
                restart_required.append(name)
    return reboot_required, restart_required


def apply_system_update_history(
    stdin: Any,
    stdout: Any,
    run: Any = subprocess.run,
) -> int:
    del run
    try:
        read_payload(stdin)
        log_path = update_history_log_path()
        reboot_required, restart_required = inspect_update_restart_markers(update_history_state_dir())
        if not log_path.is_file():
            json.dump(
                {
                    "ok": True,
                    "available": False,
                    "empty": True,
                    "entries": [],
                    "failures": [],
                    "logPath": str(log_path),
                    "logModifiedAt": None,
                    "rebootRequired": reboot_required,
                    "restartRequired": restart_required,
                    "explanation": "No update transcript is available on this session.",
                },
                stdout,
            )
            stdout.write("\n")
            return 0
        text = log_path.read_text(encoding="utf-8", errors="replace")
        failures = analyze_update_history_text(text)
        occurred_at = iso_from_mtime(log_path)
        status = "failed" if failures else "recorded"
        title = "Last Omarchy update transcript"
        if failures:
            explanation = "The last update transcript recorded structured failures."
            detail = failures[0]["detail"]
        else:
            explanation = "The last Omarchy update transcript is available on this session."
            detail = "This session read the existing Omarchy update log. Restart and reboot writers stay unavailable."
        json.dump(
            {
                "ok": True,
                "available": True,
                "empty": False,
                "entries": [
                    {
                        "id": "update.history.transcript",
                        "kind": "transcript",
                        "status": status,
                        "title": title,
                        "detail": detail,
                        "occurredAt": occurred_at,
                    }
                ],
                "failures": failures,
                "logPath": str(log_path),
                "logModifiedAt": occurred_at,
                "rebootRequired": reboot_required,
                "restartRequired": restart_required,
                "explanation": explanation,
            },
            stdout,
        )
        stdout.write("\n")
        return 0
    except ApplyError as error:
        json.dump({"ok": False, "code": error.code, "explanation": error.explanation}, stdout)
        stdout.write("\n")
        return 1


def classify_update_failure(completed: Any) -> ApplyError:
    detail = (completed.stderr or completed.stdout or "").strip()[:480]
    text = detail.lower()
    if any(marker in text for marker in UPDATE_AUTH_MARKERS):
        return ApplyError("update.auth-denied", detail or "This session could not authorize the update.")
    if "already running" in text:
        return ApplyError("update.lock-held", detail or "An Omarchy update is already running.")
    if "10 gib" in text or "free to safely update" in text:
        return ApplyError("update.disk-space", detail or "This machine does not have enough free disk space to update safely.")
    return ApplyError("command.failed", detail or "The session update helper reported a failure.")

def apply_system_update_status(
    stdin: Any,
    stdout: Any,
    run: Any = subprocess.run,
    lock_held: Any = None,
) -> int:
    try:
        read_payload(stdin)
        channel = probe_update_channel(run)
        available, lines = probe_update_available(run)
        held = lock_held() if callable(lock_held) else default_update_lock_held()
        disk_ok, disk_detail = probe_update_disk(run)
        if held:
            explanation = "An Omarchy update is already running."
        elif not disk_ok:
            explanation = disk_detail
        elif available:
            explanation = f"Updates are available on {channel}."
        else:
            explanation = f"Omarchy is up to date on {channel}."
        json.dump(
            {
                "ok": True,
                "channel": channel,
                "available": available,
                "availableLines": lines,
                "lockHeld": held,
                "diskOk": disk_ok,
                "explanation": explanation,
            },
            stdout,
        )
        stdout.write("\n")
        return 0
    except ApplyError as error:
        json.dump({"ok": False, "code": error.code, "explanation": error.explanation}, stdout)
        stdout.write("\n")
        return 1

def apply_system_update(
    stdin: Any,
    stdout: Any,
    run: Any = subprocess.run,
    lock_held: Any = None,
) -> int:
    try:
        payload = read_payload(stdin)
        requested = require_update_channel(payload)
        active = probe_update_channel(run)
        refuse_channel_mismatch(requested, active)
        if lock_held() if callable(lock_held) else default_update_lock_held():
            raise ApplyError("update.lock-held", "An Omarchy update is already running.")
        disk_ok, disk_detail = probe_update_disk(run)
        if not disk_ok:
            raise ApplyError("update.disk-space", disk_detail)
        available, _lines = probe_update_available(run)
        if not available:
            raise ApplyError("update.none-available", "No system updates are available.")
        completed = run_update_helper([OMARCHY_UPDATE, "-y"], run, UPDATE_COMMAND_TIMEOUT_SECONDS)
        if completed.returncode != 0:
            raise classify_update_failure(completed)
    except ApplyError as error:
        json.dump({"ok": False, "code": error.code, "explanation": error.explanation}, stdout)
        stdout.write("\n")
        return 1
    json.dump(
        {
            "ok": True,
            "channel": requested,
            "explanation": f"Installed system updates on {requested}.",
        },
        stdout,
    )
    stdout.write("\n")
    return 0

MAX_STARTUP_FILES = 64
MAX_DESKTOP_BYTES = 65536
SYSTEM_AUTOSTART = pathlib.Path("/etc/xdg/autostart")


def valid_startup_desktop_id(value: object) -> bool:
    return (
        isinstance(value, str)
        and value.isascii()
        and 9 <= len(value) <= 255
        and value.endswith(".desktop")
        and all(character.isalnum() or character in "_.+-" for character in value)
        and "/" not in value
        and "\\" not in value
    )


def resolve_startup_home(home: Any) -> pathlib.Path:
    path = pathlib.Path.home() if home is None else pathlib.Path(home)
    try:
        if path.is_symlink() or not path.is_dir():
            raise ApplyError("startup.home-unavailable", "This session has no usable home directory for XDG autostart.")
    except OSError as error:
        raise ApplyError("startup.home-unavailable", "This session has no usable home directory for XDG autostart.") from error
    return path


def resolve_startup_system_root(system_root: Any) -> pathlib.Path:
    return SYSTEM_AUTOSTART if system_root is None else pathlib.Path(system_root)


def user_autostart_dir(home: pathlib.Path) -> pathlib.Path:
    return home / ".config" / "autostart"


def user_autostart_writable(home: pathlib.Path) -> bool:
    target = user_autostart_dir(home)
    try:
        if target.exists():
            return (not target.is_symlink()) and target.is_dir() and os.access(target, os.W_OK)
        config = home / ".config"
        if config.exists():
            return (not config.is_symlink()) and config.is_dir() and os.access(config, os.W_OK)
        return os.access(home, os.W_OK)
    except OSError:
        return False


def read_bounded_fd(descriptor: int, maximum: int) -> bytes:
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


def parse_autostart_bytes(raw: bytes) -> dict[str, Any] | None:
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
        if key in {"Type", "Name", "Hidden", "X-GNOME-Autostart-enabled"}:
            if key in values:
                raise ValueError("duplicate autostart key")
            values[key] = value.strip()
    if values.get("Type") != "Application" or not values.get("Name"):
        return None
    name = values["Name"]
    if not name or len(name) > 160:
        return None
    if any(ord(character) < 32 for character in name):
        raise ValueError("desktop display field contains a control character")
    enabled = values.get("Hidden", "false").lower() != "true" and values.get(
        "X-GNOME-Autostart-enabled", "true"
    ).lower() != "false"
    return {"name": name, "enabled": enabled, "text": text}


def rewrite_autostart_enabled(text: str, enabled: bool) -> str:
    newline = "\r\n" if "\r\n" in text else "\n"
    lines = text.splitlines()
    start = None
    end = len(lines)
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped == "[Desktop Entry]":
            start = index
            continue
        if start is not None and index > start and stripped.startswith("[") and stripped.endswith("]"):
            end = index
            break
    if start is None:
        raise ApplyError("startup.entry-unsafe", "The autostart file has no Desktop Entry section.")
    hidden_value = "false" if enabled else "true"
    gnome_value = "true" if enabled else "false"
    hidden_seen = False
    for index in range(start + 1, end):
        stripped = lines[index].strip()
        if stripped.startswith("Hidden="):
            lines[index] = f"Hidden={hidden_value}"
            hidden_seen = True
        elif stripped.startswith("X-GNOME-Autostart-enabled="):
            lines[index] = f"X-GNOME-Autostart-enabled={gnome_value}"
    if not hidden_seen:
        lines.insert(end, f"Hidden={hidden_value}")
    body = newline.join(lines)
    if text.endswith(("\n", "\r\n")):
        body += newline
    return body


def read_startup_name(dir_fd: int, name: str) -> bytes | None:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(name, flags, dir_fd=dir_fd)
    except OSError:
        return None
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_DESKTOP_BYTES:
            return None
        return read_bounded_fd(descriptor, MAX_DESKTOP_BYTES)
    except (OSError, ValueError):
        return None
    finally:
        os.close(descriptor)


def collect_startup_dir(root: pathlib.Path, source: str, entries: dict[str, dict[str, Any]], examined: list[int]) -> None:
    if examined[0] >= MAX_STARTUP_FILES:
        return
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        directory_fd = os.open(root, flags)
    except FileNotFoundError:
        return
    except OSError as error:
        raise ApplyError("startup.autostart-unreadable", "An autostart directory is not a real no-follow directory.") from error
    try:
        names = sorted(os.listdir(directory_fd))
    except OSError as error:
        os.close(directory_fd)
        raise ApplyError("startup.autostart-unreadable", "An autostart directory could not be enumerated.") from error
    try:
        for name in names:
            if examined[0] >= MAX_STARTUP_FILES:
                break
            if not valid_startup_desktop_id(name) or name in entries:
                continue
            examined[0] += 1
            raw = read_startup_name(directory_fd, name)
            if raw is None:
                continue
            try:
                parsed = parse_autostart_bytes(raw)
            except (UnicodeError, ValueError):
                continue
            if parsed is None:
                continue
            entries[name] = {
                "desktopId": name,
                "name": parsed["name"],
                "enabled": parsed["enabled"],
                "source": source,
                "text": parsed["text"],
            }
    finally:
        os.close(directory_fd)


def list_startup_inventory(home: pathlib.Path, system_root: pathlib.Path) -> list[dict[str, Any]]:
    entries: dict[str, dict[str, Any]] = {}
    examined = [0]
    collect_startup_dir(user_autostart_dir(home), "user", entries, examined)
    collect_startup_dir(system_root, "system", entries, examined)
    controllable = user_autostart_writable(home)
    inventory = []
    for desktop_id in sorted(entries):
        entry = entries[desktop_id]
        inventory.append(
            {
                "desktopId": desktop_id,
                "name": entry["name"],
                "enabled": entry["enabled"],
                "source": entry["source"],
                "controllable": controllable,
            }
        )
    return inventory


def locate_startup_entry(desktop_id: str, home: pathlib.Path, system_root: pathlib.Path) -> dict[str, Any] | None:
    entries: dict[str, dict[str, Any]] = {}
    examined = [0]
    collect_startup_dir(user_autostart_dir(home), "user", entries, examined)
    collect_startup_dir(system_root, "system", entries, examined)
    return entries.get(desktop_id)


def ensure_user_autostart(home: pathlib.Path) -> pathlib.Path:
    target = user_autostart_dir(home)
    try:
        if target.exists():
            if target.is_symlink() or not target.is_dir() or not os.access(target, os.W_OK):
                raise ApplyError("startup.autostart-unwritable", "This session cannot write ~/.config/autostart.")
            return target
        target.mkdir(parents=True, exist_ok=True)
    except ApplyError:
        raise
    except OSError as error:
        raise ApplyError("startup.autostart-unwritable", "This session cannot write ~/.config/autostart.") from error
    return target


def write_user_autostart(user_dir: pathlib.Path, desktop_id: str, text: str) -> None:
    dest = user_dir / desktop_id
    try:
        info = dest.lstat()
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
            raise ApplyError("startup.entry-unsafe", "The user autostart file is not a regular file.")
    except FileNotFoundError:
        pass
    except ApplyError:
        raise
    except OSError as error:
        raise ApplyError("startup.entry-unsafe", "The user autostart file is not a regular file.") from error
    tmp = user_dir / f".{desktop_id}.{os.getpid()}.tmp"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(tmp, flags, 0o644)
    except OSError as error:
        raise ApplyError("startup.autostart-unwritable", "This session cannot write ~/.config/autostart.") from error
    try:
        os.write(descriptor, text.encode("utf-8"))
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    try:
        os.replace(tmp, dest)
    except OSError as error:
        try:
            tmp.unlink()
        except OSError:
            pass
        raise ApplyError("startup.autostart-unwritable", "This session cannot write ~/.config/autostart.") from error


def apply_apps_startup_list(stdin: Any, stdout: Any, home: Any = None, system_root: Any = None) -> int:
    try:
        read_payload(stdin)
        home_path = resolve_startup_home(home)
        inventory = list_startup_inventory(home_path, resolve_startup_system_root(system_root))
    except ApplyError as error:
        json.dump({"ok": False, "code": error.code, "explanation": error.explanation}, stdout)
        stdout.write("\n")
        return 1
    empty = len(inventory) == 0
    json.dump(
        {
            "ok": True,
            "empty": empty,
            "entries": inventory,
            "reason": "startup.empty" if empty else "",
            "explanation": (
                "No XDG autostart applications were found for this session. Hyprland session hooks stay outside this list."
                if empty
                else "Startup applications from this session XDG autostart."
            ),
        },
        stdout,
    )
    stdout.write("\n")
    return 0


def apply_apps_startup_set(stdin: Any, stdout: Any, home: Any = None, system_root: Any = None) -> int:
    try:
        payload = read_payload(stdin)
        desktop_id = payload.get("desktopId")
        enabled = payload.get("enabled")
        if not valid_startup_desktop_id(desktop_id) or enabled is not True and enabled is not False:
            raise ApplyError("startup.payload-invalid", "The apply payload names no XDG autostart desktop identity.")
        home_path = resolve_startup_home(home)
        system_path = resolve_startup_system_root(system_root)
        located = locate_startup_entry(desktop_id, home_path, system_path)
        if located is None:
            raise ApplyError("startup.entry-missing", "That startup application is not present in XDG autostart.")
        if located["enabled"] is enabled:
            json.dump(
                {
                    "ok": True,
                    "desktopId": desktop_id,
                    "enabled": enabled,
                    "source": located["source"],
                    "explanation": f"{'Enabled' if enabled else 'Disabled'} {desktop_id} for this session.",
                },
                stdout,
            )
            stdout.write("\n")
            return 0
        user_dir = ensure_user_autostart(home_path)
        write_user_autostart(user_dir, desktop_id, rewrite_autostart_enabled(located["text"], enabled))
        source = "user"
    except ApplyError as error:
        json.dump({"ok": False, "code": error.code, "explanation": error.explanation}, stdout)
        stdout.write("\n")
        return 1
    json.dump(
        {
            "ok": True,
            "desktopId": desktop_id,
            "enabled": enabled,
            "source": source,
            "explanation": f"{'Enabled' if enabled else 'Disabled'} {desktop_id} for this session.",
        },
        stdout,
    )
    stdout.write("\n")
    return 0

ACTIONS = {
    "audio-output-volume-set": apply_audio_output_volume,
    "display-brightness-set": apply_display_brightness,
    "input-keyboard-layout-set": apply_input_keyboard_layout,
    "network-wifi-enabled-set": apply_network_wifi_enabled,
    "defaults-protocol-set": apply_defaults_protocol_set,
    "defaults-mime-set": apply_defaults_mime_set,
    "process-terminate": apply_process_terminate,
    "power-profile-set": apply_power_profile,
    "files-directory-create": apply_files_directory_create,
    "files-entry-trash": apply_files_entry_trash,
    "files-trash-restore": apply_files_trash_restore,
    "files-trash-manage": apply_files_trash_manage,
    "files-entry-open": apply_files_entry_open,
    "files-entry-rename": apply_files_entry_rename,
    "files-entry-copy": apply_files_entry_copy,
    "files-clipboard-copy": apply_files_clipboard_copy,
    "files-clipboard-paste": apply_files_clipboard_paste,
    "files-entry-move": apply_files_entry_move,
    "files-entry-delete": apply_files_entry_delete,
    "files-archive-create": apply_files_archive_create,
    "files-archive-extract": apply_files_archive_extract,
    "files-entry-properties": apply_files_entry_properties,
    "software-install": apply_software_install,
    "software-remove": apply_software_remove,
    "system-update-status": apply_system_update_status,
    "system-update": apply_system_update,
    "system-update-history": apply_system_update_history,
    "apps-startup-list": apply_apps_startup_list,
    "apps-startup-set": apply_apps_startup_set,
}

def main(argv: list[str], stdin: Any = None, stdout: Any = None) -> int:
    stdin = stdin if stdin is not None else sys.stdin
    stdout = stdout if stdout is not None else sys.stdout
    action = argv[0] if argv else "audio-output-volume-set"
    try:
        handler = ACTIONS.get(action)
        if handler is None:
            raise ApplyError("action.unknown", "The requested apply action is not code owned.")
        return handler(stdin, stdout)
    except ApplyError as error:
        json.dump({"ok": False, "code": error.code, "explanation": error.explanation}, stdout)
        stdout.write("\n")
        return 1
    except subprocess.TimeoutExpired:
        json.dump({"ok": False, "code": "probe.timeout", "explanation": "The apply command did not finish."}, stdout)
        stdout.write("\n")
        return 1
    except OSError:
        json.dump({"ok": False, "code": "probe.unavailable", "explanation": "A code-owned command for this action is not installed."}, stdout)
        stdout.write("\n")
        return 1

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
