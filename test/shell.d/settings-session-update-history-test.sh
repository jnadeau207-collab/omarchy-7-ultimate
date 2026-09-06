#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
settings_app="$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml"
settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
settings_card="$ROOT/shell/apps/ultimate-settings/SettingsUpdateHistory.qml"
settings_session="$ROOT/shell/apps/shared/SettingsSessionUpdate.qml"
settings_apply="$ROOT/shell/apps/ultimate-settings/SettingsUpdateApply.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
debt="$ROOT/default/ultimate/capabilities/legacy-debt-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"

[[ -f $helper ]] || fail "session apply helper exists"
[[ -f $settings_app ]] || fail "Settings application exists"
[[ -f $settings_model ]] || fail "Settings model exists"
[[ -f $settings_session ]] || fail "Settings hosts a session update plane"
[[ -f $settings_card ]] || fail "Settings ships an Update history card"
[[ -f $settings_apply ]] || fail "Settings still ships the Update apply card"

grep -Fq '"system-update-history": apply_system_update_history' "$helper" ||
  fail "session apply owns system-update-history"
grep -Fq 'system-update-history' "$settings_session" || fail "session update QML calls system-update-history"
grep -Fq 'function readHistory(' "$settings_session" || fail "session update QML exposes readHistory"
grep -Fq 'function refreshHistory(' "$settings_card" || fail "Update history card chrome exposes refreshHistory"
if grep -Fq 'function readHistory(' "$settings_card"; then
  fail "Update history card must not invent a local readHistory"
fi
grep -Fq 'omarchy-fabric-session-apply' "$settings_session" ||
  fail "session history QML uses the session apply helper"
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$settings_session" "$settings_card"; then
  fail "Settings Update history must not mint Fabric durable operations"
fi
if grep -A20 'SettingsComponents.SettingsUpdateHistory' "$settings_app" | grep -Eq 'operation\.(preflight|start|approve)|requestFabric'; then
  fail "Settings Update history host must not mint Fabric durable operations"
fi
if grep -Eq 'pkexec|sudo|/usr/bin/pacman|omarchy-update-confirm' "$settings_session" "$settings_card"; then
  fail "Settings Update history QML must not spawn privileged or interactive update argv"
fi
if grep -Eq 'OMARCHY_UPDATE_ANALYZE|/usr/bin/omarchy-update-analyze-logs' "$helper"; then
  fail "history read must parse the transcript in-process instead of spawning analyze-logs"
fi
grep -Fq 'SettingsComponents.SettingsUpdateHistory' "$settings_app" ||
  fail "Settings Update hosts the session history card"
grep -Fq 'No update transcript is available on this session' "$settings_card" ||
  fail "Settings Update history names the empty honest state"
grep -Fq 'this session' "$settings_card" || fail "Settings Update history names the session principal"
grep -Fq 'Fabric' "$settings_card" || fail "Settings Update history keeps Fabric inspect honest"
if grep -Eqi 'Fabric system\.update is LIVE' "$settings_card" "$settings_app"; then
  fail "Settings Update history must not invent Fabric LIVE"
fi
if grep -Eqi 'claim=present' "$settings_card" "$settings_app" && ! grep -Eqi 'not claim=present|Never claim=present|never claim=present' "$settings_card" "$settings_app"; then
  fail "Settings Update history must not invent claim=present"
fi
if grep -Eqi 'Update is present as product|Update Center present' "$settings_card" "$settings_app"; then
  fail "Settings Update history must not invent Update present"
fi
grep -Fq 'sessionUpdateHistory' "$settings_model" || fail "Settings model normalizes session update history"
grep -Fq 'History is readable from this session' "$settings_model" ||
  fail "Settings coverage names the session history read"
if grep -Fq 'History, restart, and reboot writers remain unavailable from Settings' "$settings_model"; then
  fail "Settings coverage still treats history as unavailable"
fi
if grep -Fq 'Update history, restart, and reboot writers stay unavailable' "$settings_apply"; then
  fail "Settings apply card still treats history as unavailable"
fi
grep -Fq 'Restart and reboot writers stay unavailable' "$settings_apply" ||
  fail "Settings apply card keeps restart/reboot writers unavailable"

pass "Settings wires a session update history plane instead of a Fabric LIVE reader"

cd "$ROOT/default/fabric"
PYTHONPATH="$ROOT/default/fabric" PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import io
import json
import os
import tempfile
from pathlib import Path

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


def fake_run(argv, **kwargs):
    raise AssertionError(argv)


def run_action(payload, **env):
    previous = {key: os.environ.get(key) for key in env}
    try:
        for key, value in env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        stream = io.StringIO()
        status = sa.apply_system_update_history(io.StringIO(json.dumps(payload)), stream, run=fake_run)
        raw = stream.getvalue().strip()
        return status, json.loads(raw) if raw else {}
    finally:
        for key, value in previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


