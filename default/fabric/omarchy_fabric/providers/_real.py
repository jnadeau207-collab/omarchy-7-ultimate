"""Read-only real backend boundary for provisional domain providers."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import Any, Mapping

from omarchy_fabric.models import FabricError

from ._engine import BackendSnapshot
from ._immutable import freeze
from ._probe import probe_error

ResourceLoader = Callable[[], Awaitable[list[Mapping[str, Any]]]]

class ReadOnlyProbeBackend:
    def __init__(self, domain: str, loader: ResourceLoader) -> None:
        self.domain = domain
        self.loader = loader

    async def snapshot(self) -> BackendSnapshot:
        try:
            resources = await self.loader()
            if len(resources) > 64:
                raise ValueError("resource inventory exceeds 64 entries")
            if any(not isinstance(resource, Mapping) for resource in resources):
                raise ValueError("resource inventory contains a non-object")
        except Exception as error:
            reason = error if isinstance(error, FabricError) else probe_error(self.domain, error)
            return BackendSnapshot(False, False, (), reason)
        reason = FabricError(
            f"{self.domain}.operation-read-only",
            f"{self.domain.title()} changes are not available yet",
            "This page can read the current state. The controls that would change it are not connected yet.",
            retryable=True,
            recovery_actions=("operation.integration-required",),
        )
        return BackendSnapshot(True, False, tuple(freeze(resource) for resource in resources), reason)

    async def replace(
        self,
        resource_id: str,
        resource: Mapping[str, Any],
        expected_revision: str,
    ) -> BackendSnapshot:
        raise FabricError(
            f"{self.domain}.operation-unavailable",
            f"{self.domain.title()} operation is unavailable",
            "This page only reads the current state; it never changes the computer.",
            detail=resource_id,
            retryable=True,
            recovery_actions=("operation.integration-required",),
        )
