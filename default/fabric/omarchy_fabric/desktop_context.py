from __future__ import annotations

import json
import os
import socket
import subprocess
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

from .managed_work import Actor, ManagedWorkError, ManagedWorkPlane
from .managed_work.validation import require_context_source

DESKTOP_SOURCES = frozenset({
    "open-windows",
    "focused-application",
    "selection",
    "virtual-desktops",
    "mode-profile",
})
EXCLUDED_WINDOW_CLASSES = frozenset(
    {
        "hyprlock",
        "org.omarchy.screensaver",
        "polkit-gnome-authentication-agent-1",
        "polkit-kde-authentication-agent-1",
        "lxqt-policykit-agent",
        "gcr-prompter",
        "pinentry",
        "pinentry-qt",
        "pinentry-gtk-2",
    }
)
EXCLUDED_TITLE_MARKERS = (
    "password",
    "passphrase",
    "polkit",
    "unlock",
    "credential",
    "sudo",
    "authentication",
)
WL_PASTE = "/usr/bin/wl-paste"
SELECTION_LIMIT = 4096
PASTE_TIMEOUT = 2
PROTOCOL_MARKERS = (
    "wayland",
    "protocol",
    "connect",
    "display",
    "compositor",
    "no such file",
    "not found",
)
EMPTY_MARKERS = (
    "nothing is copied",
    "no selection",
    "clipboard is empty",
    "no contents",
)

def _hypr_socket() -> str | None:
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not runtime or not signature:
        return None
    path = os.path.join(runtime, "hypr", signature, ".socket.sock")
    if not os.path.exists(path):
        return None
    return path

def _hypr_json(command: str) -> Any:
    path = _hypr_socket()
    if path is None:
        raise ManagedWorkError(
            "context.compositor-unavailable",
            "Desktop context cannot be captured because the compositor socket is unavailable.",
        )
    payload = f"j/{command}".encode("utf-8")
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        client.settimeout(2)
        client.connect(path)
        client.sendall(payload)
        chunks: list[bytes] = []
        while True:
            piece = client.recv(65536)
            if not piece:
                break
            chunks.append(piece)
    except OSError as error:
        raise ManagedWorkError(
            "context.compositor-unavailable",
            "Desktop context cannot be captured because the compositor socket failed.",
            detail=type(error).__name__,
        ) from error
    finally:
        client.close()
    raw = b"".join(chunks).decode("utf-8")
    try:
        return json.loads(raw)
    except json.JSONDecodeError as error:
        raise ManagedWorkError(
            "context.compositor-unavailable",
            "Desktop context cannot be captured because the compositor reply was not JSON.",
        ) from error

def _excluded_window(client: Mapping[str, Any]) -> bool:
    klass = str(client.get("class") or "").strip().lower()
    title = str(client.get("title") or "").strip().lower()
    if klass in EXCLUDED_WINDOW_CLASSES:
        return True
    if any(marker in klass or marker in title for marker in EXCLUDED_TITLE_MARKERS):
        return True
    return False

def _window_record(client: Mapping[str, Any], *, focused: bool) -> dict[str, Any]:
    return {
        "class": str(client.get("class") or ""),
        "title": str(client.get("title") or ""),
        "address": str(client.get("address") or ""),
        "focused": focused,
        "mapped": bool(client.get("mapped", True)),
    }

def _selection_excluded() -> dict[str, Any]:
    return {"available": False, "reason": "selection-excluded", "text": ""}

def _selection_empty() -> dict[str, Any]:
    return {"available": True, "reason": "empty", "text": ""}

def _selection_captured(text: str) -> dict[str, Any]:
    return {"available": True, "reason": "captured", "text": text}

def _decode_selection(payload: bytes) -> str:
    if len(payload) > SELECTION_LIMIT:
        payload = payload[:SELECTION_LIMIT]
    return payload.decode("utf-8", errors="replace")

def _wl_paste_bin() -> str:
    path = Path(WL_PASTE)
    if not path.is_file() or not os.access(path, os.X_OK):
        raise ManagedWorkError(
            "context.selection-unavailable",
            "Desktop selection cannot be captured because wl-paste is unavailable.",
            detail=WL_PASTE,
        )
    return str(path)

def _classify_paste_failure(stderr: str) -> str:
    lowered = stderr.casefold()
    if any(marker in lowered for marker in EMPTY_MARKERS):
        return "empty"
    if any(marker in lowered for marker in PROTOCOL_MARKERS):
        return "unavailable"
    return "unavailable"

