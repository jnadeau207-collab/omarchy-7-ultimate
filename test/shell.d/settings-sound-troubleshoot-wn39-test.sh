#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

settings_app="$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml"
settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
settings_card="$ROOT/shell/apps/ultimate-settings/SettingsSound.qml"
settings_session="$ROOT/shell/apps/shared/SettingsSessionSound.qml"
helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
restart_bin="$ROOT/bin/omarchy-restart-audio"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
debt="$ROOT/default/ultimate/capabilities/legacy-debt-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
settings_api="$ROOT/docs/settings-service-api.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
audio_provider="$ROOT/default/fabric/omarchy_fabric/providers/audio/provider.py"
daemon="$ROOT/default/fabric/omarchy_fabric/daemon.py"

[[ -f $settings_app ]] || fail "Settings application exists"
[[ -f $settings_model ]] || fail "Settings model exists"
[[ -f $settings_session ]] || fail "Settings hosts a session Sound plane"
[[ -f $settings_card ]] || fail "Settings ships a Sound card"
[[ -f $helper ]] || fail "session apply helper exists"
[[ -f $restart_bin ]] || fail "tip-true omarchy-restart-audio exists"

grep -Fq 'omarchy-fabric-session-apply' "$settings_session" ||
  fail "session Sound QML uses the session apply helper"
grep -Fq 'OMARCHY_PATH' "$settings_session" || fail "session Sound QML prefers OMARCHY_PATH"
grep -Fq '/bin/omarchy-fabric-session-apply' "$settings_session" ||
  fail "session Sound QML spawns omarchy-fabric-session-apply from an absolute bin path"
if grep -Eq 'return "omarchy-fabric-session-apply"|: "omarchy-fabric-session-apply"' "$settings_session"; then
  fail "session Sound QML must not spawn a bare omarchy-fabric-session-apply PATH name"
fi
grep -Fq '"audio-troubleshoot-restart": apply_audio_troubleshoot_restart' "$helper" ||
  fail "session apply owns audio-troubleshoot-restart"
grep -Fq 'audio-troubleshoot-restart' "$settings_session" || fail "session Sound QML calls audio-troubleshoot-restart"
grep -Fq 'function restartAudio(' "$settings_session" || fail "session Sound QML exposes restartAudio"
if grep -Fq 'function restartAudio(' "$settings_card"; then
  fail "Sound card must not invent a local restartAudio"
fi
grep -Fq 'function applyTroubleshoot(' "$settings_card" || fail "Sound card exposes applyTroubleshoot"
grep -Fq 'Restart audio services' "$settings_card" || fail "Sound card hosts Restart audio services"
grep -Fq 'omarchy-restart-audio' "$settings_card" || fail "Sound card names tip-true omarchy-restart-audio"
grep -Fq 'session leftover recorded' "$settings_card" || fail "Settings Sound records a session leftover"
grep -Fq 'session-UI leftover only' "$settings_card" || fail "Settings Sound names session-UI leftover only"
grep -Fq 'not product CLOSED' "$settings_card" || fail "Settings Sound refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$settings_card" || fail "Settings Sound refuses metal CLOSED"
grep -Fq 'not claim=present' "$settings_card" || fail "Settings Sound refuses claim=present"
grep -Fq 'OPEN leftover' "$settings_card" || fail "Settings Sound names port/wizard OPEN leftover"
grep -Fq 'windows-native.39 stays prototype/pending' "$settings_card" ||
  fail "Settings Sound keeps windows-native.39 prototype/pending"
grep -Fq 'windows-native.6 stays pending' "$settings_card" || fail "Settings Sound keeps windows-native.6 pending"
if grep -Eq 'CLOSED leftover:' "$settings_card"; then
  fail "Settings Sound must not use bare CLOSED leftover invent"
fi
if grep -Eqi 'is Sound complete|Close one product hole' "$settings_card" "$settings_app"; then
  fail "Settings Sound must not invent present or Sound product-complete"
fi
if grep -Eqi 'Sound product-complete' "$settings_card" "$settings_app" && ! grep -Eqi 'not Sound product-complete' "$settings_card"; then
  fail "Settings Sound must not invent Sound product-complete"
