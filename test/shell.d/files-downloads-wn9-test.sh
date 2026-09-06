#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

files_app="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"
files_model="$ROOT/shell/apps/ultimate-files/FilesModel.js"
nav_pane="$ROOT/shell/apps/ultimate-files/ExplorerNavigationPane.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
project="$ROOT/plans/project-ultimate.md"
files_docs="$ROOT/docs/files-defaults-provider.md"
acc="$ROOT/WINDOWS_NATIVE_ACCEPTANCE.md"
app_search="$ROOT/shell/services/AppSearch.js"
files_desktop="$ROOT/applications/org.omarchy.Files.desktop"

[[ -f $files_app ]] || fail "FilesApplication exists"
[[ -f $files_model ]] || fail "FilesModel exists"
[[ -f $nav_pane ]] || fail "ExplorerNavigationPane exists"

grep -Fq 'files.location.downloads' "$files_model" || fail "FilesModel hosts files.location.downloads"
grep -Fq 'routeId: "files.downloads"' "$files_model" || fail "FilesModel hosts files.downloads route"
grep -Fq 'favorites.downloads' "$nav_pane" || fail "ExplorerNavigationPane hosts Downloads favorite"
grep -Fq 'routeId: "files.downloads"' "$nav_pane" || fail "ExplorerNavigationPane routes to files.downloads"
grep -Fq 'actionId: "Downloads"' "$app_search" || fail "AppSearch publishes Start Downloads"
grep -Fq '[Desktop Action Downloads]' "$files_desktop" || fail "Files desktop publishes Downloads action"
grep -Fq 'files.downloads' "$files_desktop" || fail "Files Downloads action targets files.downloads"
grep -Fiq 'soft leftover-attached' "$files_app" || fail "Files honesty soft leftover-attaches"
grep -Fq 'windows-native.9 stays prototype/pending' "$files_app" ||
  fail "Files honesty keeps windows-native.9 prototype/pending"
grep -Fq 'not product CLOSED' "$files_app" || fail "Files honesty refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$files_app" || fail "Files honesty refuses metal CLOSED"
grep -Fq 'not claim=present' "$files_app" || fail "Files honesty refuses claim=present"
grep -Fq 'FilesModel' "$files_app" || fail "Files coverage names tip-true FilesModel"
grep -Fq 'files.location.downloads' "$files_app" || fail "Files coverage names files.location.downloads"
grep -Fq 'files.downloads.open' "$files_app" || fail "Files coverage names files.downloads.open"

if grep -Eqi 'claim=present' "$files_app" && ! grep -Eqi 'not claim=present|Never claim=present|never claim=present' "$files_app"; then
  fail "Files must not invent claim=present"
fi
if grep -Eqi 'Settings Power LIVE' "$files_app"; then
  fail "Files must not invent Settings Power LIVE"
fi
if grep -Eqi 'End Task LIVE' "$files_app"; then
  fail "Files must not invent End Task LIVE"
fi
if grep -Eqi 'Win7 visual closed|Win7 visual leftover CLOSED' "$files_app"; then
  fail "Files must not invent Win7 visual closed"
fi

pass "Files hosts tip-true Downloads place without invent"

python3 - "$catalog" "$jobs" "$gaps" "$parity" "$handoff" "$project" "$files_docs" "$acc" "$files_app" "$files_model" "$nav_pane" <<'PY'
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
files_model = open(sys.argv[10], encoding="utf-8").read()
nav_pane = open(sys.argv[11], encoding="utf-8").read()

