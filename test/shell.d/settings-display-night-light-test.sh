#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

settings_app="$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml"
settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
settings_card="$ROOT/shell/apps/ultimate-settings/SettingsDisplayNightLight.qml"
settings_session="$ROOT/shell/apps/shared/SettingsSessionNightlight.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
debt="$ROOT/default/ultimate/capabilities/legacy-debt-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
settings_api="$ROOT/docs/settings-service-api.md"
display_provider="$ROOT/default/fabric/omarchy_fabric/providers/display/provider.py"
display_manifest="$ROOT/default/fabric/omarchy_fabric/providers/display/manifest-v0.json"

[[ -f $settings_app ]] || fail "Settings application exists"
[[ -f $settings_model ]] || fail "Settings model exists"
[[ -f $settings_session ]] || fail "Settings hosts a NightlightService session plane"
[[ -f $settings_card ]] || fail "Settings ships a Display night-light card"

grep -Fq 'omarchy-shell' "$settings_session" || fail "session night-light QML calls omarchy-shell"
grep -Fq 'OMARCHY_PATH' "$settings_session" || fail "session night-light QML prefers OMARCHY_PATH for omarchy-shell"
grep -Fq '/bin/omarchy-shell' "$settings_session" || fail "session night-light QML spawns omarchy-shell from an absolute bin path"
if grep -Eq 'return "omarchy-shell"|: "omarchy-shell"' "$settings_session"; then
  fail "session night-light QML must not spawn a bare omarchy-shell PATH name"
fi
grep -Fq 'nightlight' "$settings_session" || fail "session night-light QML targets NightlightService IPC"
grep -Fq 'function readStatus(' "$settings_session" || fail "session night-light QML exposes readStatus"
grep -Fq 'function setEnabled(' "$settings_session" || fail "session night-light QML exposes setEnabled"
if grep -Fq 'function readStatus(' "$settings_card"; then
  fail "Display night-light card must not invent a local readStatus"
fi
if grep -Fq 'function setEnabled(' "$settings_card"; then
  fail "Display night-light card must not invent a local setEnabled"
fi
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$settings_session" "$settings_card"; then
  fail "Settings Display night-light must not mint Fabric durable operations"
fi
if grep -A20 'SettingsComponents.SettingsDisplayNightLight' "$settings_app" | grep -Eq 'operation\.(preflight|start|approve)|requestFabric'; then
  fail "Settings Display night-light host must not mint Fabric durable operations"
fi
if grep -Eq 'pkexec|sudo' "$settings_session" "$settings_card"; then
  fail "Settings Display night-light QML must not spawn privilege"
fi
if grep -Eq 'provider: "display.provider"|action: "brightness.set"|action: "night-light' "$settings_session" "$settings_card"; then
  fail "Settings Display night-light must not invent a Fabric night-light writer"
fi
if grep -Eq 'hyprctl|hyprsunset|omarchy-toggle-nightlight' "$settings_session" "$settings_card"; then
  fail "Settings Display night-light must use NightlightService IPC instead of a parallel hyprsunset writer"
fi
grep -Fq 'SettingsComponents.SettingsDisplayNightLight' "$settings_app" ||
  fail "Settings Display hosts the session night-light card"
grep -Fq 'settings.display.overview' "$settings_app" || fail "Settings still owns the Display route"
grep -Fq 'this session' "$settings_card" || fail "Settings Display night-light names the session principal"
grep -Fq 'Quick Settings' "$settings_card" || fail "Settings Display night-light names the QS plane"
grep -Fq 'NightlightService' "$settings_card" || fail "Settings Display night-light names NightlightService"
grep -Fq 'Fabric' "$settings_card" || fail "Settings Display night-light keeps Fabric inspect honest"
if grep -Eqi 'claim=present|is modern display complete' "$settings_card" "$settings_app"; then
  fail "Settings Display night-light must not invent present or modern-display complete"
fi
if grep -Eqi 'invents a display.provider night-light|display.provider night-light.set' "$settings_card" "$settings_app"; then
  fail "Settings Display night-light must not invent a Fabric night-light writer"
fi
if grep -Eqi 'Settings Power LIVE|LIVE CONTROL' "$settings_card"; then
  fail "Settings Display night-light must not invent LIVE CONTROL or Settings Power LIVE"
fi
grep -Fq 'sessionNightlight' "$settings_model" || fail "Settings model normalizes session night-light outcomes"
grep -Fq 'NightlightService' "$settings_model" || fail "Settings coverage names the NightlightService plane"
grep -Fq 'Quick Settings' "$settings_model" || fail "Settings coverage names the QS night-light plane"
if grep -Fq 'Night light remains a Superbar leftover, not a Settings LIVE writer.' "$settings_model"; then
  fail "Settings coverage still treats night-light as absent from Settings"
