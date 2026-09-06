#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

settings_app="$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml"
settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
settings_card="$ROOT/shell/apps/ultimate-settings/SettingsDisplayScaling.qml"
settings_session="$ROOT/shell/apps/shared/SettingsSessionScaling.qml"
helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
debt="$ROOT/default/ultimate/capabilities/legacy-debt-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
settings_api="$ROOT/docs/settings-service-api.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
display_provider="$ROOT/default/fabric/omarchy_fabric/providers/display/provider.py"
display_manifest="$ROOT/default/fabric/omarchy_fabric/providers/display/manifest-v0.json"
daemon="$ROOT/default/fabric/omarchy_fabric/daemon.py"

[[ -f $settings_app ]] || fail "Settings application exists"
[[ -f $settings_model ]] || fail "Settings model exists"
[[ -f $settings_session ]] || fail "Settings hosts a session scaling plane"
[[ -f $settings_card ]] || fail "Settings ships a Display scaling card"
[[ -f $helper ]] || fail "session apply helper exists"

grep -Fq 'omarchy-fabric-session-apply' "$settings_session" ||
  fail "session scaling QML uses the session apply helper"
grep -Fq 'OMARCHY_PATH' "$settings_session" || fail "session scaling QML prefers OMARCHY_PATH"
grep -Fq '/bin/omarchy-fabric-session-apply' "$settings_session" ||
  fail "session scaling QML spawns omarchy-fabric-session-apply from an absolute bin path"
if grep -Eq 'return "omarchy-fabric-session-apply"|: "omarchy-fabric-session-apply"' "$settings_session"; then
  fail "session scaling QML must not spawn a bare omarchy-fabric-session-apply PATH name"
fi
grep -Fq '"display-monitor-scale": apply_display_monitor_scale' "$helper" ||
  fail "session apply owns display-monitor-scale"
grep -Fq '"display-monitor-scale-status": apply_display_monitor_scale_status' "$helper" ||
  fail "session apply owns display-monitor-scale-status"
grep -Fq 'display-monitor-scale' "$settings_session" || fail "session scaling QML calls display-monitor-scale"
grep -Fq 'display-monitor-scale-status' "$settings_session" || fail "session scaling QML calls display-monitor-scale-status"
grep -Fq 'function readStatus(' "$settings_session" || fail "session scaling QML exposes readStatus"
grep -Fq 'function setScale(' "$settings_session" || fail "session scaling QML exposes setScale"
if grep -Fq 'function readStatus(' "$settings_card"; then
  fail "Display scaling card must not invent a local readStatus"
fi
if grep -Fq 'function setScale(' "$settings_card"; then
  fail "Display scaling card must not invent a local setScale"
fi
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$settings_session" "$settings_card"; then
  fail "Settings Display scaling must not mint Fabric durable operations"
fi
if grep -A20 'SettingsComponents.SettingsDisplayScaling' "$settings_app" | grep -Eq 'operation\.(preflight|start|approve)|requestFabric'; then
  fail "Settings Display scaling host must not mint Fabric durable operations"
fi
if grep -Eq 'pkexec|sudo' "$settings_session" "$settings_card"; then
  fail "Settings Display scaling QML must not spawn privilege"
fi
if grep -Eq 'provider: "display.provider"|action: "scale.set"|action: "configure"' "$settings_session" "$settings_card"; then
  fail "Settings Display scaling must not invent a Fabric scale writer"
fi
if grep -Eq 'hyprctl|bash -c' "$settings_session" "$settings_card"; then
  fail "Settings Display scaling must use the session apply verb instead of a parallel hyprctl writer"
fi
if grep -Eq 'omarchy-hyprland-monitor-scaling' "$settings_session"; then
  fail "session scaling QML must not spawn omarchy-hyprland-monitor-scaling directly"
fi
grep -Fq 'SettingsComponents.SettingsDisplayScaling' "$settings_app" ||
  fail "Settings Display hosts the session scaling card"
grep -Fq 'settings.display.overview' "$settings_app" || fail "Settings still owns the Display route"
grep -Fq 'this session' "$settings_card" || fail "Settings Display scaling names the session principal"
grep -Fq 'omarchy-hyprland-monitor-scaling' "$settings_card" || fail "Settings Display scaling names the absolute helper"
grep -Fq 'session leftover recorded' "$settings_card" || fail "Settings Display scaling records a session leftover"
grep -Fq 'session-UI leftover only' "$settings_card" || fail "Settings Display scaling names session-UI leftover only"
grep -Fq 'not product CLOSED' "$settings_card" || fail "Settings Display scaling refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$settings_card" || fail "Settings Display scaling refuses metal CLOSED"
grep -Fq 'not claim=present' "$settings_card" || fail "Settings Display scaling refuses claim=present"
if grep -Eq 'CLOSED leftover:' "$settings_card"; then
  fail "Settings Display scaling must not use bare CLOSED leftover invent"
