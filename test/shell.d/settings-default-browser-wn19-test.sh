#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

settings_app="$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml"
settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
project="$ROOT/plans/project-ultimate.md"
controlpanel="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-catalog-controlpanel.md"
settings_api="$ROOT/docs/settings-service-api.md"
defaults_docs="$ROOT/docs/files-defaults-provider.md"
acc="$ROOT/WINDOWS_NATIVE_ACCEPTANCE.md"

[[ -f $settings_app ]] || fail "Settings application exists"
[[ -f $settings_model ]] || fail "Settings model exists"

grep -Fq 'function applyDefaultBrowser(' "$settings_app" || fail "Settings hosts applyDefaultBrowser"
grep -Fq 'action: "protocol.set"' "$settings_app" || fail "Settings uses typed protocol.set"
grep -Fq 'provider: "defaults.provider"' "$settings_app" || fail "Settings uses defaults.provider"
grep -Fq 'BROWSER_SCHEMES' "$settings_model" || fail "Settings model names BROWSER_SCHEMES"
grep -Fq 'settings.apps.default-programs' "$settings_model" || fail "Settings model hosts Default Programs route"
grep -Fq 'http' "$settings_model" || fail "Settings model covers http"
grep -Fq 'https' "$settings_model" || fail "Settings model covers https"
grep -Fq 'windows-native.19 stays prototype/pending' "$settings_app" ||
  fail "Default Programs honesty keeps windows-native.19 prototype/pending"
grep -Fq 'windows-native.19 stays prototype/pending' "$settings_model" ||
  fail "Settings coverage keeps windows-native.19 prototype/pending"
grep -Fq 'not product CLOSED' "$settings_app" || fail "Default Programs honesty refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$settings_app" || fail "Default Programs honesty refuses metal CLOSED"
grep -Fq 'not claim=present' "$settings_app" || fail "Default Programs honesty refuses claim=present"
grep -Fq 'soft leftover-attaches windows-native.19' "$settings_app" ||
  fail "Default Programs honesty soft leftover-attaches wn.19"
grep -Fq 'AutoPlay' "$settings_app" || fail "Default Programs honesty keeps AutoPlay unavailable"
grep -Fq 'files.associations.set' "$settings_app" || fail "Default Programs honesty keeps files.associations.set unavailable"
grep -Fq 'Set Program Access and Computer Defaults' "$settings_app" || fail "Default Programs honesty keeps SPAC unavailable"

if grep -Eqi 'claim=present' "$settings_app" && ! grep -Eqi 'not claim=present|Never claim=present|never claim=present' "$settings_app"; then
  fail "Default Programs must not invent claim=present"
fi
if grep -Eqi 'Default Programs product-complete|Win7 Default Programs applet present|full Default Programs LIVE' "$settings_app" "$settings_model"; then
  fail "Default Programs must not invent product-complete / present applet"
fi
if grep -Eqi 'Settings Power LIVE' "$settings_app"; then
  fail "Default Programs must not invent Settings Power LIVE"
fi
if grep -Eqi 'Empty Bin LIVE' "$settings_app"; then
  fail "Default Programs must not invent Empty Bin LIVE"
fi
if grep -Eqi 'AutoPlay LIVE CONTROL|SPAC LIVE CONTROL|files\.associations\.set claim=present' "$settings_app" "$settings_model"; then
  fail "Default Programs must not invent AutoPlay/SPAC/files.associations.set product-complete"
fi
if grep -Eqi 'files\.associations\.set product-complete' "$settings_app" "$settings_model" | grep -Eiv 'not invent|Do not invent|stay unavailable|remain unavailable'; then
  fail "Default Programs must not invent files.associations.set product-complete"
fi

pass "Settings Default Programs hosts tip-true protocol.set browser plane without invent"

python3 - "$catalog" "$jobs" "$gaps" "$parity" "$handoff" "$project" "$controlpanel" "$settings_api" "$defaults_docs" "$acc" "$settings_app" "$settings_model" <<'PY'
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
defaults_docs = open(sys.argv[9], encoding="utf-8").read()
acc = open(sys.argv[10], encoding="utf-8").read()
settings_app = open(sys.argv[11], encoding="utf-8").read()
settings_model = open(sys.argv[12], encoding="utf-8").read()

by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
protocol = by_id["defaults.protocol.set"]
route = protocol["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"defaults.protocol.set route is {route}")
if route.get("path") != "Settings > Default Programs":
    raise SystemExit(f"defaults.protocol.set path is {route}")
if protocol.get("availability", {}).get("claim") == "present":
    raise SystemExit("defaults.protocol.set must not claim present")
if protocol.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"defaults.protocol.set claim is {protocol.get('availability')}")
if protocol.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"defaults.protocol.set human is {protocol.get('availability')}")
if protocol.get("provider", {}).get("id") != "defaults.provider":
    raise SystemExit(f"defaults.protocol.set provider is {protocol.get('provider')}")
if protocol.get("provider", {}).get("state") != "present":
    raise SystemExit(f"defaults.protocol.set provider state is {protocol.get('provider')}")
if protocol.get("source", {}).get("file") != "shell/apps/ultimate-settings/SettingsApplication.qml":
    raise SystemExit(f"defaults.protocol.set source is {protocol.get('source')}")
if protocol.get("source", {}).get("symbol") != "applyDefaultBrowser":
    raise SystemExit(f"defaults.protocol.set source symbol is {protocol.get('source')}")

mime = by_id["defaults.mime.set"]
if mime.get("availability", {}).get("claim") == "present":
    raise SystemExit("defaults.mime.set must not claim present")