fi
if grep -Eqi 'night-light|nightlight|night light' "$display_provider" "$display_manifest"; then
  fail "display.provider invented a durable night-light writer"
fi

pass "Settings Display hosts the NightlightService / QS night-light plane instead of a Fabric LIVE writer"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-settings/SettingsModel.js')

const idle = Model.sessionNightlightIdle()
assertEqual(idle.phase, 'idle', 'session night-light starts idle')
assertEqual(idle.enabled, false, 'session night-light starts off')
assertEqual(idle.known, false, 'session night-light starts unknown')
assertEqual(idle.temperature, null, 'session night-light starts without a temperature')

const on = Model.sessionNightlightFinished(idle, {
  ok: true,
  enabled: true,
  known: true,
  temperature: 4000,
  explanation: 'Night light is on through NightlightService.'
})
assertEqual(on.phase, 'succeeded', 'successful status is succeeded')
assertEqual(on.enabled, true, 'successful on status is enabled')
assertEqual(on.known, true, 'successful on status is known')
assertEqual(on.temperature, 4000, 'successful on status keeps temperature')
assertEqual(on.message, 'Night light is on through NightlightService.', 'successful on status keeps the helper explanation')

const off = Model.sessionNightlightFinished(idle, {
  ok: true,
  enabled: false,
  known: true,
  temperature: 6500,
  explanation: 'Night light is off through NightlightService.'
})
assertEqual(off.enabled, false, 'successful off status is disabled')
assertEqual(off.known, true, 'successful off status is known')
assertEqual(off.temperature, 6500, 'successful off status keeps daylight temperature')

const unknown = Model.sessionNightlightFinished(idle, {
  ok: true,
  enabled: false,
  known: false,
  temperature: null,
  explanation: 'NightlightService could not read hyprsunset temperature.'
})
assertEqual(unknown.phase, 'succeeded', 'unknown temperature is still a successful read')
assertEqual(unknown.known, false, 'unknown temperature stays unknown')
assertEqual(unknown.enabled, false, 'unknown temperature is not treated as on')
assertEqual(unknown.code, '', 'unknown temperature is not a helper failure code')

const broken = Model.sessionNightlightFinished(idle, {
  ok: false,
  code: 'nightlight.shell-unavailable',
  explanation: 'NightlightService is not reachable through this session.'
})
assertEqual(broken.phase, 'failed', 'helper failure is failed')
assertEqual(broken.code, 'nightlight.shell-unavailable', 'failure keeps the helper code')
assertEqual(broken.known, false, 'failure stays unknown')

const statusOn = Model.sessionNightlightFromIpc('status', '{"enabled":true,"temperature":4000}', 0, '')
assertEqual(statusOn.ok, true, 'status IPC JSON succeeds')
assertEqual(statusOn.enabled, true, 'status IPC JSON reports enabled')
assertEqual(statusOn.known, true, 'status IPC JSON with temperature is known')
assertEqual(statusOn.temperature, 4000, 'status IPC JSON keeps temperature')

const statusUnknown = Model.sessionNightlightFromIpc('status', '{"enabled":false,"temperature":null}', 0, '')
assertEqual(statusUnknown.ok, true, 'null temperature status is a successful read')
assertEqual(statusUnknown.known, false, 'null temperature status is unknown')
assertEqual(statusUnknown.enabled, false, 'null temperature status is not on')

const applyOn = Model.sessionNightlightFromIpc('set', 'enabled', 0, '')
assertEqual(applyOn.ok, true, 'enable IPC succeeds')
assertEqual(applyOn.enabled, true, 'enable IPC reports enabled')

const applyOff = Model.sessionNightlightFromIpc('set', 'disabled', 0, '')
assertEqual(applyOff.ok, true, 'disable IPC succeeds')
assertEqual(applyOff.enabled, false, 'disable IPC reports disabled')

const missing = Model.sessionNightlightFromIpc('status', '', 1, 'omarchy-shell is not running')
assertEqual(missing.ok, false, 'missing shell is a failure')
assertEqual(missing.code, 'nightlight.shell-unavailable', 'missing shell uses shell-unavailable')

const parsed = Model.sessionNightlightFromIpc('status', 'not-json', 0, '')
assertEqual(parsed.ok, false, 'garbage status is a failure')
assertEqual(parsed.code, 'nightlight.parse-failed', 'garbage status uses parse-failed')

