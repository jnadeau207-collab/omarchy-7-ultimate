"""Read-only adapter from the typed provider registry into durable preflight."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping, Protocol

from ..models import FabricError
from ..security.normalize import normalize_json
from ..security.principal import EndpointPrincipal
from .contracts import ProviderBinding, operation_error


class OperationPreflightGateway(Protocol):
    async def preflight(
        self,
        provider_id: str,
        action: str,
        arguments: Mapping[str, Any],
        principal: EndpointPrincipal,
    ) -> Mapping[str, Any]:
        ...

    def assert_current(self, binding: ProviderBinding) -> None:
        ...


@dataclass(frozen=True)
class RegistryOperationGateway:
    """Uses only the registry's public catalog and validated preflight seam.

    The coordinator never receives a provider apply handle. Provider lifecycle
    drift is checked before authorization; resource CAS remains the executor's
    independent last line immediately before mutation.
    """

    registry: Any

    async def preflight(
        self,
        provider_id: str,
        action: str,
        arguments: Mapping[str, Any],
        principal: EndpointPrincipal,
    ) -> Mapping[str, Any]:
        result = await self.registry.preflight(provider_id, action, arguments, principal)
        if not isinstance(result, Mapping):
            raise operation_error("operation.preflight-invalid", "Provider preflight returned no typed plan.")
        return result

    def assert_current(self, binding: ProviderBinding) -> None:
        matches = []
        try:
            catalog = normalize_json(self.registry.catalog())
        except FabricError:
            raise
        except Exception as error:
            raise operation_error(
                "operation.provider-unavailable",
                "Provider lifecycle state could not be verified.",
                detail=type(error).__name__,
                retryable=True,
            ) from error
        if not isinstance(catalog, list):
            raise operation_error(
                "operation.provider-unavailable",
                "Provider lifecycle catalog is not a bounded typed list.",
                retryable=True,
            )
        for entry in catalog:
            manifest = entry.get("manifest", {}) if isinstance(entry, Mapping) else {}
            if manifest.get("provider") == binding.provider_id:
                matches.append(entry)
        if len(matches) != 1:
            raise operation_error(
                "operation.provider-unavailable",
                "The exact provider binding is not registered.",
                retryable=True,
                recovery_actions=("provider.refresh",),
            )
        entry = matches[0]
        manifest = entry.get("manifest", {})
        actual = (
            manifest.get("providerVersion"),
            entry.get("fingerprint"),
            entry.get("generation"),
        )
        expected = (binding.version, binding.fingerprint, binding.generation)
        if actual != expected or entry.get("state") not in {"available", "degraded"}:
            raise operation_error(
                "operation.provider-stale",
                "Provider version, fingerprint, generation, or availability changed after preflight.",
                retryable=True,
                recovery_actions=("operation.preflight",),
            )
