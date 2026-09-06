#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

settings_app="$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml"
settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
settings_card="$ROOT/shell/apps/ultimate-settings/SettingsUpdateHistory.qml"
settings_session="$ROOT/shell/apps/shared/SettingsSessionUpdate.qml"
settings_apply="$ROOT/shell/apps/ultimate-settings/SettingsUpdateApply.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
project="$ROOT/plans/project-ultimate.md"
controlpanel="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-catalog-controlpanel.md"
settings_api="$ROOT/docs/settings-service-api.md"
acc="$ROOT/WINDOWS_NATIVE_ACCEPTANCE.md"

[[ -f $settings_app ]] || fail "Settings application exists"
[[ -f $settings_model ]] || fail "Settings model exists"
[[ -f $settings_card ]] || fail "Settings Update history card exists"
[[ -f $settings_session ]] || fail "Settings session update plane exists"

grep -Fq 'SettingsComponents.SettingsUpdateHistory' "$settings_app" ||
  fail "Settings Update hosts the session history card"
grep -Fq 'function readHistory(' "$settings_session" || fail "session update QML exposes readHistory"
grep -Fq 'system-update-history' "$settings_session" || fail "session update QML calls system-update-history"
grep -Fq 'function refreshHistory(' "$settings_card" || fail "Update history card chrome exposes refreshHistory"
if grep -Fq 'function readHistory(' "$settings_card"; then
  fail "Update history card must not invent a local readHistory"
fi
grep -Fq 'windows-native.29 stays prototype/pending' "$settings_card" ||
  fail "Update history honesty keeps windows-native.29 prototype/pending"
grep -Fq 'windows-native.29 stays prototype/pending' "$settings_model" ||
  fail "Settings coverage keeps windows-native.29 prototype/pending"
grep -Fq 'not product CLOSED' "$settings_card" || fail "Update history honesty refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$settings_card" || fail "Update history honesty refuses metal CLOSED"
grep -Fq 'not claim=present' "$settings_card" || fail "Update history honesty refuses claim=present"
grep -Fq 'soft leftover-attaches windows-native.29' "$settings_card" ||
  fail "Update history honesty soft leftover-attaches wn.29"
grep -Fq 'SettingsSessionUpdate.readHistory' "$settings_model" ||
  fail "Settings coverage names tip-true readHistory path"

if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$settings_session" "$settings_card"; then
  fail "Settings Update history must not mint Fabric durable operations"
fi
if grep -Eq 'pkexec|sudo|/usr/bin/pacman|omarchy-update-confirm' "$settings_session" "$settings_card"; then
  fail "Settings Update history QML must not spawn privileged or interactive update argv"
fi
if grep -Eqi 'claim=present' "$settings_card" && ! grep -Eqi 'not claim=present|Never claim=present|never claim=present' "$settings_card"; then
  fail "Update history must not invent claim=present"
fi
if grep -Eqi 'Update Center present|Update is present as product|claim=present Update' "$settings_card" "$settings_model"; then
  fail "Update history must not invent Update Center / present"
fi
if grep -Eqi 'Settings Power LIVE' "$settings_card"; then
  fail "Update history must not invent Settings Power LIVE"
fi
if grep -Eqi 'Empty Bin LIVE' "$settings_card"; then
  fail "Update history must not invent Empty Bin LIVE"
fi
if grep -Eqi 'Win7 visual closed|Win7 visual leftover CLOSED' "$settings_card"; then
  fail "Update history must not invent Win7 visual closed"
fi

pass "Settings Update history hosts tip-true session readHistory plane without invent"

python3 - "$catalog" "$jobs" "$gaps" "$parity" "$handoff" "$project" "$controlpanel" "$settings_api" "$acc" "$settings_app" "$settings_model" "$settings_card" "$settings_session" "$settings_apply" <<'PY'
import json
import sys

catalog = json.loads(open(sys.argv[1], encoding="utf-8").read())
jobs = json.loads(open(sys.argv[2], encoding="utf-8").read())
gaps = open(sys.argv[3], encoding="utf-8").read()
parity = open(sys.argv[4], encoding="utf-8").read()
handoff = open(sys.argv[5], encoding="utf-8").read()
project = open(sys.argv[6], encoding="utf-8").read()
controlpanel = open(sys.argv[7], encoding="utf-8").read()
settings_api = open(sys.argv[8], encoding="utf-8").read()
acc = open(sys.argv[9], encoding="utf-8").read()
settings_app = open(sys.argv[10], encoding="utf-8").read()
settings_model = open(sys.argv[11], encoding="utf-8").read()
settings_card = open(sys.argv[12], encoding="utf-8").read()
settings_session = open(sys.argv[13], encoding="utf-8").read()
settings_apply = open(sys.argv[14], encoding="utf-8").read()

by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
history = by_id["update.history.read"]
route = history["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"update.history.read route is {route}")
if route.get("path") not in {"Settings > Update", "Start > Settings > Update"}:
    raise SystemExit(f"update.history.read path is {route}")
if route.get("label") != "Update history":
    raise SystemExit(f"update.history.read label is {route}")
if history.get("availability", {}).get("claim") == "present":
    raise SystemExit("update.history.read must not claim present")
if history.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"update.history.read claim is {history.get('availability')}")
if history.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"update.history.read human is {history.get('availability')}")
if history.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"update.history.read agent is {history.get('availability')}")
if history.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"update.history.read provider state is {history.get('provider')}")
if history.get("provider", {}).get("id") != "update.provider":
    raise SystemExit(f"update.history.read provider is {history.get('provider')}")
