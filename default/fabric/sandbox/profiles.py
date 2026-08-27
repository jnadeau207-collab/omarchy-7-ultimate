"""Pure validation of declarative managed-task sandbox profiles."""

from __future__ import annotations

import re
from pathlib import PurePosixPath
from types import MappingProxyType
from typing import Any, Mapping

_STABLE_RE = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$")
_HOST_RE = re.compile(r"^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")

DEFAULT_EXPOSURE = MappingProxyType(
    {
        "home": False,
        "wayland": False,
        "sessionBus": False,
        "sshAgent": False,
        "browserProfiles": False,
        "keyring": False,
        "mainFabricSocket": False,
        "hostNetwork": False,
    }
)


class ProfileValidationError(ValueError):
    pass


def default_profile(task_id: str) -> dict[str, Any]:
    """Create the only ambient-authority profile: every exposure is off."""

    document = {
        "schemaVersion": "v0",
        "profileId": "managed.default",
        "taskId": task_id,
        "exposure": dict(DEFAULT_EXPOSURE),
        "binds": [],
        "network": {"mode": "none", "scopes": []},
    }
    return validate_profile_document(document)


def validate_profile_document(document: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(document, Mapping):
        raise ProfileValidationError("Sandbox profile must be an object.")
    required = {"schemaVersion", "profileId", "taskId", "exposure", "binds", "network"}
    if set(document) != required:
        raise ProfileValidationError("Sandbox profile fields do not match the fixed schema.")
    if document["schemaVersion"] != "v0":
        raise ProfileValidationError("Unsupported sandbox profile version.")
    for field in ("profileId", "taskId"):
        if not isinstance(document[field], str) or not _STABLE_RE.fullmatch(document[field]):
            raise ProfileValidationError(f"{field} must be a stable identifier.")
    if document["exposure"] != dict(DEFAULT_EXPOSURE):
        raise ProfileValidationError("Managed task exposure is fail-closed and cannot be enabled in-process.")
    binds = document["binds"]
    if not isinstance(binds, list) or len(binds) > 32:
        raise ProfileValidationError("Binds must be a bounded list.")
    for bind in binds:
        if not isinstance(bind, Mapping) or set(bind) != {"source", "sourceRoot", "target", "writable"}:
            raise ProfileValidationError("Every bind must use the fixed scoped-bind shape.")
        if not all(isinstance(bind[key], str) and bind[key] for key in ("source", "sourceRoot", "target")):
            raise ProfileValidationError("Bind paths must be non-empty strings.")
        if any("\x00" in bind[key] for key in ("source", "sourceRoot", "target")):
            raise ProfileValidationError("Bind paths cannot contain NUL.")
        if not bind["source"].startswith("/") or not bind["sourceRoot"].startswith("/"):
            raise ProfileValidationError("Host bind sources must be absolute paths.")
        target = PurePosixPath(bind["target"])
        if (
            not target.is_absolute()
            or str(target) != bind["target"]
            or ".." in target.parts
            or "." in target.parts
            or not (str(target).startswith("/workspace/") or str(target).startswith("/artifacts/"))
        ):
            raise ProfileValidationError("Bind target must be a normalized workspace or artifact path.")
        if not isinstance(bind["writable"], bool):
            raise ProfileValidationError("Bind writable must be boolean.")
    network = document["network"]
    if not isinstance(network, Mapping) or set(network) != {"mode", "scopes"}:
        raise ProfileValidationError("Network must use the fixed mode/scopes shape.")
    if network["mode"] not in {"none", "task-proxy"}:
        raise ProfileValidationError("Host network is never an allowed managed-task mode.")
    if not isinstance(network["scopes"], list):
        raise ProfileValidationError("Network scopes must be a list.")
    if network["mode"] == "none" and network["scopes"]:
        raise ProfileValidationError("Network-off profiles cannot carry scopes.")
    if network["mode"] == "task-proxy" and not network["scopes"]:
        raise ProfileValidationError("Task-proxy mode requires explicit destination scopes.")
    normalized_scopes: list[dict[str, Any]] = []
    for scope in network["scopes"]:
        if not isinstance(scope, Mapping) or set(scope) != {"protocol", "host", "port"}:
            raise ProfileValidationError("Network scopes must use the fixed protocol/host/port shape.")
        host = scope["host"]
        port = scope["port"]
        if scope["protocol"] != "https":
            raise ProfileValidationError("Task proxy supports HTTPS scopes only.")
        if not isinstance(host, str) or not _HOST_RE.fullmatch(host.lower().rstrip(".")):
            raise ProfileValidationError("Task proxy host must be an explicit DNS name.")
        if host.lower().rstrip(".") in {"localhost", "localhost.localdomain"}:
            raise ProfileValidationError("Task proxy scopes cannot target localhost.")
        if not isinstance(port, int) or isinstance(port, bool) or not 1 <= port <= 65535:
            raise ProfileValidationError("Task proxy port is invalid.")
        normalized_scopes.append({"protocol": "https", "host": host.lower().rstrip("."), "port": port})
    return {
        "schemaVersion": document["schemaVersion"],
        "profileId": document["profileId"],
        "taskId": document["taskId"],
        "exposure": dict(DEFAULT_EXPOSURE),
        "binds": [dict(item) for item in binds],
        "network": {"mode": network["mode"], "scopes": normalized_scopes},
    }
