from __future__ import annotations

import unittest
from pathlib import Path

from omarchy_fabric.models import FabricError
from omarchy_fabric.providers.compatibility.engine import CompatibilityEngine
from omarchy_fabric.providers.compatibility.measured_host import measure_host
from omarchy_fabric.providers.compatibility.provider import CompatibilityProvider

from helper import host, provider, recipes, request


class MeasuredHostTests(unittest.IsolatedAsyncioTestCase):
    def test_probe_reads_fixed_paths_and_normalizes_architecture(self) -> None:
        existing = {Path("/usr/bin/bwrap"), Path("/usr/bin/firefox"), Path("/dev/kvm")}
        measured = measure_host(
            architecture="AMD64",
            memory_mib=8192,
            disk_mib=4096,
            path_exists=existing.__contains__,
        )
        self.assertEqual(measured["architecture"], "x86_64")
        self.assertTrue(measured["isolationAvailable"])
        self.assertTrue(measured["browserAvailable"])
        self.assertTrue(measured["virtualizationAvailable"])
        self.assertFalse(measured["protonAvailable"])
        self.assertEqual(measured["availableRuntimes"], ["native", "container", "browser"])

    def test_unknown_architecture_fails_closed(self) -> None:
        with self.assertRaises(FabricError) as caught:
            measure_host(architecture="riscv64", memory_mib=1024, disk_mib=1024, path_exists=lambda _path: False)
        self.assertEqual(caught.exception.code, "compatibility.host-unmeasured")

    async def test_provider_probe_replaces_caller_host(self) -> None:
        measured = host(virtualizationAvailable=False, protonAvailable=False, availableRuntimes=["native", "browser"])
        value = CompatibilityProvider(recipes(), CompatibilityEngine(recipes()), host_probe=lambda: measured)
        workload = request(
            identity="workload.windows-admin",
            workload_type="windows-app",
            artifact_kind="windows-executable",
            requiresAdmin=True,
        )
        result = await value.read("route.decide", {"request": workload, "host": host()})
        self.assertEqual(result["eligibility"], "unsupported")
        self.assertIsNone(result["selectedRoute"])
        native = await provider().read(
            "route.decide",
            {"request": request(identity="workload.native", artifact_kind="native-package"), "host": host()},
        )
        self.assertEqual(native["selectedRoute"], "native")


if __name__ == "__main__":
    unittest.main()