const display = Model.queryForRoute('settings.display.overview')
assert(display.coverage.indexOf('NightlightService') >= 0, 'display coverage names NightlightService')
assert(display.coverage.indexOf('Quick Settings') >= 0, 'display coverage names the QS plane')
assert(display.coverage.indexOf('display.inspect') >= 0, 'display coverage keeps Fabric inspect separate')
assert(display.coverage.indexOf('does not invent a display.provider night-light durable writer') >= 0, 'display coverage refuses a Fabric night-light writer')
assert(display.coverage.indexOf('Resolution, arrangement, and HDR remain unavailable') >= 0, 'display coverage still refuses arrangement and HDR')
assert(display.coverage.indexOf('does not invent a display.provider scale durable writer') >= 0, 'display coverage refuses a Fabric scale writer')
assert(display.coverage.indexOf('not modern display complete') >= 0, 'display coverage refuses modern-display complete')
assert(Model.declaredOpsHonesty('settings.display.overview').indexOf('NightlightService') >= 0, 'display declared ops name NightlightService')
assert(Model.declaredOpsHonesty('settings.display.overview').indexOf('durable coordinator') >= 0, 'display declared ops keep brightness on the durable coordinator')
assert(Model.declaredOpsHonesty('settings.display.overview').indexOf('does not invent a display.provider night-light durable writer') >= 0, 'display declared ops do not invent a Fabric night-light writer')
assert(Model.authorityFooter().indexOf('NightlightService') >= 0, 'authority footer names NightlightService')
JS

pass "Settings model maps NightlightService session outcomes and refuses a Fabric invent"

python3 - "$catalog" "$jobs" "$debt" "$gaps" "$parity" "$settings_api" <<'PY'
import json
import sys

catalog = json.loads(open(sys.argv[1], encoding="utf-8").read())
jobs = json.loads(open(sys.argv[2], encoding="utf-8").read())
debt = json.loads(open(sys.argv[3], encoding="utf-8").read())
gaps = open(sys.argv[4], encoding="utf-8").read()
parity = open(sys.argv[5], encoding="utf-8").read()
settings_api = open(sys.argv[6], encoding="utf-8").read()
by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
night = by_id["display.night-light.set"]
route = night["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"display.night-light.set route is {route}")
if route.get("path") != "Settings > Display; Superbar > Quick Settings > Night light":
    raise SystemExit(f"display.night-light.set path is {route}")
if "Settings > Display" not in str(route.get("path") or ""):
    raise SystemExit(f"display.night-light.set underclaims the Settings Display host: {route}")
if "Superbar > Quick Settings > Night light" not in str(route.get("path") or ""):
    raise SystemExit(f"display.night-light.set underclaims the QS leftover tile: {route}")
if route.get("label") != "Turn night light on or off; QS leftover tile remains":
    raise SystemExit(f"display.night-light.set underclaims the QS leftover tile in label: {route}")
if night.get("source", {}).get("file") != "shell/plugins/services/nightlight/Service.qml":
    raise SystemExit(f"display.night-light.set source is {night.get('source')}")
if night.get("source", {}).get("symbol") != "NightlightService":
    raise SystemExit(f"display.night-light.set source is {night.get('source')}")
if "SettingsDisplayNightLight.qml" in str(night.get("source", {}).get("file") or ""):
    raise SystemExit("display.night-light.set must not invent source on SettingsDisplayNightLight.qml")
if night.get("availability", {}).get("claim") == "present":
    raise SystemExit("display.night-light.set must not claim present")
if night.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"display.night-light.set claim is {night.get('availability')}")
if night.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"display.night-light.set human availability is {night.get('availability')}")
if night.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"display.night-light.set agent availability is {night.get('availability')}")
if night.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"display.night-light.set was raised off leftover: {night.get('provider')}")
if night.get("provider", {}).get("id") != "display.provider":
    raise SystemExit(f"display.night-light.set provider is {night.get('provider')}")

by_job = {job["id"]: job for job in jobs["jobs"]}
parity_display = by_job["parity.display"]
if parity_display.get("claim") == "present":
    raise SystemExit("parity.display must not claim present")
if "display.night-light.set" not in (parity_display.get("capabilityIds") or []):
    raise SystemExit("parity.display dropped display.night-light.set")
modern = by_job["parity.modern-display-scaling-hdr-night-light"]
if modern.get("claim") == "present":
    raise SystemExit("parity.modern-display-scaling-hdr-night-light must not claim present")
if modern.get("claim") != "prototype":
    raise SystemExit(f"parity.modern-display-scaling-hdr-night-light claim is {modern.get('claim')}")
