#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

settings_app="$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml"
settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
settings_card="$ROOT/shell/apps/ultimate-settings/SettingsInputLayout.qml"
settings_session="$ROOT/shell/apps/shared/SettingsSessionKeyboardLayout.qml"
helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
debt="$ROOT/default/ultimate/capabilities/legacy-debt-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
settings_api="$ROOT/docs/settings-service-api.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
input_provider="$ROOT/default/fabric/omarchy_fabric/providers/input/provider.py"
input_manifest="$ROOT/default/fabric/omarchy_fabric/providers/input/manifest-v0.json"
daemon="$ROOT/default/fabric/omarchy_fabric/daemon.py"

[[ -f $settings_app ]] || fail "Settings application exists"
[[ -f $settings_model ]] || fail "Settings model exists"
[[ -f $settings_session ]] || fail "Settings hosts a session keyboard-layout plane"
[[ -f $settings_card ]] || fail "Settings ships an Input keyboard-layout card"
[[ -f $helper ]] || fail "session apply helper exists"

grep -Fq 'omarchy-fabric-session-apply' "$settings_session" ||
  fail "session keyboard-layout QML uses the session apply helper"
grep -Fq 'OMARCHY_PATH' "$settings_session" || fail "session keyboard-layout QML prefers OMARCHY_PATH"
grep -Fq '/bin/omarchy-fabric-session-apply' "$settings_session" ||
  fail "session keyboard-layout QML spawns omarchy-fabric-session-apply from an absolute bin path"
if grep -Eq 'return "omarchy-fabric-session-apply"|: "omarchy-fabric-session-apply"' "$settings_session"; then
  fail "session keyboard-layout QML must not spawn a bare omarchy-fabric-session-apply PATH name"
fi
grep -Fq '"input-keyboard-layout": apply_input_keyboard_layout_session' "$helper" ||
  fail "session apply owns input-keyboard-layout"
grep -Fq '"input-keyboard-layout-status": apply_input_keyboard_layout_status' "$helper" ||
  fail "session apply owns input-keyboard-layout-status"
grep -Fq 'input-keyboard-layout' "$settings_session" || fail "session keyboard-layout QML calls input-keyboard-layout"
grep -Fq 'input-keyboard-layout-status' "$settings_session" || fail "session keyboard-layout QML calls input-keyboard-layout-status"
grep -Fq 'function readStatus(' "$settings_session" || fail "session keyboard-layout QML exposes readStatus"
grep -Fq 'function setLayout(' "$settings_session" || fail "session keyboard-layout QML exposes setLayout"
if grep -Fq 'function readStatus(' "$settings_card"; then
  fail "Input keyboard-layout card must not invent a local readStatus"
fi
if grep -Fq 'function setLayout(' "$settings_card"; then
  fail "Input keyboard-layout card must not invent a local setLayout"
fi
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$settings_session" "$settings_card"; then
  fail "Settings Input keyboard-layout must not mint Fabric durable operations"
fi
if grep -A20 'SettingsComponents.SettingsInputLayout' "$settings_app" | grep -Eq 'operation\.(preflight|start|approve)|requestFabric'; then
  fail "Settings Input keyboard-layout host must not mint Fabric durable operations"
fi
if grep -Eq 'pkexec|sudo' "$settings_session" "$settings_card"; then
  fail "Settings Input keyboard-layout QML must not spawn privilege"
fi
if grep -Eq 'provider: "input.provider"|action: "keyboard-layout.set"' "$settings_session" "$settings_card"; then
  fail "Settings Input keyboard-layout must not invent a Fabric layout writer"
fi
if grep -Eq 'hyprctl|bash -c|switchxkblayout' "$settings_session"; then
  fail "session keyboard-layout QML must use the session apply verb instead of a parallel hyprctl writer"
