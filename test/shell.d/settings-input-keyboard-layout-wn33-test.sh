#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
settings_card="$ROOT/shell/apps/ultimate-settings/SettingsInputLayout.qml"
session_layout="$ROOT/shell/apps/shared/SettingsSessionKeyboardLayout.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
project="$ROOT/plans/project-ultimate.md"
settings_api="$ROOT/docs/settings-service-api.md"
acc="$ROOT/WINDOWS_NATIVE_ACCEPTANCE.md"

[[ -f $settings_model ]] || fail "Settings model exists"
[[ -f $settings_card ]] || fail "SettingsInputLayout exists"
[[ -f $session_layout ]] || fail "SettingsSessionKeyboardLayout exists"

grep -Fq 'function setLayout(' "$session_layout" || fail "SettingsSessionKeyboardLayout hosts setLayout"
grep -Fq 'input-keyboard-layout' "$session_layout" || fail "SettingsSessionKeyboardLayout calls input-keyboard-layout"
grep -Fq 'sessionHost.setLayout' "$settings_card" || fail "SettingsInputLayout routes through setLayout"
grep -Fq 'soft leftover-attaches windows-native.33' "$settings_model" ||
  fail "Input honesty soft leftover-attaches wn.33"
grep -Fq 'windows-native.33 stays prototype/pending' "$settings_model" ||
  fail "Input honesty keeps windows-native.33 prototype/pending"
grep -Fq 'not product CLOSED' "$settings_model" || fail "Input honesty refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$settings_model" || fail "Input honesty refuses metal CLOSED"
grep -Fq 'not claim=present' "$settings_model" || fail "Input honesty refuses claim=present"
grep -Fq 'SettingsSessionKeyboardLayout.setLayout' "$settings_model" ||
  fail "Input coverage names tip-true setLayout"
grep -Fq 'input-keyboard-layout' "$settings_model" || fail "Input coverage names input-keyboard-layout"
grep -Fq 'does not invent an input.provider keyboard-layout durable writer' "$settings_model" ||
  fail "Input coverage refuses Fabric layout writer"
grep -Eqi 'soft leftover-attaches windows-native.33' "$settings_card" ||
  fail "SettingsInputLayout honesty soft leftover-attaches wn.33"
grep -Fq 'windows-native.33 stays prototype/pending' "$settings_card" ||
  fail "SettingsInputLayout honesty keeps wn.33 prototype/pending"

if grep -Eqi 'claim=present' "$settings_model" && ! grep -Eqi 'not claim=present|Never claim=present|never claim=present' "$settings_model"; then
  fail "Input must not invent claim=present"
fi
if grep -Eqi 'Settings Power LIVE' "$settings_model"; then
  fail "Input must not invent Settings Power LIVE"
fi
if grep -Eqi 'Empty Bin LIVE' "$settings_model"; then
  fail "Input must not invent Empty Bin LIVE"
fi
if grep -Eqi 'End Task LIVE' "$settings_model"; then
  fail "Input must not invent End Task LIVE"
fi
if grep -Eqi 'Win7 visual closed|Win7 visual leftover CLOSED' "$settings_model"; then
  fail "Input must not invent Win7 visual closed"
fi
if grep -Eqi 'phase 5' "$settings_model"; then
  fail "Input must not invent a Phase 5 fence"
fi
if grep -Eqi 'locale complete|locale product-complete' "$settings_card" "$settings_model" | grep -Eiv 'not locale complete|Layout alone is not locale'; then
  fail "Input must not invent locale complete"
fi

pass "Settings Input hosts tip-true setLayout keyboard plane without invent"

python3 - "$catalog" "$jobs" "$gaps" "$parity" "$handoff" "$project" "$settings_api" "$acc" "$settings_model" "$settings_card" "$session_layout" <<'PY'
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
session_layout = open(sys.argv[11], encoding="utf-8").read()

by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
layout = by_id["input.keyboard-layout.set"]
route = layout["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"input.keyboard-layout.set route is {route}")
if route.get("path") != "Settings > Input":
    raise SystemExit(f"input.keyboard-layout.set path is {route}")
if route.get("label") != "Change keyboard layout":
    raise SystemExit(f"input.keyboard-layout.set label is {route}")
if layout.get("availability", {}).get("claim") == "present":
    raise SystemExit("input.keyboard-layout.set must not claim present")
if layout.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"input.keyboard-layout.set claim is {layout.get('availability')}")
if layout.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"input.keyboard-layout.set human is {layout.get('availability')}")
if layout.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"input.keyboard-layout.set agent is {layout.get('availability')}")
if layout.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"input.keyboard-layout.set provider state is {layout.get('provider')}")
if layout.get("provider", {}).get("id") != "input.provider":
    raise SystemExit(f"input.keyboard-layout.set provider is {layout.get('provider')}")
if layout.get("source", {}).get("file") != "default/fabric/omarchy_fabric/helpers/session_apply.py":
    raise SystemExit(f"input.keyboard-layout.set source is {layout.get('source')}")
if layout.get("source", {}).get("symbol") != "apply_input_keyboard_layout_session":
    raise SystemExit(f"input.keyboard-layout.set source symbol is {layout.get('source')}")
if "SettingsInputLayout.qml" in str(layout.get("source", {}).get("file") or ""):
    raise SystemExit("input.keyboard-layout.set must not invent source on SettingsInputLayout.qml")
recovery = layout.get("recovery") or {}
if recovery.get("mode") != "undo":
    raise SystemExit(f"input.keyboard-layout.set recovery mode is {recovery}")
if recovery.get("stateFingerprintRequired") is not False:
    raise SystemExit(f"input.keyboard-layout.set recovery fingerprint invent: {recovery}")
