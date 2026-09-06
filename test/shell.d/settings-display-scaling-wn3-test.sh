#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
settings_card="$ROOT/shell/apps/ultimate-settings/SettingsDisplayScaling.qml"
session_scaling="$ROOT/shell/apps/shared/SettingsSessionScaling.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
project="$ROOT/plans/project-ultimate.md"
settings_api="$ROOT/docs/settings-service-api.md"
acc="$ROOT/WINDOWS_NATIVE_ACCEPTANCE.md"

[[ -f $settings_model ]] || fail "Settings model exists"
[[ -f $settings_card ]] || fail "SettingsDisplayScaling exists"
[[ -f $session_scaling ]] || fail "SettingsSessionScaling exists"

grep -Fq 'function setScale(' "$session_scaling" || fail "SettingsSessionScaling hosts setScale"
grep -Fq 'display-monitor-scale' "$session_scaling" || fail "SettingsSessionScaling targets display-monitor-scale"
grep -Fq 'sessionHost.setScale' "$settings_card" || fail "SettingsDisplayScaling routes through setScale"
grep -Fiq 'soft leftover-attaches windows-native.3' "$settings_model" ||
  fail "Display honesty soft leftover-attaches wn.3"
grep -Fq 'windows-native.3 stays prototype/pending' "$settings_model" ||
  fail "Display honesty keeps windows-native.3 prototype/pending"
grep -Fq 'not product CLOSED' "$settings_model" || fail "Display honesty refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$settings_model" || fail "Display honesty refuses metal CLOSED"
grep -Fq 'not claim=present' "$settings_model" || fail "Display honesty refuses claim=present"
grep -Fq 'SettingsSessionScaling.setScale' "$settings_model" ||
  fail "Display coverage names tip-true setScale"
grep -Fq 'display-monitor-scale' "$settings_model" || fail "Display coverage names display-monitor-scale"
grep -Fq 'does not invent a display.provider scale durable writer' "$settings_model" ||
  fail "Display coverage refuses Fabric scale writer"
grep -Eqi 'soft leftover-attaches windows-native.3' "$settings_card" ||
  fail "SettingsDisplayScaling honesty soft leftover-attaches wn.3"
grep -Fq 'windows-native.3 stays prototype/pending' "$settings_card" ||
  fail "SettingsDisplayScaling honesty keeps wn.3 prototype/pending"

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
if grep -Eqi 'is modern display complete|modern display complete' "$settings_card" "$settings_model" | grep -Eiv 'not modern display complete|Scaling alone is not modern|Night light or scaling alone is not modern|Night light alone is not modern'; then
  fail "Display must not invent modern display complete"
fi

pass "Settings Display hosts tip-true setScale scale plane without invent"

python3 - "$catalog" "$jobs" "$gaps" "$parity" "$handoff" "$project" "$settings_api" "$acc" "$settings_model" "$settings_card" "$session_scaling" <<'PY'
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
session_scaling = open(sys.argv[11], encoding="utf-8").read()

by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
scale = by_id["display.scale.set"]
route = scale["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"display.scale.set route is {route}")
if route.get("path") != "Settings > Display":
    raise SystemExit(f"display.scale.set path is {route}")
if route.get("label") != "Set display scaling":
    raise SystemExit(f"display.scale.set label is {route}")
if scale.get("availability", {}).get("claim") == "present":
    raise SystemExit("display.scale.set must not claim present")
if scale.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"display.scale.set claim is {scale.get('availability')}")
if scale.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"display.scale.set human is {scale.get('availability')}")
if scale.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"display.scale.set agent is {scale.get('availability')}")
if scale.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"display.scale.set provider state is {scale.get('provider')}")
if scale.get("provider", {}).get("id") != "display.provider":
    raise SystemExit(f"display.scale.set provider is {scale.get('provider')}")
if scale.get("source", {}).get("file") != "shell/apps/shared/SettingsSessionScaling.qml":
    raise SystemExit(f"display.scale.set source is {scale.get('source')}")
if scale.get("source", {}).get("symbol") != "setScale":
    raise SystemExit(f"display.scale.set source symbol is {scale.get('source')}")
if "SettingsDisplayScaling.qml" in str(scale.get("source", {}).get("file") or ""):
    raise SystemExit("display.scale.set must not invent source on SettingsDisplayScaling.qml")
recovery = scale.get("recovery") or {}
if recovery.get("mode") != "undo":
    raise SystemExit(f"display.scale.set recovery mode is {recovery}")
if recovery.get("stateFingerprintRequired") is not False:
    raise SystemExit(f"display.scale.set recovery fingerprint invent: {recovery}")
exp = recovery.get("expectation") or ""
for needle in (
    "setScale",
    "display-monitor-scale",
    "omarchy-hyprland-monitor-scaling",
    "no Fabric durable undo fingerprint invent",
    "no timed auto-rollback",
):
    if needle not in exp:
        raise SystemExit(f"display.scale.set recovery missing {needle!r}: {exp}")

by_job = {job["id"]: job for job in jobs["jobs"]}
native3 = by_job["windows-native.3"]
if native3.get("claim") == "present":
    raise SystemExit("windows-native.3 must not claim present")
