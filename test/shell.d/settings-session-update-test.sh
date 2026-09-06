#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
settings_app="$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml"
settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
settings_card="$ROOT/shell/apps/ultimate-settings/SettingsUpdateApply.qml"
settings_session="$ROOT/shell/apps/shared/SettingsSessionUpdate.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"

[[ -f $helper ]] || fail "session apply helper exists"
[[ -f $settings_app ]] || fail "Settings application exists"
[[ -f $settings_model ]] || fail "Settings model exists"

grep -Fq '"system-update-status": apply_system_update_status' "$helper" ||
  fail "session apply owns system-update-status"
grep -Fq '"system-update": apply_system_update' "$helper" ||
  fail "session apply owns system-update"
[[ -f $settings_session ]] || fail "Settings hosts a session update plane"
[[ -f $settings_card ]] || fail "Settings ships an Update apply card"
grep -Fq 'system-update-status' "$settings_session" || fail "session update QML calls system-update-status"
grep -Fq 'system-update' "$settings_session" || fail "session update QML calls system-update"
grep -Fq 'omarchy-fabric-session-apply' "$settings_session" ||
  fail "session update QML uses the session apply helper"
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$settings_session" "$settings_card"; then
  fail "Settings Update must not mint Fabric durable operations"
fi
if grep -A20 'SettingsComponents.SettingsUpdateApply' "$settings_app" | grep -Eq 'operation\.(preflight|start|approve)|requestFabric'; then
  fail "Settings Update host must not mint Fabric durable operations"
fi
if grep -Eq 'pkexec|sudo|/usr/bin/pacman|omarchy-update-confirm' "$settings_session" "$settings_card"; then
  fail "Settings Update QML must not spawn privileged or interactive update argv"
fi
grep -Fq 'SettingsComponents.SettingsUpdateApply' "$settings_app" ||
  fail "Settings Update hosts the session apply card"
grep -Fq 'this session' "$settings_card" || fail "Settings Update names the session principal"
grep -Fq 'Fabric' "$settings_card" || fail "Settings Update keeps Fabric inspect honest"
if grep -Eqi 'Fabric system\.update is LIVE|dead Fabric LIVE' "$settings_card" "$settings_app"; then
  fail "Settings Update must not invent a Fabric LIVE apply button"
fi
grep -Fq 'sessionUpdatePlan' "$settings_model" || fail "Settings model plans session updates"
grep -Fq 'settings.update.overview' "$settings_model" || fail "Settings model still owns the Update route"

pass "Settings wires a session update plane instead of a Fabric LIVE button"

cd "$ROOT/default/fabric"
PYTHONPATH="$ROOT/default/fabric" PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import io
import json

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


calls = []
lock_held = False
commands = {
    sa.OMARCHY_VERSION_CHANNEL: Result(stdout="stable\n"),
    sa.OMARCHY_UPDATE_AVAILABLE: Result(stdout="omarchy 1.0.0-1 -> 1.0.1-1\n"),
    sa.OMARCHY_UPDATE_FREE_SPACE: Result(),
    sa.OMARCHY_UPDATE: Result(stdout="updated\n"),
}


def fake_run(argv, **kwargs):
    calls.append(list(argv))
    if not argv:
        raise AssertionError(argv)
    name = argv[0]
    if name in commands:
        result = commands[name]
        if callable(result):
            return result(argv)
        return result
    raise AssertionError(argv)


def run_action(handler, payload, **kwargs):
    stream = io.StringIO()
    status = handler(io.StringIO(json.dumps(payload)), stream, run=fake_run, lock_held=lambda: lock_held, **kwargs)
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