exp = recovery.get("expectation") or ""
for needle in (
    "setLayout",
    "input-keyboard-layout",
    "no Fabric durable undo fingerprint invent",
):
    if needle not in exp:
        raise SystemExit(f"input.keyboard-layout.set recovery missing {needle!r}: {exp}")

by_job = {job["id"]: job for job in jobs["jobs"]}
native33 = by_job["windows-native.33"]
if native33.get("claim") == "present":
    raise SystemExit("windows-native.33 must not claim present")
if native33.get("claim") != "prototype":
    raise SystemExit(f"windows-native.33 claim is {native33.get('claim')}")
if native33.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.33 sourceStatus is {native33.get('sourceStatus')}")
if native33.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.33 proofStatus is {native33.get('proofStatus')}")
if native33.get("capabilityIds") != ["input.keyboard-layout.set"]:
    raise SystemExit(f"windows-native.33 capabilityIds are {native33.get('capabilityIds')}")
if native33.get("humanRoute", {}).get("path") != "Settings > Input":
    raise SystemExit(f"windows-native.33 path is {native33.get('humanRoute')}")
if native33.get("humanRoute", {}).get("status") != "visible":
    raise SystemExit(f"windows-native.33 route is {native33.get('humanRoute')}")
if native33.get("humanRoute", {}).get("surface") != "Settings":
    raise SystemExit(f"windows-native.33 surface is {native33.get('humanRoute')}")
rec33 = native33.get("recoveryExpectation") or ""
for needle in ("setLayout", "input-keyboard-layout"):
    if needle not in rec33:
        raise SystemExit(f"windows-native.33 recovery missing {needle!r}")
if "fingerprint invent" not in rec33.lower() and "no Fabric durable undo fingerprint invent" not in rec33:
    raise SystemExit(f"windows-native.33 recovery must refuse Fabric fingerprint invent: {rec33}")

parity_locale = by_job["parity.language-locale"]
if parity_locale.get("claim") == "present":
    raise SystemExit("parity.language-locale must not claim present")
if "input.keyboard-layout.set" not in (parity_locale.get("capabilityIds") or []):
    raise SystemExit("parity.language-locale dropped input.keyboard-layout.set")

if "| 33 | Change keyboard layout | pending |" not in acc:
    raise SystemExit("WINDOWS_NATIVE_ACCEPTANCE must keep wn.33 pending")

required_gaps = [
    "Honesty addendum 2026-09-06 vs Settings Input keyboard layout leftover plane (windows-native.33)",
    "| `windows-native.33` | prototype/pending | visible: Settings > Input |",
    "setLayout",
    "input-keyboard-layout",
    "input.keyboard-layout.set",
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
if "CLOSED leftover: Settings Input keyboard layout" in gaps.split(
    "Honesty addendum 2026-09-06 vs Settings Input keyboard layout leftover plane (windows-native.33)", 1
)[1].split("Honesty addendum", 1)[0]:
    raise SystemExit("fleet-doctrine-gaps invents CLOSED leftover for soft leftover-attach ACC wn.33")
if "windows-native.33 stays prototype/pending" not in gaps.replace("`", ""):
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.33 prototype/pending")

required_handoff = [
    "Honesty addendum 2026-09-06 vs Settings Input keyboard layout leftover plane (windows-native.33)",
    "Settings > Input",
    "input.keyboard-layout.set",
    "setLayout",
    "input-keyboard-layout",
    "not claim=present",
]
for needle in required_handoff:
    if needle not in handoff:
        raise SystemExit(f"HANDOFF_WRITERS missing {needle!r}")
if "windows-native.33 stays prototype/pending" not in handoff.replace("`", ""):
    raise SystemExit("HANDOFF_WRITERS must keep windows-native.33 prototype/pending")

if "soft leftover-attaches `windows-native.33`" not in parity and "soft leftover-attaches windows-native.33" not in parity:
    raise SystemExit("PARITY must soft leftover-attach wn.33")
if 'Forty-task "Change keyboard layout" stays pending' not in parity and "Forty-task \"Change keyboard layout\" stays pending" not in parity:
    raise SystemExit("PARITY must keep forty-task Change keyboard layout pending")
if "setLayout" not in parity or "input-keyboard-layout" not in parity:
    raise SystemExit("PARITY must name tip-true setLayout → input-keyboard-layout")

if "windows-native.33" not in project:
    raise SystemExit("project-ultimate must keep windows-native.33")
if "setLayout" not in project or "input-keyboard-layout" not in project:
    raise SystemExit("project-ultimate must name tip-true setLayout → input-keyboard-layout plane")

if "windows-native.33" not in settings_api:
    raise SystemExit("settings-service-api must keep windows-native.33")
if "prototype/pending" not in settings_api:
    raise SystemExit("settings-service-api must keep windows-native.33 prototype/pending")
if "setLayout" not in settings_api and "input-keyboard-layout" not in settings_api:
    raise SystemExit("settings-service-api must name tip-true keyboard layout plane")

if "function setLayout(" not in session_layout:
    raise SystemExit("SettingsSessionKeyboardLayout must host setLayout")
if "input-keyboard-layout" not in session_layout:
    raise SystemExit("SettingsSessionKeyboardLayout must call input-keyboard-layout")
if "sessionHost.setLayout" not in settings_card:
    raise SystemExit("SettingsInputLayout must route through setLayout")
if "soft leftover-attaches windows-native.33" not in settings_model:
    raise SystemExit("SettingsModel must soft leftover-attach wn.33")
if "windows-native.33 stays prototype/pending" not in settings_model:
    raise SystemExit("SettingsModel must keep wn.33 prototype/pending")
PY

pass "input.keyboard-layout.set stays partial with visible Settings > Input soft leftover-attached to wn.33"
