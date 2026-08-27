"""Strict JSON, identity, cursor, and context-redaction helpers."""

from __future__ import annotations

import base64
import hashlib
import json
import math
import re
from collections.abc import Mapping, Sequence
from typing import Any

from .errors import ManagedWorkError

MAX_JSON_BYTES = 64 * 1024
MAX_JSON_DEPTH = 16
MAX_JSON_NODES = 4096
MAX_STRING_BYTES = 16 * 1024
MAX_ID_BYTES = 160

_ID_RE = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$")
_UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_SECRET_KEY_RE = re.compile(
    r"(?:^|[-_.])(authorization|cookie|credential|keyring|pass(?:word|phrase)?|secret|token)(?:$|[-_.])",
    re.IGNORECASE,
)
_SECRET_COMPACT_KEYS = frozenset(
    {
        "accesstoken",
        "apikey",
        "authorization",
        "cookie",
        "credential",
        "credentials",
        "keyring",
        "passphrase",
        "password",
        "privatekey",
        "refreshtoken",
        "secret",
        "token",
    }
)
_EXCLUDED_CONTEXT_SOURCES = frozenset(
    {
        "lock-screen",
        "password-field",
        "polkit-prompt",
        "browser-credentials",
        "keyring",
        "private-notification",
    }
)


def stable_id(value: Any, *, field: str) -> str:
    if not isinstance(value, str) or not value or len(value.encode("utf-8")) > MAX_ID_BYTES:
        raise ManagedWorkError("validation.id", f"{field} must be a bounded stable identifier.")
    if not _ID_RE.fullmatch(value):
        raise ManagedWorkError("validation.id", f"{field} must be a lowercase stable identifier.")
    return value


def opaque_id(value: Any, *, field: str) -> str:
    if not isinstance(value, str) or not value or len(value.encode("utf-8")) > MAX_ID_BYTES:
        raise ManagedWorkError("validation.id", f"{field} must be a bounded opaque identifier.")
    if not _ID_RE.fullmatch(value) and not _UUID_RE.fullmatch(value):
        raise ManagedWorkError("validation.id", f"{field} must be a stable identifier or lowercase UUID.")
    return value


def sha256_id(value: Any, *, field: str) -> str:
    if not isinstance(value, str) or not _SHA256_RE.fullmatch(value):
        raise ManagedWorkError("validation.sha256", f"{field} must be a lowercase SHA-256 digest.")
    return value


def bounded_text(value: Any, *, field: str, maximum: int = 4096, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise ManagedWorkError("validation.text", f"{field} must be text.")
    if (not allow_empty and not value.strip()) or len(value.encode("utf-8")) > maximum or "\x00" in value:
        raise ManagedWorkError("validation.text", f"{field} is empty, oversized, or contains NUL.")
    return value


def finite_number(value: Any, *, field: str, minimum: float = 0, maximum: float = 1e18) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ManagedWorkError("validation.number", f"{field} must be a finite number.")
    converted = float(value)
    if not math.isfinite(converted) or converted < minimum or converted > maximum:
        raise ManagedWorkError("validation.number", f"{field} is outside its finite bounds.")
    return converted


def integer(value: Any, *, field: str, minimum: int = 0, maximum: int = 2**53 - 1) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum or value > maximum:
        raise ManagedWorkError("validation.integer", f"{field} must be an integer within bounds.")
    return value


def timestamp(value: Any, *, field: str) -> float:
    return finite_number(value, field=field, minimum=0, maximum=32_503_680_000)


def enum_value(value: Any, *, field: str, choices: set[str] | frozenset[str]) -> str:
    if not isinstance(value, str) or value not in choices:
        raise ManagedWorkError(
            "validation.enum",
            f"{field} must be one of: {', '.join(sorted(choices))}.",
        )
    return value


def closed_object(
    value: Any,
    *,
    field: str,
    required: set[str] | frozenset[str],
    optional: set[str] | frozenset[str] = frozenset(),
) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise ManagedWorkError("validation.object", f"{field} must be an object.")
    keys = set(value)
    if not all(isinstance(key, str) for key in keys):
        raise ManagedWorkError("validation.object-key", f"{field} contains a non-text key.")
    missing = required - keys
    extra = keys - required - optional
    if missing:
        raise ManagedWorkError("validation.missing-field", f"{field} is missing: {', '.join(sorted(missing))}.")
    if extra:
        raise ManagedWorkError("validation.unknown-field", f"{field} contains unknown fields: {', '.join(sorted(extra))}.")
    return dict(value)


def normalize_json(value: Any, *, field: str = "value") -> Any:
    nodes = 0

    def visit(current: Any, depth: int, location: str) -> Any:
        nonlocal nodes
        nodes += 1
        if nodes > MAX_JSON_NODES:
            raise ManagedWorkError("validation.json-capacity", f"{field} contains too many JSON values.")
        if depth > MAX_JSON_DEPTH:
            raise ManagedWorkError("validation.json-depth", f"{field} is nested too deeply.")
        if current is None or isinstance(current, bool):
            return current
        if isinstance(current, int) and not isinstance(current, bool):
            if abs(current) > 2**53 - 1:
                raise ManagedWorkError("validation.json-number", f"{location} exceeds the portable integer range.")
            return current
        if isinstance(current, float):
            if not math.isfinite(current):
                raise ManagedWorkError("validation.json-number", f"{location} is not finite.")
            return current
        if isinstance(current, str):
            if "\x00" in current or len(current.encode("utf-8")) > MAX_STRING_BYTES:
                raise ManagedWorkError("validation.json-string", f"{location} is oversized or contains NUL.")
            return current
        if isinstance(current, Mapping):
            result: dict[str, Any] = {}
            for key in sorted(current):
                if not isinstance(key, str) or not key or "\x00" in key or len(key.encode("utf-8")) > 256:
                    raise ManagedWorkError("validation.json-key", f"{location} has an invalid object key.")
                result[key] = visit(current[key], depth + 1, f"{location}/{key}")
            return result
        if isinstance(current, Sequence) and not isinstance(current, (str, bytes, bytearray)):
            return [visit(item, depth + 1, f"{location}/{index}") for index, item in enumerate(current)]
        raise ManagedWorkError("validation.json-type", f"{location} contains a non-JSON value.")

    result = visit(value, 0, field)
    encoded = json.dumps(result, ensure_ascii=False, allow_nan=False, separators=(",", ":"), sort_keys=True)
    if len(encoded.encode("utf-8")) > MAX_JSON_BYTES:
        raise ManagedWorkError("validation.json-size", f"{field} exceeds {MAX_JSON_BYTES} encoded bytes.")
    return result


def canonical_json(value: Any, *, field: str = "value") -> str:
    return json.dumps(
        normalize_json(value, field=field),
        ensure_ascii=False,
        allow_nan=False,
        separators=(",", ":"),
        sort_keys=True,
    )


def fingerprint(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def secret_shaped_key(key: str) -> bool:
    expanded = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "-", key)
    expanded = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "-", expanded)
    compact = re.sub(r"[^a-z0-9]", "", key.casefold())
    return bool(_SECRET_KEY_RE.search(expanded)) or compact in _SECRET_COMPACT_KEYS


