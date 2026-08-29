"""Redacted desktop context broker for open windows, focus, and selection."""

from __future__ import annotations

import json
import os
import socket
from collections.abc import Mapping, Sequence
from typing import Any

from .managed_work import Actor, ManagedWorkError, ManagedWorkPlane
from .managed_work.validation import require_context_source

DESKTOP_SOURCES = frozenset({"open-windows", "focused-application", "selection"})
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
        "selection": {
            "available": False,
            "reason": "selection-not-exported",
            "text": "",
        },
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
    selection = {"available": False, "reason": "selection-not-exported", "text": ""}
    if isinstance(selection_in, dict):
        text = str(selection_in.get("text") or "")
        if len(text.encode("utf-8")) > 4096:
            raise ManagedWorkError("context.snapshot", "Selection text exceeds its bound.")
        lowered = text.casefold()
        if any(marker in lowered for marker in EXCLUDED_TITLE_MARKERS):
            selection = {"available": False, "reason": "selection-excluded", "text": ""}
        else:
            selection = {
                "available": bool(text),
                "reason": "supplied" if text else "empty",
                "text": text,
            }
    return {"windows": windows, "focus": focus, "selection": selection}


def _content_for_source(source: str, snapshot: Mapping[str, Any]) -> dict[str, Any]:
    if source == "open-windows":
        return {"windows": list(snapshot.get("windows") or [])}
    if source == "focused-application":
        focus = snapshot.get("focus")
        return {"focus": focus, "application": (focus or {}).get("class", "")}
    return {"selection": snapshot.get("selection") or {"available": False, "reason": "selection-not-exported", "text": ""}}


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
            "Desktop context capture accepts open-windows, focused-application, and selection only.",
            detail=source_value,
        )
    data = _normalize_snapshot(snapshot) if snapshot is not None else collect_compositor_snapshot()
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
