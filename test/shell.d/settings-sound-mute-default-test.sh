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
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
debt="$ROOT/default/ultimate/capabilities/legacy-debt-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
settings_api="$ROOT/docs/settings-service-api.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
audio_provider="$ROOT/default/fabric/omarchy_fabric/providers/audio/provider.py"
audio_manifest="$ROOT/default/fabric/omarchy_fabric/providers/audio/manifest-v0.json"
daemon="$ROOT/default/fabric/omarchy_fabric/daemon.py"

[[ -f $settings_app ]] || fail "Settings application exists"
[[ -f $settings_model ]] || fail "Settings model exists"
[[ -f $settings_session ]] || fail "Settings hosts a session Sound plane"
[[ -f $settings_card ]] || fail "Settings ships a Sound mute/default card"
[[ -f $helper ]] || fail "session apply helper exists"

grep -Fq 'omarchy-fabric-session-apply' "$settings_session" ||
  fail "session Sound QML uses the session apply helper"
grep -Fq 'OMARCHY_PATH' "$settings_session" || fail "session Sound QML prefers OMARCHY_PATH"
grep -Fq '/bin/omarchy-fabric-session-apply' "$settings_session" ||
  fail "session Sound QML spawns omarchy-fabric-session-apply from an absolute bin path"
if grep -Eq 'return "omarchy-fabric-session-apply"|: "omarchy-fabric-session-apply"' "$settings_session"; then
  fail "session Sound QML must not spawn a bare omarchy-fabric-session-apply PATH name"
fi
grep -Fq '"audio-output-status": apply_audio_output_status' "$helper" ||
  fail "session apply owns audio-output-status"
grep -Fq '"audio-output-mute-set": apply_audio_output_mute_set' "$helper" ||
  fail "session apply owns audio-output-mute-set"
grep -Fq '"audio-output-default-set": apply_audio_output_default_set' "$helper" ||
  fail "session apply owns audio-output-default-set"
grep -Fq 'audio-output-status' "$settings_session" || fail "session Sound QML calls audio-output-status"
grep -Fq 'audio-output-mute-set' "$settings_session" || fail "session Sound QML calls audio-output-mute-set"
grep -Fq 'audio-output-default-set' "$settings_session" || fail "session Sound QML calls audio-output-default-set"
grep -Fq 'function readStatus(' "$settings_session" || fail "session Sound QML exposes readStatus"
grep -Fq 'function setMuted(' "$settings_session" || fail "session Sound QML exposes setMuted"
grep -Fq 'function setDefault(' "$settings_session" || fail "session Sound QML exposes setDefault"
if grep -Fq 'function readStatus(' "$settings_card"; then
  fail "Sound card must not invent a local readStatus"
fi
if grep -Fq 'function setMuted(' "$settings_card"; then
  fail "Sound card must not invent a local setMuted"
fi
if grep -Fq 'function setDefault(' "$settings_card"; then
  fail "Sound card must not invent a local setDefault"
fi
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$settings_session" "$settings_card"; then
  fail "Settings Sound mute/default must not mint Fabric durable operations"
fi
if grep -A20 'SettingsComponents.SettingsSound' "$settings_app" | grep -Eq 'operation\.(preflight|start|approve)|requestFabric'; then
  fail "Settings Sound mute/default host must not mint Fabric durable operations"
fi
if grep -Eq 'pkexec|sudo' "$settings_session" "$settings_card"; then
  fail "Settings Sound mute/default QML must not spawn privilege"
fi
if grep -Eq 'provider: "audio.provider"|action: "output-mute|action: "default-sink|"mute\.set"|"default\.set"' "$settings_session" "$settings_card"; then
  fail "Settings Sound mute/default must not invent a Fabric mute/default writer"
fi
if grep -Eq 'pactl|bash -c|wpctl|omarchy-audio-output' "$settings_session"; then
  fail "session Sound QML must use the session apply verb instead of a parallel pactl writer"
