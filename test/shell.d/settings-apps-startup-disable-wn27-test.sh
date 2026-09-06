#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
settings_startup="$ROOT/shell/apps/ultimate-settings/SettingsAppsStartup.qml"
session_startup="$ROOT/shell/apps/shared/SettingsSessionStartup.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
project="$ROOT/plans/project-ultimate.md"
settings_api="$ROOT/docs/settings-service-api.md"
acc="$ROOT/WINDOWS_NATIVE_ACCEPTANCE.md"

[[ -f $settings_model ]] || fail "Settings model exists"
[[ -f $settings_startup ]] || fail "SettingsAppsStartup exists"
[[ -f $session_startup ]] || fail "SettingsSessionStartup exists"

grep -Fq 'function setEnabled(' "$session_startup" || fail "SettingsSessionStartup hosts setEnabled"
grep -Fq 'apps-startup-set' "$session_startup" || fail "SettingsSessionStartup calls apps-startup-set"
grep -Fq 'sessionHost.setEnabled' "$settings_startup" || fail "SettingsAppsStartup routes through setEnabled"
grep -Fq 'soft leftover-attaches windows-native.27' "$settings_model" ||
  fail "Apps honesty soft leftover-attaches wn.27"
grep -Fq 'windows-native.27 stays prototype/pending' "$settings_model" ||
  fail "Apps honesty keeps windows-native.27 prototype/pending"
grep -Fq 'not product CLOSED' "$settings_model" || fail "Apps honesty refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$settings_model" || fail "Apps honesty refuses metal CLOSED"
grep -Fq 'not claim=present' "$settings_model" || fail "Apps honesty refuses claim=present"
grep -Fq 'SettingsSessionStartup.setEnabled' "$settings_model" ||
  fail "Apps coverage names tip-true setEnabled"
grep -Fq 'apps-startup-set' "$settings_model" || fail "Apps coverage names apps-startup-set"
grep -Fq 'does not invent a Fabric apps.startup.disable durable writer' "$settings_model" ||
  fail "Apps coverage refuses Fabric startup writer"
grep -Fq 'does not invent Task Manager present' "$settings_model" ||
  fail "Apps coverage refuses Task Manager present"
grep -Eqi 'soft leftover-attaches windows-native.27' "$settings_startup" ||
  fail "SettingsAppsStartup honesty soft leftover-attaches wn.27"
grep -Fq 'windows-native.27 stays prototype/pending' "$settings_startup" ||
  fail "SettingsAppsStartup honesty keeps wn.27 prototype/pending"

if grep -Eqi 'claim=present' "$settings_model" && ! grep -Eqi 'not claim=present|Never claim=present|never claim=present' "$settings_model"; then
  fail "Apps must not invent claim=present"
fi
if grep -Eqi 'Settings Power LIVE' "$settings_model"; then
  fail "Apps must not invent Settings Power LIVE"
fi
if grep -Eqi 'Empty Bin LIVE' "$settings_model"; then
  fail "Apps must not invent Empty Bin LIVE"
fi
if grep -Eqi 'End Task LIVE' "$settings_model"; then
  fail "Apps must not invent End Task LIVE"
fi
if grep -Eqi 'Win7 visual closed|Win7 visual leftover CLOSED' "$settings_model"; then
  fail "Apps must not invent Win7 visual closed"
fi
if grep -Eqi 'phase 5' "$settings_model"; then
  fail "Apps must not invent a Phase 5 fence"
fi

pass "Settings Apps hosts tip-true setEnabled startup plane without invent"

python3 - "$catalog" "$jobs" "$gaps" "$parity" "$handoff" "$project" "$settings_api" "$acc" "$settings_model" "$settings_startup" "$session_startup" <<'PY'
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
settings_startup = open(sys.argv[10], encoding="utf-8").read()
session_startup = open(sys.argv[11], encoding="utf-8").read()