fi
if grep -Eqi 'is modern display complete|Close one product hole' "$settings_card" "$settings_app"; then
  fail "Settings Display scaling must not invent present or modern-display complete"
fi
if grep -Eqi 'claim=present' "$settings_card" "$settings_app" && ! grep -Eqi 'not claim=present' "$settings_card"; then
  fail "Settings Display scaling must not invent claim=present"
fi
if grep -Eqi 'LIVE CONTROL' "$settings_card"; then
  fail "Settings Display scaling must not invent LIVE CONTROL"
fi
if grep -Eqi 'Settings Power LIVE' "$settings_card"; then
  fail "Settings Display scaling must not invent Settings Power LIVE"
fi
grep -Fq 'sessionScaling' "$settings_model" || fail "Settings model normalizes session scaling outcomes"
grep -Fq 'omarchy-hyprland-monitor-scaling' "$settings_model" || fail "Settings coverage names the scaling helper"
grep -Fq 'does not invent a display.provider scale durable writer' "$settings_model" ||
  fail "Settings coverage refuses a Fabric scale writer"
if grep -Eqi 'scale.set|display.provider scale durable LIVE' "$display_provider" "$display_manifest"; then
  fail "display.provider invented a durable scale writer"
fi
if grep -Eq 'display-monitor-scale' "$daemon" "$display_provider"; then
  fail "Fabric durable plane invented a display-monitor-scale writer"
fi

pass "Settings Display hosts the session scaling plane instead of a Fabric LIVE writer"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-settings/SettingsModel.js')

const idle = Model.sessionScalingIdle()
assertEqual(idle.phase, 'idle', 'session scaling starts idle')
assertEqual(idle.scale, '', 'session scaling starts without a scale')
assertEqual(idle.known, false, 'session scaling starts unknown')
assertEqual(Model.sessionScalingCanSubmit('1.25'), true, '125% is allowed')
assertEqual(Model.sessionScalingCanSubmit('1.33'), false, 'arbitrary floats are refused')
assertEqual(Model.sessionScalingCanSubmit('up'), false, 'direction tokens are refused')
assertEqual(Model.sessionScalingLabel('1.25'), '125%', '1.25 labels as 125%')

const on = Model.sessionScalingFinished(idle, {
  ok: true,
  scale: '1.25',
  known: true,
  explanation: 'Applied the focused Hyprland monitor scale through this session.'
})
assertEqual(on.phase, 'succeeded', 'successful apply is succeeded')
assertEqual(on.scale, '1.25', 'successful apply keeps 1.25')
assertEqual(on.known, true, 'successful apply is known')
assertEqual(on.message, 'Applied the focused Hyprland monitor scale through this session.', 'successful apply keeps the helper explanation')

const refused = Model.sessionScalingFinished(idle, {
  ok: false,
  code: 'payload.invalid',
  explanation: 'Scale must be one of 1, 1.25, 1.6, 2, 3, or 4.'
})
assertEqual(refused.phase, 'failed', 'whitelist refuse is failed')
assertEqual(refused.code, 'payload.invalid', 'whitelist refuse keeps payload.invalid')
assertEqual(refused.known, false, 'whitelist refuse stays unknown')

const unknown = Model.sessionScalingFinished(idle, {
  ok: true,
  scale: '1.33',
  known: true,
  explanation: 'Focused Hyprland monitor scale through this session.'
})
assertEqual(unknown.phase, 'failed', 'non-whitelist helper scale is failed')
assertEqual(unknown.known, false, 'non-whitelist helper scale stays unknown')

const display = Model.queryForRoute('settings.display.overview')
assert(display.coverage.indexOf('omarchy-hyprland-monitor-scaling') >= 0, 'display coverage names the scaling helper')
assert(display.coverage.indexOf('does not invent a display.provider scale durable writer') >= 0, 'display coverage refuses a Fabric scale writer')
assert(display.coverage.indexOf('session leftover recorded') >= 0, 'display coverage records a session leftover')
assert(display.coverage.indexOf('not product CLOSED') >= 0, 'display coverage refuses product CLOSED')
assert(display.coverage.indexOf('not metal CLOSED') >= 0, 'display coverage refuses metal CLOSED')
assert(display.coverage.indexOf('not claim=present') >= 0, 'display coverage refuses claim=present')
assert(display.coverage.indexOf('Resolution, arrangement, and HDR remain unavailable') >= 0, 'display coverage still refuses HDR and arrangement')
assert(display.coverage.indexOf('not modern display complete') >= 0, 'display coverage refuses modern-display complete')
assert(Model.declaredOpsHonesty('settings.display.overview').indexOf('omarchy-hyprland-monitor-scaling') >= 0, 'display declared ops name the scaling helper')
assert(Model.declaredOpsHonesty('settings.display.overview').indexOf('does not invent a display.provider scale durable writer') >= 0, 'display declared ops refuse a Fabric scale writer')
assert(Model.authorityFooter().indexOf('omarchy-hyprland-monitor-scaling') >= 0, 'authority footer names the scaling helper')
JS