def _run_wl_paste(argv: Sequence[str]) -> tuple[int, bytes, str]:
    try:
        completed = subprocess.run(
            list(argv),
            capture_output=True,
            timeout=PASTE_TIMEOUT,
            check=False,
        )
    except FileNotFoundError as error:
        raise ManagedWorkError(
            "context.selection-unavailable",
            "Desktop selection cannot be captured because wl-paste is unavailable.",
            detail=WL_PASTE,
        ) from error
    except subprocess.TimeoutExpired as error:
        raise ManagedWorkError(
            "context.selection-unavailable",
            "Desktop selection cannot be captured because wl-paste timed out.",
            detail=WL_PASTE,
        ) from error
    stderr = (completed.stderr or b"").decode("utf-8", errors="replace")
    return completed.returncode, completed.stdout or b"", stderr

def _paste_text(*, primary: bool) -> dict[str, Any]:
    binary = _wl_paste_bin()
    argv = [binary, "--no-newline"]
    if primary:
        argv = [binary, "--primary", "--no-newline"]
    code, stdout, stderr = _run_wl_paste(argv)
    if code == 0:
        text = _decode_selection(stdout)
        if not text:
            return _selection_empty()
        return _selection_captured(text)
    kind = _classify_paste_failure(stderr)
    if kind == "empty":
        return _selection_empty()
    if primary:
        return {"available": False, "reason": "primary-unavailable", "text": ""}
    raise ManagedWorkError(
        "context.selection-unavailable",
        "Desktop selection cannot be captured because the clipboard protocol is unavailable.",
        detail=stderr.strip() or WL_PASTE,
    )

def _redact_selection(selection: Mapping[str, Any]) -> dict[str, Any]:
    text = str(selection.get("text") or "")
    if any(marker in text.casefold() for marker in EXCLUDED_TITLE_MARKERS):
        return _selection_excluded()
    return dict(selection)

def _live_selection(*, excluded_focus: bool) -> dict[str, Any]:
    if excluded_focus:
        return _selection_excluded()
    selection = _redact_selection(_paste_text(primary=False))
    primary = _redact_selection(_paste_text(primary=True))
    if primary.get("reason") != "primary-unavailable":
        selection = dict(selection)
        selection["primary"] = primary
    return selection

def collect_compositor_snapshot() -> dict[str, Any]:
    clients = _hypr_json("clients")
    active = _hypr_json("activewindow")
    if not isinstance(clients, list):
        clients = []
    if not isinstance(active, dict):
        active = {}
    active_address = str(active.get("address") or "")
    windows = []
    for client in clients:
        if not isinstance(client, dict) or _excluded_window(client):
            continue
        windows.append(_window_record(client, focused=str(client.get("address") or "") == active_address))
    focus = None
    if active and not _excluded_window(active):
        focus = _window_record(active, focused=True)
    return {
        "windows": windows,
        "focus": focus,
        "selection": _live_selection(excluded_focus=bool(active) and _excluded_window(active)),
        "desktops": [],
        "mode": "",
        "features": {},
    }

def collect_virtual_desktops() -> dict[str, Any]:
    workspaces = _hypr_json("workspaces")
    active = _hypr_json("activeworkspace")
    if not isinstance(workspaces, list):
        workspaces = []
    if not isinstance(active, dict):
        active = {}
    active_id = str(active.get("id") or active.get("name") or "")
    desktops = []
    for item in workspaces[:64]:
        if not isinstance(item, dict):
            continue
        ident = str(item.get("id") or item.get("name") or "")
        if not ident:
            continue
        desktops.append(
            {
                "id": ident,
                "name": str(item.get("name") or ident),
                "active": ident == active_id or bool(item.get("focused", False)),
            }
        )
    return {
        "windows": [],
        "focus": None,
        "selection": _selection_empty(),
        "desktops": desktops,
        "mode": "",
        "features": {},
    }

