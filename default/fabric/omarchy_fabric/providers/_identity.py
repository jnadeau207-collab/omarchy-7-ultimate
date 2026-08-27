"""Opaque, deterministic identities for leaf-owned native resources."""

from __future__ import annotations

import hashlib


def stable_resource_id(domain: str, kind: str, backend_key: str) -> str:
    """Hide backend selectors while retaining a stable, domain-scoped identity."""

    if not domain or not kind or not isinstance(backend_key, str) or not backend_key:
        raise ValueError("resource identity inputs must be non-empty strings")
    digest = hashlib.sha256(f"{domain}\0{backend_key}".encode("utf-8", errors="strict")).hexdigest()
    return f"{domain}.{kind}.{digest}"
