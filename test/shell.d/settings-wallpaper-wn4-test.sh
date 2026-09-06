#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
settings_host="$ROOT/shell/Ui/SettingsPersonalizationHost.qml"
image_picker="$ROOT/shell/plugins/image-picker/ImagePicker.qml"
theme_bg_set="$ROOT/bin/omarchy-theme-bg-set"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
project="$ROOT/plans/project-ultimate.md"
controlpanel="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-catalog-controlpanel.md"
settings_api="$ROOT/docs/settings-service-api.md"
acc="$ROOT/WINDOWS_NATIVE_ACCEPTANCE.md"

[[ -f $settings_model ]] || fail "Settings model exists"
[[ -f $settings_host ]] || fail "Settings Personalization host exists"
[[ -f $image_picker ]] || fail "ImagePicker exists"
[[ -f $theme_bg_set ]] || fail "omarchy-theme-bg-set exists"

grep -Fq 'settings.personalization.overview' "$settings_model" || fail "Settings model hosts Personalization route"
grep -Fq 'Ui/SettingsPersonalizationHost.qml' "$settings_model" || fail "Settings model hosts Personalization host"
grep -Fq 'omarchy.image-picker' "$settings_model" || fail "Settings model names omarchy.image-picker"
grep -Fq 'embedApplyKind: "wallpaper"' "$settings_host" || fail "Personalization host embeds wallpaper picker"
grep -Fq 'function applyEmbedded(' "$image_picker" || fail "ImagePicker exposes applyEmbedded"
grep -Fq 'omarchy-theme-bg-set' "$image_picker" || fail "ImagePicker applyEmbedded calls omarchy-theme-bg-set"
grep -Fq 'omarchy-shell -q background set' "$theme_bg_set" || fail "omarchy-theme-bg-set applies background"

grep -Fq 'windows-native.4 stays prototype/pending' "$settings_model" ||
  fail "Personalization honesty keeps windows-native.4 prototype/pending"
grep -Fq 'not product CLOSED' "$settings_model" || fail "Personalization honesty refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$settings_model" || fail "Personalization honesty refuses metal CLOSED"
grep -Fq 'not claim=present' "$settings_model" || fail "Personalization honesty refuses claim=present"
grep -Fq 'soft leftover-attaches windows-native.4' "$settings_model" ||
  fail "Personalization honesty soft leftover-attaches wn.4"
grep -Fq 'ImagePicker.applyEmbedded' "$settings_model" || fail "Personalization coverage names tip-true applyEmbedded"
grep -Fq 'omarchy-theme-bg-set' "$settings_model" || fail "Personalization coverage names omarchy-theme-bg-set"
grep -Fq 'No code-owned personalization.provider is registered' "$settings_model" ||
  fail "Personalization coverage keeps typed provider refuse"
grep -Fq 'remain unavailable' "$settings_model" || fail "Personalization coverage keeps density/cursor/motion refuse"

if grep -Eqi 'claim=present' "$settings_model" && ! grep -Eqi 'not claim=present|Never claim=present|never claim=present' "$settings_model"; then
  fail "Personalization must not invent claim=present"
fi
if grep -Eqi 'wallpaper product-complete|Win7 Personalization present|claim=present wallpaper' "$settings_model"; then
  fail "Personalization must not invent wallpaper product-complete / present"
fi
if grep -Eqi 'Settings Power LIVE' "$settings_model"; then
  fail "Personalization must not invent Settings Power LIVE"
fi
if grep -Eqi 'Empty Bin LIVE' "$settings_model"; then
  fail "Personalization must not invent Empty Bin LIVE"
fi
if grep -Eqi 'Win7 visual closed|Win7 visual leftover CLOSED' "$settings_model"; then
  fail "Personalization must not invent Win7 visual closed"
fi
if grep -Eqi 'phase 5' "$settings_model"; then
  fail "Personalization must not invent a Phase 5 fence"
fi

pass "Settings Personalization hosts tip-true wallpaper applyEmbedded plane without invent"

python3 - "$catalog" "$jobs" "$gaps" "$parity" "$handoff" "$project" "$controlpanel" "$settings_api" "$acc" "$settings_model" "$settings_host" "$image_picker" "$theme_bg_set" <<'PY'
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
settings_model = open(sys.argv[10], encoding="utf-8").read()
settings_host = open(sys.argv[11], encoding="utf-8").read()
image_picker = open(sys.argv[12], encoding="utf-8").read()
theme_bg_set = open(sys.argv[13], encoding="utf-8").read()

by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
wallpaper = by_id["desktop.wallpaper.set"]
route = wallpaper["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"desktop.wallpaper.set route is {route}")
if route.get("path") not in {"Settings > Personalization", "Start > Settings > Personalization"}:
    raise SystemExit(f"desktop.wallpaper.set path is {route}")
if wallpaper.get("availability", {}).get("claim") == "present":
    raise SystemExit("desktop.wallpaper.set must not claim present")
if wallpaper.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"desktop.wallpaper.set claim is {wallpaper.get('availability')}")
if wallpaper.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"desktop.wallpaper.set human is {wallpaper.get('availability')}")
if wallpaper.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"desktop.wallpaper.set agent is {wallpaper.get('availability')}")
if wallpaper.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"desktop.wallpaper.set provider state is {wallpaper.get('provider')}")
if wallpaper.get("provider", {}).get("id") != "desktop.provider":
    raise SystemExit(f"desktop.wallpaper.set provider is {wallpaper.get('provider')}")
if wallpaper.get("source", {}).get("file") != "shell/plugins/image-picker/ImagePicker.qml":
    raise SystemExit(f"desktop.wallpaper.set source is {wallpaper.get('source')}")
