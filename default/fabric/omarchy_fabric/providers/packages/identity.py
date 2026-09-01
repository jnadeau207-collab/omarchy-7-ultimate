"""Canonical identities and revisions for Software Center documents."""

from __future__ import annotations

import hashlib
import json
import re
from typing import Any

STABLE_ID_RE = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$")
SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
REVISION_RE = re.compile(r"^sha256\.[0-9a-f]{64}$")

def canonical_json(value: Any) -> str:
    return json.dumps(value, allow_nan=False, ensure_ascii=False, separators=(",", ":"), sort_keys=True)

def revision(value: Any) -> str:
    return "sha256." + hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()

def stable_id(namespace: str, *parts: str) -> str:
    if not STABLE_ID_RE.fullmatch(namespace):
        raise ValueError("identity namespace is invalid")
    material = "\x00".join(parts)
    if not material or any(not isinstance(part, str) or not part for part in parts):
        raise ValueError("identity material must contain non-empty strings")
    digest = hashlib.sha256(material.encode("utf-8")).hexdigest()
    return f"{namespace}.{digest}"

def require_stable_id(value: object, label: str) -> str:
    if not isinstance(value, str) or len(value) > 160 or STABLE_ID_RE.fullmatch(value) is None:
        raise ValueError(f"{label} must be a stable ID")
    return value

def require_digest(value: object, label: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise ValueError(f"{label} must be a sha256 digest")
    return value
