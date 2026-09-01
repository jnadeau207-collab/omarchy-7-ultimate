"""Code-owned session apply helper for user-scope operations."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from typing import Any, Mapping

PACTL = "/usr/bin/pactl"
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

def main(argv: list[str], stdin: Any = None, stdout: Any = None) -> int:
    stdin = stdin if stdin is not None else sys.stdin
    stdout = stdout if stdout is not None else sys.stdout
    try:
        payload = read_payload(stdin)
        resource_id = require_resource_id(payload)
        percent = require_percent(payload)
        sink_name = resolve_sink_name(resource_id, list_sinks())
        apply_volume(sink_name, percent)
    except ApplyError as error:
        json.dump({"ok": False, "code": error.code, "explanation": error.explanation}, stdout)
        stdout.write("\n")
        return 1
    except subprocess.TimeoutExpired:
        json.dump({"ok": False, "code": "probe.timeout", "explanation": "The audio command did not finish."}, stdout)
        stdout.write("\n")
        return 1
    json.dump({"ok": True, "resourceId": resource_id, "percent": percent}, stdout)
    stdout.write("\n")
    return 0

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
