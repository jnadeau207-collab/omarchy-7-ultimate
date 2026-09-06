#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
settings_card="$ROOT/shell/apps/ultimate-settings/SettingsDisplayNightLight.qml"
session_nightlight="$ROOT/shell/apps/shared/SettingsSessionNightlight.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
project="$ROOT/plans/project-ultimate.md"
settings_api="$ROOT/docs/settings-service-api.md"
acc="$ROOT/WINDOWS_NATIVE_ACCEPTANCE.md"

[[ -f $settings_model ]] || fail "Settings model exists"
[[ -f $settings_card ]] || fail "SettingsDisplayNightLight exists"
[[ -f $session_nightlight ]] || fail "SettingsSessionNightlight exists"

grep -Fq 'function setEnabled(' "$session_nightlight" || fail "SettingsSessionNightlight hosts setEnabled"
grep -Fq 'nightlight' "$session_nightlight" || fail "SettingsSessionNightlight targets nightlight IPC"
grep -Fq 'sessionHost.setEnabled' "$settings_card" || fail "SettingsDisplayNightLight routes through setEnabled"
grep -Fiq 'soft leftover-attaches windows-native.34' "$settings_model" ||
  fail "Display honesty soft leftover-attaches wn.34"
grep -Fq 'windows-native.34 stays prototype/pending' "$settings_model" ||
  fail "Display honesty keeps windows-native.34 prototype/pending"
grep -Fq 'not product CLOSED' "$settings_model" || fail "Display honesty refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$settings_model" || fail "Display honesty refuses metal CLOSED"
grep -Fq 'not claim=present' "$settings_model" || fail "Display honesty refuses claim=present"
grep -Fq 'SettingsSessionNightlight.setEnabled' "$settings_model" ||
  fail "Display coverage names tip-true setEnabled"
grep -Fq 'NightlightService' "$settings_model" || fail "Display coverage names NightlightService"
grep -Fq 'does not invent a display.provider night-light durable writer' "$settings_model" ||
  fail "Display coverage refuses Fabric night-light writer"
grep -Eqi 'soft leftover-attaches windows-native.34' "$settings_card" ||
  fail "SettingsDisplayNightLight honesty soft leftover-attaches wn.34"
grep -Fq 'windows-native.34 stays prototype/pending' "$settings_card" ||
  fail "SettingsDisplayNightLight honesty keeps wn.34 prototype/pending"

if grep -Eqi 'claim=present' "$settings_model" && ! grep -Eqi 'not claim=present|Never claim=present|never claim=present' "$settings_model"; then
  fail "Display must not invent claim=present"
fi
if grep -Eqi 'Settings Power LIVE' "$settings_model"; then
  fail "Display must not invent Settings Power LIVE"
fi
if grep -Eqi 'Empty Bin LIVE' "$settings_model"; then
  fail "Display must not invent Empty Bin LIVE"
fi
if grep -Eqi 'End Task LIVE' "$settings_model"; then
  fail "Display must not invent End Task LIVE"
fi
if grep -Eqi 'Win7 visual closed|Win7 visual leftover CLOSED' "$settings_model"; then
  fail "Display must not invent Win7 visual closed"
fi
if grep -Eqi 'phase 5' "$settings_model"; then
  fail "Display must not invent a Phase 5 fence"
fi
if grep -Eqi 'is modern display complete|modern display complete' "$settings_card" "$settings_model" | grep -Eiv 'not modern display complete|Night light alone is not modern|Night light or scaling alone is not modern'; then
  fail "Display must not invent modern display complete"
fi

pass "Settings Display hosts tip-true setEnabled night-light plane without invent"

python3 - "$catalog" "$jobs" "$gaps" "$parity" "$handoff" "$project" "$settings_api" "$acc" "$settings_model" "$settings_card" "$session_nightlight" <<'PY'
import json
import sys

