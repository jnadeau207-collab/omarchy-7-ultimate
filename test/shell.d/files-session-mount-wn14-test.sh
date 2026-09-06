#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

files_app="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"
files_session="$ROOT/shell/apps/shared/FilesSessionMount.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
project="$ROOT/plans/project-ultimate.md"
files_docs="$ROOT/docs/files-defaults-provider.md"
acc="$ROOT/WINDOWS_NATIVE_ACCEPTANCE.md"

[[ -f $files_app ]] || fail "FilesApplication exists"
[[ -f $files_session ]] || fail "FilesSessionMount exists"

grep -Fq 'function mountVolume(' "$files_session" || fail "FilesSessionMount hosts mountVolume"
grep -Fq 'storage-removable-mount' "$files_session" || fail "FilesSessionMount targets storage-removable-mount"
grep -Fq 'sessionMount.mountVolume' "$files_app" || fail "FilesApplication routes through mountVolume"
grep -Fiq 'soft leftover-attached' "$files_app" || fail "Files honesty soft leftover-attaches"
grep -Fq 'windows-native.14 stays prototype/pending' "$files_app" ||
  fail "Files honesty keeps windows-native.14 prototype/pending"
grep -Fq 'not product CLOSED' "$files_app" || fail "Files honesty refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$files_app" || fail "Files honesty refuses metal CLOSED"
grep -Fq 'not claim=present' "$files_app" || fail "Files honesty refuses claim=present"
grep -Fq 'FilesSessionMount.mountVolume' "$files_app" ||
  fail "Files coverage names tip-true mountVolume"
grep -Fq 'storage-removable-mount' "$files_app" || fail "Files coverage names storage-removable-mount"
grep -Fq 'does not invent a Fabric SHELL LIVE mount writer' "$files_app" ||
  fail "Files coverage refuses Fabric SHELL LIVE mount writer"

if grep -Eqi 'claim=present' "$files_app" && ! grep -Eqi 'not claim=present|Never claim=present|never claim=present' "$files_app"; then
  fail "Files must not invent claim=present"
fi
if grep -Eqi 'LIVE CONTROL' "$files_session"; then
  fail "FilesSessionMount must not invent LIVE CONTROL"
fi
if grep -Eqi 'Settings Power LIVE' "$files_app"; then
  fail "Files must not invent Settings Power LIVE"
fi
if grep -Eqi 'Empty Bin LIVE' "$files_app" | grep -Eiv 'Empty Bin LIVE remain unavailable|Fabric Restore UI and Empty Bin LIVE'; then
  fail "Files must not invent Empty Bin LIVE"
fi
if grep -Eqi 'End Task LIVE' "$files_app"; then
  fail "Files must not invent End Task LIVE"
fi
if grep -Eqi 'Win7 visual closed|Win7 visual leftover CLOSED' "$files_app"; then
  fail "Files must not invent Win7 visual closed"
fi

pass "Files Devices hosts tip-true mountVolume mount plane without invent"

python3 - "$catalog" "$jobs" "$gaps" "$parity" "$handoff" "$project" "$files_docs" "$acc" "$files_app" "$files_session" <<'PY'
import json
import sys

catalog = json.loads(open(sys.argv[1], encoding="utf-8").read())
jobs = json.loads(open(sys.argv[2], encoding="utf-8").read())
gaps = open(sys.argv[3], encoding="utf-8").read()
parity = open(sys.argv[4], encoding="utf-8").read()
handoff = open(sys.argv[5], encoding="utf-8").read()
project = open(sys.argv[6], encoding="utf-8").read()
files_docs = open(sys.argv[7], encoding="utf-8").read()
acc = open(sys.argv[8], encoding="utf-8").read()
files_app = open(sys.argv[9], encoding="utf-8").read()
files_session = open(sys.argv[10], encoding="utf-8").read()

