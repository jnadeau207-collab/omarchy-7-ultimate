"""Small helpers for immutable leaf contracts."""

from __future__ import annotations

import json
from pathlib import Path
from types import MappingProxyType
from typing import Any, Mapping


def freeze(value: Any) -> Any:
    if isinstance(value, Mapping):
        return MappingProxyType({str(key): freeze(child) for key, child in value.items()})
    if isinstance(value, (list, tuple)):
        return tuple(freeze(child) for child in value)
    return value


def thaw(value: Any) -> Any:
    if isinstance(value, Mapping):
        return {str(key): thaw(child) for key, child in value.items()}
    if isinstance(value, tuple):
        return [thaw(child) for child in value]
    return value


def load_frozen_json(path: Path) -> Mapping[str, Any]:
    raw = path.read_bytes()
    if len(raw) > 256 * 1024:
        raise ValueError(f"leaf contract exceeds 256 KiB: {path.name}")
    document = json.loads(raw)
    if not isinstance(document, dict):
        raise ValueError(f"leaf contract must be an object: {path.name}")
    return freeze(document)
