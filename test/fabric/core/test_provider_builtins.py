from __future__ import annotations

import asyncio
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from omarchy_fabric import provider_builtins as builtins
from omarchy_fabric.models import FabricError
from omarchy_fabric.provider_builtins import (
    BUILTIN_PROVIDER_IDS,
    BUILTIN_PROVIDER_FACTORIES,
    BUILTIN_PROVIDER_SPECS,
    BuiltinProviderSpec,
    build_builtin_providers,
)
from omarchy_fabric.provider_registry import ProviderRegistry
from omarchy_fabric.providers._immutable import thaw

EXPECTED_PROVIDER_IDS = (
    "audio.provider",
    "bluetooth.provider",
    "display.provider",
    "input.provider",
    "network.provider",
    "power.provider",
    "files.provider",
    "defaults.provider",
    "packages.provider",
    "compatibility.provider",
    "account.provider",
    "backup.provider",
    "device.provider",
    "diagnostics.provider",
    "firewall.provider",
    "printer.provider",
    "process.provider",
    "recovery.provider",
    "schedule.provider",
    "service.provider",
    "storage.provider",
    "update.provider",
)

class BuiltinProviderTests(unittest.TestCase):
    @staticmethod
    def _specs_with(provider_id: str, factory) -> tuple[BuiltinProviderSpec, ...]:
        return tuple(
            BuiltinProviderSpec(spec.provider_id, factory if spec.provider_id == provider_id else spec.factory)
            for spec in BUILTIN_PROVIDER_SPECS
        )

    def test_production_provider_set_is_explicit_complete_and_registry_valid(self) -> None:
        self.assertEqual(BUILTIN_PROVIDER_IDS, EXPECTED_PROVIDER_IDS)
        self.assertEqual(len(BUILTIN_PROVIDER_FACTORIES), len(EXPECTED_PROVIDER_IDS))
        with (
            mock.patch.object(builtins, "_trusted_account_home", return_value=Path("/home/fabric-test")),
            mock.patch("asyncio.create_subprocess_exec") as process_spawn,
        ):
            providers = build_builtin_providers()
        process_spawn.assert_not_called()
        self.assertEqual(
            tuple(provider.manifest["provider"] for provider in providers),
            EXPECTED_PROVIDER_IDS,
        )
        self.assertFalse(
            any(
                provider.manifest["provider"].startswith(("fake.", "test."))
                for provider in providers
            )
        )

        registry = ProviderRegistry()
        registrations = tuple(registry.register(provider) for provider in providers)
        self.assertEqual(registry.provider_count, len(EXPECTED_PROVIDER_IDS))
        self.assertEqual(registry.available_count, 20)
        self.assertEqual(registry.degraded_count, 2)
        self.assertEqual(registry.usable_count, 22)
        catalog = registry.catalog()
        self.assertEqual(
            tuple(entry["manifest"]["provider"] for entry in catalog),
            tuple(sorted(EXPECTED_PROVIDER_IDS)),
        )
        self.assertEqual(
            tuple(entry["manifest"]["provider"] for entry in sorted(catalog, key=lambda entry: entry["registrationOrder"])),
            EXPECTED_PROVIDER_IDS,
        )
        states = {entry["manifest"]["provider"]: entry["state"] for entry in catalog}
        self.assertEqual(states["packages.provider"], "degraded")
        self.assertEqual(states["compatibility.provider"], "degraded")
        self.assertTrue(all(entry["detail"] for entry in catalog if entry["state"] == "degraded"))
        self.assertTrue(all(item.disposition == "registered" for item in registrations))

    def test_repeat_construction_is_fresh_and_stable(self) -> None:
        with mock.patch.object(builtins, "_trusted_account_home", return_value=Path("/home/fabric-test")):
            first = build_builtin_providers()
            second = build_builtin_providers()
        self.assertEqual(tuple(provider.manifest["provider"] for provider in first), EXPECTED_PROVIDER_IDS)
        self.assertEqual(tuple(provider.manifest["provider"] for provider in second), EXPECTED_PROVIDER_IDS)
        self.assertTrue(all(left is not right for left, right in zip(first, second, strict=True)))
        first_packages = first[EXPECTED_PROVIDER_IDS.index("packages.provider")]
        second_packages = second[EXPECTED_PROVIDER_IDS.index("packages.provider")]
        self.assertIsNot(first_packages.engine, second_packages.engine)

    def test_account_home_comes_only_from_uid_lookup_and_code_owned_paths(self) -> None:
        account = SimpleNamespace(pw_uid=1000, pw_dir="/home/trusted-account")
        files_result = object()
        defaults_result = object()
        backup_result = object()
        with (
            mock.patch.object(builtins.os, "getuid", return_value=1000, create=True),
            mock.patch.object(builtins, "_pwd", SimpleNamespace(getpwuid=mock.Mock(return_value=account))),
            mock.patch("omarchy_fabric.providers.files.build_provider", return_value=files_result) as files_builder,
            mock.patch("omarchy_fabric.providers.defaults.build_provider", return_value=defaults_result) as defaults_builder,
            mock.patch("omarchy_fabric.providers.backup.build_provider", return_value=backup_result) as backup_builder,
            mock.patch.dict(os.environ, {"HOME": "/tmp/untrusted-home", "OMARCHY_PATH": "/tmp/untrusted-root"}),
        ):
            self.assertIs(builtins._build_files_provider(), files_result)
            self.assertIs(builtins._build_defaults_provider(), defaults_result)
            self.assertIs(builtins._build_backup_provider(), backup_result)
        files_builder.assert_called_once_with(
            session_operable=True,
            home=Path("/home/trusted-account"),
            config_path=builtins._default_root() / "ultimate" / "files" / "locations-v0.json",
        )
        defaults_builder.assert_called_once_with(
            session_operable=True,
            home=Path("/home/trusted-account"),
            config_path=builtins._default_root() / "ultimate" / "files" / "default-associations-v0.json",
        )
        backup_builder.assert_called_once_with(home_root="/home/trusted-account")

    def test_account_home_is_bounded_as_strict_utf8(self) -> None:
        accepted_home = "/" + "é" * 2047
        with (
            mock.patch.object(builtins.os, "getuid", return_value=1000, create=True),
            mock.patch.object(
                builtins,
                "_pwd",
                SimpleNamespace(getpwuid=mock.Mock(return_value=SimpleNamespace(pw_uid=1000, pw_dir=accepted_home))),
            ),
        ):
            self.assertEqual(builtins._trusted_account_home(), Path(accepted_home))

        for invalid_home in ("/" + "é" * 2048, "/home/\ud800"):
            with (
                self.subTest(representation=ascii(invalid_home)),
                mock.patch.object(builtins.os, "getuid", return_value=1000, create=True),
                mock.patch.object(
                    builtins,
                    "_pwd",
                    SimpleNamespace(
                        getpwuid=mock.Mock(
                            return_value=SimpleNamespace(pw_uid=1000, pw_dir=invalid_home)
                        )
                    ),
                ),
            ):
                with self.assertRaises(RuntimeError):
                    builtins._trusted_account_home()

    def test_builder_failure_isolated_and_unavailable_before_dispatch(self) -> None:
        def broken_builder():
            raise RuntimeError("secret-builder-token")

        specs = self._specs_with("display.provider", broken_builder)
        with (
            mock.patch.object(builtins, "BUILTIN_PROVIDER_SPECS", specs),
            mock.patch.object(builtins, "_trusted_account_home", return_value=Path("/home/fabric-test")),
        ):
            providers = build_builtin_providers()
        self.assertEqual(tuple(provider.manifest["provider"] for provider in providers), EXPECTED_PROVIDER_IDS)
        display = providers[EXPECTED_PROVIDER_IDS.index("display.provider")]
        display.read = mock.AsyncMock(side_effect=AssertionError("dispatch reached placeholder"))
        registry = ProviderRegistry()
        for provider in providers:
            registry.register(provider)
        entry = next(item for item in registry.catalog() if item["manifest"]["provider"] == "display.provider")
        self.assertEqual(entry["state"], "unavailable")
        self.assertEqual(set(entry["manifest"]["actions"]), {"availability.inspect"})
        self.assertIn("builder contract failed", entry["detail"])
        self.assertNotIn("secret-builder-token", entry["detail"])
        with self.assertRaises(FabricError) as read_error:
            asyncio.run(registry.read("display.provider", "inspect", {}))
        self.assertEqual(read_error.exception.code, "provider.unavailable")
        with self.assertRaises(FabricError) as preflight_error:
            asyncio.run(registry.preflight("display.provider", "brightness.set", {}, object()))
        self.assertEqual(preflight_error.exception.code, "provider.unavailable")
        display.read.assert_not_awaited()
        self.assertEqual(registry.available_count, 19)
        self.assertEqual(registry.degraded_count, 2)
        self.assertEqual(registry.usable_count, 21)

    def test_provider_module_import_failure_isolated_after_registry_module_startup(self) -> None:
        original_import = __import__

        def fail_display_import(name, globals=None, locals=None, fromlist=(), level=0):
            if name in {"providers.display", "omarchy_fabric.providers.display"}:
                raise ImportError("secret-import-token")
            return original_import(name, globals, locals, fromlist, level)

        with (
            mock.patch("builtins.__import__", side_effect=fail_display_import),
            mock.patch.object(builtins, "_trusted_account_home", return_value=Path("/home/fabric-test")),
        ):
            providers = build_builtin_providers()

        self.assertEqual(tuple(provider.manifest["provider"] for provider in providers), EXPECTED_PROVIDER_IDS)
        placeholder = providers[EXPECTED_PROVIDER_IDS.index("display.provider")]
        self.assertEqual(placeholder.availability.state, "unavailable")
        self.assertNotIn("secret-import-token", placeholder.availability.detail)

        source = Path(builtins.__file__).read_text(encoding="utf-8")
        module_preamble = source.split("def _build_audio_provider", maxsplit=1)[0]
        self.assertNotIn("from .providers.", module_preamble)

    def test_missing_code_owned_provider_config_isolated_without_path_disclosure(self) -> None:
        with (
            tempfile.TemporaryDirectory() as temporary,
            mock.patch(
                "omarchy_fabric.providers.packages.provider._default_root",
                return_value=Path(temporary),
            ),
            mock.patch.object(builtins, "_trusted_account_home", return_value=Path("/home/fabric-test")),
        ):
            providers = build_builtin_providers()

        packages = providers[EXPECTED_PROVIDER_IDS.index("packages.provider")]
        self.assertEqual(tuple(provider.manifest["provider"] for provider in providers), EXPECTED_PROVIDER_IDS)
        self.assertEqual(packages.availability.state, "unavailable")
        self.assertIn("builder contract failed", packages.availability.detail)
        self.assertNotIn(temporary, packages.availability.detail)

    def test_duplicate_schema_and_version_faults_become_expected_id_placeholders(self) -> None:
        display_spec = next(spec for spec in BUILTIN_PROVIDER_SPECS if spec.provider_id == "display.provider")

        def invalid_factory(kind: str):
            def build():
                provider = display_spec.factory()
                provider.manifest = thaw(provider.manifest)
                provider.schemas = thaw(provider.schemas)
                if kind == "duplicate":
                    provider.manifest["provider"] = "audio.provider"
                elif kind == "schema":
                    provider.schemas = {}
                else:
                    provider.manifest["providerVersion"] = "invalid-version"
                return provider
            return build

        for kind in ("duplicate", "schema", "version"):
            with self.subTest(kind=kind):
                specs = self._specs_with("display.provider", invalid_factory(kind))
                with (
                    mock.patch.object(builtins, "BUILTIN_PROVIDER_SPECS", specs),
                    mock.patch.object(builtins, "_trusted_account_home", return_value=Path("/home/fabric-test")),
                ):
                    providers = build_builtin_providers()
                ids = tuple(provider.manifest["provider"] for provider in providers)
                self.assertEqual(ids, EXPECTED_PROVIDER_IDS)
                placeholder = providers[EXPECTED_PROVIDER_IDS.index("display.provider")]
                self.assertEqual(placeholder.availability.state, "unavailable")
                self.assertIn("admission contract failed", placeholder.availability.detail)

    def test_degraded_provider_lifecycle_remains_usable_until_explicit_disconnect(self) -> None:
        with mock.patch.object(builtins, "_trusted_account_home", return_value=Path("/home/fabric-test")):
            package_provider = build_builtin_providers()[EXPECTED_PROVIDER_IDS.index("packages.provider")]
        registry = ProviderRegistry(clock=lambda: 10.0)
        registered = registry.register(package_provider)
        self.assertEqual(registered.state, "degraded")
        search = asyncio.run(registry.read("packages.provider", "catalog.search", {"query": "editor", "sourceTypes": []}))
        self.assertEqual(search["value"]["assurance"], "contract-seed")
        disconnected = registry.mark_unavailable(
            "packages.provider",
            expected_generation=1,
            detail="The code-owned contract seed was withdrawn.",
        )
        self.assertEqual(disconnected.state, "unavailable")
        with self.assertRaises(FabricError) as unavailable:
            asyncio.run(registry.read("packages.provider", "catalog.search", {"query": "", "sourceTypes": []}))
        self.assertEqual(unavailable.exception.code, "provider.unavailable")
        restored = registry.reregister(package_provider, expected_generation=2)
        self.assertEqual(restored.state, "degraded")
        self.assertEqual(restored.generation, 3)
        self.assertEqual(registry.degraded_count, 1)
        self.assertEqual(registry.usable_count, 1)

    def test_builtin_source_has_no_dynamic_or_environment_selected_discovery(self) -> None:
        source = Path(builtins.__file__).read_text(encoding="utf-8")
        for forbidden in (
            "importlib",
            "pkgutil",
            "os.environ",
            "os.getenv",
            "Path.home",
            ".iterdir(",
            ".glob(",
            ".rglob(",
        ):
            self.assertNotIn(forbidden, source)

if __name__ == "__main__":
    unittest.main()