def reject_secret_fields(value: Any, *, field: str) -> None:
    def visit(current: Any, path: str) -> None:
        if isinstance(current, Mapping):
            for key, child in current.items():
                if secret_shaped_key(key):
                    raise ManagedWorkError(
                        "validation.secret-field",
                        f"{field} contains a secret-shaped field that must not be persisted.",
                        detail=f"{path}/{key}",
                    )
                visit(child, f"{path}/{key}")
        elif isinstance(current, Sequence) and not isinstance(current, (str, bytes, bytearray)):
            for index, child in enumerate(current):
                visit(child, f"{path}/{index}")

    visit(value, "")


def require_context_source(source: Any) -> str:
    value = stable_id(source, field="source")
    if value in _EXCLUDED_CONTEXT_SOURCES:
        raise ManagedWorkError(
            "context.source-excluded",
            "This context source is excluded from managed work by default.",
            detail=value,
        )
    return value


def redact_context(content: Any, *, extra_keys: Sequence[str] = ()) -> tuple[Any, list[str]]:
    normalized = normalize_json(content, field="context content")
    configured: set[str] = set()
    for key in extra_keys:
        configured.add(bounded_text(key, field="redaction key", maximum=256).casefold())
    paths: list[str] = []

    def visit(current: Any, path: str) -> Any:
        if isinstance(current, dict):
            result: dict[str, Any] = {}
            private_notification = current.get("private") is True
            for key, value in current.items():
                child = f"{path}/{key}"
                if secret_shaped_key(key) or key.casefold() in configured:
                    result[key] = "[redacted]"
                    paths.append(child)
                elif private_notification and key.casefold() in {"body", "content", "message", "preview", "title"}:
                    result[key] = "[private notification excluded]"
                    paths.append(child)
                else:
                    result[key] = visit(value, child)
            return result
        if isinstance(current, list):
            return [visit(value, f"{path}/{index}") for index, value in enumerate(current)]
        return current

    return visit(normalized, ""), sorted(paths)


def encode_cursor(*, view: str, principal_id: str, row_id: int) -> str:
    payload = canonical_json({"principalId": principal_id, "rowId": row_id, "version": 0, "view": view})
    return base64.urlsafe_b64encode(payload.encode("utf-8")).decode("ascii").rstrip("=")


def decode_cursor(cursor: Any, *, view: str, principal_id: str) -> int:
    if not isinstance(cursor, str) or not cursor or len(cursor) > 1024:
        raise ManagedWorkError("query.cursor", "The pagination cursor is invalid.")
    try:
        padding = "=" * (-len(cursor) % 4)
        raw = base64.urlsafe_b64decode((cursor + padding).encode("ascii"))
        payload = json.loads(raw)
        data = closed_object(
            payload,
            field="cursor",
            required={"version", "view", "principalId", "rowId"},
        )
        if data["version"] != 0 or data["view"] != view or data["principalId"] != principal_id:
            raise ValueError("cursor binding mismatch")
        return integer(data["rowId"], field="cursor row", minimum=1)
    except ManagedWorkError:
        raise
    except Exception as error:
        raise ManagedWorkError("query.cursor", "The pagination cursor is malformed or belongs to another view.") from error
