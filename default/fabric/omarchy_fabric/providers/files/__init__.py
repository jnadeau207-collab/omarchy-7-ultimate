"""Consumer-complete Files provider domain."""

from .provider import (
    DOMAIN,
    PROVIDER_ID,
    RESOURCE_ID,
    build_fake_provider,
    build_provider,
    canonicalize_workspace,
    normalize_name,
    normalize_relative_path,
    validate_workspace,
)

__all__ = [
    "DOMAIN",
    "PROVIDER_ID",
    "RESOURCE_ID",
    "build_fake_provider",
    "build_provider",
    "canonicalize_workspace",
    "normalize_name",
    "normalize_relative_path",
    "validate_workspace",
]