calls.clear()
status, result = run_action(sa.apply_system_update_status, {})
check("status succeeds", status == 0 and result.get("ok") is True, str(result))
check("status reports the machine channel", result.get("channel") == "stable", str(result))
check("status reports updates available", result.get("available") is True, str(result))
check("status reports lock free", result.get("lockHeld") is False, str(result))
check("status reports disk ok", result.get("diskOk") is True, str(result))
check("channel helper is /usr/bin pinned", sa.OMARCHY_VERSION_CHANNEL == "/usr/bin/omarchy-version-channel", sa.OMARCHY_VERSION_CHANNEL)
check("update helper is /usr/bin pinned", sa.OMARCHY_UPDATE == "/usr/bin/omarchy-update", sa.OMARCHY_UPDATE)
check("available helper is /usr/bin pinned", sa.OMARCHY_UPDATE_AVAILABLE == "/usr/bin/omarchy-update-available", sa.OMARCHY_UPDATE_AVAILABLE)
check("free-space helper is /usr/bin pinned", sa.OMARCHY_UPDATE_FREE_SPACE == "/usr/bin/omarchy-update-requires-free-space", sa.OMARCHY_UPDATE_FREE_SPACE)
check(
    "status probes channel before apply",
    any(call and call[0] == "/usr/bin/omarchy-version-channel" for call in calls),
    str(calls),
)

calls.clear()
status, result = run_action(sa.apply_system_update, {"channel": "stable"})
check("apply on the tracked channel succeeds", status == 0 and result.get("ok") is True, str(result))
check("apply reports the channel", result.get("channel") == "stable", str(result))
check(
    "apply uses /usr/bin/omarchy-update unattended",
    any(call and call[0] == "/usr/bin/omarchy-update" and "-y" in call for call in calls),
    str(calls),
)

status, result = run_action(sa.apply_system_update, {"channel": "candidate"})
check("channel mismatch is refused", status == 1 and result.get("ok") is False, str(result))
check("channel mismatch uses update.channel-mismatch", result.get("code") == "update.channel-mismatch", str(result))
check("channel mismatch is not command.unavailable", result.get("code") != "command.unavailable", str(result))

commands[sa.OMARCHY_VERSION_CHANNEL] = Result(stdout="rc\n")
status, result = run_action(sa.apply_system_update, {"channel": "stable"})
check("stable on an rc machine is channel-mismatch", result.get("code") == "update.channel-mismatch", str(result))
commands[sa.OMARCHY_VERSION_CHANNEL] = Result(stdout="stable\n")

commands[sa.OMARCHY_UPDATE_AVAILABLE] = Result(returncode=1, stdout="Omarchy is up to date\n")
status, result = run_action(sa.apply_system_update, {"channel": "stable"})
check("no updates is refused", status == 1 and result.get("ok") is False, str(result))
check("no updates uses update.none-available", result.get("code") == "update.none-available", str(result))
commands[sa.OMARCHY_UPDATE_AVAILABLE] = Result(stdout="omarchy 1.0.0-1 -> 1.0.1-1\n")

lock_held = True
status, result = run_action(sa.apply_system_update, {"channel": "stable"})
check("held lock is refused", status == 1 and result.get("ok") is False, str(result))
check("held lock uses update.lock-held", result.get("code") == "update.lock-held", str(result))
lock_held = False

commands[sa.OMARCHY_UPDATE_FREE_SPACE] = Result(returncode=1, stdout="You need at least 10 GiB free to safely update Omarchy.\n")
status, result = run_action(sa.apply_system_update, {"channel": "stable"})
check("disk space is refused", status == 1 and result.get("ok") is False, str(result))
check("disk space uses update.disk-space", result.get("code") == "update.disk-space", str(result))
commands[sa.OMARCHY_UPDATE_FREE_SPACE] = Result()

commands[sa.OMARCHY_UPDATE] = Result(returncode=1, stderr="sudo: a password is required")
status, result = run_action(sa.apply_system_update, {"channel": "stable"})
check("auth denial is refused", status == 1 and result.get("ok") is False, str(result))
check("auth denial uses update.auth-denied", result.get("code") == "update.auth-denied", str(result))
commands[sa.OMARCHY_UPDATE] = Result(stdout="updated\n")

status, result = run_action(sa.apply_system_update, {"channel": "nightly"})
check("unknown requested channel is refused", status == 1 and result.get("ok") is False, str(result))
check(
    "unknown requested channel is not command.unavailable",
    result.get("code") != "command.unavailable",
    str(result),
)

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session system-update reports success and honest refusal"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-settings/SettingsModel.js')

const idle = Model.sessionUpdateIdle()
assertEqual(idle.phase, 'idle', 'session update starts idle')

const check = Model.sessionUpdatePlan('check')
assertEqual(check.action, 'check', 'check plans a status probe')
assert(Model.sessionUpdateCanSubmit(check), 'check can submit')