with tempfile.TemporaryDirectory() as tmp:
    missing = str(Path(tmp) / "missing-omarchy-update.log")
    status, result = run_action({}, OMARCHY_UPDATE_LOG=missing, XDG_STATE_HOME=str(Path(tmp) / "state"))
    check("missing log succeeds", status == 0 and result.get("ok") is True, str(result))
    check("missing log is empty", result.get("empty") is True, str(result))
    check("missing log is unavailable", result.get("available") is False, str(result))
    check("missing log has no entries", result.get("entries") == [], str(result))
    check("missing log has no failures", result.get("failures") == [], str(result))
    check(
        "missing log names the honest empty state",
        "No update transcript is available on this session" in str(result.get("explanation")),
        str(result),
    )
    check("missing log does not invent reboot writers", result.get("rebootRequired") is False, str(result))
    check("missing log does not invent restart writers", result.get("restartRequired") == [], str(result))

    log_path = Path(tmp) / "omarchy-update.log"
    log_path.write_text(
        "Updating linux initcpios\n"
        "error: something broke before initramfs finished\n"
        "Something went wrong during the update!\n",
        encoding="utf-8",
    )
    status, result = run_action({}, OMARCHY_UPDATE_LOG=str(log_path), XDG_STATE_HOME=str(Path(tmp) / "state"))
    check("failed log succeeds as a read", status == 0 and result.get("ok") is True, str(result))
    check("failed log is available", result.get("available") is True, str(result))
    check("failed log is not empty", result.get("empty") is False, str(result))
    codes = [item.get("code") for item in result.get("failures") or []]
    check("failed log reports initramfs", "update.history.initramfs" in codes, str(result))
    check("failed log reports transcript failure", "update.history.failed" in codes, str(result))
    check("failed log keeps structured failures", all(item.get("title") and item.get("detail") for item in result.get("failures") or []), str(result))
    check("failed log records a transcript entry", any(item.get("kind") == "transcript" for item in result.get("entries") or []), str(result))

    log_path.write_text(
        "omarchy 1.0.0-1 -> 1.0.1-1\n"
        "Initcpio image generation successful\n"
        "Updating linux initcpios\n",
        encoding="utf-8",
    )
    state = Path(tmp) / "state" / "omarchy"
    state.mkdir(parents=True)
    (state / "reboot-required").write_text("1\n", encoding="utf-8")
    (state / "restart-hyprland-required").write_text("1\n", encoding="utf-8")
    status, result = run_action({}, OMARCHY_UPDATE_LOG=str(log_path), XDG_STATE_HOME=str(Path(tmp) / "state"))
    check("successful log is available", result.get("available") is True, str(result))
    check("successful initramfs is not a failure", "update.history.initramfs" not in [item.get("code") for item in result.get("failures") or []], str(result))
    check("reboot marker is inspect-only", result.get("rebootRequired") is True, str(result))
    check("restart marker is inspect-only", "hyprland" in (result.get("restartRequired") or []), str(result))
    check("history read did not spawn helpers", True)

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session system-update-history reports empty honest state and structured failures"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-settings/SettingsModel.js')

const idle = Model.sessionUpdateHistoryIdle()
assertEqual(idle.phase, 'idle', 'session history starts idle')
assertEqual(idle.empty, true, 'session history starts empty')
assertEqual(idle.available, false, 'session history starts unavailable')

const empty = Model.sessionUpdateHistoryFinished(idle, {
  ok: true,
  empty: true,
  available: false,
  entries: [],
  failures: [],
  explanation: 'No update transcript is available on this session.'
})
assertEqual(empty.phase, 'succeeded', 'empty history is a successful read')
assertEqual(empty.empty, true, 'empty history stays empty')
assertEqual(empty.message, 'No update transcript is available on this session.', 'empty history keeps the helper explanation')

const failed = Model.sessionUpdateHistoryFinished(idle, {
  ok: true,
  empty: false,
  available: true,
  entries: [{ id: 'update.history.transcript', kind: 'transcript', status: 'failed', title: 'Last Omarchy update transcript', detail: 'failed' }],
  failures: [{ code: 'update.history.initramfs', title: 'Initramfs generation may have failed', detail: 'Review the log before restart.' }],
  explanation: 'The last update transcript recorded structured failures.',
  rebootRequired: false,
  restartRequired: []
})
assertEqual(failed.empty, false, 'failed history is not empty')
assertEqual(failed.failures.length, 1, 'failed history keeps structured failures')
assertEqual(failed.failures[0].code, 'update.history.initramfs', 'failed history keeps the initramfs code')
assertEqual(failed.entries[0].kind, 'transcript', 'failed history keeps the transcript entry')