fi
if grep -Eq 'command:[[:space:]]*\[.*hyprctl|["'\'']hyprctl["'\'']' "$settings_card"; then
  fail "Input keyboard-layout card must not spawn hyprctl directly"
fi
if grep -Eq 'localectl' "$settings_session" "$settings_card"; then
  fail "Settings Input keyboard-layout must not invent a localectl writer"
fi
grep -Fq 'SettingsComponents.SettingsInputLayout' "$settings_app" ||
  fail "Settings Input hosts the session keyboard-layout card"
grep -Fq 'settings.input.overview' "$settings_app" || fail "Settings still owns the Input route"
grep -Fq 'this session' "$settings_card" || fail "Settings Input keyboard-layout names the session principal"
grep -Fq 'hyprctl' "$settings_card" || fail "Settings Input keyboard-layout names the absolute helper"
grep -Fq 'session leftover recorded' "$settings_card" || fail "Settings Input keyboard-layout records a session leftover"
grep -Fq 'session-UI leftover only' "$settings_card" || fail "Settings Input keyboard-layout names session-UI leftover only"
grep -Fq 'not product CLOSED' "$settings_card" || fail "Settings Input keyboard-layout refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$settings_card" || fail "Settings Input keyboard-layout refuses metal CLOSED"
grep -Fq 'not claim=present' "$settings_card" || fail "Settings Input keyboard-layout refuses claim=present"
if grep -Eq 'CLOSED leftover:' "$settings_card"; then
  fail "Settings Input keyboard-layout must not use bare CLOSED leftover invent"
fi
if grep -Eqi 'is locale complete|Close one product hole' "$settings_card" "$settings_app"; then
  fail "Settings Input keyboard-layout must not invent present or locale complete"
fi
if grep -Eqi 'full locale complete|locale product-complete' "$settings_card" "$settings_app"; then
  fail "Settings Input keyboard-layout must not invent locale product-complete"
fi
if grep -Eqi 'claim=present' "$settings_card" "$settings_app" && ! grep -Eqi 'not claim=present' "$settings_card"; then
  fail "Settings Input keyboard-layout must not invent claim=present"
fi
if grep -Eqi 'LIVE CONTROL' "$settings_card"; then
  fail "Settings Input keyboard-layout must not invent LIVE CONTROL"
fi
if grep -Eqi 'Settings Power LIVE' "$settings_card"; then
  fail "Settings Input keyboard-layout must not invent Settings Power LIVE"
fi
if grep -Fq 'function applyKeyboardLayout(' "$settings_app"; then
  fail "Settings application must not keep a Fabric applyKeyboardLayout writer"
fi
grep -Fq 'sessionKeyboardLayout' "$settings_model" || fail "Settings model normalizes session keyboard-layout outcomes"
grep -Fq 'input-keyboard-layout' "$settings_model" || fail "Settings coverage names the session layout verb"
grep -Fq 'does not invent a input.provider keyboard-layout durable writer' "$settings_model" ||
  grep -Fq 'does not invent an input.provider keyboard-layout durable writer' "$settings_model" ||
  fail "Settings coverage refuses a Fabric layout writer"
if grep -Eqi 'input.provider keyboard-layout durable LIVE' "$input_provider" "$input_manifest"; then
  fail "input.provider invented a durable LIVE layout claim"
fi
if grep -Eq 'input-keyboard-layout-status|input-keyboard-layout"' "$daemon"; then
  fail "Fabric durable plane invented a session keyboard-layout writer"
fi

pass "Settings Input hosts the session keyboard-layout plane instead of a Fabric LIVE writer"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-settings/SettingsModel.js')

const idle = Model.sessionKeyboardLayoutIdle()
assertEqual(idle.phase, 'idle', 'session keyboard layout starts idle')
assertEqual(idle.layout, '', 'session keyboard layout starts without a layout')
assertEqual(idle.known, false, 'session keyboard layout starts unknown')
assertEqual(idle.layouts.length, 0, 'session keyboard layout starts with no configured layouts')
assertEqual(Model.sessionKeyboardLayoutCanSubmit('us', ['us', 'de']), true, 'configured us is allowed')
assertEqual(Model.sessionKeyboardLayoutCanSubmit('de', ['us', 'de']), true, 'configured de is allowed')
assertEqual(Model.sessionKeyboardLayoutCanSubmit('fr', ['us', 'de']), false, 'unconfigured fr is refused')
assertEqual(Model.sessionKeyboardLayoutCanSubmit('us;rm -rf /', ['us', 'de']), false, 'arbitrary strings are refused')
assertEqual(Model.sessionKeyboardLayoutCanSubmit('', ['us', 'de']), false, 'empty identity is refused')
assertEqual(Model.sessionKeyboardLayoutCanSubmit('us', ['us']), false, 'single-layout seats cannot submit')
assertEqual(Model.sessionKeyboardLayoutCanSubmit('us', []), false, 'empty seats cannot submit')

const on = Model.sessionKeyboardLayoutFinished(idle, {
  ok: true,
  layout: 'de',
  layouts: ['us', 'de'],
  known: true,
  explanation: 'Applied the typed Hyprland keyboard layout through this session.'
})
assertEqual(on.phase, 'succeeded', 'successful apply is succeeded')
assertEqual(on.layout, 'de', 'successful apply keeps de')
assertEqual(on.known, true, 'successful apply is known')
assertEqual(on.layouts.join(','), 'us,de', 'successful apply keeps configured layouts')
assertEqual(on.message, 'Applied the typed Hyprland keyboard layout through this session.', 'successful apply keeps the helper explanation')

const refused = Model.sessionKeyboardLayoutFinished(idle, {
  ok: false,
  code: 'payload.invalid',
  explanation: 'Layout must be one of the configured keyboard layouts.'
})
assertEqual(refused.phase, 'failed', 'whitelist refuse is failed')
assertEqual(refused.code, 'payload.invalid', 'whitelist refuse keeps payload.invalid')
assertEqual(refused.known, false, 'whitelist refuse stays unknown')

const unknown = Model.sessionKeyboardLayoutFinished(idle, {
  ok: true,
  layout: 'zz',
  layouts: ['us', 'de'],
  known: true,
  explanation: 'Typed Hyprland keyboard layout through this session.'
})
assertEqual(unknown.phase, 'failed', 'non-configured helper layout is failed')
assertEqual(unknown.known, false, 'non-configured helper layout stays unknown')

const empty = Model.sessionKeyboardLayoutFinished(idle, {
  ok: true,
  layout: '',
  layouts: [],
  known: true,
  explanation: 'No typed keyboard reported configured layouts through this session.'
})
assertEqual(empty.phase, 'succeeded', 'honest empty status can succeed')
assertEqual(empty.known, false, 'empty status stays unknown')
assertEqual(empty.empty, true, 'empty status is empty')

const single = Model.sessionKeyboardLayoutFinished(idle, {
  ok: true,
  layout: 'us',
  layouts: ['us'],
  known: true,
  explanation: 'Typed Hyprland keyboard layout through this session.'
})
assertEqual(single.phase, 'succeeded', 'honest single-layout status can succeed')
assertEqual(single.known, true, 'single-layout status is known')
assertEqual(single.switchable, false, 'single-layout status is not switchable')

const input = Model.queryForRoute('settings.input.overview')
assert(input.coverage.indexOf('input-keyboard-layout') >= 0, 'input coverage names the session layout verb')
assert(input.coverage.indexOf('does not invent an input.provider keyboard-layout durable writer') >= 0 ||
  input.coverage.indexOf('does not invent a input.provider keyboard-layout durable writer') >= 0,
  'input coverage refuses a Fabric layout writer')
assert(input.coverage.indexOf('session leftover recorded') >= 0, 'input coverage records a session leftover')
assert(input.coverage.indexOf('not product CLOSED') >= 0, 'input coverage refuses product CLOSED')
assert(input.coverage.indexOf('not metal CLOSED') >= 0, 'input coverage refuses metal CLOSED')
assert(input.coverage.indexOf('not claim=present') >= 0, 'input coverage refuses claim=present')
assert(input.coverage.indexOf('Pointer, repeat rate, and accessibility input changes remain unavailable') >= 0, 'input coverage still refuses pointer and locale')
assert(input.coverage.indexOf('not locale complete') >= 0 || input.coverage.indexOf('full locale') >= 0, 'input coverage refuses locale complete')
assert(Model.declaredOpsHonesty('settings.input.overview').indexOf('input-keyboard-layout') >= 0, 'input declared ops name the session layout verb')
assert(Model.declaredOpsHonesty('settings.input.overview').indexOf('does not invent') >= 0, 'input declared ops refuse a Fabric layout writer')
assert(Model.authorityFooter().indexOf('input-keyboard-layout') >= 0, 'authority footer names the session layout verb')
JS

pass "Settings model maps session keyboard-layout outcomes and refuses a Fabric invent"

cd "$ROOT/default/fabric"
OMARCHY_PATH="$ROOT" PYTHONPATH="$ROOT/default/fabric" PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import io
import json
import os
import pathlib
import tempfile

os.environ.pop("XDG_DATA_HOME", None)
root = pathlib.Path(tempfile.mkdtemp())
home = root / "tester"
home.mkdir(parents=True)
os.environ["HOME"] = str(home)
os.environ["USERPROFILE"] = str(home)
os.environ["OMARCHY_PATH"] = os.environ["OMARCHY_PATH"]

from omarchy_fabric.helpers import session_apply as sa

failures = []


def check(label, condition, detail=""):
    if not condition:
        failures.append(f"{label}{': ' + detail if detail else ''}")


class Result:
    def __init__(self, returncode=0, stdout="", stderr=""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


DEVICES = json.dumps({
    "keyboards": [
        {"name": "power-button", "layout": "us", "active_layout_index": 0, "active_keymap": "English (US)", "main": True},
        {"name": "at-translated-set-2-keyboard", "layout": "us,de", "active_layout_index": 0, "active_keymap": "English (US)", "main": False},
    ]
})


def run_set(payload, runner=None):
    stream = io.StringIO()
    status = sa.apply_input_keyboard_layout_session(
        io.StringIO(json.dumps(payload)),
        stream,
        run=runner or (lambda *args, **kwargs: Result(stdout=DEVICES)),
    )
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


def run_status(payload, runner=None):
    stream = io.StringIO()
    status = sa.apply_input_keyboard_layout_status(
        io.StringIO(json.dumps(payload)),
        stream,
        run=runner or (lambda *args, **kwargs: Result(stdout=DEVICES)),
    )
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


if "input-keyboard-layout" not in sa.ACTIONS:
    failures.append("session apply ACTIONS omitted input-keyboard-layout")
if "input-keyboard-layout-status" not in sa.ACTIONS:
    failures.append("session apply ACTIONS omitted input-keyboard-layout-status")

helper = sa.keyboard_layout_helper()
check("helper is absolute hyprctl", helper == "/usr/bin/hyprctl", helper)
check("helper is absolute", helper.startswith("/"), helper)

status, result = run_set({})
check("empty payload is refused first", status == 1 and result.get("ok") is False, str(result))
check("empty payload uses payload.invalid", result.get("code") == "payload.invalid", str(result))
check("empty payload uses the fixed whitelist explanation", result.get("explanation") == sa.KEYBOARD_LAYOUT_REFUSE, str(result))

status, result = run_set({"layout": "fr"})
check("unconfigured layout is refused first", status == 1 and result.get("ok") is False, str(result))
check("unconfigured layout uses payload.invalid", result.get("code") == "payload.invalid", str(result))
check("unconfigured layout uses the fixed explanation", result.get("explanation") == sa.KEYBOARD_LAYOUT_REFUSE, str(result))
check("unconfigured layout is not echoed", "fr" not in json.dumps(result), str(result))

status, result = run_set({"layout": "us;rm -rf /"})
check("arbitrary string is refused", status == 1 and result.get("code") == "payload.invalid", str(result))
check("arbitrary string is not echoed", "rm -rf" not in json.dumps(result), str(result))

status, result = run_set({"layout": "us", "password": "hunter2"})
check("credential keys are refused", status == 1 and result.get("ok") is False, str(result))
check("credential keys use payload.invalid", result.get("code") == "payload.invalid", str(result))
check("credential refuse does not leak secrets", "hunter2" not in json.dumps(result), str(result))

ok_calls = []


def ok_run(argv, **kwargs):
    ok_calls.append(list(argv))
    if argv[1:3] == ["-j", "devices"]:
        return Result(stdout=DEVICES)
    return Result()


status, result = run_set({"layout": "de"}, ok_run)
check("mocked de apply succeeds after refuse", status == 0 and result.get("ok") is True, str(result))
check("mocked de apply keeps layout", result.get("layout") == "de", str(result))
check("mocked de apply names this session", "this session" in str(result.get("explanation") or ""), str(result))
check(
    "mocked de apply uses the absolute helper",
    ok_calls[-1] == [helper, "switchxkblayout", "at-translated-set-2-keyboard", "1"],
    str(ok_calls),
)

single_devices = json.dumps({
    "keyboards": [
        {"name": "at-translated-set-2-keyboard", "layout": "us", "active_layout_index": 0, "active_keymap": "English (US)", "main": True},
    ]
})


def single_run(argv, **kwargs):
    if argv[1:3] == ["-j", "devices"]:
        return Result(stdout=single_devices)
    return Result()


status, result = run_set({"layout": "us"}, single_run)
check("single-layout set is refused", status == 1 and result.get("ok") is False, str(result))
check("single-layout set uses payload.invalid", result.get("code") == "payload.invalid", str(result))
check("single-layout set uses the fixed explanation", result.get("explanation") == sa.KEYBOARD_LAYOUT_REFUSE, str(result))


def missing_command_run(argv, **kwargs):
    raise FileNotFoundError(argv[0])


status, result = run_set({"layout": "de"}, missing_command_run)
check("missing helper is command.unavailable", status == 1 and result.get("code") == "command.unavailable", str(result))

status, result = run_status({})
check("status read succeeds after refuse", status == 0 and result.get("ok") is True, str(result))
check("status read keeps us", result.get("layout") == "us", str(result))
check("status read lists configured layouts", result.get("layouts") == ["us", "de"], str(result))
check("status read is known", result.get("known") is True, str(result))
check("status read is switchable", result.get("switchable") is True, str(result))

status, result = run_status({"password": "hunter2"})
check("status extra keys are refused", status == 1 and result.get("code") == "payload.invalid", str(result))
check("status extra keys do not leak secrets", "hunter2" not in json.dumps(result), str(result))

status, result = run_status({}, single_run)
check("single-layout status succeeds", status == 0 and result.get("ok") is True, str(result))
check("single-layout status is not switchable", result.get("switchable") is False, str(result))
check("single-layout status keeps us", result.get("layout") == "us", str(result))

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session keyboard-layout reports success and honest whitelist refuse"

python3 - "$catalog" "$jobs" "$debt" "$gaps" "$parity" "$settings_api" "$handoff" <<'PY'
import json
import sys

catalog = json.loads(open(sys.argv[1], encoding="utf-8").read())
jobs = json.loads(open(sys.argv[2], encoding="utf-8").read())
debt = json.loads(open(sys.argv[3], encoding="utf-8").read())
gaps = open(sys.argv[4], encoding="utf-8").read()
parity = open(sys.argv[5], encoding="utf-8").read()
settings_api = open(sys.argv[6], encoding="utf-8").read()
handoff = open(sys.argv[7], encoding="utf-8").read()
by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
layout = by_id["input.keyboard-layout.set"]
route = layout["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"input.keyboard-layout.set route is {route}")
if route.get("path") != "Settings > Input":
    raise SystemExit(f"input.keyboard-layout.set path is {route}")
if "Settings > Input" not in str(route.get("path") or ""):
    raise SystemExit(f"input.keyboard-layout.set underclaims the Settings Input host: {route}")
if layout.get("source", {}).get("file") != "default/fabric/omarchy_fabric/helpers/session_apply.py":
    raise SystemExit(f"input.keyboard-layout.set source is {layout.get('source')}")
if layout.get("source", {}).get("symbol") != "apply_input_keyboard_layout_session":
    raise SystemExit(f"input.keyboard-layout.set source is {layout.get('source')}")
if "SettingsInputLayout.qml" in str(layout.get("source", {}).get("file") or ""):
    raise SystemExit("input.keyboard-layout.set must not invent source on SettingsInputLayout.qml")
if "SettingsApplication.qml" in str(layout.get("source", {}).get("file") or ""):
    raise SystemExit("input.keyboard-layout.set must not invent source on SettingsApplication.qml")
if "KeyboardLayout.qml" in str(layout.get("source", {}).get("file") or ""):
    raise SystemExit("input.keyboard-layout.set must not invent source on the bar widget")
if layout.get("availability", {}).get("claim") == "present":
    raise SystemExit("input.keyboard-layout.set must not claim present")
if layout.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"input.keyboard-layout.set claim is {layout.get('availability')}")
if layout.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"input.keyboard-layout.set human availability is {layout.get('availability')}")
if layout.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"input.keyboard-layout.set agent availability is {layout.get('availability')}")
if layout.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"input.keyboard-layout.set was raised off leftover: {layout.get('provider')}")
if layout.get("provider", {}).get("id") != "input.provider":
    raise SystemExit(f"input.keyboard-layout.set provider is {layout.get('provider')}")