def collect_mode_profile() -> dict[str, Any]:
    home = os.environ.get("HOME") or ""
    omarchy = os.environ.get("OMARCHY_PATH") or ""
    mode = "desktop"
    mode_path = Path(home) / ".local/state/omarchy/ultimate/mode"
    if mode_path.is_file():
        raw = mode_path.read_text(encoding="utf-8").strip()
        if raw == "power-user":
            mode = "power-user"
        elif raw and raw != "desktop":
            raise ManagedWorkError(
                "context.mode-invalid",
                "Mode profile capture refused an unknown mode file value.",
                detail=raw,
            )
    features: dict[str, bool] = {}
    profile_path = Path(omarchy) / "default/ultimate/profiles" / f"{mode}.json"
    if not profile_path.is_file():
        raise ManagedWorkError(
            "context.mode-unavailable",
            "Mode profile capture cannot read the shipped profile contract.",
            detail=str(profile_path),
        )
    try:
        parsed = json.loads(profile_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ManagedWorkError(
            "context.mode-unavailable",
            "Mode profile capture refused a malformed profile contract.",
            detail=type(error).__name__,
        ) from error
    raw_features = parsed.get("features") if isinstance(parsed, dict) else None
    if not isinstance(raw_features, dict):
        raise ManagedWorkError(
            "context.mode-unavailable",
            "Mode profile capture requires a features object.",
        )
    for key, value in raw_features.items():
        if isinstance(key, str):
            features[key] = value is True
    return {
        "windows": [],
        "focus": None,
        "selection": _selection_empty(),
        "desktops": [],
        "mode": mode,
        "features": features,
    }

def _normalize_snapshot(snapshot: Mapping[str, Any]) -> dict[str, Any]:
    windows_in = snapshot.get("windows", [])
    if not isinstance(windows_in, list) or len(windows_in) > 256:
        raise ManagedWorkError("context.snapshot", "Window snapshot must be a bounded array.")
    windows = []
    for item in windows_in:
        if not isinstance(item, dict):
            raise ManagedWorkError("context.snapshot", "Each window record must be an object.")
        if _excluded_window(item):
            continue
        windows.append(
            _window_record(
                item,
                focused=bool(item.get("focused", False)),
            )
        )
    focus_in = snapshot.get("focus")
    focus = None
    if isinstance(focus_in, dict) and not _excluded_window(focus_in):
        focus = _window_record(focus_in, focused=True)
    selection_in = snapshot.get("selection")
    if not isinstance(selection_in, dict):
        selection = _selection_empty()
    else:
        text = str(selection_in.get("text") or "")
        if len(text.encode("utf-8")) > SELECTION_LIMIT:
            raise ManagedWorkError("context.snapshot", "Selection text exceeds its bound.")
        if any(marker in text.casefold() for marker in EXCLUDED_TITLE_MARKERS):
            selection = _selection_excluded()
        elif text:
            selection = _selection_captured(text)
        else:
            selection = _selection_empty()
    desktops_in = snapshot.get("desktops", [])
    if not isinstance(desktops_in, list) or len(desktops_in) > 64:
        raise ManagedWorkError("context.snapshot", "Desktop snapshot must be a bounded array.")
    desktops = []
    for item in desktops_in:
        if not isinstance(item, dict):
            raise ManagedWorkError("context.snapshot", "Each desktop record must be an object.")
        ident = str(item.get("id") or item.get("name") or "")
        if not ident:
            continue
        desktops.append(
            {
                "id": ident,
                "name": str(item.get("name") or ident),
                "active": bool(item.get("active", False)),
            }
        )
    mode = str(snapshot.get("mode") or "")
    features_in = snapshot.get("features", {})
    if features_in is None:
        features_in = {}
    if not isinstance(features_in, dict):
        raise ManagedWorkError("context.snapshot", "Mode features must be an object.")
    features = {str(key): value is True for key, value in features_in.items()}
    return {
        "windows": windows,
        "focus": focus,
        "selection": selection,
        "desktops": desktops,
        "mode": mode,
        "features": features,
    }

def _content_for_source(source: str, snapshot: Mapping[str, Any]) -> dict[str, Any]:
    if source == "open-windows":
        return {"windows": list(snapshot.get("windows") or [])}
    if source == "focused-application":
        focus = snapshot.get("focus")
        return {"focus": focus, "application": (focus or {}).get("class", "")}
    if source == "virtual-desktops":
        return {"desktops": list(snapshot.get("desktops") or [])}
    if source == "mode-profile":
        return {"mode": str(snapshot.get("mode") or "desktop"), "features": dict(snapshot.get("features") or {})}
    return {"selection": snapshot.get("selection") or _selection_empty()}

def capture_desktop_context(
    plane: ManagedWorkPlane,
    actor: Actor,
    *,
    source: str,
    snapshot: Mapping[str, Any] | None = None,
    access_scope: str = "principal",
    sensitivity: str = "personal",
    ttl_seconds: int = 600,
    idempotency_key: str,
    now: float | None = None,
) -> dict[str, Any]:
    source_value = require_context_source(source)
    if source_value not in DESKTOP_SOURCES:
        raise ManagedWorkError(
            "context.source-unsupported",
            "Desktop context capture accepts open-windows, focused-application, selection, virtual-desktops, and mode-profile only.",
            detail=source_value,
        )
    if snapshot is not None:
        data = _normalize_snapshot(snapshot)
    elif source_value == "virtual-desktops":
        data = collect_virtual_desktops()
    elif source_value == "mode-profile":
        data = collect_mode_profile()
    else:
        data = collect_compositor_snapshot()
    return plane.capture_context(
        actor,
        source=source_value,
        access_scope=access_scope,
        content=_content_for_source(source_value, data),
        sensitivity=sensitivity,
        ttl_seconds=ttl_seconds,
        idempotency_key=idempotency_key,
        now=now,
    )