fi
if grep -Eqi 'claim=present' "$settings_card" "$settings_app" && ! grep -Eqi 'not claim=present' "$settings_card"; then
  fail "Settings Sound must not invent claim=present"
fi
if grep -Eqi 'LIVE CONTROL' "$settings_card"; then
  fail "Settings Sound troubleshoot must not invent LIVE CONTROL"
fi
if grep -Eqi 'Settings Power LIVE|Empty Bin LIVE|End Task LIVE|Open With' "$settings_card"; then
  fail "Settings Sound must not invent unrelated LIVE surfaces"
fi
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$settings_session" "$settings_card"; then
  fail "Settings Sound troubleshoot must not mint Fabric durable operations"
fi
if grep -A30 'SettingsComponents.SettingsSound' "$settings_app" | grep -Eq 'operation\.(preflight|start|approve)|requestFabric'; then
  fail "Settings Sound troubleshoot host must not mint Fabric durable operations"
fi
if grep -Eq 'pkexec|sudo' "$settings_session" "$settings_card"; then
  fail "Settings Sound troubleshoot QML must not spawn privilege"
fi
if grep -Eq 'provider: "audio.provider"|provider: "troubleshooting.provider"|action: "troubleshoot|"troubleshoot\.run"' "$settings_session" "$settings_card"; then
  fail "Settings Sound troubleshoot must not invent a Fabric troubleshoot writer"
fi
if grep -Eq 'bash -c|wpctl|systemctl|omarchy-restart-audio' "$settings_session"; then
  fail "session Sound QML must use the session apply verb instead of a parallel restart shell writer"
fi
if grep -Eq 'command:[[:space:]]*\[.*(bash|systemctl|wpctl|omarchy-restart-audio)' "$settings_card"; then
  fail "Sound card must not spawn restart tools directly"
fi
grep -Fq 'audio-troubleshoot-restart' "$settings_model" || fail "Settings coverage names the session troubleshoot verb"
grep -Fq 'windows-native.39 stays prototype/pending' "$settings_model" ||
  fail "Settings coverage keeps windows-native.39 prototype/pending"
grep -Fq 'does not invent a troubleshooting.provider or audio.provider troubleshoot durable writer' "$settings_model" ||
  fail "Settings coverage refuses a Fabric troubleshoot writer"
if grep -Eq 'audio-troubleshoot-restart' "$daemon"; then
  fail "Fabric durable plane invented a session Sound troubleshoot writer"
fi
if grep -Eqi 'troubleshooting.provider|output-troubleshoot|troubleshoot\.run' "$audio_provider"; then
  fail "audio.provider invented a durable LIVE troubleshoot claim"
fi
grep -Fq 'def audio_restart_helper' "$helper" || fail "session apply exposes audio_restart_helper"
grep -Fq 'return "/usr/bin/omarchy-restart-audio"' "$helper" || fail "session apply pins absolute /usr/bin/omarchy-restart-audio"
grep -Fq 'Audio restart refuses appended arguments' "$helper" || fail "session apply refuses appended restart argv"

pass "Settings Sound hosts the session audio troubleshoot restart plane instead of a Fabric LIVE writer"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-settings/SettingsModel.js')

const idle = Model.sessionSoundIdle()
const accepted = Model.sessionSoundAccepted(idle, 'troubleshoot')
assertEqual(accepted.phase, 'busy', 'troubleshoot accept is busy')
assertEqual(accepted.action, 'troubleshoot', 'troubleshoot accept keeps action')

const goodId = 'audio.sink.' + 'a'.repeat(64)
const sinks = [
  { resourceId: goodId, label: 'Speakers', muted: false, default: true }
]
const on = Model.sessionSoundFinished(accepted, {
  ok: true,
  sinks: sinks,
  defaultResourceId: goodId,
  known: true,
  restarted: true,
  explanation: 'Restarted audio services through this session.'
})
assertEqual(on.phase, 'succeeded', 'successful troubleshoot is succeeded')
assertEqual(on.action, 'troubleshoot', 'successful troubleshoot keeps action')
assertEqual(on.known, true, 'successful troubleshoot is known')

const refused = Model.sessionSoundFinished(accepted, {
  ok: false,
  code: 'payload.invalid',
  explanation: 'stdin JSON for audio troubleshoot restart must be empty; this session leftover refuses extra keys'
})
assertEqual(refused.phase, 'failed', 'whitelist refuse is failed')
assertEqual(refused.code, 'payload.invalid', 'whitelist refuse keeps payload.invalid')