fi
if grep -Eq 'command:[[:space:]]*\[.*pactl|["'\'']pactl["'\'']' "$settings_card"; then
  fail "Sound card must not spawn pactl directly"
fi
grep -Fq 'SettingsComponents.SettingsSound' "$settings_app" ||
  fail "Settings Sound hosts the session mute/default card"
grep -Fq 'settings.audio.overview' "$settings_app" || fail "Settings still owns the Sound route"
grep -Fq 'this session' "$settings_card" || fail "Settings Sound names the session principal"
grep -Fq '/usr/bin/pactl' "$settings_card" || fail "Settings Sound names the absolute helper"
grep -Fq 'session leftover recorded' "$settings_card" || fail "Settings Sound records a session leftover"
grep -Fq 'session-UI leftover only' "$settings_card" || fail "Settings Sound names session-UI leftover only"
grep -Fq 'not product CLOSED' "$settings_card" || fail "Settings Sound refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$settings_card" || fail "Settings Sound refuses metal CLOSED"
grep -Fq 'not claim=present' "$settings_card" || fail "Settings Sound refuses claim=present"
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
  fail "Settings Sound mute/default must not invent LIVE CONTROL"
fi
if grep -Eqi 'Settings Power LIVE|Empty Bin LIVE|Open With' "$settings_card"; then
  fail "Settings Sound must not invent unrelated LIVE surfaces"
fi
grep -Fq 'sessionSound' "$settings_model" || fail "Settings model normalizes session Sound outcomes"
grep -Fq 'audio-output-mute-set' "$settings_model" || fail "Settings coverage names the session mute verb"
grep -Fq 'audio-output-default-set' "$settings_model" || fail "Settings coverage names the session default verb"
grep -Fq 'does not invent an audio.provider mute or default-sink durable writer' "$settings_model" ||
  fail "Settings coverage refuses a Fabric mute/default writer"
if grep -Eqi 'audio.provider mute durable LIVE|audio.provider default-sink durable LIVE|output-mute\.set"|default-sink\.set"' "$audio_provider" "$audio_manifest"; then
  fail "audio.provider invented a durable LIVE mute/default claim"
fi
if grep -Eq 'audio-output-status|audio-output-mute-set|audio-output-default-set' "$daemon"; then
  fail "Fabric durable plane invented a session Sound writer"
fi
grep -Fq 'PACTL = "/usr/bin/pactl"' "$helper" || fail "session apply pins absolute /usr/bin/pactl"
grep -Fq 'def audio_output_helper' "$helper" || fail "session apply exposes audio_output_helper"
grep -Fq 'return PACTL' "$helper" || fail "session apply audio helper returns PACTL"

pass "Settings Sound hosts the session mute/default plane instead of a Fabric LIVE writer"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-settings/SettingsModel.js')

const idle = Model.sessionSoundIdle()
assertEqual(idle.phase, 'idle', 'session sound starts idle')
assertEqual(idle.sinks.length, 0, 'session sound starts without sinks')
assertEqual(idle.known, false, 'session sound starts unknown')

const goodId = 'audio.sink.' + 'a'.repeat(64)
const otherId = 'audio.sink.' + 'b'.repeat(64)
const sinks = [
  { resourceId: goodId, label: 'Speakers', muted: false, default: true },
  { resourceId: otherId, label: 'Headphones', muted: true, default: false }
]
assertEqual(Model.sessionSoundCanSubmit(goodId, sinks), true, 'tip-true sink is allowed')
assertEqual(Model.sessionSoundCanSubmit(otherId, sinks), true, 'second tip-true sink is allowed')
assertEqual(Model.sessionSoundCanSubmit('audio.sink.short', sinks), false, 'malformed identity is refused')
assertEqual(Model.sessionSoundCanSubmit('display.output.' + 'a'.repeat(64), sinks), false, 'foreign identity is refused')
assertEqual(Model.sessionSoundCanSubmit(goodId, []), false, 'empty inventory cannot submit')

const on = Model.sessionSoundFinished(idle, {
  ok: true,
  sinks: sinks,
  defaultResourceId: goodId,
  known: true,
  explanation: 'Typed audio outputs through this session.'
})
assertEqual(on.phase, 'succeeded', 'successful status is succeeded')
assertEqual(on.known, true, 'successful status is known')
assertEqual(on.sinks.length, 2, 'successful status keeps sinks')
assertEqual(on.defaultResourceId, goodId, 'successful status keeps default')

const refused = Model.sessionSoundFinished(idle, {
  ok: false,
  code: 'payload.invalid',
  explanation: 'Mute must name one tip-true audio.sink identity with a boolean muted flag.'
})
assertEqual(refused.phase, 'failed', 'whitelist refuse is failed')
assertEqual(refused.code, 'payload.invalid', 'whitelist refuse keeps payload.invalid')
assertEqual(refused.known, false, 'whitelist refuse stays unknown')

const empty = Model.sessionSoundFinished(idle, {
  ok: true,
  sinks: [],
  defaultResourceId: '',
  known: true,
  explanation: 'No audio outputs reported through this session.'
})
assertEqual(empty.phase, 'succeeded', 'honest empty status can succeed')
assertEqual(empty.known, false, 'empty status stays unknown')
assertEqual(empty.empty, true, 'empty status is empty')

const audio = Model.queryForRoute('settings.audio.overview')
assert(audio.coverage.indexOf('audio-output-mute-set') >= 0, 'audio coverage names the session mute verb')
assert(audio.coverage.indexOf('audio-output-default-set') >= 0, 'audio coverage names the session default verb')
assert(audio.coverage.indexOf('does not invent an audio.provider mute or default-sink durable writer') >= 0,
  'audio coverage refuses a Fabric mute/default writer')
assert(audio.coverage.indexOf('session leftover recorded') >= 0, 'audio coverage records a session leftover')
assert(audio.coverage.indexOf('not product CLOSED') >= 0, 'audio coverage refuses product CLOSED')
assert(audio.coverage.indexOf('not metal CLOSED') >= 0, 'audio coverage refuses metal CLOSED')
assert(audio.coverage.indexOf('not claim=present') >= 0, 'audio coverage refuses claim=present')
assert(audio.coverage.indexOf('windows-native.6 stays pending') >= 0, 'audio coverage keeps wn.6 pending')
assert(Model.declaredOpsHonesty('settings.audio.overview').indexOf('audio-output-mute-set') >= 0, 'audio declared ops name mute')
assert(Model.declaredOpsHonesty('settings.audio.overview').indexOf('does not invent') >= 0, 'audio declared ops refuse Fabric invent')
assert(Model.authorityFooter().indexOf('Sound mute and default output') >= 0, 'authority footer names session Sound')
JS

pass "Settings model maps session Sound outcomes and refuses a Fabric invent"

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
HEADPHONES = "alsa_output.usb-Example-00.analog-stereo"
SPEAKERS_ID = "audio.sink." + hashlib.sha256(f"audio\0{SPEAKERS}".encode()).hexdigest()
HEADPHONES_ID = "audio.sink." + hashlib.sha256(f"audio\0{HEADPHONES}".encode()).hexdigest()
SINKS = json.dumps(
    [
        {"name": SPEAKERS, "description": "Built-in Speakers", "mute": False},
        {"name": HEADPHONES, "description": "USB Headphones", "mute": True},
    ]
)


def run_status(payload, runner=None):
    stream = io.StringIO()
    status = sa.apply_audio_output_status(
        io.StringIO(json.dumps(payload)),
        stream,
        run=runner or default_run,
    )
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


def run_mute(payload, runner=None):
    stream = io.StringIO()
    status = sa.apply_audio_output_mute_set(
        io.StringIO(json.dumps(payload)),
        stream,
        run=runner or default_run,
    )
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


def run_default(payload, runner=None):
    stream = io.StringIO()
    status = sa.apply_audio_output_default_set(
        io.StringIO(json.dumps(payload)),
        stream,
        run=runner or default_run,
    )
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


state = {"default": SPEAKERS, "mute": {SPEAKERS: False, HEADPHONES: True}}


def default_run(argv, **kwargs):
    if argv[:3] == [sa.PACTL, "--format=json", "list"] and argv[3:] == ["sinks"]:
        sinks = json.loads(SINKS)
        for sink in sinks:
            sink["mute"] = state["mute"][sink["name"]]
        return Result(stdout=json.dumps(sinks))
    if argv[:2] == [sa.PACTL, "get-default-sink"]:
        return Result(stdout=state["default"] + "\n")
    if argv[:2] == [sa.PACTL, "set-sink-mute"]:
        state["mute"][argv[2]] = argv[3] == "1"
        return Result()
    if argv[:2] == [sa.PACTL, "set-default-sink"]:
        state["default"] = argv[2]
        return Result()
    raise AssertionError(argv)


if "audio-output-status" not in sa.ACTIONS:
    failures.append("session apply ACTIONS omitted audio-output-status")
if "audio-output-mute-set" not in sa.ACTIONS:
    failures.append("session apply ACTIONS omitted audio-output-mute-set")
if "audio-output-default-set" not in sa.ACTIONS:
    failures.append("session apply ACTIONS omitted audio-output-default-set")

helper = sa.audio_output_helper()
check("helper is absolute pactl", helper == "/usr/bin/pactl", helper)
check("helper is absolute", helper.startswith("/"), helper)
check("PACTL constant is absolute", sa.PACTL == "/usr/bin/pactl", sa.PACTL)

status, result = run_mute({})
check("empty mute payload is refused first", status == 1 and result.get("ok") is False, str(result))
check("empty mute payload uses payload.invalid", result.get("code") == "payload.invalid", str(result))

status, result = run_mute({"resourceId": SPEAKERS_ID, "muted": "yes"})
check("non-boolean muted is refused", status == 1 and result.get("code") == "payload.invalid", str(result))

status, result = run_mute({"resourceId": "audio.sink." + "c" * 64, "muted": True})
check("unknown sink mute is refused", status == 1 and result.get("code") == "payload.invalid", str(result))

status, result = run_mute({"resourceId": SPEAKERS_ID, "muted": True, "password": "hunter2"})
check("mute credential keys are refused", status == 1 and result.get("code") == "payload.invalid", str(result))
check("mute credential refuse does not leak secrets", "hunter2" not in json.dumps(result), str(result))

ok_calls = []


def ok_run(argv, **kwargs):
    ok_calls.append(list(argv))
    return default_run(argv, **kwargs)


status, result = run_mute({"resourceId": SPEAKERS_ID, "muted": True}, ok_run)
check("mocked mute succeeds after refuse", status == 0 and result.get("ok") is True, str(result))
check("mocked mute keeps resourceId", result.get("resourceId") == SPEAKERS_ID, str(result))
check("mocked mute keeps muted", result.get("muted") is True, str(result))
check("mocked mute names this session", "this session" in str(result.get("explanation") or ""), str(result))
check(
    "mocked mute uses absolute FixedArgv pactl",
    [sa.PACTL, "set-sink-mute", SPEAKERS, "1"] in ok_calls,
    str(ok_calls),
)

status, result = run_default({})
check("empty default payload is refused", status == 1 and result.get("code") == "payload.invalid", str(result))

status, result = run_default({"resourceId": "not-a-sink"})
check("malformed default identity is refused", status == 1 and result.get("code") == "payload.invalid", str(result))

status, result = run_default({"resourceId": HEADPHONES_ID, "extra": True})
check("default extra keys are refused", status == 1 and result.get("code") == "payload.invalid", str(result))

ok_calls.clear()
status, result = run_default({"resourceId": HEADPHONES_ID}, ok_run)
check("mocked default succeeds after refuse", status == 0 and result.get("ok") is True, str(result))
check("mocked default keeps resourceId", result.get("resourceId") == HEADPHONES_ID, str(result))
check(
    "mocked default uses absolute FixedArgv pactl",
    [sa.PACTL, "set-default-sink", HEADPHONES] in ok_calls,
    str(ok_calls),
)
check("mocked default refreshes defaultResourceId", result.get("defaultResourceId") == HEADPHONES_ID, str(result))

status, result = run_status({})
check("status read succeeds after refuse", status == 0 and result.get("ok") is True, str(result))
check("status read keeps tip-true speakers id", any(row.get("resourceId") == SPEAKERS_ID for row in result.get("sinks") or []), str(result))
check("status read keeps tip-true headphones id", any(row.get("resourceId") == HEADPHONES_ID for row in result.get("sinks") or []), str(result))
check("status read is known", result.get("known") is True, str(result))
check("status public sinks omit raw names", all("name" not in row for row in result.get("sinks") or []), str(result))

status, result = run_status({"password": "hunter2"})
check("status extra keys are refused", status == 1 and result.get("code") == "payload.invalid", str(result))
check("status extra keys do not leak secrets", "hunter2" not in json.dumps(result), str(result))


def missing_command_run(argv, **kwargs):
    raise FileNotFoundError(argv[0])


status, result = run_mute({"resourceId": SPEAKERS_ID, "muted": False}, missing_command_run)
check("missing helper is command.unavailable", status == 1 and result.get("code") == "command.unavailable", str(result))

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session Sound mute/default reports success and honest whitelist refuse"

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
manage = by_id["audio.output.manage"]
route = manage["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"audio.output.manage route is {route}")
if route.get("path") != "Settings > Sound; Superbar > Quick Settings > Sound":
    raise SystemExit(f"audio.output.manage path is {route}")
if "Settings > Sound" not in str(route.get("path") or ""):
    raise SystemExit(f"audio.output.manage underclaims the Settings Sound host: {route}")
if manage.get("source", {}).get("file") != "default/fabric/omarchy_fabric/helpers/session_apply.py":
    raise SystemExit(f"audio.output.manage source is {manage.get('source')}")
if manage.get("source", {}).get("symbol") != "apply_audio_output_default_set":
    raise SystemExit(f"audio.output.manage source is {manage.get('source')}")
if "SettingsSound.qml" in str(manage.get("source", {}).get("file") or ""):
    raise SystemExit("audio.output.manage must not invent source on SettingsSound.qml")
if "Panel.qml" in str(manage.get("source", {}).get("file") or ""):
    raise SystemExit("audio.output.manage must not keep QS panel-only source after soft leftover-attach")
if manage.get("availability", {}).get("claim") == "present":
    raise SystemExit("audio.output.manage must not claim present")
if manage.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"audio.output.manage claim is {manage.get('availability')}")
if manage.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"audio.output.manage human is {manage.get('availability')}")
if manage.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"audio.output.manage was raised off leftover: {manage.get('provider')}")
volume = by_id["audio.volume.set"]
if volume.get("availability", {}).get("claim") == "present":
    raise SystemExit("audio.volume.set must not claim present")