by_job = {job["id"]: job for job in jobs["jobs"]}
parity_locale = by_job["parity.language-locale"]
if parity_locale.get("claim") == "present":
    raise SystemExit("parity.language-locale must not claim present")
if "input.keyboard-layout.set" not in (parity_locale.get("capabilityIds") or []):
    raise SystemExit("parity.language-locale dropped input.keyboard-layout.set")
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
if native33["humanRoute"].get("status") != "visible":
    raise SystemExit(f"windows-native.33 route is {native33.get('humanRoute')}")
if native33["humanRoute"].get("path") != "Settings > Input":
    raise SystemExit(f"windows-native.33 path is {native33.get('humanRoute')}")

by_debt = {entry["id"]: entry for entry in debt["entries"]}
legacy = by_debt["legacy.domain.direct-providers"]
if "input.keyboard-layout.set" not in legacy.get("capabilityIds", []):
    raise SystemExit("input.keyboard-layout.set is not leftover-direct debt")
if "capability:input.keyboard-layout.set" not in legacy.get("surfaceRefs", []):
    raise SystemExit("input.keyboard-layout.set leftover surfaceRef is missing")
agent = by_debt["missing.agent.routes"]
if "input.keyboard-layout.set" not in agent.get("capabilityIds", []):
    raise SystemExit("input.keyboard-layout.set left missing.agent.routes")