const audio = Model.queryForRoute('settings.audio.overview')
assert(audio.coverage.indexOf('audio-troubleshoot-restart') >= 0, 'audio coverage names the session troubleshoot verb')
assert(audio.coverage.indexOf('omarchy-restart-audio') >= 0, 'audio coverage names tip-true restart bin')
assert(audio.coverage.indexOf('troubleshooting.audio.run') >= 0, 'audio coverage soft leftover-attaches troubleshooting.audio.run')
assert(audio.coverage.indexOf('OPEN leftover') >= 0, 'audio coverage names OPEN leftover')
assert(audio.coverage.indexOf('session leftover recorded') >= 0, 'audio coverage records a session leftover')
assert(audio.coverage.indexOf('not product CLOSED') >= 0, 'audio coverage refuses product CLOSED')
assert(audio.coverage.indexOf('not metal CLOSED') >= 0, 'audio coverage refuses metal CLOSED')
assert(audio.coverage.indexOf('not claim=present') >= 0, 'audio coverage refuses claim=present')
assert(audio.coverage.indexOf('windows-native.39 stays prototype/pending') >= 0, 'audio coverage keeps wn.39 pending')
assert(audio.coverage.indexOf('windows-native.6 stays pending') >= 0, 'audio coverage keeps wn.6 pending')
assert(Model.declaredOpsHonesty('settings.audio.overview').indexOf('audio-troubleshoot-restart') >= 0, 'audio declared ops name troubleshoot')
assert(Model.declaredOpsHonesty('settings.audio.overview').indexOf('does not invent') >= 0, 'audio declared ops refuse Fabric invent')
assert(Model.authorityFooter().indexOf('audio troubleshoot restart') >= 0, 'authority footer names session Sound troubleshoot')
JS

pass "Settings model maps session Sound troubleshoot outcomes and refuses a Fabric invent"

cd "$ROOT/default/fabric"
OMARCHY_PATH="$ROOT" PYTHONPATH="$ROOT/default/fabric" PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import hashlib
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


SPEAKERS = "alsa_output.pci-0000_00_1f.3.analog-stereo"
SPEAKERS_ID = "audio.sink." + hashlib.sha256(f"audio\0{SPEAKERS}".encode()).hexdigest()
SINKS = json.dumps(
    [
        {"name": SPEAKERS, "description": "Built-in Speakers", "mute": False},
    ]
)

expected_helper = str(pathlib.Path(os.environ["OMARCHY_PATH"]) / "bin" / "omarchy-restart-audio")


def run_restart(payload, runner=None):
    stream = io.StringIO()
    status = sa.apply_audio_troubleshoot_restart(
        io.StringIO(json.dumps(payload)),
        stream,
        run=runner or default_run,
    )
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


def default_run(argv, **kwargs):
    if argv == [expected_helper]:
        return Result(stdout="Restarting audio services...\n")
    if argv[:3] == [sa.PACTL, "--format=json", "list"] and argv[3:] == ["sinks"]:
        return Result(stdout=SINKS)
    if argv[:2] == [sa.PACTL, "get-default-sink"]:
        return Result(stdout=SPEAKERS + "\n")
    raise AssertionError(argv)


if "audio-troubleshoot-restart" not in sa.ACTIONS:
    failures.append("session apply ACTIONS omitted audio-troubleshoot-restart")

omarchy_path = str(pathlib.Path(expected_helper).parents[1])
os.environ["OMARCHY_PATH"] = omarchy_path
helper = sa.audio_restart_helper()
check("helper prefers OMARCHY_PATH restart bin", helper == expected_helper, helper)
check("helper is absolute", helper.startswith("/"), helper)

os.environ.pop("OMARCHY_PATH", None)
fallback = sa.audio_restart_helper()
check("fallback helper is absolute /usr/bin/omarchy-restart-audio", fallback == "/usr/bin/omarchy-restart-audio", fallback)
os.environ["OMARCHY_PATH"] = omarchy_path

status, result = run_restart({"password": "hunter2"})
check("credential keys are refused", status == 1 and result.get("code") == "payload.invalid", str(result))
check("credential refuse does not leak secrets", "hunter2" not in json.dumps(result), str(result))
check("refused restart does not claim restarted", result.get("restarted") is False, str(result))