pass "Settings model maps session scaling outcomes and refuses a Fabric invent"

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


def run_set(payload, runner=None):
    stream = io.StringIO()
    status = sa.apply_display_monitor_scale(
        io.StringIO(json.dumps(payload)),
        stream,
        run=runner or (lambda *args, **kwargs: Result()),
    )
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


def run_status(payload, runner=None):
    stream = io.StringIO()
    status = sa.apply_display_monitor_scale_status(
        io.StringIO(json.dumps(payload)),
        stream,
        run=runner or (lambda *args, **kwargs: Result(stdout="1.25\n")),
    )
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


if "display-monitor-scale" not in sa.ACTIONS:
    failures.append("session apply ACTIONS omitted display-monitor-scale")
if "display-monitor-scale-status" not in sa.ACTIONS:
    failures.append("session apply ACTIONS omitted display-monitor-scale-status")

helper = sa.monitor_scaling_helper()
check("helper prefers OMARCHY_PATH", helper == "/workspace/bin/omarchy-hyprland-monitor-scaling", helper)
check("helper is absolute", helper.startswith("/"), helper)

status, result = run_set({})
check("empty payload is refused first", status == 1 and result.get("ok") is False, str(result))
check("empty payload uses payload.invalid", result.get("code") == "payload.invalid", str(result))
check("empty payload uses the fixed whitelist explanation", result.get("explanation") == sa.MONITOR_SCALING_REFUSE, str(result))

status, result = run_set({"scale": "1.33"})
check("arbitrary float string is refused first", status == 1 and result.get("ok") is False, str(result))
check("arbitrary float string uses payload.invalid", result.get("code") == "payload.invalid", str(result))
check("arbitrary float string uses the fixed explanation", result.get("explanation") == sa.MONITOR_SCALING_REFUSE, str(result))
check("arbitrary float string is not echoed", "1.33" not in json.dumps(result), str(result))

status, result = run_set({"scale": 1.33})
check("arbitrary JSON float is refused", status == 1 and result.get("code") == "payload.invalid", str(result))
check("arbitrary JSON float is not echoed", "1.33" not in json.dumps(result), str(result))

status, result = run_set({"scale": "up"})
check("direction token is refused", status == 1 and result.get("code") == "payload.invalid", str(result))
check("direction token is not echoed", "up" not in json.dumps(result), str(result))

secret_payload = {"scale": "1.25", "password": "hunter2"}
status, result = run_set(secret_payload)
check("credential keys are refused", status == 1 and result.get("ok") is False, str(result))
check("credential keys use payload.invalid", result.get("code") == "payload.invalid", str(result))
check("credential refuse does not leak secrets", "hunter2" not in json.dumps(result), str(result))

ok_calls = []


def ok_run(argv, **kwargs):
    ok_calls.append(list(argv))
    return Result()


status, result = run_set({"scale": "1.25"}, ok_run)
check("mocked 125% apply succeeds after refuse", status == 0 and result.get("ok") is True, str(result))
check("mocked 125% apply keeps scale", result.get("scale") == "1.25", str(result))
check("mocked 125% apply names this session", "this session" in str(result.get("explanation") or ""), str(result))
check(
    "mocked 125% apply uses the absolute helper",
    ok_calls == [[helper, "1.25"]],
    str(ok_calls),
)

int_calls = []


def int_run(argv, **kwargs):
    int_calls.append(list(argv))
    return Result()


status, result = run_set({"scale": 2}, int_run)
check("JSON integer 2 is accepted", status == 0 and result.get("scale") == "2", str(result))
check("JSON integer 2 uses the absolute helper", int_calls == [[helper, "2"]], str(int_calls))


def missing_command_run(argv, **kwargs):
    raise FileNotFoundError(argv[0])


status, result = run_set({"scale": "1.25"}, missing_command_run)
check("missing helper is command.unavailable", status == 1 and result.get("code") == "command.unavailable", str(result))

