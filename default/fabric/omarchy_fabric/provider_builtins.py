"""Code-owned production provider construction and failure isolation.

The builtin list is explicit and ordered. Provider names and factories never
come from RPC input, environment variables, filesystem scanning, or import
strings. Each builder and admission is isolated so one unavailable domain is
represented honestly without preventing the daemon from starting.
"""

from __future__ import annotations

import os
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

try:
    import pwd as _pwd
except ImportError:
    _pwd = None

from .provider_registry import ProviderAvailability, ProviderRegistry, TypedProvider

ProviderFactory = Callable[[], TypedProvider]

@dataclass(frozen=True)
class BuiltinProviderSpec:
    provider_id: str
    factory: ProviderFactory

def _default_root() -> Path:
    return Path(__file__).resolve().parents[2]

def _trusted_account_home() -> Path:
    """Resolve the daemon account home from the authenticated OS UID database."""

    getuid = getattr(os, "getuid", None)
    if getuid is None or _pwd is None:
        raise RuntimeError("OS account lookup is unavailable")
    uid = getuid()
    try:
        record = _pwd.getpwuid(uid)
    except (KeyError, OSError) as error:
        raise RuntimeError("OS account lookup failed") from error
    raw_home = record.pw_dir
    if not isinstance(raw_home, str):
        raise RuntimeError("OS account home is invalid")
    try:
        encoded_home = raw_home.encode("utf-8")
    except UnicodeEncodeError as error:
        raise RuntimeError("OS account home is invalid") from error
    home = PurePosixPath(raw_home)
    if (
        getattr(record, "pw_uid", uid) != uid
        or not 1 < len(encoded_home) <= 4096
        or not home.is_absolute()
        or home == PurePosixPath("/")
        or any(part in {"", ".", ".."} for part in home.parts[1:])
        or any(ord(character) < 32 or ord(character) == 127 for character in raw_home)
    ):
        raise RuntimeError("OS account home is invalid")
    return Path(raw_home)

def _build_audio_provider() -> TypedProvider:
    from .providers.audio import build_provider

    return build_provider()

def _build_bluetooth_provider() -> TypedProvider:
    from .providers.bluetooth import build_provider

    return build_provider()

def _build_display_provider() -> TypedProvider:
    from .providers.display import build_provider

    return build_provider()

def _build_input_provider() -> TypedProvider:
    from .providers.input import build_provider

    return build_provider()

def _build_network_provider() -> TypedProvider:
    from .providers.network import build_provider

    return build_provider()

def _build_power_provider() -> TypedProvider:
    from .providers.power import build_provider

    return build_provider()

def _build_files_provider() -> TypedProvider:
    from .providers.files import build_provider

    return build_provider(
        home=_trusted_account_home(),
        config_path=_default_root() / "ultimate" / "files" / "locations-v0.json",
    )

def _build_defaults_provider() -> TypedProvider:
    from .providers.defaults import build_provider

    return build_provider(
        home=_trusted_account_home(),
        config_path=_default_root() / "ultimate" / "files" / "default-associations-v0.json",
    )

def _build_packages_provider() -> TypedProvider:
    from .providers.packages import build_provider

    return build_provider()

def _build_compatibility_provider() -> TypedProvider:
    from .providers.compatibility import build_provider

    return build_provider()

def _build_account_provider() -> TypedProvider:
    from .providers.account import build_provider

    return build_provider()

def _build_backup_provider() -> TypedProvider:
    from .providers.backup import build_provider

    return build_provider(home_root=_trusted_account_home().as_posix())

def _build_device_provider() -> TypedProvider:
    from .providers.device import build_provider

    return build_provider()

def _build_diagnostics_provider() -> TypedProvider:
    from .providers.diagnostics import build_provider

    return build_provider()

def _build_firewall_provider() -> TypedProvider:
    from .providers.firewall import build_provider

    return build_provider()

def _build_printer_provider() -> TypedProvider:
    from .providers.printer import build_provider

    return build_provider()

def _build_process_provider() -> TypedProvider:
    from .providers.process import build_provider

    return build_provider()

def _build_recovery_provider() -> TypedProvider:
    from .providers.recovery import build_provider

    return build_provider()

def _build_schedule_provider() -> TypedProvider:
    from .providers.schedule import build_provider

    return build_provider()

def _build_service_provider() -> TypedProvider:
    from .providers.service import build_provider

    return build_provider()

def _build_storage_provider() -> TypedProvider:
    from .providers.storage import build_provider

    return build_provider()

def _build_update_provider() -> TypedProvider:
    from .providers.update import build_provider

    return build_provider()