status, result = run_restart({"extra": True})
check("extra keys are refused", status == 1 and result.get("code") == "payload.invalid", str(result))

ok_calls = []


def ok_run(argv, **kwargs):
    ok_calls.append(list(argv))
    return default_run(argv, **kwargs)


status, result = run_restart({}, ok_run)
check("mocked restart succeeds after refuse", status == 0 and result.get("ok") is True, str(result))
check("mocked restart sets restarted", result.get("restarted") is True, str(result))
check("mocked restart names this session", "this session" in str(result.get("explanation") or ""), str(result))
check(
    "mocked restart uses absolute FixedArgv restart bin only",
    [expected_helper] in ok_calls and all(len(call) == 1 for call in ok_calls if call and call[0] == expected_helper),
    str(ok_calls),
)
check("mocked restart refreshes tip-true sink", any(row.get("resourceId") == SPEAKERS_ID for row in result.get("sinks") or []), str(result))
check("mocked restart public sinks omit raw names", all("name" not in row for row in result.get("sinks") or []), str(result))


def appended_run(argv, **kwargs):
    if argv and argv[0] == expected_helper and len(argv) != 1:
        raise AssertionError("helper must refuse appended argv before spawn")
    return default_run(argv, **kwargs)


try:
    sa.run_audio_restart([expected_helper, "--force"], appended_run)
    failures.append("run_audio_restart accepted appended arguments")
except sa.ApplyError as error:
    check("appended argv uses payload.invalid", error.code == "payload.invalid", error.code)


def relative_run(argv, **kwargs):
    raise AssertionError(argv)


try:
    sa.run_audio_restart(["omarchy-restart-audio"], relative_run)
    failures.append("run_audio_restart accepted a relative path")
except sa.ApplyError as error:
    check("relative path uses command.unavailable", error.code == "command.unavailable", error.code)


def missing_command_run(argv, **kwargs):
    raise FileNotFoundError(argv[0])


status, result = run_restart({}, missing_command_run)
check("missing helper is command.unavailable", status == 1 and result.get("code") == "command.unavailable", str(result))


def failing_restart_run(argv, **kwargs):
    if argv == [expected_helper]:
        return Result(returncode=1, stdout="Audio services are still not responding.\n")
    return default_run(argv, **kwargs)


status, result = run_restart({}, failing_restart_run)
check("failed restart is apply.failed", status == 1 and result.get("code") == "apply.failed", str(result))
check("failed restart does not claim restarted", result.get("restarted") is False, str(result))

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session Sound troubleshoot reports success and honest FixedArgv refuse"

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
troubleshoot = by_id["troubleshooting.audio.run"]
route = troubleshoot["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"troubleshooting.audio.run route is {route}")
if route.get("path") != "Settings > Sound":
    raise SystemExit(f"troubleshooting.audio.run path is {route}")
if troubleshoot.get("source", {}).get("file") != "default/fabric/omarchy_fabric/helpers/session_apply.py":
    raise SystemExit(f"troubleshooting.audio.run source is {troubleshoot.get('source')}")
if troubleshoot.get("source", {}).get("symbol") != "apply_audio_troubleshoot_restart":
    raise SystemExit(f"troubleshooting.audio.run source is {troubleshoot.get('source')}")
if "SettingsSound.qml" in str(troubleshoot.get("source", {}).get("file") or ""):
    raise SystemExit("troubleshooting.audio.run must not invent source on SettingsSound.qml")
if troubleshoot.get("availability", {}).get("claim") == "present":
    raise SystemExit("troubleshooting.audio.run must not claim present")
if troubleshoot.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"troubleshooting.audio.run claim is {troubleshoot.get('availability')}")
if troubleshoot.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"troubleshooting.audio.run human is {troubleshoot.get('availability')}")
if troubleshoot.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"troubleshooting.audio.run was raised off leftover: {troubleshoot.get('provider')}")
troubleshoot_recovery = troubleshoot.get("recovery") or {}
if troubleshoot_recovery.get("mode") == "compensating" or troubleshoot_recovery.get("stateFingerprintRequired") is True:
    raise SystemExit(f"troubleshooting.audio.run recovery still invents compensating fingerprint: {troubleshoot_recovery}")