if "Honesty addendum 2026-09-06 vs Settings Input keyboard layout" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must add a dated Settings Input keyboard layout addendum")
addendum = gaps.split("Honesty addendum 2026-09-06 vs Settings Input keyboard layout", 1)[1].split("Honesty addendum", 1)[0]
if "CLOSED leftover:" in addendum:
    raise SystemExit("fleet-doctrine-gaps must not use bare CLOSED leftover invent for keyboard layout")
for required in (
    "session leftover recorded",
    "session-UI leftover only",
    "not product CLOSED",
    "not metal CLOSED",
    "not claim=present",
    "Settings > Input",
    "input.keyboard-layout.set",
    "legacy-direct",
    "hyprctl",
    "input-keyboard-layout",
    "Cloud EXIT 0 is not metal leftover CLOSED",
    "Cloud mocks do not close windows-native.33",
    "windows-native.33",
    "Settings Power LIVE",
    "locale",
):
    if required not in addendum:
        raise SystemExit(f"fleet-doctrine-gaps keyboard-layout addendum dropped required honesty: {required}")
if "Do not walk `windows-native.33` to present" not in addendum and "Do not walk windows-native.33 to present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse walking windows-native.33 to present")
if "Do not invent claim=present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse claim=present invent")
if "| `windows-native.33` | prototype/pending | visible: Settings > Input |" not in gaps:
    raise SystemExit("fleet-doctrine-gaps invent-mode must keep windows-native.33 visible Settings > Input")