by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
startup = by_id["apps.startup.disable"]
route = startup["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"apps.startup.disable route is {route}")
if route.get("path") != "Settings > Apps":
    raise SystemExit(f"apps.startup.disable path is {route}")
if route.get("label") != "Disable startup application":
    raise SystemExit(f"apps.startup.disable label is {route}")
if startup.get("availability", {}).get("claim") == "present":
    raise SystemExit("apps.startup.disable must not claim present")
if startup.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"apps.startup.disable claim is {startup.get('availability')}")
if startup.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"apps.startup.disable human is {startup.get('availability')}")
if startup.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"apps.startup.disable agent is {startup.get('availability')}")
if startup.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"apps.startup.disable provider state is {startup.get('provider')}")
if startup.get("provider", {}).get("id") != "apps.provider":
    raise SystemExit(f"apps.startup.disable provider is {startup.get('provider')}")
if startup.get("source", {}).get("file") != "shell/apps/shared/SettingsSessionStartup.qml":
    raise SystemExit(f"apps.startup.disable source is {startup.get('source')}")
if startup.get("source", {}).get("symbol") != "setEnabled":
    raise SystemExit(f"apps.startup.disable source symbol is {startup.get('source')}")
if "SettingsAppsStartup.qml" in str(startup.get("source", {}).get("file") or ""):
    raise SystemExit("apps.startup.disable must not invent source on SettingsAppsStartup.qml")
recovery = startup.get("recovery") or {}
if recovery.get("mode") != "undo":
    raise SystemExit(f"apps.startup.disable recovery mode is {recovery}")
if recovery.get("stateFingerprintRequired") is not False:
    raise SystemExit(f"apps.startup.disable recovery fingerprint invent: {recovery}")
exp = recovery.get("expectation") or ""
for needle in (
    "setEnabled",
    "apps-startup-set",
    "autostart",
    "no Fabric durable undo fingerprint invent",
):
    if needle not in exp:
        raise SystemExit(f"apps.startup.disable recovery missing {needle!r}: {exp}")

by_job = {job["id"]: job for job in jobs["jobs"]}
native27 = by_job["windows-native.27"]
if native27.get("claim") == "present":
    raise SystemExit("windows-native.27 must not claim present")
if native27.get("claim") != "prototype":
    raise SystemExit(f"windows-native.27 claim is {native27.get('claim')}")
if native27.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.27 sourceStatus is {native27.get('sourceStatus')}")
if native27.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.27 proofStatus is {native27.get('proofStatus')}")
if native27.get("capabilityIds") != ["apps.startup.disable"]:
    raise SystemExit(f"windows-native.27 capabilityIds are {native27.get('capabilityIds')}")
if native27.get("humanRoute", {}).get("path") != "Settings > Apps":
    raise SystemExit(f"windows-native.27 path is {native27.get('humanRoute')}")
if native27.get("humanRoute", {}).get("status") != "visible":
    raise SystemExit(f"windows-native.27 route is {native27.get('humanRoute')}")
if native27.get("humanRoute", {}).get("surface") != "Settings":
    raise SystemExit(f"windows-native.27 surface is {native27.get('humanRoute')}")
if "Task Manager" in str(native27["humanRoute"].get("surface") or "") or "Task Manager" in str(native27["humanRoute"].get("path") or ""):
    raise SystemExit(f"windows-native.27 invents a Task Manager Startup page: {native27['humanRoute']}")
rec27 = native27.get("recoveryExpectation") or ""
for needle in ("setEnabled", "apps-startup-set", "autostart"):
    if needle not in rec27:
        raise SystemExit(f"windows-native.27 recovery missing {needle!r}")
if "Restore the previous startup state" in rec27:
    raise SystemExit("windows-native.27 recovery still invents Restore the previous startup state")

parity_task = by_job["parity.task-manager"]
if parity_task.get("claim") == "present":
    raise SystemExit("parity.task-manager must not claim present")
if "apps.startup.disable" in (parity_task.get("capabilityIds") or []):
    raise SystemExit("parity.task-manager still claims apps.startup.disable")