if wallpaper.get("source", {}).get("symbol") != "applyEmbedded":
    raise SystemExit(f"desktop.wallpaper.set source symbol is {wallpaper.get('source')}")

theme = by_id["personalization.theme.set"]
if theme.get("availability", {}).get("claim") == "present":
    raise SystemExit("personalization.theme.set must not claim present")

by_job = {job["id"]: job for job in jobs["jobs"]}
native4 = by_job["windows-native.4"]
if native4.get("claim") == "present":
    raise SystemExit("windows-native.4 must not claim present")
if native4.get("claim") != "prototype":
    raise SystemExit(f"windows-native.4 claim is {native4.get('claim')}")
if native4.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.4 sourceStatus is {native4.get('sourceStatus')}")
if native4.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.4 proofStatus is {native4.get('proofStatus')}")
if native4.get("capabilityIds") != ["desktop.wallpaper.set"]:
    raise SystemExit(f"windows-native.4 capabilityIds are {native4.get('capabilityIds')}")
if native4.get("humanRoute", {}).get("path") != "Settings > Personalization":
    raise SystemExit(f"windows-native.4 path is {native4.get('humanRoute')}")
if native4.get("humanRoute", {}).get("status") != "visible":
    raise SystemExit(f"windows-native.4 route is {native4.get('humanRoute')}")
if native4.get("humanRoute", {}).get("surface") != "Settings":
    raise SystemExit(f"windows-native.4 surface is {native4.get('humanRoute')}")

parity_person = by_job["parity.personalization"]
if parity_person.get("claim") == "present":
    raise SystemExit("parity.personalization must not claim present")
if parity_person.get("claim") != "prototype":
    raise SystemExit(f"parity.personalization claim is {parity_person.get('claim')}")
if "desktop.wallpaper.set" not in (parity_person.get("capabilityIds") or []):
    raise SystemExit("parity.personalization must name desktop.wallpaper.set")

if "| 4 | Change the wallpaper | pending |" not in acc:
    raise SystemExit("WINDOWS_NATIVE_ACCEPTANCE must keep wn.4 pending")

required_gaps = [
    "Honesty addendum 2026-09-06 vs Settings Personalization wallpaper leftover plane (windows-native.4)",
    "| `windows-native.4` | prototype/pending | visible: Settings > Personalization |",
    "applyEmbedded",
    "omarchy-theme-bg-set",
    "desktop.wallpaper.set",
    "not product CLOSED",
    "not metal CLOSED",
    "not claim=present",
    "Do not invent Settings Power LIVE",
    "Do not invent Empty Bin LIVE",
]
for needle in required_gaps:
    if needle not in gaps:
        raise SystemExit(f"fleet-doctrine-gaps missing {needle!r}")
if "| `windows-native.4` | prototype/pending | visible: Personalization > Background |" in gaps:
    raise SystemExit("fleet-doctrine-gaps still points wn.4 at Personalization > Background")
if "windows-native.4 stays prototype/pending" not in gaps.replace("`", ""):
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.4 prototype/pending")
if "claims: missing=30, partial=6, plumbing=4, present=0, prototype=42" not in gaps:
    raise SystemExit("fleet-doctrine-gaps job header must match jobs.json claims after wn.4 soft leftover-attach")

required_handoff = [
    "Honesty addendum 2026-09-06 vs Settings Personalization wallpaper leftover plane (windows-native.4)",
    "Settings > Personalization",
    "desktop.wallpaper.set",
    "not claim=present",
]
for needle in required_handoff:
    if needle not in handoff:
        raise SystemExit(f"HANDOFF_WRITERS missing {needle!r}")
if "windows-native.4 stays prototype/pending" not in handoff.replace("`", ""):
    raise SystemExit("HANDOFF_WRITERS must keep windows-native.4 prototype/pending")

if "soft leftover-attaches `windows-native.4`" not in parity and "soft leftover-attaches windows-native.4" not in parity:
    raise SystemExit("PARITY must soft leftover-attach wn.4")
if 'Forty-task "Change the wallpaper" stays pending' not in parity and "Forty-task \"Change the wallpaper\" stays pending" not in parity:
    raise SystemExit("PARITY must keep forty-task Change the wallpaper pending")

if "windows-native.4" not in project:
    raise SystemExit("project-ultimate must keep windows-native.4")
if "Settings > Personalization" not in project and "omarchy-theme-bg-set" not in project:
    raise SystemExit("project-ultimate must name Personalization wallpaper plane")

if "windows-native.4" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must keep windows-native.4")
if "applyEmbedded" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must name applyEmbedded")

if "windows-native.4" not in settings_api:
    raise SystemExit("settings-service-api must name windows-native.4 leftover-attach")
if "omarchy-theme-bg-set" not in settings_api and "applyEmbedded" not in settings_api:
    raise SystemExit("settings-service-api must name wallpaper apply plane")

if "soft leftover-attaches windows-native.4" not in settings_model:
    raise SystemExit("SettingsModel must soft leftover-attach wn.4")
if "windows-native.4 stays prototype/pending" not in settings_model:
    raise SystemExit("SettingsModel must keep wn.4 prototype/pending")
if 'embedApplyKind: "wallpaper"' not in settings_host:
    raise SystemExit("SettingsPersonalizationHost must keep wallpaper embed")
if "function applyEmbedded(" not in image_picker:
    raise SystemExit("ImagePicker must keep applyEmbedded")
if "omarchy-theme-bg-set" not in image_picker:
    raise SystemExit("ImagePicker must keep omarchy-theme-bg-set apply")
if "omarchy-shell -q background set" not in theme_bg_set:
    raise SystemExit("omarchy-theme-bg-set must keep background set")
PY

pass "desktop.wallpaper.set stays partial with visible Settings > Personalization soft leftover-attached to wn.4"