if "metal CLOSED from Cloud EXIT 0" not in gaps.split("`windows-native.33`", 1)[1].split("`windows-native.34`", 1)[0]:
    raise SystemExit("fleet-doctrine-gaps invent-mode for windows-native.33 must include metal CLOSED from Cloud EXIT 0")
if "session leftover recorded" not in parity:
    raise SystemExit("PARITY Input row must record the session leftover")
if "input.keyboard-layout.set" not in parity:
    raise SystemExit("PARITY Input row must name input.keyboard-layout.set")
if "does not invent an `input.provider` keyboard-layout durable writer" not in parity and "does not invent a input.provider keyboard-layout" not in parity and "does not invent an input.provider keyboard-layout" not in parity:
    raise SystemExit("PARITY Input row must refuse a Fabric layout invent")
if "windows-native.33` stays prototype/pending" not in parity and "windows-native.33` stays pending" not in parity and "windows-native.33 stays prototype/pending" not in parity:
    raise SystemExit("PARITY Input row must keep windows-native.33 pending")
if "Cloud mocks do not close windows-native.33" not in parity:
    raise SystemExit("PARITY Input row must refuse Cloud mocks closing windows-native.33")
if "input.keyboard-layout.set" not in settings_api:
    raise SystemExit("settings-service-api must name input.keyboard-layout.set")
if "windows-native.33" not in settings_api:
    raise SystemExit("settings-service-api must keep windows-native.33 pending")
if "session leftover recorded" not in settings_api:
    raise SystemExit("settings-service-api must record the session leftover")
if "input-keyboard-layout" not in settings_api:
    raise SystemExit("settings-service-api must name input-keyboard-layout")
if "input-keyboard-layout" not in handoff:
    raise SystemExit("HANDOFF must name input-keyboard-layout")
if "session leftover recorded" not in handoff:
    raise SystemExit("HANDOFF must record the session leftover")
if "Cloud mocks do not close windows-native.33" not in handoff:
    raise SystemExit("HANDOFF must refuse Cloud mocks closing windows-native.33")
PY

pass "input.keyboard-layout.set stays leftover partial with visible Settings Input route"