by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
downloads = by_id["files.downloads.open"]
route = downloads["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Files":
    raise SystemExit(f"files.downloads.open route is {route}")
if route.get("path") != "Start > Downloads; Superbar > Files > Downloads":
    raise SystemExit(f"files.downloads.open path is {route}")
if route.get("label") != "Open Downloads":
    raise SystemExit(f"files.downloads.open label is {route}")
if downloads.get("availability", {}).get("claim") == "present":
    raise SystemExit("files.downloads.open must not claim present")
if downloads.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"files.downloads.open claim is {downloads.get('availability')}")
if downloads.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"files.downloads.open human is {downloads.get('availability')}")
if downloads.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"files.downloads.open agent is {downloads.get('availability')}")
if downloads.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"files.downloads.open provider state is {downloads.get('provider')}")
if downloads.get("provider", {}).get("id") != "files.provider":
    raise SystemExit(f"files.downloads.open provider is {downloads.get('provider')}")
if downloads.get("source", {}).get("file") != "shell/apps/ultimate-files/FilesModel.js":
    raise SystemExit(f"files.downloads.open source is {downloads.get('source')}")
if downloads.get("source", {}).get("symbol") != "files.downloads":
    raise SystemExit(f"files.downloads.open source symbol is {downloads.get('source')}")
if "omarchy-launch-files" in str(downloads.get("source") or "").lower():
    raise SystemExit(f"files.downloads.open still invents launch-files: {downloads.get('source')}")
if "nautilus" in str(downloads.get("source") or "").lower():
    raise SystemExit(f"files.downloads.open still invents Nautilus: {downloads.get('source')}")
recovery = downloads.get("recovery") or {}
if recovery.get("mode") != "none":
    raise SystemExit(f"files.downloads.open recovery mode is {recovery}")
if recovery.get("stateFingerprintRequired") is not False:
    raise SystemExit(f"files.downloads.open recovery fingerprint invent: {recovery}")
exp = recovery.get("expectation") or ""
for needle in (
    "FilesModel",
    "files.downloads",
    "files.location.downloads",
    "no Fabric fingerprint invent",
):
    if needle not in exp:
        raise SystemExit(f"files.downloads.open recovery missing {needle!r}: {exp}")

by_job = {job["id"]: job for job in jobs["jobs"]}
native9 = by_job["windows-native.9"]
if native9.get("claim") == "present":
    raise SystemExit("windows-native.9 must not claim present")
if native9.get("claim") != "prototype":
    raise SystemExit(f"windows-native.9 claim is {native9.get('claim')}")
if native9.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.9 sourceStatus is {native9.get('sourceStatus')}")
if native9.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.9 proofStatus is {native9.get('proofStatus')}")
if native9.get("capabilityIds") != ["files.downloads.open"]:
    raise SystemExit(f"windows-native.9 capabilityIds are {native9.get('capabilityIds')}")
if native9.get("humanRoute", {}).get("path") != "Start > Downloads; Superbar > Files > Downloads":
    raise SystemExit(f"windows-native.9 path is {native9.get('humanRoute')}")
if native9.get("humanRoute", {}).get("status") != "visible":
    raise SystemExit(f"windows-native.9 route is {native9.get('humanRoute')}")
if native9.get("humanRoute", {}).get("surface") != "Files":
    raise SystemExit(f"windows-native.9 surface is {native9.get('humanRoute')}")
rec9 = native9.get("recoveryExpectation") or ""
for needle in ("FilesModel", "files.downloads", "files.location.downloads"):
    if needle not in rec9:
        raise SystemExit(f"windows-native.9 recovery missing {needle!r}")
if "fingerprint invent" not in rec9.lower() and "no Fabric fingerprint invent" not in rec9:
    raise SystemExit(f"windows-native.9 recovery must refuse Fabric fingerprint invent: {rec9}")

explorer = by_job["parity.explorer-this-pc"]
if explorer.get("claim") == "present":
    raise SystemExit("parity.explorer-this-pc must not claim present")
if "files.downloads.open" in (explorer.get("capabilityIds") or []):
    raise SystemExit("parity.explorer-this-pc invents Explorer present by naming files.downloads.open")

if "| 9 | Open Downloads | pending |" not in acc:
    raise SystemExit("WINDOWS_NATIVE_ACCEPTANCE must keep wn.9 pending")

