"""Code-owned session apply helper for user-scope operations."""

from __future__ import annotations

import hashlib
import json
import pathlib
import subprocess
import sys
from typing import Any, Mapping

PACTL = "/usr/bin/pactl"
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

def apply_files_directory_create(stdin: Any, stdout: Any) -> int:
    payload = read_payload(stdin)
    resource_id = payload.get("resourceId")
    if resource_id != FILES_WORKSPACE_ID:
        raise ApplyError("payload.invalid", "The apply payload names no files workspace.")
    created = create_directory(payload, pathlib.Path.home())
    json.dump({"ok": True, "resourceId": resource_id, "created": created.name}, stdout)
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

ACTIONS = {
    "audio-output-volume-set": apply_audio_output_volume,
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