status, result = run_status({})
check("status read succeeds after refuse", status == 0 and result.get("ok") is True, str(result))
check("status read keeps 1.25", result.get("scale") == "1.25", str(result))
check("status read is known", result.get("known") is True, str(result))

status, result = run_status({"password": "hunter2"})
check("status extra keys are refused", status == 1 and result.get("code") == "payload.invalid", str(result))
check("status extra keys do not leak secrets", "hunter2" not in json.dumps(result), str(result))

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session scaling reports success and honest whitelist refuse"

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
scale = by_id["display.scale.set"]
route = scale["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"display.scale.set route is {route}")
if route.get("path") != "Settings > Display":
    raise SystemExit(f"display.scale.set path is {route}")
if "Settings > Display" not in str(route.get("path") or ""):
    raise SystemExit(f"display.scale.set underclaims the Settings Display host: {route}")
if scale.get("source", {}).get("file") != "bin/omarchy-hyprland-monitor-scaling":
    raise SystemExit(f"display.scale.set source is {scale.get('source')}")
if scale.get("source", {}).get("symbol") != "omarchy-hyprland-monitor-scaling":
    raise SystemExit(f"display.scale.set source is {scale.get('source')}")
if "SettingsDisplayScaling.qml" in str(scale.get("source", {}).get("file") or ""):
    raise SystemExit("display.scale.set must not invent source on SettingsDisplayScaling.qml")
if scale.get("availability", {}).get("claim") == "present":
    raise SystemExit("display.scale.set must not claim present")
if scale.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"display.scale.set claim is {scale.get('availability')}")
if scale.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"display.scale.set human availability is {scale.get('availability')}")
if scale.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"display.scale.set agent availability is {scale.get('availability')}")
if scale.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"display.scale.set was raised off leftover: {scale.get('provider')}")
if scale.get("provider", {}).get("id") != "display.provider":
    raise SystemExit(f"display.scale.set provider is {scale.get('provider')}")

by_job = {job["id"]: job for job in jobs["jobs"]}
parity_display = by_job["parity.display"]
if parity_display.get("claim") == "present":
    raise SystemExit("parity.display must not claim present")
if "display.scale.set" not in (parity_display.get("capabilityIds") or []):
    raise SystemExit("parity.display dropped display.scale.set")
modern = by_job["parity.modern-display-scaling-hdr-night-light"]
if modern.get("claim") == "present":
    raise SystemExit("parity.modern-display-scaling-hdr-night-light must not claim present")
if modern.get("claim") != "prototype":
    raise SystemExit(f"parity.modern-display-scaling-hdr-night-light claim is {modern.get('claim')}")
if "display.scale.set" not in (modern.get("capabilityIds") or []):
    raise SystemExit("parity.modern-display-scaling-hdr-night-light dropped display.scale.set")
modern_recovery = str(modern.get("recoveryExpectation") or "")
if "timed" in modern_recovery.lower() and "no timed" not in modern_recovery.lower():
    raise SystemExit(f"parity.modern-display invents timed rollback: {modern_recovery}")
if "unless" in modern_recovery.lower() and "kept" in modern_recovery.lower():
    raise SystemExit(f"parity.modern-display invents keep-prompt rollback: {modern_recovery}")
if "no timed auto-rollback" not in modern_recovery:
    raise SystemExit(f"parity.modern-display recoveryExpectation dropped no timed auto-rollback: {modern_recovery}")
if modern["humanRoute"].get("status") != "visible":
    raise SystemExit(f"parity.modern-display underclaims a visible route: {modern.get('humanRoute')}")
if "Settings > Display" not in str(modern["humanRoute"].get("path") or ""):
    raise SystemExit(f"parity.modern-display underclaims Settings > Display: {modern.get('humanRoute')}")
if str(modern["humanRoute"].get("path") or "") == "Superbar > Display":
    raise SystemExit(f"parity.modern-display invents Superbar-only scaling: {modern.get('humanRoute')}")
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
if native3["humanRoute"].get("status") != "visible":
    raise SystemExit(f"windows-native.3 route is {native3.get('humanRoute')}")
if native3["humanRoute"].get("path") != "Settings > Display":
    raise SystemExit(f"windows-native.3 path is {native3.get('humanRoute')}")
native3_recovery = str(native3.get("recoveryExpectation") or "")
if "timed" in native3_recovery.lower() and "no timed" not in native3_recovery.lower():
    raise SystemExit(f"windows-native.3 invents timed rollback: {native3_recovery}")
if "unless" in native3_recovery.lower() and "kept" in native3_recovery.lower():
    raise SystemExit(f"windows-native.3 invents keep-prompt rollback: {native3_recovery}")
