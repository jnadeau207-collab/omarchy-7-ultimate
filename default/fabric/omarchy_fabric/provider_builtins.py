"""Code-owned production provider factories.

This module is the only production discovery seam for leaf providers.  The
factory list is deliberately explicit: provider names never come from RPC
input, environment variables, filesystem scanning, or import strings.
"""

from __future__ import annotations

from collections.abc import Callable

from .provider_registry import TypedProvider
from .providers.audio import build_provider as build_audio_provider
from .providers.bluetooth import build_provider as build_bluetooth_provider
from .providers.display import build_provider as build_display_provider
from .providers.input import build_provider as build_input_provider
from .providers.network import build_provider as build_network_provider
from .providers.power import build_provider as build_power_provider


ProviderFactory = Callable[[], TypedProvider]

BUILTIN_PROVIDER_FACTORIES: tuple[ProviderFactory, ...] = (
    build_audio_provider,
    build_bluetooth_provider,
    build_display_provider,
    build_input_provider,
    build_network_provider,
    build_power_provider,
)


def build_builtin_providers() -> tuple[TypedProvider, ...]:
    """Construct the deterministic production provider set without probing hardware."""

    return tuple(factory() for factory in BUILTIN_PROVIDER_FACTORIES)
