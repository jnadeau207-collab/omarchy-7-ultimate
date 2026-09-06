#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

files_app="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"
files_session="$ROOT/shell/apps/shared/FilesSessionEject.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
project="$ROOT/plans/project-ultimate.md"
files_docs="$ROOT/docs/files-defaults-provider.md"
acc="$ROOT/WINDOWS_NATIVE_ACCEPTANCE.md"

[[ -f $files_app ]] || fail "FilesApplication exists"
[[ -f $files_session ]] || fail "FilesSessionEject exists"

grep -Fq 'function ejectDevice(' "$files_session" || fail "FilesSessionEject hosts ejectDevice"
grep -Fq 'storage-removable-eject' "$files_session" || fail "FilesSessionEject targets storage-removable-eject"
grep -Fq 'sessionEject.ejectDevice' "$files_app" || fail "FilesApplication routes through ejectDevice"
grep -Fiq 'soft leftover-attached' "$files_app" || fail "Files honesty soft leftover-attaches"
grep -Fq 'windows-native.15 stays prototype/pending' "$files_app" ||
  fail "Files honesty keeps windows-native.15 prototype/pending"
grep -Fq 'not product CLOSED' "$files_app" || fail "Files honesty refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$files_app" || fail "Files honesty refuses metal CLOSED"
grep -Fq 'not claim=present' "$files_app" || fail "Files honesty refuses claim=present"
grep -Fq 'FilesSessionEject.ejectDevice' "$files_app" ||
  fail "Files coverage names tip-true ejectDevice"
grep -Fq 'storage-removable-eject' "$files_app" || fail "Files coverage names storage-removable-eject"
grep -Fq 'does not invent a Fabric SHELL LIVE eject writer' "$files_app" ||
  fail "Files coverage refuses Fabric SHELL LIVE eject writer"

if grep -Eqi 'claim=present' "$files_app" && ! grep -Eqi 'not claim=present|Never claim=present|never claim=present' "$files_app"; then
  fail "Files must not invent claim=present"
fi
if grep -Eqi 'LIVE CONTROL' "$files_session"; then
  fail "FilesSessionEject must not invent LIVE CONTROL"
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

pass "Files Devices hosts tip-true ejectDevice eject plane without invent"

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
eject = by_id["storage.removable.eject"]
route = eject["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Files":
    raise SystemExit(f"storage.removable.eject route is {route}")
if route.get("path") != "Files > Devices > Eject":
    raise SystemExit(f"storage.removable.eject path is {route}")
if route.get("label") != "Safely eject storage":
    raise SystemExit(f"storage.removable.eject label is {route}")
if eject.get("availability", {}).get("claim") == "present":
    raise SystemExit("storage.removable.eject must not claim present")
if eject.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"storage.removable.eject claim is {eject.get('availability')}")
if eject.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"storage.removable.eject human is {eject.get('availability')}")
if eject.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"storage.removable.eject agent is {eject.get('availability')}")
if eject.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"storage.removable.eject provider state is {eject.get('provider')}")
if eject.get("provider", {}).get("id") != "storage.provider":
    raise SystemExit(f"storage.removable.eject provider is {eject.get('provider')}")
if eject.get("source", {}).get("file") != "shell/apps/shared/FilesSessionEject.qml":
    raise SystemExit(f"storage.removable.eject source is {eject.get('source')}")
if eject.get("source", {}).get("symbol") != "ejectDevice":
    raise SystemExit(f"storage.removable.eject source symbol is {eject.get('source')}")
recovery = eject.get("recovery") or {}
if recovery.get("mode") != "compensating":
    raise SystemExit(f"storage.removable.eject recovery mode is {recovery}")
if recovery.get("stateFingerprintRequired") is not False:
    raise SystemExit(f"storage.removable.eject recovery fingerprint invent: {recovery}")
exp = recovery.get("expectation") or ""
for needle in (
    "ejectDevice",
    "storage-removable-eject",
    "device.busy",
    "FilesSessionMount.mountVolume",
    "storage-removable-mount",
    "no Fabric durable undo fingerprint invent",
    "no timed auto-rollback",
):
    if needle not in exp:
        raise SystemExit(f"storage.removable.eject recovery missing {needle!r}: {exp}")
if "state-fingerprint-guarded" in exp:
    raise SystemExit(f"storage.removable.eject still invents fingerprint-guarded compensating path: {exp}")

by_job = {job["id"]: job for job in jobs["jobs"]}
native15 = by_job["windows-native.15"]
if native15.get("claim") == "present":
    raise SystemExit("windows-native.15 must not claim present")
if native15.get("claim") != "prototype":
    raise SystemExit(f"windows-native.15 claim is {native15.get('claim')}")