if history.get("source", {}).get("file") != "shell/apps/shared/SettingsSessionUpdate.qml":
    raise SystemExit(f"update.history.read source is {history.get('source')}")
if history.get("source", {}).get("symbol") != "readHistory":
    raise SystemExit(f"update.history.read source symbol is {history.get('source')}")
if "SettingsUpdateHistory.qml" in str(history.get("source", {}).get("file") or ""):
    raise SystemExit("update.history.read must not invent source on SettingsUpdateHistory.qml")

install = by_id["update.install"]
if install.get("availability", {}).get("claim") == "present":
    raise SystemExit("update.install must not claim present")

by_job = {job["id"]: job for job in jobs["jobs"]}
native29 = by_job["windows-native.29"]
if native29.get("claim") == "present":
    raise SystemExit("windows-native.29 must not claim present")
if native29.get("claim") != "prototype":
    raise SystemExit(f"windows-native.29 claim is {native29.get('claim')}")
if native29.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.29 sourceStatus is {native29.get('sourceStatus')}")
if native29.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.29 proofStatus is {native29.get('proofStatus')}")
if native29.get("capabilityIds") != ["update.history.read"]:
    raise SystemExit(f"windows-native.29 capabilityIds are {native29.get('capabilityIds')}")
if native29.get("humanRoute", {}).get("path") != "Settings > Update":
    raise SystemExit(f"windows-native.29 path is {native29.get('humanRoute')}")
if native29.get("humanRoute", {}).get("status") != "visible":
    raise SystemExit(f"windows-native.29 route is {native29.get('humanRoute')}")

native28 = by_job["windows-native.28"]
if native28.get("claim") == "present":
    raise SystemExit("windows-native.28 must not claim present")
if native28.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.28 sourceStatus is {native28.get('sourceStatus')}")

parity_update = by_job["parity.update"]
if parity_update.get("claim") == "present":
    raise SystemExit("parity.update must not claim present")
if parity_update.get("claim") != "prototype":
    raise SystemExit(f"parity.update claim is {parity_update.get('claim')}")
if "update.history.read" not in (parity_update.get("capabilityIds") or []):
    raise SystemExit("parity.update must name update.history.read")

if "| 29 | Inspect update history | pending |" not in acc:
    raise SystemExit("WINDOWS_NATIVE_ACCEPTANCE must keep wn.29 pending")

required_gaps = [
    "Honesty addendum 2026-09-06 vs Settings Update history leftover plane (windows-native.29)",
    "| `windows-native.29` | prototype/pending | visible: Settings > Update |",
    "SettingsSessionUpdate.qml",
    "readHistory",
    "update.history.read",
    "Soft leftover-attach: Settings > Update history exists",
    "not product CLOSED",
    "not metal CLOSED",
    "not claim=present",
    "Do not invent Settings Power LIVE",
    "Do not invent Empty Bin LIVE",
]
for needle in required_gaps:
    if needle not in gaps:
        raise SystemExit(f"fleet-doctrine-gaps missing {needle!r}")
if "windows-native.29 stays prototype/pending" not in gaps.replace("`", ""):
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.29 prototype/pending")
if "claims: missing=30, partial=6, plumbing=4, present=0, prototype=42" not in gaps:
    raise SystemExit("fleet-doctrine-gaps job header must match jobs.json claims after wn.29 soft leftover-attach")

required_handoff = [
    "Honesty addendum 2026-09-06 vs Settings Update history leftover plane (windows-native.29)",
    "Settings > Update",
    "update.history.read",
    "not claim=present",
]
for needle in required_handoff:
    if needle not in handoff:
        raise SystemExit(f"HANDOFF_WRITERS missing {needle!r}")
if "windows-native.29 stays prototype/pending" not in handoff.replace("`", ""):
    raise SystemExit("HANDOFF_WRITERS must keep windows-native.29 prototype/pending")

if "soft leftover-attaches `windows-native.29`" not in parity and "soft leftover-attaches windows-native.29" not in parity:
    raise SystemExit("PARITY must soft leftover-attach wn.29")
if "Forty-task \"Inspect update history\" stays pending" not in parity and 'Forty-task "Inspect update history" stays pending' not in parity:
    raise SystemExit("PARITY must keep forty-task Inspect update history pending")

if "windows-native.29" not in project:
    raise SystemExit("project-ultimate must keep windows-native.29")
if "Settings > Update" not in project and "system-update-history" not in project:
    raise SystemExit("project-ultimate must name Update history plane")

if "windows-native.29" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must keep windows-native.29")
if "readHistory" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must name readHistory")

if "windows-native.29" not in settings_api:
    raise SystemExit("settings-service-api must name windows-native.29 leftover-attach")
if "system-update-history" not in settings_api and "readHistory" not in settings_api:
    raise SystemExit("settings-service-api must name history plane")

if "SettingsComponents.SettingsUpdateHistory" not in settings_app:
    raise SystemExit("SettingsApplication must keep SettingsUpdateHistory host")
if "function readHistory(" not in settings_session:
    raise SystemExit("SettingsSessionUpdate must keep readHistory")
if "soft leftover-attaches windows-native.29" not in settings_card:
    raise SystemExit("SettingsUpdateHistory must soft leftover-attach wn.29")
if "windows-native.29 stays prototype/pending" not in settings_model:
    raise SystemExit("SettingsModel must keep wn.29 prototype/pending")
if "Restart and reboot writers" not in settings_apply and "Restart and reboot writers stay unavailable" not in settings_apply:
    raise SystemExit("SettingsUpdateApply must keep restart/reboot writers unavailable")
PY

pass "update.history.read stays partial with visible Settings > Update soft leftover-attached to wn.29"