catalog = json.loads(open(sys.argv[1], encoding="utf-8").read())
jobs = json.loads(open(sys.argv[2], encoding="utf-8").read())
gaps = open(sys.argv[3], encoding="utf-8").read()
parity = open(sys.argv[4], encoding="utf-8").read()
handoff = open(sys.argv[5], encoding="utf-8").read()
project = open(sys.argv[6], encoding="utf-8").read()
settings_api = open(sys.argv[7], encoding="utf-8").read()
acc = open(sys.argv[8], encoding="utf-8").read()
settings_model = open(sys.argv[9], encoding="utf-8").read()
settings_card = open(sys.argv[10], encoding="utf-8").read()
session_nightlight = open(sys.argv[11], encoding="utf-8").read()

by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
night = by_id["display.night-light.set"]
route = night["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"display.night-light.set route is {route}")
if route.get("path") != "Settings > Display; Superbar > Quick Settings > Night light":
    raise SystemExit(f"display.night-light.set path is {route}")
if route.get("label") != "Turn night light on or off; QS leftover tile remains":
    raise SystemExit(f"display.night-light.set label is {route}")
if night.get("availability", {}).get("claim") == "present":
    raise SystemExit("display.night-light.set must not claim present")
if night.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"display.night-light.set claim is {night.get('availability')}")
if night.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"display.night-light.set human is {night.get('availability')}")
if night.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"display.night-light.set agent is {night.get('availability')}")
if night.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"display.night-light.set provider state is {night.get('provider')}")
if night.get("provider", {}).get("id") != "display.provider":
    raise SystemExit(f"display.night-light.set provider is {night.get('provider')}")
if night.get("source", {}).get("file") != "shell/plugins/services/nightlight/Service.qml":
    raise SystemExit(f"display.night-light.set source is {night.get('source')}")
if night.get("source", {}).get("symbol") != "NightlightService":
    raise SystemExit(f"display.night-light.set source symbol is {night.get('source')}")
if "SettingsDisplayNightLight.qml" in str(night.get("source", {}).get("file") or ""):
    raise SystemExit("display.night-light.set must not invent source on SettingsDisplayNightLight.qml")
recovery = night.get("recovery") or {}
if recovery.get("mode") != "undo":
    raise SystemExit(f"display.night-light.set recovery mode is {recovery}")
if recovery.get("stateFingerprintRequired") is not False:
    raise SystemExit(f"display.night-light.set recovery fingerprint invent: {recovery}")
exp = recovery.get("expectation") or ""
for needle in (
    "setEnabled",
    "NightlightService",
    "no Fabric durable undo fingerprint invent",
):
    if needle not in exp:
        raise SystemExit(f"display.night-light.set recovery missing {needle!r}: {exp}")

by_job = {job["id"]: job for job in jobs["jobs"]}
native34 = by_job["windows-native.34"]
if native34.get("claim") == "present":
    raise SystemExit("windows-native.34 must not claim present")
if native34.get("claim") != "prototype":
    raise SystemExit(f"windows-native.34 claim is {native34.get('claim')}")
if native34.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.34 sourceStatus is {native34.get('sourceStatus')}")
if native34.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.34 proofStatus is {native34.get('proofStatus')}")
if native34.get("capabilityIds") != ["display.night-light.set"]:
    raise SystemExit(f"windows-native.34 capabilityIds are {native34.get('capabilityIds')}")
if native34.get("humanRoute", {}).get("path") != "Settings > Display":
    raise SystemExit(f"windows-native.34 path is {native34.get('humanRoute')}")
if native34.get("humanRoute", {}).get("status") != "visible":
    raise SystemExit(f"windows-native.34 route is {native34.get('humanRoute')}")
if native34.get("humanRoute", {}).get("surface") != "Settings":
    raise SystemExit(f"windows-native.34 surface is {native34.get('humanRoute')}")
rec34 = native34.get("recoveryExpectation") or ""
for needle in ("setEnabled", "NightlightService"):
    if needle not in rec34:
        raise SystemExit(f"windows-native.34 recovery missing {needle!r}")
if "fingerprint invent" not in rec34.lower() and "no Fabric durable undo fingerprint invent" not in rec34:
    raise SystemExit(f"windows-native.34 recovery must refuse Fabric fingerprint invent: {rec34}")

parity_display = by_job["parity.display"]
if parity_display.get("claim") == "present":
    raise SystemExit("parity.display must not claim present")