if native15.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.15 sourceStatus is {native15.get('sourceStatus')}")
if native15.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.15 proofStatus is {native15.get('proofStatus')}")
if native15.get("capabilityIds") != ["storage.removable.eject"]:
    raise SystemExit(f"windows-native.15 capabilityIds are {native15.get('capabilityIds')}")
if native15.get("humanRoute", {}).get("path") != "Files > Devices > Eject":
    raise SystemExit(f"windows-native.15 path is {native15.get('humanRoute')}")
if native15.get("humanRoute", {}).get("status") != "visible":
    raise SystemExit(f"windows-native.15 route is {native15.get('humanRoute')}")
if native15.get("humanRoute", {}).get("surface") != "Files":
    raise SystemExit(f"windows-native.15 surface is {native15.get('humanRoute')}")
rec15 = native15.get("recoveryExpectation") or ""
for needle in ("ejectDevice", "storage-removable-eject", "device.busy", "no timed auto-rollback"):
    if needle not in rec15:
        raise SystemExit(f"windows-native.15 recovery missing {needle!r}")
if "fingerprint invent" not in rec15.lower() and "no Fabric durable undo fingerprint invent" not in rec15:
    raise SystemExit(f"windows-native.15 recovery must refuse Fabric fingerprint invent: {rec15}")

explorer = by_job["parity.explorer-this-pc"]
if explorer.get("claim") == "present":
    raise SystemExit("parity.explorer-this-pc must not claim present")
if "storage.removable.eject" in (explorer.get("capabilityIds") or []):
    raise SystemExit("parity.explorer-this-pc invents Explorer present by naming storage.removable.eject")

if "| 15 | Eject it | pending |" not in acc:
    raise SystemExit("WINDOWS_NATIVE_ACCEPTANCE must keep wn.15 pending")

required_gaps = [
    "Honesty addendum 2026-09-06 vs Files Devices Eject leftover plane (windows-native.15)",
    "| `windows-native.15` | prototype/pending | visible: Files > Devices > Eject |",
    "ejectDevice",
    "FilesSessionEject",
    "storage.removable.eject",
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
if "CLOSED leftover: Files Devices Eject" in gaps.split(
    "Honesty addendum 2026-09-06 vs Files Devices Eject leftover plane (windows-native.15)", 1
)[1].split("Honesty addendum", 1)[0]:
    raise SystemExit("fleet-doctrine-gaps invents CLOSED leftover for soft leftover-attach ACC wn.15")
if "windows-native.15 stays prototype/pending" not in gaps.replace("`", ""):
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.15 prototype/pending")

required_handoff = [
    "Honesty addendum 2026-09-06 vs Files Devices Eject leftover plane (windows-native.15)",
    "Files > Devices > Eject",
    "storage.removable.eject",
    "ejectDevice",
    "FilesSessionEject",
    "not claim=present",
]
for needle in required_handoff:
    if needle not in handoff:
        raise SystemExit(f"HANDOFF_WRITERS missing {needle!r}")
if "windows-native.15 stays prototype/pending" not in handoff.replace("`", ""):
    raise SystemExit("HANDOFF_WRITERS must keep windows-native.15 prototype/pending")
if "`storage.removable.eject` stays leftover" not in handoff:
    raise SystemExit("HANDOFF_WRITERS must tip-align storage.removable.eject debt honesty")

if "soft leftover-attaches" not in parity.lower() or "windows-native.15" not in parity:
    raise SystemExit("PARITY must soft leftover-attach wn.15")
if "ejectDevice" not in parity or "FilesSessionEject" not in parity:
    raise SystemExit("PARITY must name tip-true FilesSessionEject.ejectDevice")

if "windows-native.15" not in project:
    raise SystemExit("project-ultimate must keep windows-native.15")
if "ejectDevice" not in project or "FilesSessionEject" not in project:
    raise SystemExit("project-ultimate must name tip-true FilesSessionEject.ejectDevice plane")

if "windows-native.15" not in files_docs:
    raise SystemExit("files-defaults-provider must keep windows-native.15")
if "prototype/pending" not in files_docs:
    raise SystemExit("files-defaults-provider must keep windows-native.15 prototype/pending")
if "ejectDevice" not in files_docs and "FilesSessionEject" not in files_docs:
    raise SystemExit("files-defaults-provider must name tip-true eject plane")

if "function ejectDevice(" not in files_session:
    raise SystemExit("FilesSessionEject must host ejectDevice")
if "storage-removable-eject" not in files_session:
    raise SystemExit("FilesSessionEject must call storage-removable-eject")
if "soft leftover-attached" not in files_app.lower() or "windows-native.15" not in files_app:
    raise SystemExit("FilesApplication must soft leftover-attach wn.15")
if "windows-native.15 stays prototype/pending" not in files_app:
    raise SystemExit("FilesApplication must keep wn.15 prototype/pending")
PY

pass "storage.removable.eject stays partial with visible Files > Devices > Eject soft leftover-attached to wn.15"
