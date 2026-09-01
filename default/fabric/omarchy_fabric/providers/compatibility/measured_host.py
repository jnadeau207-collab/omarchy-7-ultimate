"""Measured Compatibility Center host inputs.

Route decisions must not trust a caller-supplied host document. This probe
reads architecture, memory, disk, and the presence of fixed runtime paths.
It never executes a process and never falls back to RPC-supplied guesses.
"""

from __future__ import annotations

import os
import platform
import shutil
from pathlib import Path
from typing import Callable, Mapping

from jsonschema import Draft202012Validator

from omarchy_fabric.models import FabricError

from .contracts import HOST

ARCHITECTURES = {
    "amd64": "x86_64",
    "x86_64": "x86_64",
    "x64": "x86_64",
    "aarch64": "aarch64",
    "arm64": "aarch64",
}
BROWSER_PATHS = (
    Path("/usr/bin/chromium"),
    Path("/usr/bin/chromium-browser"),
    Path("/usr/bin/google-chrome-stable"),
    Path("/usr/bin/firefox"),
    Path("/usr/bin/firefox-esr"),
)
PROTON_PATHS = (Path("/usr/bin/umu-run"), Path("/usr/bin/proton"))
WINE_PATHS = (Path("/usr/bin/wine"), Path("/usr/bin/wine64"))
ISOLATION_PATHS = (Path("/usr/bin/bwrap"),)
KVM_PATHS = (Path("/dev/kvm"), Path("/sys/module/kvm"))

HostProbe = Callable[[], Mapping[str, object]]


def _normalize_architecture(value: str) -> str:
    token = value.strip().casefold().replace("-", "_")
    architecture = ARCHITECTURES.get(token)
    if architecture is None:
        raise FabricError(
            "compatibility.host-unmeasured",
            "Compatibility host architecture is unmeasured",
            "The machine architecture is not a supported Compatibility Center value.",
            detail=value[:64],
        )
    return architecture


def _clamp_int(value: int, minimum: int, maximum: int) -> int:
    if value < minimum:
        return minimum
    if value > maximum:
        return maximum
    return value


def _memory_mib() -> int:
    if hasattr(os, "sysconf"):
        try:
            pages = os.sysconf("SC_PHYS_PAGES")
            page_size = os.sysconf("SC_PAGE_SIZE")
        except (ValueError, OSError, OverflowError):
            pages = -1
            page_size = -1
        if isinstance(pages, int) and isinstance(page_size, int) and pages > 0 and page_size > 0:
            return _clamp_int((pages * page_size) // (1024 * 1024), 128, 262144)
    meminfo = Path("/proc/meminfo")
    if meminfo.is_file():
        try:
            for line in meminfo.read_text(encoding="utf-8").splitlines():
                if line.startswith("MemTotal:"):
                    parts = line.split()
                    kib = int(parts[1])
                    return _clamp_int(kib // 1024, 128, 262144)
        except (OSError, ValueError, IndexError, UnicodeDecodeError):
            pass
    if os.name == "nt":
        try:
            import ctypes

            class _MemoryStatus(ctypes.Structure):
                _fields_ = [
                    ("dwLength", ctypes.c_ulong),
                    ("dwMemoryLoad", ctypes.c_ulong),
                    ("ullTotalPhys", ctypes.c_ulonglong),
                    ("ullAvailPhys", ctypes.c_ulonglong),
                    ("ullTotalPageFile", ctypes.c_ulonglong),
                    ("ullAvailPageFile", ctypes.c_ulonglong),
                    ("ullTotalVirtual", ctypes.c_ulonglong),
                    ("ullAvailVirtual", ctypes.c_ulonglong),
                    ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
                ]

            status = _MemoryStatus()
            status.dwLength = ctypes.sizeof(_MemoryStatus)
            if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
                return _clamp_int(int(status.ullTotalPhys) // (1024 * 1024), 128, 262144)
        except (AttributeError, OSError, OverflowError, TypeError, ValueError):
            pass
    raise FabricError(
        "compatibility.host-unmeasured",
        "Compatibility host memory is unmeasured",
        "Physical memory could not be read from the operating system.",
    )


def _disk_mib() -> int:
    root = Path("C:\\") if os.name == "nt" else Path("/")
    try:
        usage = shutil.disk_usage(root)
    except OSError as error:
        raise FabricError(
            "compatibility.host-unmeasured",
            "Compatibility host disk is unmeasured",
            "Free disk capacity could not be read from the operating system.",
        ) from error
    return _clamp_int(int(usage.free) // (1024 * 1024), 1, 1048576)


def _any_exists(paths: tuple[Path, ...]) -> bool:
    return any(path.exists() for path in paths)


def measure_host(
    *,
    architecture: str | None = None,
    memory_mib: int | None = None,
    disk_mib: int | None = None,
    path_exists: Callable[[Path], bool] | None = None,
) -> dict[str, object]:
    exists = path_exists or (lambda path: path.exists())
    proton = any(exists(path) for path in PROTON_PATHS)
    wine = any(exists(path) for path in WINE_PATHS)
    isolation = any(exists(path) for path in ISOLATION_PATHS)
    browser = any(exists(path) for path in BROWSER_PATHS)
    virtualization = any(exists(path) for path in KVM_PATHS)
    runtimes = ["native"]
    if wine:
        runtimes.append("wine")
    if proton:
        runtimes.append("proton")
    if isolation:
        runtimes.append("container")
    if browser:
        runtimes.append("browser")
    host = {
        "architecture": _normalize_architecture(architecture if architecture is not None else platform.machine()),
        "virtualizationAvailable": virtualization,
        "protonAvailable": proton,
        "isolationAvailable": isolation,
        "browserAvailable": browser,
        "availableRuntimes": runtimes,
        "memoryMiB": memory_mib if memory_mib is not None else _memory_mib(),
        "diskMiB": disk_mib if disk_mib is not None else _disk_mib(),
    }
    error = next(iter(Draft202012Validator(HOST).iter_errors(host)), None)
    if error is not None:
        raise FabricError(
            "compatibility.host-unmeasured",
            "Compatibility host measurement is invalid",
            "The measured host document does not satisfy the closed Compatibility Center host contract.",
        )
    return host