if "display.night-light.set" not in (parity_display.get("capabilityIds") or []):
    raise SystemExit("parity.display dropped display.night-light.set")
modern = by_job["parity.modern-display-scaling-hdr-night-light"]
if modern.get("claim") == "present":
    raise SystemExit("parity.modern-display-scaling-hdr-night-light must not claim present")
if "display.night-light.set" not in (modern.get("capabilityIds") or []):
    raise SystemExit("parity.modern-display-scaling-hdr-night-light dropped display.night-light.set")

if "| 34 | Enable night light | pending |" not in acc:
    raise SystemExit("WINDOWS_NATIVE_ACCEPTANCE must keep wn.34 pending")

required_gaps = [
    "Honesty addendum 2026-09-06 vs Settings Display night-light leftover plane (windows-native.34)",
    "| `windows-native.34` | prototype/pending | visible: Settings > Display |",
    "setEnabled",
    "NightlightService",
    "display.night-light.set",
    "not product CLOSED",
    "not metal CLOSED",
    "not claim=present",
    "Do not invent Settings Power LIVE",
    "Do not invent Empty Bin LIVE",
    "Do not invent End Task LIVE",
    "claims: missing=29, partial=6, plumbing=4, present=0, prototype=43",
]
for needle in required_gaps:
    if needle not in gaps:
        raise SystemExit(f"fleet-doctrine-gaps missing {needle!r}")
if "CLOSED leftover: Settings Display night-light UI" in gaps.split(
    "Honesty addendum 2026-09-06 vs Settings Display night-light leftover plane (windows-native.34)", 1
)[1].split("Honesty addendum", 1)[0]:
    raise SystemExit("fleet-doctrine-gaps invents CLOSED leftover for soft leftover-attach ACC wn.34")
if "windows-native.34 stays prototype/pending" not in gaps.replace("`", ""):
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.34 prototype/pending")

required_handoff = [
    "Honesty addendum 2026-09-06 vs Settings Display night-light leftover plane (windows-native.34)",
    "Settings > Display",
    "display.night-light.set",
    "setEnabled",
    "NightlightService",
    "not claim=present",
]
for needle in required_handoff:
    if needle not in handoff:
        raise SystemExit(f"HANDOFF_WRITERS missing {needle!r}")
if "windows-native.34 stays prototype/pending" not in handoff.replace("`", ""):
    raise SystemExit("HANDOFF_WRITERS must keep windows-native.34 prototype/pending")

if "soft leftover-attaches" not in parity.lower() or "windows-native.34" not in parity:
    raise SystemExit("PARITY must soft leftover-attach wn.34")
if "setEnabled" not in parity or "NightlightService" not in parity:
    raise SystemExit("PARITY must name tip-true setEnabled → NightlightService")

if "windows-native.34" not in project:
    raise SystemExit("project-ultimate must keep windows-native.34")
if "setEnabled" not in project or "NightlightService" not in project:
    raise SystemExit("project-ultimate must name tip-true setEnabled → NightlightService plane")

if "windows-native.34" not in settings_api:
    raise SystemExit("settings-service-api must keep windows-native.34")
if "prototype/pending" not in settings_api:
    raise SystemExit("settings-service-api must keep windows-native.34 prototype/pending")
if "setEnabled" not in settings_api and "NightlightService" not in settings_api:
    raise SystemExit("settings-service-api must name tip-true night-light plane")

if "function setEnabled(" not in session_nightlight:
    raise SystemExit("SettingsSessionNightlight must host setEnabled")
if "nightlight" not in session_nightlight:
    raise SystemExit("SettingsSessionNightlight must call nightlight IPC")
if "sessionHost.setEnabled" not in settings_card:
    raise SystemExit("SettingsDisplayNightLight must route through setEnabled")
if "soft leftover-attaches windows-native.34" not in settings_model.lower():
    raise SystemExit("SettingsModel must soft leftover-attach wn.34")
if "windows-native.34 stays prototype/pending" not in settings_model:
    raise SystemExit("SettingsModel must keep wn.34 prototype/pending")
PY

pass "display.night-light.set stays partial with visible Settings > Display soft leftover-attached to wn.34"