const broken = Model.sessionUpdateHistoryFinished(idle, { ok: false, code: 'command.failed', explanation: 'The session update helper failed.' })
assertEqual(broken.phase, 'failed', 'helper failure is failed')
assertEqual(broken.code, 'command.failed', 'failure keeps the helper code')
JS

pass "Settings model maps session update history outcomes"

python3 - "$catalog" "$jobs" "$debt" "$gaps" <<'PY'
import json
import sys

catalog = json.loads(open(sys.argv[1], encoding="utf-8").read())
jobs = json.loads(open(sys.argv[2], encoding="utf-8").read())
debt = json.loads(open(sys.argv[3], encoding="utf-8").read())
gaps = open(sys.argv[4], encoding="utf-8").read()
by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
history = by_id["update.history.read"]
route = history["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"update.history.read route is {route}")
if route.get("path") not in {"Settings > Update", "Start > Settings > Update"}:
    raise SystemExit(f"update.history.read path is {route}")
if route.get("label") != "Update history":
    raise SystemExit(f"update.history.read label is {route}")
if history.get("source", {}).get("file") != "shell/apps/shared/SettingsSessionUpdate.qml":
    raise SystemExit(f"update.history.read source is {history.get('source')}")
if history.get("source", {}).get("symbol") != "readHistory":
    raise SystemExit(f"update.history.read source is {history.get('source')}")
if "SettingsUpdateHistory.qml" in str(history.get("source", {}).get("file") or ""):
    raise SystemExit("update.history.read must not invent source on SettingsUpdateHistory.qml")
if history.get("availability", {}).get("claim") == "present":
    raise SystemExit("update.history.read must not claim present")
if history.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"update.history.read claim is {history.get('availability')}")
if history.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"update.history.read human availability is {history.get('availability')}")
if history.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"update.history.read agent availability is {history.get('availability')}")
if history.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"update.history.read was not leftover-direct: {history.get('provider')}")
if history.get("provider", {}).get("id") != "update.provider":
    raise SystemExit(f"update.history.read provider is {history.get('provider')}")

by_job = {job["id"]: job for job in jobs["jobs"]}
parity = by_job["parity.update"]
if parity.get("claim") == "present":
    raise SystemExit("parity.update must not claim present")
if parity.get("claim") != "prototype":
    raise SystemExit(f"parity.update claim is {parity.get('claim')}")
native28 = by_job["windows-native.28"]
if native28.get("claim") == "present":
    raise SystemExit("windows-native.28 must not claim present")
if native28.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.28 sourceStatus is {native28.get('sourceStatus')}")
if native28.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.28 proofStatus is {native28.get('proofStatus')}")
native29 = by_job["windows-native.29"]
if native29.get("claim") == "present":
    raise SystemExit("windows-native.29 must not claim present")
if native29.get("claim") != "prototype":
    raise SystemExit(f"windows-native.29 claim is {native29.get('claim')}")
if native29.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.29 sourceStatus is {native29.get('sourceStatus')}")
if native29.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.29 proofStatus is {native29.get('proofStatus')}")
if native29["humanRoute"].get("status") != "visible":
    raise SystemExit(f"windows-native.29 route is {native29.get('humanRoute')}")
if native29["humanRoute"].get("path") != "Settings > Update":
    raise SystemExit(f"windows-native.29 path is {native29.get('humanRoute')}")

by_debt = {entry["id"]: entry for entry in debt["entries"]}
missing_providers = by_debt["missing.domain.providers"]
if "update.history.read" in missing_providers.get("capabilityIds", []):
    raise SystemExit("update.history.read still sits in missing.domain.providers")
legacy = by_debt["legacy.domain.direct-providers"]
if "update.history.read" not in legacy.get("capabilityIds", []):
    raise SystemExit("update.history.read is not leftover-direct debt")
if "capability:update.history.read" not in legacy.get("surfaceRefs", []):
    raise SystemExit("update.history.read leftover surfaceRef is missing")
agent = by_debt["missing.agent.routes"]
if "update.history.read" not in agent.get("capabilityIds", []):
    raise SystemExit("update.history.read left missing.agent.routes")

if "Honesty addendum 2026-09-06 vs Settings Update history" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must add a dated Settings Update history addendum")
if "CLOSED leftover: Update history UI" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must name CLOSED leftover as Update history UI")
if "windows-native.29 stays prototype/pending" not in gaps.replace("`", ""):
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.29 prototype/pending")
if "not product CLOSED" not in gaps or "not metal CLOSED" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep session leftover honesty")
if "Restart/reboot writers" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep Restart/reboot writers OPEN")
if "windows-native.28 metal" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.28 metal OPEN")
if "Do not invent claim=present" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must refuse claim=present invent")
PY

pass "update.history.read stays leftover partial with a visible Settings Update route"