BUILTIN_PROVIDER_SPECS: tuple[BuiltinProviderSpec, ...] = (
    BuiltinProviderSpec("audio.provider", _build_audio_provider),
    BuiltinProviderSpec("bluetooth.provider", _build_bluetooth_provider),
    BuiltinProviderSpec("display.provider", _build_display_provider),
    BuiltinProviderSpec("input.provider", _build_input_provider),
    BuiltinProviderSpec("network.provider", _build_network_provider),
    BuiltinProviderSpec("power.provider", _build_power_provider),
    BuiltinProviderSpec("files.provider", _build_files_provider),
    BuiltinProviderSpec("defaults.provider", _build_defaults_provider),
    BuiltinProviderSpec("packages.provider", _build_packages_provider),
    BuiltinProviderSpec("compatibility.provider", _build_compatibility_provider),
    BuiltinProviderSpec("account.provider", _build_account_provider),
    BuiltinProviderSpec("backup.provider", _build_backup_provider),
    BuiltinProviderSpec("device.provider", _build_device_provider),
    BuiltinProviderSpec("diagnostics.provider", _build_diagnostics_provider),
    BuiltinProviderSpec("firewall.provider", _build_firewall_provider),
    BuiltinProviderSpec("printer.provider", _build_printer_provider),
    BuiltinProviderSpec("process.provider", _build_process_provider),
    BuiltinProviderSpec("recovery.provider", _build_recovery_provider),
    BuiltinProviderSpec("schedule.provider", _build_schedule_provider),
    BuiltinProviderSpec("service.provider", _build_service_provider),
    BuiltinProviderSpec("storage.provider", _build_storage_provider),
    BuiltinProviderSpec("update.provider", _build_update_provider),
)
BUILTIN_PROVIDER_IDS = tuple(spec.provider_id for spec in BUILTIN_PROVIDER_SPECS)
BUILTIN_PROVIDER_FACTORIES = tuple(spec.factory for spec in BUILTIN_PROVIDER_SPECS)

class _UnavailableProvider:
    def __init__(self, provider_id: str, detail: str) -> None:
        domain = provider_id.removesuffix(".provider")
        capability = f"{domain}.availability.inspect"
        arguments_id = f"urn:omarchy:fabric:provider:{domain}:unavailable-arguments:v0"
        result_id = f"urn:omarchy:fabric:provider:{domain}:unavailable-result:v0"
        reference = lambda schema_id: {"id": schema_id, "version": "v0"}
        self.availability = ProviderAvailability("unavailable", detail)
        self.manifest: Mapping[str, Any] = {
            "schemaVersion": "v0",
            "provider": provider_id,
            "providerVersion": "v0",
            "minFabricProtocol": 0,
            "maxFabricProtocol": 0,
            "capabilities": [capability],
            "actions": {
                "availability.inspect": {
                    "capability": capability,
                    "mode": "read",
                    "risk": "read-only",
                    "effects": [],
                    "arguments": reference(arguments_id),
                    "result": reference(result_id),
                    "preflight": None,
                    "state": None,
                    "supportsRollback": False,
                    "supportsCancellation": False,
                }
            },
        }
        self.schemas: Mapping[str, Mapping[str, Any]] = {
            arguments_id: {
                "$schema": "https://json-schema.org/draft/2020-12/schema",
                "$id": arguments_id,
                "x-omarchy-version": "v0",
                "type": "object",
                "properties": {},
                "additionalProperties": False,
            },
            result_id: {
                "$schema": "https://json-schema.org/draft/2020-12/schema",
                "$id": result_id,
                "x-omarchy-version": "v0",
                "type": "object",
                "required": ["schemaVersion", "provider", "state", "detail"],
                "properties": {
                    "schemaVersion": {"const": "v0"},
                    "provider": {"const": provider_id},
                    "state": {"const": "unavailable"},
                    "detail": {"const": detail},
                },
                "additionalProperties": False,
            },
        }
        self._result = {
            "schemaVersion": "v0",
            "provider": provider_id,
            "state": "unavailable",
            "detail": detail,
        }

    async def read(self, action: str, arguments: Mapping[str, Any]) -> Mapping[str, Any]:
        if action != "availability.inspect" or arguments:
            raise AssertionError("unavailable provider was invoked outside its closed contract")
        return dict(self._result)

def _unavailable(provider_id: str, phase: str, registry: ProviderRegistry) -> TypedProvider:
    detail = f"{provider_id} is unavailable because its code-owned {phase} contract failed."
    provider = _UnavailableProvider(provider_id, detail)
    registry.register(provider)
    return provider

def build_builtin_providers() -> tuple[TypedProvider, ...]:
    """Construct all builtins in deterministic order without probing hardware."""

    providers: list[TypedProvider] = []
    admission_registry = ProviderRegistry()
    for spec in BUILTIN_PROVIDER_SPECS:
        try:
            provider = spec.factory()
        except Exception:
            providers.append(_unavailable(spec.provider_id, "builder", admission_registry))
            continue
        try:
            manifest = provider.manifest
            if not isinstance(manifest, Mapping) or manifest.get("provider") != spec.provider_id:
                raise ValueError("builder returned a different provider identity")
            registration = admission_registry.register(provider)
            if registration.provider_id != spec.provider_id:
                raise ValueError("admission returned a different provider identity")
        except Exception:
            provider = _unavailable(spec.provider_id, "admission", admission_registry)
        providers.append(provider)
    return tuple(providers)