if native3.get("claim") != "prototype":
    raise SystemExit(f"windows-native.3 claim is {native3.get('claim')}")
if native3.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.3 sourceStatus is {native3.get('sourceStatus')}")
if native3.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.3 proofStatus is {native3.get('proofStatus')}")
if native3.get("capabilityIds") != ["display.scale.set"]:
    raise SystemExit(f"windows-native.3 capabilityIds are {native3.get('capabilityIds')}")
if native3.get("humanRoute", {}).get("path") != "Settings > Display":
    raise SystemExit(f"windows-native.3 path is {native3.get('humanRoute')}")
if native3.get("humanRoute", {}).get("status") != "visible":
    raise SystemExit(f"windows-native.3 route is {native3.get('humanRoute')}")
if native3.get("humanRoute", {}).get("surface") != "Settings":
    raise SystemExit(f"windows-native.3 surface is {native3.get('humanRoute')}")
rec3 = native3.get("recoveryExpectation") or ""
for needle in ("setScale", "display-monitor-scale", "no timed auto-rollback"):
    if needle not in rec3:
        raise SystemExit(f"windows-native.3 recovery missing {needle!r}")
if "fingerprint invent" not in rec3.lower() and "no Fabric durable undo fingerprint invent" not in rec3:
    raise SystemExit(f"windows-native.3 recovery must refuse Fabric fingerprint invent: {rec3}")

parity_display = by_job["parity.display"]
if parity_display.get("claim") == "present":
    raise SystemExit("parity.display must not claim present")
if "display.scale.set" not in (parity_display.get("capabilityIds") or []):
    raise SystemExit("parity.display dropped display.scale.set")
modern = by_job["parity.modern-display-scaling-hdr-night-light"]
if modern.get("claim") == "present":
    raise SystemExit("parity.modern-display-scaling-hdr-night-light must not claim present")
if "display.scale.set" not in (modern.get("capabilityIds") or []):
    raise SystemExit("parity.modern-display-scaling-hdr-night-light dropped display.scale.set")

if "| 3 | Set display scaling to 125% | pending |" not in acc:
    raise SystemExit("WINDOWS_NATIVE_ACCEPTANCE must keep wn.3 pending")

required_gaps = [
    "Honesty addendum 2026-09-06 vs Settings Display scaling leftover plane (windows-native.3)",
    "| `windows-native.3` | prototype/pending | visible: Settings > Display |",
    "setScale",
    "SettingsSessionScaling",
    "display.scale.set",
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
if "CLOSED leftover: Settings Display scaling" in gaps.split(
    "Honesty addendum 2026-09-06 vs Settings Display scaling leftover plane (windows-native.3)", 1
)[1].split("Honesty addendum", 1)[0]:
    raise SystemExit("fleet-doctrine-gaps invents CLOSED leftover for soft leftover-attach ACC wn.3")
if "windows-native.3 stays prototype/pending" not in gaps.replace("`", ""):
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.3 prototype/pending")

required_handoff = [
    "Honesty addendum 2026-09-06 vs Settings Display scaling leftover plane (windows-native.3)",
    "Settings > Display",
    "display.scale.set",
    "setScale",
    "SettingsSessionScaling",
    "not claim=present",
]
for needle in required_handoff:
    if needle not in handoff:
        raise SystemExit(f"HANDOFF_WRITERS missing {needle!r}")
if "windows-native.3 stays prototype/pending" not in handoff.replace("`", ""):
    raise SystemExit("HANDOFF_WRITERS must keep windows-native.3 prototype/pending")

if "soft leftover-attaches" not in parity.lower() or "windows-native.3" not in parity:
    raise SystemExit("PARITY must soft leftover-attach wn.3")
if "setScale" not in parity or "SettingsSessionScaling" not in parity:
    raise SystemExit("PARITY must name tip-true SettingsSessionScaling.setScale")

if "windows-native.3" not in project:
    raise SystemExit("project-ultimate must keep windows-native.3")
if "setScale" not in project or "SettingsSessionScaling" not in project:
    raise SystemExit("project-ultimate must name tip-true SettingsSessionScaling.setScale plane")

if "windows-native.3" not in settings_api:
    raise SystemExit("settings-service-api must keep windows-native.3")
if "prototype/pending" not in settings_api:
    raise SystemExit("settings-service-api must keep windows-native.3 prototype/pending")
if "setScale" not in settings_api and "SettingsSessionScaling" not in settings_api:
    raise SystemExit("settings-service-api must name tip-true scale plane")

if "function setScale(" not in session_scaling:
    raise SystemExit("SettingsSessionScaling must host setScale")
if "display-monitor-scale" not in session_scaling:
    raise SystemExit("SettingsSessionScaling must call display-monitor-scale")
if "sessionHost.setScale" not in settings_card:
    raise SystemExit("SettingsDisplayScaling must route through setScale")
if "soft leftover-attaches windows-native.3" not in settings_model.lower():
    raise SystemExit("SettingsModel must soft leftover-attach wn.3")
if "windows-native.3 stays prototype/pending" not in settings_model:
    raise SystemExit("SettingsModel must keep wn.3 prototype/pending")
PY

pass "display.scale.set stays partial with visible Settings > Display soft leftover-attached to wn.3"