if "| 27 | Disable a startup application | pending |" not in acc:
    raise SystemExit("WINDOWS_NATIVE_ACCEPTANCE must keep wn.27 pending")

required_gaps = [
    "Honesty addendum 2026-09-06 vs Settings Apps startup disable leftover plane (windows-native.27)",
    "| `windows-native.27` | prototype/pending | visible: Settings > Apps |",
    "setEnabled",
    "apps-startup-set",
    "apps.startup.disable",
    "not product CLOSED",
    "not metal CLOSED",
    "not claim=present",
    "Do not invent Task Manager present",
    "Do not invent Settings Power LIVE",
    "Do not invent Empty Bin LIVE",
    "Do not invent End Task LIVE",
    "claims: missing=29, partial=6, plumbing=4, present=0, prototype=43",
]
for needle in required_gaps:
    if needle not in gaps:
        raise SystemExit(f"fleet-doctrine-gaps missing {needle!r}")
if "CLOSED leftover: Settings Apps startup disable UI" in gaps.split(
    "Honesty addendum 2026-09-06 vs Settings Apps startup disable leftover plane (windows-native.27)", 1
)[1].split("Honesty addendum", 1)[0]:
    raise SystemExit("fleet-doctrine-gaps invents CLOSED leftover for soft leftover-attach ACC wn.27")
if "windows-native.27 stays prototype/pending" not in gaps.replace("`", ""):
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.27 prototype/pending")

required_handoff = [
    "Honesty addendum 2026-09-06 vs Settings Apps startup disable leftover plane (windows-native.27)",
    "Settings > Apps",
    "apps.startup.disable",
    "setEnabled",
    "apps-startup-set",
    "not claim=present",
]
for needle in required_handoff:
    if needle not in handoff:
        raise SystemExit(f"HANDOFF_WRITERS missing {needle!r}")
if "windows-native.27 stays prototype/pending" not in handoff.replace("`", ""):
    raise SystemExit("HANDOFF_WRITERS must keep windows-native.27 prototype/pending")

if "soft leftover-attaches `windows-native.27`" not in parity and "soft leftover-attaches windows-native.27" not in parity:
    raise SystemExit("PARITY must soft leftover-attach wn.27")
if 'Forty-task "Disable a startup application" stays pending' not in parity and "Forty-task \"Disable a startup application\" stays pending" not in parity:
    raise SystemExit("PARITY must keep forty-task Disable a startup application pending")
if "setEnabled" not in parity or "apps-startup-set" not in parity:
    raise SystemExit("PARITY must name tip-true setEnabled → apps-startup-set")

if "windows-native.27" not in project:
    raise SystemExit("project-ultimate must keep windows-native.27")
if "setEnabled" not in project or "apps-startup-set" not in project:
    raise SystemExit("project-ultimate must name tip-true setEnabled → apps-startup-set plane")

if "windows-native.27" not in settings_api:
    raise SystemExit("settings-service-api must keep windows-native.27")
if "prototype/pending" not in settings_api:
    raise SystemExit("settings-service-api must keep windows-native.27 prototype/pending")
if "setEnabled" not in settings_api and "apps-startup-set" not in settings_api:
    raise SystemExit("settings-service-api must name tip-true startup plane")

if "function setEnabled(" not in session_startup:
    raise SystemExit("SettingsSessionStartup must host setEnabled")
if "apps-startup-set" not in session_startup:
    raise SystemExit("SettingsSessionStartup must call apps-startup-set")
if "sessionHost.setEnabled" not in settings_startup:
    raise SystemExit("SettingsAppsStartup must route through setEnabled")
if "soft leftover-attaches windows-native.27" not in settings_model:
    raise SystemExit("SettingsModel must soft leftover-attach wn.27")
if "windows-native.27 stays prototype/pending" not in settings_model:
    raise SystemExit("SettingsModel must keep wn.27 prototype/pending")
PY

pass "apps.startup.disable stays partial with visible Settings > Apps soft leftover-attached to wn.27"