if "no timed auto-rollback" not in native3_recovery:
    raise SystemExit(f"windows-native.3 recoveryExpectation dropped no timed auto-rollback: {native3_recovery}")
if "Settings > Display" not in native3_recovery:
    raise SystemExit(f"windows-native.3 recoveryExpectation dropped Settings > Display: {native3_recovery}")

by_debt = {entry["id"]: entry for entry in debt["entries"]}
legacy = by_debt["legacy.domain.direct-providers"]
if "display.scale.set" not in legacy.get("capabilityIds", []):
    raise SystemExit("display.scale.set is not leftover-direct debt")
if "capability:display.scale.set" not in legacy.get("surfaceRefs", []):
    raise SystemExit("display.scale.set leftover surfaceRef is missing")
agent = by_debt["missing.agent.routes"]
if "display.scale.set" not in agent.get("capabilityIds", []):
    raise SystemExit("display.scale.set left missing.agent.routes")

if "Honesty addendum 2026-09-06 vs Settings Display scaling" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must add a dated Settings Display scaling addendum")
addendum = gaps.split("Honesty addendum 2026-09-06 vs Settings Display scaling", 1)[1].split("Honesty addendum", 1)[0]
if "CLOSED leftover:" in addendum:
    raise SystemExit("fleet-doctrine-gaps must not use bare CLOSED leftover invent for scaling")
for required in (
    "session leftover recorded",
    "session-UI leftover only",
    "not product CLOSED",
    "not metal CLOSED",
    "not claim=present",
    "Settings > Display",
    "display.scale.set",
    "legacy-direct",
    "omarchy-hyprland-monitor-scaling",
    "display-monitor-scale",
    "Cloud EXIT 0 is not metal leftover CLOSED",
    "Cloud mocks do not close windows-native.3",
    "windows-native.3",
    "Settings Power LIVE",
    "HDR",
):
    if required not in addendum:
        raise SystemExit(f"fleet-doctrine-gaps scaling addendum dropped required honesty: {required}")
if "Do not walk `windows-native.3` to present" not in addendum and "Do not walk windows-native.3 to present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse walking windows-native.3 to present")
if "Do not invent claim=present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse claim=present invent")
if "Do not walk `parity.modern-display-scaling-hdr-night-light` to present" not in addendum and "Do not walk parity.modern-display-scaling-hdr-night-light to present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse walking modern-display to present")
if "| `windows-native.3` | prototype/pending | visible: Settings > Display |" not in gaps:
    raise SystemExit("fleet-doctrine-gaps invent-mode must keep windows-native.3 visible Settings > Display")
if "metal CLOSED from Cloud EXIT 0" not in gaps.split("`windows-native.3`", 1)[1].split("`windows-native.4`", 1)[0]:
    raise SystemExit("fleet-doctrine-gaps invent-mode for windows-native.3 must include metal CLOSED from Cloud EXIT 0")
if "session leftover recorded" not in parity:
    raise SystemExit("PARITY Display row must record the session leftover")
if "display.scale.set" not in parity:
    raise SystemExit("PARITY Display row must name display.scale.set")
if "does not invent a `display.provider` scale durable writer" not in parity and "does not invent a display.provider scale" not in parity:
    raise SystemExit("PARITY Display row must refuse a Fabric scale invent")
if "windows-native.3` stays prototype/pending" not in parity and "windows-native.3` stays pending" not in parity and "windows-native.3 stays prototype/pending" not in parity:
    raise SystemExit("PARITY Display row must keep windows-native.3 pending")
if "Cloud mocks do not close windows-native.3" not in parity:
    raise SystemExit("PARITY Display row must refuse Cloud mocks closing windows-native.3")
if "display.scale.set" not in settings_api:
    raise SystemExit("settings-service-api must name display.scale.set")
if "windows-native.3" not in settings_api:
    raise SystemExit("settings-service-api must keep windows-native.3 pending")
if "session leftover recorded" not in settings_api:
    raise SystemExit("settings-service-api must record the session leftover")
if "display-monitor-scale" not in settings_api:
    raise SystemExit("settings-service-api must name display-monitor-scale")
if "display-monitor-scale" not in handoff:
    raise SystemExit("HANDOFF must name display-monitor-scale")
if "session leftover recorded" not in handoff:
    raise SystemExit("HANDOFF must record the session leftover")
if "Cloud mocks do not close windows-native.3" not in handoff:
    raise SystemExit("HANDOFF must refuse Cloud mocks closing windows-native.3")
PY

pass "display.scale.set stays leftover partial with visible Settings Display route"