if "display.night-light.set" not in (modern.get("capabilityIds") or []):
    raise SystemExit("parity.modern-display-scaling-hdr-night-light dropped display.night-light.set")
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
if native34["humanRoute"].get("status") != "visible":
    raise SystemExit(f"windows-native.34 route is {native34.get('humanRoute')}")
if native34["humanRoute"].get("path") not in {"Settings > Display", "Start > Settings > Display"}:
    raise SystemExit(f"windows-native.34 path is {native34.get('humanRoute')}")

by_debt = {entry["id"]: entry for entry in debt["entries"]}
legacy = by_debt["legacy.domain.direct-providers"]
if "display.night-light.set" not in legacy.get("capabilityIds", []):
    raise SystemExit("display.night-light.set is not leftover-direct debt")
if "capability:display.night-light.set" not in legacy.get("surfaceRefs", []):
    raise SystemExit("display.night-light.set leftover surfaceRef is missing")
agent = by_debt["missing.agent.routes"]
if "display.night-light.set" not in agent.get("capabilityIds", []):
    raise SystemExit("display.night-light.set left missing.agent.routes")

if "Honesty addendum 2026-09-06 vs Settings Display night-light" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must add a dated Settings Display night-light addendum")
addendum = gaps.split("Honesty addendum 2026-09-06 vs Settings Display night-light", 1)[1].split("Honesty addendum", 1)[0]
if "CLOSED leftover: Settings Display night-light UI" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name CLOSED leftover as Settings Display night-light UI")
for required in (
    "Settings Power LIVE",
    "Files LIVE metal",
    "Win7 visual",
    "End Task LIVE",
    "Update present",
    "Software Center present",
    "scaling",
    "HDR",
):
    if required not in addendum:
        raise SystemExit(f"fleet-doctrine-gaps night-light addendum dropped OPEN leftover: {required}")
if "does not invent Fabric durable night-light LIVE / claim=present" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep Settings from inventing Fabric durable night-light LIVE / claim=present")
if "Settings > Display; Superbar > Quick Settings > Night light" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name both visible night-light routes")
if "QS leftover tile" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name the QS leftover tile residual")
if "Do not walk `windows-native.34` to present" not in addendum and "Do not walk windows-native.34 to present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse walking windows-native.34 to present")
if "Do not invent claim=present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse claim=present invent")
if "Do not walk `parity.modern-display-scaling-hdr-night-light` to present" not in addendum and "Do not walk parity.modern-display-scaling-hdr-night-light to present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse walking modern-display to present")
if "Cloud EXIT 0 is not metal leftover CLOSED" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Cloud EXIT 0 as metal leftover CLOSED")
if "NightlightService" not in addendum or "Quick Settings" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name Settings vs QS NightlightService planes")
if "display.inspect" not in addendum and "Fabric" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must keep Fabric inspect separate")
if "Settings → Display" in parity and "does not invent Fabric durable night-light LIVE / claim=present" not in parity and "does not invent a display.provider night-light" not in parity:
    raise SystemExit("PARITY Display row must keep Fabric durable night-light LIVE / claim=present refused")
if "NightlightService" not in parity:
    raise SystemExit("PARITY Display row must name NightlightService")
if "does not invent Fabric durable night-light LIVE / claim=present" not in parity and "does not invent a display.provider night-light" not in parity:
    raise SystemExit("PARITY Display row must refuse a Fabric night-light invent")
if "Settings > Display; Superbar > Quick Settings > Night light" not in parity:
    raise SystemExit("PARITY Display row must name both visible night-light routes")
if "NightlightService" not in settings_api:
    raise SystemExit("settings-service-api must name NightlightService")
if "Settings Display hosts" not in settings_api and "Settings Display hosts that control" not in settings_api:
    raise SystemExit("settings-service-api must name the Settings Display night-light host")
if "display.provider night-light" not in settings_api:
    raise SystemExit("settings-service-api must refuse a display.provider night-light durable writer")
if "windows-native.34" not in settings_api:
    raise SystemExit("settings-service-api must keep windows-native.34 pending")
if "does not invent Fabric durable night-light LIVE / claim=present" not in settings_api:
    raise SystemExit("settings-service-api must refuse Fabric durable night-light LIVE / claim=present")
if "Settings > Display; Superbar > Quick Settings > Night light" not in settings_api:
    raise SystemExit("settings-service-api must name both visible night-light routes")
PY

pass "display.night-light.set stays leftover partial with dual visible Settings Display and QS leftover routes"