const apply = Model.sessionUpdatePlan('apply', { channel: 'stable', available: true, lockHeld: false, diskOk: true })
assertEqual(apply.action, 'apply', 'available updates can apply')
assertEqual(apply.channel, 'stable', 'apply keeps the probed channel')
assert(Model.sessionUpdateCanSubmit(apply), 'available apply can submit')

const mismatch = Model.sessionUpdatePlan('apply', { channel: 'candidate', available: true, lockHeld: false, diskOk: true, requestedChannel: 'stable' })
assertEqual(mismatch.action, 'unavailable', 'a requested channel that is not the probed channel stays unavailable')
assert(!Model.sessionUpdateCanSubmit(mismatch), 'mismatched apply cannot submit')

const none = Model.sessionUpdatePlan('apply', { channel: 'stable', available: false, lockHeld: false, diskOk: true })
assertEqual(none.action, 'unavailable', 'no updates stay unavailable')
assert(!Model.sessionUpdateCanSubmit(none), 'empty apply cannot submit')

const locked = Model.sessionUpdatePlan('apply', { channel: 'stable', available: true, lockHeld: true, diskOk: true })
assertEqual(locked.action, 'unavailable', 'a held lock stays unavailable')
assert(!Model.sessionUpdateCanSubmit(locked), 'locked apply cannot submit')

const disk = Model.sessionUpdatePlan('apply', { channel: 'stable', available: true, lockHeld: false, diskOk: false })
assertEqual(disk.action, 'unavailable', 'low disk stays unavailable')
assert(!Model.sessionUpdateCanSubmit(disk), 'low-disk apply cannot submit')

const running = Model.sessionUpdateAccepted(idle, apply)
assertEqual(running.phase, 'running', 'submit moves to running')
const ok = Model.sessionUpdateFinished(running, { ok: true, channel: 'stable', explanation: 'Installed system updates on stable.' })
assertEqual(ok.phase, 'succeeded', 'helper success is succeeded')
assertEqual(ok.message, 'Installed system updates on stable.', 'success keeps the helper explanation')
const failed = Model.sessionUpdateFinished(running, { ok: false, code: 'update.channel-mismatch', explanation: 'The requested channel is not the channel this machine tracks.' })
assertEqual(failed.phase, 'failed', 'helper failure is failed')
assertEqual(failed.code, 'update.channel-mismatch', 'failure keeps the helper code')
assertEqual(failed.message, 'The requested channel is not the channel this machine tracks.', 'failure keeps the helper explanation')
JS

pass "Settings model plans session update and maps helper outcomes"

python3 - "$catalog" "$jobs" <<'PY'
import json
import sys

catalog = json.loads(open(sys.argv[1], encoding="utf-8").read())
jobs = json.loads(open(sys.argv[2], encoding="utf-8").read())
by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
install = by_id["update.install"]
route = install["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"update.install route is {route}")
if route.get("path") not in {"Settings > Update", "Start > Settings > Update"}:
    raise SystemExit(f"update.install path is {route}")
if route.get("label") != "Install system updates":
    raise SystemExit(f"update.install label is {route}")
if install.get("source", {}).get("file") != "shell/apps/shared/SettingsSessionUpdate.qml":
    raise SystemExit(f"update.install source is {install.get('source')}")
if install.get("source", {}).get("symbol") != "applyUpdate":
    raise SystemExit(f"update.install source is {install.get('source')}")
if install.get("availability", {}).get("claim") == "present":
    raise SystemExit("update.install must not claim present")
if install.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"update.install human availability is {install.get('availability')}")
if install.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"update.install was raised off leftover: {install.get('provider')}")

by_job = {job["id"]: job for job in jobs["jobs"]}
parity = by_job["parity.update"]
if parity.get("claim") == "present":
    raise SystemExit("parity.update must not claim present")
native = by_job["windows-native.28"]
if native.get("claim") == "present":
    raise SystemExit("windows-native.28 must not claim present")
if native.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.28 sourceStatus is {native.get('sourceStatus')}")
if native.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.28 proofStatus is {native.get('proofStatus')}")
PY

pass "update.install stays leftover partial with a visible Settings Update route"