if troubleshoot_recovery.get("mode") != "none" or troubleshoot_recovery.get("stateFingerprintRequired") is not False:
    raise SystemExit(f"troubleshooting.audio.run recovery is not tip-true session leftover: {troubleshoot_recovery}")
troubleshoot_expectation = str(troubleshoot_recovery.get("expectation") or "")
if "omarchy-restart-audio" not in troubleshoot_expectation or "FixedArgv" not in troubleshoot_expectation:
    raise SystemExit(f"troubleshooting.audio.run recovery expectation not tip-true FixedArgv restart: {troubleshoot_expectation}")
if "fingerprint" in troubleshoot_expectation.lower() and "no compensating fingerprint" not in troubleshoot_expectation.lower():
    raise SystemExit(f"troubleshooting.audio.run recovery invents fingerprint path: {troubleshoot_expectation}")
if "compensating" in troubleshoot_expectation.lower() and "no compensating" not in troubleshoot_expectation.lower():
    raise SystemExit(f"troubleshooting.audio.run recovery invents compensating path: {troubleshoot_expectation}")
manage = by_id["audio.output.manage"]
if manage.get("availability", {}).get("claim") == "present":
    raise SystemExit("audio.output.manage must not claim present")
native39 = next(row for row in jobs["jobs"] if row["id"] == "windows-native.39")
if native39.get("sourceStatus") != "pending" or native39.get("claim") != "prototype":
    raise SystemExit(f"windows-native.39 must stay prototype/pending: {native39}")
if native39.get("humanRoute", {}).get("path") != "Settings > Sound":
    raise SystemExit(f"windows-native.39 underclaims Settings Sound: {native39.get('humanRoute')}")
native39_recovery = str(native39.get("recoveryExpectation") or "")
if native39_recovery != "Session audio restart applies immediately through tip-true omarchy-restart-audio; port changes and the full troubleshoot wizard remain OPEN leftover with no cancel/restore invent.":
    raise SystemExit(f"windows-native.39 recoveryExpectation drifted: {native39_recovery}")
if "cancel/restore invent" not in native39_recovery or "OPEN leftover" not in native39_recovery:
    raise SystemExit(f"windows-native.39 recoveryExpectation dropped leftover refuse: {native39_recovery}")
if "troubleshooting.audio.run" not in (native39.get("capabilityIds") or []):
    raise SystemExit("windows-native.39 dropped troubleshooting.audio.run")
native6 = next(row for row in jobs["jobs"] if row["id"] == "windows-native.6")
if native6.get("sourceStatus") != "pending" or native6.get("claim") != "prototype":
    raise SystemExit(f"windows-native.6 must stay prototype/pending: {native6}")
if "session leftover recorded" not in parity or "audio-troubleshoot-restart" not in parity:
    raise SystemExit("parity must record Settings Sound audio troubleshoot session leftover")
if "windows-native.39" not in parity or "prototype/pending" not in parity:
    raise SystemExit("parity must keep windows-native.39 prototype/pending")
if "OPEN leftover" not in parity:
    raise SystemExit("parity must name port/wizard OPEN leftover")
if "claim=present" in parity and "not claim=present" not in parity:
    raise SystemExit("parity must not invent claim=present for Sound")
if "audio-troubleshoot-restart" not in settings_api or "omarchy-restart-audio" not in settings_api:
    raise SystemExit("settings-service-api must name session Sound troubleshoot verbs")
if "not product CLOSED" not in settings_api or "not metal CLOSED" not in settings_api:
    raise SystemExit("settings-service-api must refuse product/metal CLOSED for Sound leftover")
if "audio-troubleshoot-restart" not in handoff or "windows-native.39" not in handoff:
    raise SystemExit("handoff must record session Sound troubleshoot leftover")
if "troubleshooting.audio.run" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep troubleshooting.audio.run honesty")
if "windows-native.39" not in gaps or "prototype/pending" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.39 pending")
if "troubleshooting.audio.run" not in json.dumps(debt):
    raise SystemExit("legacy-debt must keep troubleshooting.audio.run")
print("catalog and honesty pins ok")
PY

pass "catalog and honesty keep Sound troubleshoot leftover-direct without claim=present"
