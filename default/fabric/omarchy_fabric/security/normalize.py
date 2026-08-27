"""Canonical JSON normalization for approval and audit bindings."""

from __future__ import annotations

import hashlib
import json
import unicodedata
from collections.abc import Mapping, Sequence
from typing import Any

from .errors import SecurityValidationError

_MAX_SAFE_INTEGER = 2**53 - 1


def normalize_json(value: Any, *, _depth: int = 0) -> Any:
    """Return a deterministic JSON value or reject ambiguous input.

    Floats are intentionally rejected: NaN/infinity are not portable JSON and even
    ordinary binary floats invite cross-language approval-binding differences.
    """

    if _depth > 32:
        raise SecurityValidationError("normalization.too-deep", "JSON input exceeds the nesting limit.")
    if value is None or isinstance(value, bool):
        return value
    if isinstance(value, int):
        if not -_MAX_SAFE_INTEGER <= value <= _MAX_SAFE_INTEGER:
            raise SecurityValidationError(
                "normalization.integer-range",
                "JSON integer exceeds the cross-language safe range.",
            )
        return value
    if isinstance(value, str):
        if "\x00" in value:
            raise SecurityValidationError("normalization.nul", "Strings cannot contain NUL bytes.")
        if len(value) > 65536:
            raise SecurityValidationError("normalization.string-size", "JSON string exceeds the size limit.")
        return unicodedata.normalize("NFC", value)
    if isinstance(value, float):
        raise SecurityValidationError("normalization.float", "Approval-bound JSON cannot contain floats.")
    if isinstance(value, Mapping):
        if len(value) > 1024:
            raise SecurityValidationError("normalization.object-size", "JSON object exceeds the item limit.")
        normalized: dict[str, Any] = {}
        keys = list(value)
        if any(not isinstance(key, str) for key in keys):
            raise SecurityValidationError("normalization.key", "JSON object keys must be strings.")
        for key in sorted(keys):
            normalized_key = unicodedata.normalize("NFC", key)
            if normalized_key in normalized:
                raise SecurityValidationError(
                    "normalization.duplicate-key",
                    "Unicode normalization produced a duplicate object key.",
                )
            normalized[normalized_key] = normalize_json(value[key], _depth=_depth + 1)
        return normalized
    if isinstance(value, Sequence) and not isinstance(value, (bytes, bytearray, memoryview)):
        if len(value) > 1024:
            raise SecurityValidationError("normalization.array-size", "JSON array exceeds the item limit.")
        return [normalize_json(item, _depth=_depth + 1) for item in value]
    raise SecurityValidationError(
        "normalization.type",
        f"Unsupported approval-bound value type: {type(value).__name__}.",
    )


def canonical_json(value: Any) -> str:
    return json.dumps(
        normalize_json(value),
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )


def binding_digest(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()
