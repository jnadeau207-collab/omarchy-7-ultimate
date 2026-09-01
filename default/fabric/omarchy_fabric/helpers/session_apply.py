"""Code-owned session apply helper for user-scope operations."""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import signal
import subprocess
import sys
from typing import Any, Mapping

PACTL = "/usr/bin/pactl"
HYPRCTL = "/usr/bin/hyprctl"
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

def stable_directory_id(location_id: str, parent: str) -> str:
    digest = hashlib.sha256(f"files.directory\0{location_id}\0{parent}".encode("utf-8")).hexdigest()
    return f"files.directory.{digest}"

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

def apply_display_brightness(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    resource_id = require_resource_id(payload)
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
    "process-terminate": apply_process_terminate,
    "power-profile-set": apply_power_profile,
    "files-directory-create": apply_files_directory_create,
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

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