required_gaps = [
    "Honesty addendum 2026-09-06 vs Files Open Downloads leftover plane (windows-native.9)",
    "| `windows-native.9` | prototype/pending | visible: Start > Downloads; Superbar > Files > Downloads |",
    "FilesModel",
    "files.downloads",
    "files.location.downloads",
    "files.downloads.open",
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
if "CLOSED leftover: Files Open Downloads" in gaps.split(
    "Honesty addendum 2026-09-06 vs Files Open Downloads leftover plane (windows-native.9)", 1
)[1].split("Honesty addendum", 1)[0]:
    raise SystemExit("fleet-doctrine-gaps invents CLOSED leftover for soft leftover-attach ACC wn.9")
if "windows-native.9 stays prototype/pending" not in gaps.replace("`", ""):
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.9 prototype/pending")

required_handoff = [
    "Honesty addendum 2026-09-06 vs Files Open Downloads leftover plane (windows-native.9)",
    "Start > Downloads; Superbar > Files > Downloads",
    "files.downloads.open",
    "FilesModel",
    "files.downloads",
    "not claim=present",
]
for needle in required_handoff:
    if needle not in handoff:
        raise SystemExit(f"HANDOFF_WRITERS missing {needle!r}")
if "windows-native.9 stays prototype/pending" not in handoff.replace("`", ""):
    raise SystemExit("HANDOFF_WRITERS must keep windows-native.9 prototype/pending")
if "`files.downloads.open` stays leftover" not in handoff:
    raise SystemExit("HANDOFF_WRITERS must tip-align files.downloads.open debt honesty")

if "soft leftover-attaches" not in parity.lower() or "windows-native.9" not in parity:
    raise SystemExit("PARITY must soft leftover-attach wn.9")
if "FilesModel" not in parity or "files.location.downloads" not in parity:
    raise SystemExit("PARITY must name tip-true Files Downloads place")

if "windows-native.9" not in project:
    raise SystemExit("project-ultimate must keep windows-native.9")
if "FilesModel" not in project or "files.location.downloads" not in project:
    raise SystemExit("project-ultimate must name tip-true Files Downloads place")

if "windows-native.9" not in files_docs:
    raise SystemExit("files-defaults-provider must keep windows-native.9")
if "prototype/pending" not in files_docs:
    raise SystemExit("files-defaults-provider must keep windows-native.9 prototype/pending")
if "FilesModel" not in files_docs and "files.location.downloads" not in files_docs:
    raise SystemExit("files-defaults-provider must name tip-true Downloads place")

if 'routeId: "files.downloads"' not in files_model:
    raise SystemExit("FilesModel must host files.downloads route")
if "files.location.downloads" not in files_model:
    raise SystemExit("FilesModel must host files.location.downloads")
if "favorites.downloads" not in nav_pane or 'routeId: "files.downloads"' not in nav_pane:
    raise SystemExit("ExplorerNavigationPane must host Downloads place")
if "soft leftover-attached" not in files_app.lower() or "windows-native.9" not in files_app:
    raise SystemExit("FilesApplication must soft leftover-attach wn.9")
if "windows-native.9 stays prototype/pending" not in files_app:
    raise SystemExit("FilesApplication must keep wn.9 prototype/pending")
if "omarchy-launch-files" in files_app and "files.downloads.open" in files_app:
    # boundary may mention launch elsewhere; ensure downloads.open attachment does not invent launch-files
    slice_idx = files_app.lower().find("files.downloads.open")
    nearby = files_app[max(0, slice_idx - 80) : slice_idx + 240]
    if "omarchy-launch-files" in nearby:
        raise SystemExit("FilesApplication downloads leftover must not invent launch-files")
PY

pass "files.downloads.open stays partial with visible Start/Superbar Downloads soft leftover-attached to wn.9"