native6 = next(row for row in jobs["jobs"] if row["id"] == "windows-native.6")
if native6.get("sourceStatus") != "pending" or native6.get("claim") != "prototype":
    raise SystemExit(f"windows-native.6 must stay prototype/pending: {native6}")
if "audio.volume.set" not in (native6.get("capabilityIds") or []):
    raise SystemExit("windows-native.6 dropped audio.volume.set")
if "session leftover recorded" not in parity or "audio-output-mute-set" not in parity:
    raise SystemExit("parity must record Settings Sound mute/default session leftover")
if "windows-native.6 stays pending" not in parity and "`windows-native.6` stays pending" not in parity:
    raise SystemExit("parity must keep windows-native.6 pending")
if "claim=present" in parity and "not claim=present" not in parity:
    raise SystemExit("parity must not invent claim=present for Sound")
if "audio-output-mute-set" not in settings_api or "audio-output-default-set" not in settings_api:
    raise SystemExit("settings-service-api must name session Sound mute/default verbs")
if "not product CLOSED" not in settings_api or "not metal CLOSED" not in settings_api:
    raise SystemExit("settings-service-api must refuse product/metal CLOSED for Sound leftover")
if "audio-output-mute-set" not in handoff or "windows-native.6" not in handoff:
    raise SystemExit("handoff must record session Sound mute/default leftover")
if "audio.output.manage" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep audio.output.manage honesty")
if "windows-native.6" not in gaps or "prototype/pending" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.6 pending")
if "audio.output.manage" not in json.dumps(debt):
    raise SystemExit("legacy-debt must keep audio.output.manage")
print("catalog and honesty pins ok")
PY

pass "catalog and honesty keep Sound mute/default leftover-direct without claim=present"
