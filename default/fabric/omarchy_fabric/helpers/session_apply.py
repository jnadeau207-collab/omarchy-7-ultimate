"""Code-owned session apply helper for user-scope operations."""

from __future__ import annotations

import datetime
import errno
import hashlib
import json
import os
import pathlib
import shutil
import signal
import stat
import subprocess
import sys
from typing import Any, Mapping

from .trash_info import parse_trash_info_path, trash_info_document

PACTL = "/usr/bin/pactl"
HYPRCTL = "/usr/bin/hyprctl"
NMCLI = "/usr/bin/nmcli"
XDG_MIME = "/usr/bin/xdg-mime"
XDG_OPEN = "/usr/bin/xdg-open"
DEFAULTS_PROTOCOLS = frozenset({"http", "https", "mailto"})
MAX_MIME_LENGTH = 160
NETWORK_WIFI_ID = "network.radio.wifi"
BRIGHTNESS = "/usr/bin/omarchy-brightness-display"
POWERPROFILESCTL = "/usr/bin/powerprofilesctl"
POWER_RESOURCE_ID = "power.profile.current"
FILES_WORKSPACE_ID = "files.workspace.primary"
MAX_PAYLOAD_BYTES = 8192

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
    resource_id = require_files_resource_id(payload)
    home = pathlib.Path.home()
    _, final, relative = resolve_entry_path(payload, home)
    parent = "/".join(relative.split("/")[:-1])
    if resource_id != stable_directory_id(payload["locationId"], parent):
        raise ApplyError("payload.invalid", "The apply payload targets another directory than its resource.")
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
    resource_id = require_files_resource_id(payload)
    entry_id = require_entry_id(payload)
    home = pathlib.Path.home()
    _, destination, relative = resolve_entry_slot(payload, home)
    parent = "/".join(relative.split("/")[:-1])
    if resource_id != stable_directory_id(payload["locationId"], parent):
        raise ApplyError("payload.invalid", "The apply payload targets another directory than its resource.")
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
    if not stat.S_ISREG(info.st_mode):
        raise ApplyError("payload.invalid", "Only regular files can be copied.")
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
    if "desired" in payload:
        if destination.exists() and source.exists():
            try:
                destination.unlink()
            except OSError as error:
                raise ApplyError("apply.failed", "Removing the copied entry reported a failure status.") from error
            json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "destinationName": dest_name, "copied": False}, stdout)
            stdout.write("\n")
            return 0
        json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "destinationName": dest_name, "copied": False}, stdout)
        stdout.write("\n")
        return 0
    if destination.exists():
        raise ApplyError("apply.exists", "Something already occupies the destination name.")
    try:
        with source.open("rb") as incoming, destination.open("xb") as outgoing:
            shutil.copyfileobj(incoming, outgoing)
    except FileExistsError as error:
        raise ApplyError("apply.exists", "Something already occupies the destination name.") from error
    except OSError as error:
        raise ApplyError("apply.failed", "Copying the entry reported a failure status.") from error
    json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "destinationName": dest_name, "copied": True}, stdout)
    stdout.write("\n")
    return 0

def apply_files_entry_move(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    resource_id = require_files_resource_id(payload)
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
    if resource_id != stable_move_directory_id(dest_location, dest_parent, entry_id):
        raise ApplyError("payload.invalid", "The apply payload targets another directory than its resource.")
    _, source, relative = resolve_entry_path(payload, pathlib.Path.home())
    source_parent = "/".join(relative.split("/")[:-1])
    source_name = relative.rsplit("/", 1)[-1]
    if dest_location == payload.get("locationId") and dest_parent == source_parent and dest_name != source_name:
        raise ApplyError("payload.invalid", "Same-directory name changes use rename.")
    try:
        info = source.lstat()
    except OSError as error:
        raise ApplyError("resource.unresolved", "The entry is not present.") from error
    if stat.S_ISLNK(info.st_mode):
        raise ApplyError("payload.invalid", "Symlink entries cannot be moved.")
    if not stat.S_ISREG(info.st_mode):
        raise ApplyError("payload.invalid", "Only regular files can be moved.")
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
    if dest_location == payload.get("locationId") and dest_parent == source_parent and dest_name == source_name:
        json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "destinationName": dest_name, "moved": False}, stdout)
        stdout.write("\n")
        return 0
    if "desired" in payload:
        if destination.exists() and not source.exists():
            try:
                os.rename(destination, source)
            except OSError as error:
                raise ApplyError("apply.failed", "Restoring the moved entry reported a failure status.") from error
            json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "destinationName": dest_name, "moved": False}, stdout)
            stdout.write("\n")
            return 0
        json.dump({"ok": True, "resourceId": resource_id, "entry": relative, "destinationName": dest_name, "moved": False}, stdout)
        stdout.write("\n")
        return 0
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
    "files-entry-open": apply_files_entry_open,
    "files-entry-rename": apply_files_entry_rename,
    "files-entry-copy": apply_files_entry_copy,
    "files-entry-move": apply_files_entry_move,
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
