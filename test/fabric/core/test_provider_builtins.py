from __future__ import annotations

import unittest
from unittest import mock

from omarchy_fabric.provider_builtins import (
    BUILTIN_PROVIDER_FACTORIES,
    build_builtin_providers,
)
from omarchy_fabric.provider_registry import ProviderRegistry


EXPECTED_PROVIDER_IDS = (
    "audio.provider",
    "bluetooth.provider",
    "display.provider",
    "input.provider",
    "network.provider",
    "power.provider",
)


class BuiltinProviderTests(unittest.TestCase):
    def test_production_provider_set_is_explicit_complete_and_registry_valid(self) -> None:
        self.assertEqual(len(BUILTIN_PROVIDER_FACTORIES), len(EXPECTED_PROVIDER_IDS))
        with mock.patch("asyncio.create_subprocess_exec") as process_spawn:
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
        self.assertEqual(registry.available_count, len(EXPECTED_PROVIDER_IDS))
        self.assertEqual(
            tuple(entry["manifest"]["provider"] for entry in registry.catalog()),
            EXPECTED_PROVIDER_IDS,
        )
        self.assertTrue(all(item.disposition == "registered" for item in registrations))


if __name__ == "__main__":
    unittest.main()