by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
mount = by_id["storage.removable.mount"]
route = mount["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Files":
    raise SystemExit(f"storage.removable.mount route is {route}")
if route.get("path") != "Files > Devices > Mount":
    raise SystemExit(f"storage.removable.mount path is {route}")
if route.get("label") != "Mount removable storage":
    raise SystemExit(f"storage.removable.mount label is {route}")
if mount.get("availability", {}).get("claim") == "present":
    raise SystemExit("storage.removable.mount must not claim present")
if mount.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"storage.removable.mount claim is {mount.get('availability')}")
if mount.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"storage.removable.mount human is {mount.get('availability')}")
if mount.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"storage.removable.mount agent is {mount.get('availability')}")
if mount.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"storage.removable.mount provider state is {mount.get('provider')}")
if mount.get("provider", {}).get("id") != "storage.provider":
    raise SystemExit(f"storage.removable.mount provider is {mount.get('provider')}")
if mount.get("source", {}).get("file") != "shell/apps/shared/FilesSessionMount.qml":
    raise SystemExit(f"storage.removable.mount source is {mount.get('source')}")
if mount.get("source", {}).get("symbol") != "mountVolume":
    raise SystemExit(f"storage.removable.mount source symbol is {mount.get('source')}")
recovery = mount.get("recovery") or {}
if recovery.get("mode") != "compensating":
    raise SystemExit(f"storage.removable.mount recovery mode is {recovery}")
if recovery.get("stateFingerprintRequired") is not False:
    raise SystemExit(f"storage.removable.mount recovery fingerprint invent: {recovery}")
exp = recovery.get("expectation") or ""
for needle in (
    "mountVolume",
    "storage-removable-mount",
    "device.busy",
    "FilesSessionEject.ejectDevice",
    "storage-removable-eject",
    "no Fabric durable undo fingerprint invent",
    "no timed auto-rollback",
):
    if needle not in exp:
        raise SystemExit(f"storage.removable.mount recovery missing {needle!r}: {exp}")
if "state-fingerprint-guarded" in exp:
    raise SystemExit(f"storage.removable.mount still invents fingerprint-guarded compensating path: {exp}")

by_job = {job["id"]: job for job in jobs["jobs"]}
native14 = by_job["windows-native.14"]
if native14.get("claim") == "present":
    raise SystemExit("windows-native.14 must not claim present")
if native14.get("claim") != "prototype":
    raise SystemExit(f"windows-native.14 claim is {native14.get('claim')}")
if native14.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.14 sourceStatus is {native14.get('sourceStatus')}")
if native14.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.14 proofStatus is {native14.get('proofStatus')}")
if native14.get("capabilityIds") != ["storage.removable.mount"]:
    raise SystemExit(f"windows-native.14 capabilityIds are {native14.get('capabilityIds')}")
if native14.get("humanRoute", {}).get("path") != "Files > Devices > Mount":
    raise SystemExit(f"windows-native.14 path is {native14.get('humanRoute')}")
if native14.get("humanRoute", {}).get("status") != "visible":
    raise SystemExit(f"windows-native.14 route is {native14.get('humanRoute')}")
if native14.get("humanRoute", {}).get("surface") != "Files":
    raise SystemExit(f"windows-native.14 surface is {native14.get('humanRoute')}")
rec14 = native14.get("recoveryExpectation") or ""
for needle in ("mountVolume", "storage-removable-mount", "device.busy", "no timed auto-rollback"):
    if needle not in rec14:
        raise SystemExit(f"windows-native.14 recovery missing {needle!r}")
if "fingerprint invent" not in rec14.lower() and "no Fabric durable undo fingerprint invent" not in rec14:
    raise SystemExit(f"windows-native.14 recovery must refuse Fabric fingerprint invent: {rec14}")

explorer = by_job["parity.explorer-this-pc"]
if explorer.get("claim") == "present":
    raise SystemExit("parity.explorer-this-pc must not claim present")