if mime["humanRoute"].get("path") != "Settings > Default Programs":
    raise SystemExit(f"defaults.mime.set path drifted: {mime.get('humanRoute')}")

assoc = by_id["files.associations.set"]
if assoc.get("availability", {}).get("claim") == "present":
    raise SystemExit("files.associations.set must not claim present")

by_job = {job["id"]: job for job in jobs["jobs"]}
native19 = by_job["windows-native.19"]
if native19.get("claim") == "present":
    raise SystemExit("windows-native.19 must not claim present")
if native19.get("claim") != "prototype":
    raise SystemExit(f"windows-native.19 claim is {native19.get('claim')}")
if native19.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.19 sourceStatus is {native19.get('sourceStatus')}")
if native19.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.19 proofStatus is {native19.get('proofStatus')}")
if native19.get("capabilityIds") != ["defaults.protocol.set"]:
    raise SystemExit(f"windows-native.19 capabilityIds are {native19.get('capabilityIds')}")
if native19.get("humanRoute", {}).get("path") != "Settings > Default Programs":
    raise SystemExit(f"windows-native.19 path is {native19.get('humanRoute')}")
if native19.get("humanRoute", {}).get("status") != "visible":
    raise SystemExit(f"windows-native.19 route is {native19.get('humanRoute')}")

parity_defaults = by_job["parity.default-programs"]
if parity_defaults.get("claim") == "present":
    raise SystemExit("parity.default-programs must not claim present")
if parity_defaults.get("claim") != "prototype":
    raise SystemExit(f"parity.default-programs claim is {parity_defaults.get('claim')}")
if parity_defaults.get("humanRoute", {}).get("path") != "Settings > Default Programs":
    raise SystemExit(f"parity.default-programs path is {parity_defaults.get('humanRoute')}")
if "defaults.protocol.set" not in (parity_defaults.get("capabilityIds") or []):
    raise SystemExit("parity.default-programs must name defaults.protocol.set")

if "| 19 | Change the default browser | pending |" not in acc:
    raise SystemExit("WINDOWS_NATIVE_ACCEPTANCE must keep wn.19 pending")

required_gaps = [
    "Honesty addendum 2026-09-06 vs Settings Default Programs browser leftover plane (windows-native.19)",
    "| `windows-native.19` | prototype/pending | visible: Settings > Default Programs |",
    "applyDefaultBrowser",
    "defaults.protocol.set",
    "not product CLOSED",
    "not metal CLOSED",
    "not claim=present",
    "AutoPlay",
    "files.associations.set",
]
for needle in required_gaps:
    if needle not in gaps:
        raise SystemExit(f"fleet-doctrine-gaps missing {needle!r}")
if "| `windows-native.19` | prototype/pending | visible: Settings > Apps |" in gaps:
    raise SystemExit("fleet-doctrine-gaps still points wn.19 at Settings > Apps")
if "claim=present" in gaps and "never claim=present" not in gaps and "not claim=present" not in gaps:
    raise SystemExit("gaps invent claim=present without refuse")

required_handoff = [
    "Honesty addendum 2026-09-06 vs Settings Default Programs browser leftover plane (windows-native.19)",
    "Settings > Default Programs",
    "defaults.protocol.set",
    "not claim=present",
]
for needle in required_handoff:
    if needle not in handoff:
        raise SystemExit(f"HANDOFF_WRITERS missing {needle!r}")
if "windows-native.19 stays prototype/pending" not in handoff.replace("`", ""):
    raise SystemExit("HANDOFF_WRITERS must keep windows-native.19 prototype/pending")

if "soft leftover-attaches `windows-native.19`" not in parity and "soft leftover-attaches windows-native.19" not in parity:
    raise SystemExit("PARITY must soft leftover-attach wn.19")
if "Forty-task \"Change the default browser\" stays pending" not in parity:
    raise SystemExit("PARITY must keep forty-task browser pending")

if "windows-native.19" not in project:
    raise SystemExit("project-ultimate must keep windows-native.19")
if "Settings > Default Programs" not in project:
    raise SystemExit("project-ultimate must name Settings > Default Programs for browser")

if "Settings → Default Programs" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must retarget Default Programs surface")
if "windows-native.19" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must keep windows-native.19")
if "applyDefaultBrowser" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must name applyDefaultBrowser")

if "windows-native.19" not in settings_api:
    raise SystemExit("settings-service-api must name windows-native.19 leftover-attach")
if "defaults.protocol.set" not in settings_api and "protocol.set" not in settings_api:
    raise SystemExit("settings-service-api must name protocol.set browser plane")

if "windows-native.19" not in defaults_docs:
    raise SystemExit("files-defaults-provider must name windows-native.19 leftover-attach")
if "Settings > Default Programs" not in defaults_docs:
    raise SystemExit("files-defaults-provider must name Settings > Default Programs")

if "function applyDefaultBrowser(" not in settings_app:
    raise SystemExit("SettingsApplication must keep applyDefaultBrowser")
if 'action: "protocol.set"' not in settings_app:
    raise SystemExit("SettingsApplication must keep protocol.set action")
if "soft leftover-attaches windows-native.19" not in settings_app:
    raise SystemExit("SettingsApplication must soft leftover-attach wn.19")
if "windows-native.19 stays prototype/pending" not in settings_model:
    raise SystemExit("SettingsModel must keep wn.19 prototype/pending")
if "AutoPlay" not in settings_model or "files.associations.set" not in settings_model:
    raise SystemExit("SettingsModel must refuse AutoPlay / files.associations.set invent")
PY

pass "defaults.protocol.set stays partial with visible Settings > Default Programs soft leftover-attached to wn.19"