if "storage.removable.mount" in (explorer.get("capabilityIds") or []):
    raise SystemExit("parity.explorer-this-pc invents Explorer present by naming storage.removable.mount")

if "| 14 | Connect a USB drive | pending |" not in acc:
    raise SystemExit("WINDOWS_NATIVE_ACCEPTANCE must keep wn.14 pending")

required_gaps = [
    "Honesty addendum 2026-09-06 vs Files Devices Mount leftover plane (windows-native.14)",
    "| `windows-native.14` | prototype/pending | visible: Files > Devices > Mount |",
    "mountVolume",
    "FilesSessionMount",
    "storage.removable.mount",
    "not product CLOSED",
    "not metal CLOSED",
    "not claim=present",
    "Do not invent Settings Power LIVE",
    "Do not invent End Task LIVE",
    "claims: missing=29, partial=6, plumbing=4, present=0, prototype=43",
]
for needle in required_gaps:
    if needle not in gaps:
        raise SystemExit(f"fleet-doctrine-gaps missing {needle!r}")
if "CLOSED leftover: Files Devices Mount" in gaps.split(
    "Honesty addendum 2026-09-06 vs Files Devices Mount leftover plane (windows-native.14)", 1
)[1].split("Honesty addendum", 1)[0]:
    raise SystemExit("fleet-doctrine-gaps invents CLOSED leftover for soft leftover-attach ACC wn.14")
if "windows-native.14 stays prototype/pending" not in gaps.replace("`", ""):
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.14 prototype/pending")

required_handoff = [
    "Honesty addendum 2026-09-06 vs Files Devices Mount leftover plane (windows-native.14)",
    "Files > Devices > Mount",
    "storage.removable.mount",
    "mountVolume",
    "FilesSessionMount",
    "not claim=present",
]
for needle in required_handoff:
    if needle not in handoff:
        raise SystemExit(f"HANDOFF_WRITERS missing {needle!r}")
if "windows-native.14 stays prototype/pending" not in handoff.replace("`", ""):
    raise SystemExit("HANDOFF_WRITERS must keep windows-native.14 prototype/pending")
if "`storage.removable.mount` stays leftover" not in handoff:
    raise SystemExit("HANDOFF_WRITERS must tip-align storage.removable.mount debt honesty")

if "soft leftover-attaches" not in parity.lower() or "windows-native.14" not in parity:
    raise SystemExit("PARITY must soft leftover-attach wn.14")
if "mountVolume" not in parity or "FilesSessionMount" not in parity:
    raise SystemExit("PARITY must name tip-true FilesSessionMount.mountVolume")

if "windows-native.14" not in project:
    raise SystemExit("project-ultimate must keep windows-native.14")
if "mountVolume" not in project or "FilesSessionMount" not in project:
    raise SystemExit("project-ultimate must name tip-true FilesSessionMount.mountVolume plane")

if "windows-native.14" not in files_docs:
    raise SystemExit("files-defaults-provider must keep windows-native.14")
if "prototype/pending" not in files_docs:
    raise SystemExit("files-defaults-provider must keep windows-native.14 prototype/pending")
if "mountVolume" not in files_docs and "FilesSessionMount" not in files_docs:
    raise SystemExit("files-defaults-provider must name tip-true mount plane")

if "function mountVolume(" not in files_session:
    raise SystemExit("FilesSessionMount must host mountVolume")
if "storage-removable-mount" not in files_session:
    raise SystemExit("FilesSessionMount must call storage-removable-mount")
if "soft leftover-attached" not in files_app.lower() or "windows-native.14" not in files_app:
    raise SystemExit("FilesApplication must soft leftover-attach wn.14")
if "windows-native.14 stays prototype/pending" not in files_app:
    raise SystemExit("FilesApplication must keep wn.14 prototype/pending")
PY

pass "storage.removable.mount stays partial with visible Files > Devices > Mount soft leftover-attached to wn.14"
