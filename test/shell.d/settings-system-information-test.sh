#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

settings_app="$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml"
settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
settings_card="$ROOT/shell/apps/ultimate-settings/SettingsSystemInformation.qml"
settings_session="$ROOT/shell/apps/shared/SettingsSessionSystemInformation.qml"
helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
debt="$ROOT/default/ultimate/capabilities/legacy-debt-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
settings_api="$ROOT/docs/settings-service-api.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
desktop="$ROOT/applications/org.omarchy.Settings.desktop"
app_search="$ROOT/shell/services/AppSearch.js"

[[ -f $settings_app ]] || fail "Settings application exists"
[[ -f $settings_model ]] || fail "Settings model exists"
[[ -f $settings_session ]] || fail "Settings hosts a session system-information plane"
[[ -f $settings_card ]] || fail "Settings ships a System information card"
[[ -f $helper ]] || fail "session apply helper exists"

grep -Fq 'omarchy-fabric-session-apply' "$settings_session" ||
  fail "session system-information QML uses the session apply helper"
grep -Fq 'OMARCHY_PATH' "$settings_session" || fail "session system-information QML prefers OMARCHY_PATH"
grep -Fq '/bin/omarchy-fabric-session-apply' "$settings_session" ||
  fail "session system-information QML spawns omarchy-fabric-session-apply from an absolute bin path"
if grep -Eq 'return "omarchy-fabric-session-apply"|: "omarchy-fabric-session-apply"' "$settings_session"; then
  fail "session system-information QML must not spawn a bare omarchy-fabric-session-apply PATH name"
fi
grep -Fq '"system-information-inspect": apply_system_information_inspect' "$helper" ||
  fail "session apply owns system-information-inspect"
grep -Fq 'system-information-inspect' "$settings_session" || fail "session system-information QML calls system-information-inspect"
grep -Fq 'function readInformation(' "$settings_session" || fail "session system-information QML exposes readInformation"
grep -Fq 'function refreshInformation(' "$settings_card" || fail "System information card chrome exposes refreshInformation"
if grep -Fq 'function readInformation(' "$settings_card"; then
  fail "System information card must not invent a local readInformation"
fi
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$settings_session" "$settings_card"; then
  fail "Settings System information must not mint Fabric durable operations"
fi
if grep -A20 'SettingsComponents.SettingsSystemInformation' "$settings_app" | grep -Eq 'operation\.(preflight|start|approve)|requestFabric'; then
  fail "Settings System information host must not mint Fabric durable operations"
fi
if grep -Eq 'pkexec|sudo' "$settings_session" "$settings_card"; then
  fail "Settings System information QML must not spawn privilege"
fi
if grep -Eq 'provider: "system-information.provider"|action: "system.info' "$settings_session" "$settings_card"; then
  fail "Settings System information must not invent a Fabric system-information writer"
fi
if grep -Eq 'bash -c|subprocess|Process \{' "$settings_card"; then
  fail "System information card must not spawn a parallel Process writer"
fi
grep -Fq 'SettingsComponents.SettingsSystemInformation' "$settings_app" ||
  fail "Settings System information hosts the session card"
grep -Fq 'settings.system.overview' "$settings_app" || fail "Settings still owns the System information route"
grep -Fq 'this session' "$settings_card" || fail "Settings System information names the session principal"
grep -Fq 'session leftover recorded' "$settings_card" || fail "Settings System information records a session leftover"
grep -Eq 'session-UI leftover only|leftover-attach only' "$settings_card" || fail "Settings System information names leftover-attach only"
grep -Fq 'not product CLOSED' "$settings_card" || fail "Settings System information refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$settings_card" || fail "Settings System information refuses metal CLOSED"
grep -Fq 'not claim=present' "$settings_card" || fail "Settings System information refuses claim=present"
grep -Fiq 'soft leftover-attaches windows-native.38' "$settings_card" ||
  fail "Settings System information honesty soft leftover-attaches wn.38"
grep -Fq 'windows-native.38 stays prototype/pending' "$settings_card" ||
  fail "Settings System information honesty keeps wn.38 prototype/pending"
grep -Fq 'SettingsSessionSystemInformation.readInformation' "$settings_card" ||
  fail "Settings System information honesty names tip-true readInformation"
grep -Fiq 'soft leftover-attaches windows-native.38' "$settings_model" ||
  fail "System coverage soft leftover-attaches wn.38"
grep -Fq 'windows-native.38 stays prototype/pending' "$settings_model" ||
  fail "System coverage keeps windows-native.38 prototype/pending"
grep -Fq 'SettingsSessionSystemInformation.readInformation' "$settings_model" ||
  fail "System coverage names tip-true readInformation"
if grep -Eq 'CLOSED leftover:' "$settings_card"; then
  fail "Settings System information must not use bare CLOSED leftover invent"
fi
if grep -Eqi 'claim=present' "$settings_card" "$settings_app" && ! grep -Eqi 'not claim=present' "$settings_card"; then
  fail "Settings System information must not invent claim=present"
fi
if grep -Eqi 'LIVE CONTROL' "$settings_card"; then
  fail "Settings System information must not invent LIVE CONTROL"
fi
if grep -Eqi 'Settings Power LIVE' "$settings_card"; then
  fail "Settings System information must not invent Settings Power LIVE"
fi
grep -Fq 'sessionSystemInformation' "$settings_model" || fail "Settings model normalizes session system-information outcomes"
grep -Fq 'system-information-inspect' "$settings_model" || fail "Settings coverage names the session inspect verb"
grep -Fq 'does not invent a system-information.provider durable writer' "$settings_model" ||
  fail "Settings coverage refuses a Fabric system-information writer"
grep -Fq 'SystemInformation' "$desktop" || fail "Settings desktop publishes System information"
grep -Fq 'omarchy.start.system' "$app_search" || fail "Start search publishes System information"
grep -Fq 'settings.system.overview' "$desktop" || fail "Settings desktop System information opens settings.system.overview"

pass "Settings System information hosts the session inspect plane instead of a Fabric LIVE writer"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-settings/SettingsModel.js')

const idle = Model.sessionSystemInformationIdle()
assertEqual(idle.phase, 'idle', 'session system information starts idle')
assertEqual(idle.available, false, 'session system information starts unavailable')
assertEqual(idle.hostname, '', 'session system information starts without hostname')

const on = Model.sessionSystemInformationFinished(idle, {
  ok: true,
  available: true,
  hostname: 'desk',
  os: { name: 'Omarchy', version: '1', id: 'omarchy', kernel: '6.12.0', architecture: 'x86_64' },
  product: { name: 'Laptop', version: '1', vendor: 'Acme' },
  hardware: { cpuModel: 'CPU', memoryTotalMib: 8192, memoryAvailableMib: 2048 },
  storage: { mount: '/', totalBytes: 200 * 1024 * 1024 * 1024, usedBytes: 50 * 1024 * 1024 * 1024, freeBytes: 150 * 1024 * 1024 * 1024, available: true },
  explanation: 'Read OS, product, hardware, and root storage through this session.'
})
assertEqual(on.phase, 'succeeded', 'successful inspect is succeeded')
assertEqual(on.available, true, 'successful inspect is available')
assertEqual(on.hostname, 'desk', 'successful inspect keeps hostname')
assertEqual(on.osName, 'Omarchy', 'successful inspect keeps OS name')
assert(on.memoryLabel.indexOf('GiB') >= 0, 'successful inspect formats memory')
assert(on.storageLabel.indexOf('GiB') >= 0, 'successful inspect formats storage')
assertEqual(on.message, 'Read OS, product, hardware, and root storage through this session.', 'successful inspect keeps the helper explanation')

const refused = Model.sessionSystemInformationFinished(idle, {
  ok: false,
  code: 'payload.invalid',
  explanation: 'stdin JSON for system information must be empty; this session leftover refuses extra keys'
})
assertEqual(refused.phase, 'failed', 'payload refuse is failed')
assertEqual(refused.code, 'payload.invalid', 'payload refuse keeps payload.invalid')
assertEqual(refused.available, false, 'payload refuse stays unavailable')

const system = Model.queryForRoute('settings.system.overview')
assert(system.coverage.indexOf('system-information-inspect') >= 0 || system.coverage.indexOf('apply_system_information_inspect') >= 0, 'system coverage names the session inspect verb')
assert(system.coverage.indexOf('SettingsSessionSystemInformation.readInformation') >= 0, 'system coverage names tip-true readInformation')
assert(system.coverage.indexOf('does not invent a system-information.provider durable writer') >= 0, 'system coverage refuses a Fabric writer')
assert(system.coverage.indexOf('session leftover recorded') >= 0, 'system coverage records a session leftover')
assert(system.coverage.toLowerCase().indexOf('soft leftover-attaches windows-native.38') >= 0, 'system coverage soft leftover-attaches wn.38')
assert(system.coverage.indexOf('windows-native.38 stays prototype/pending') >= 0, 'system coverage keeps wn.38 prototype/pending')
assert(system.coverage.indexOf('not product CLOSED') >= 0, 'system coverage refuses product CLOSED')
assert(system.coverage.indexOf('not metal CLOSED') >= 0, 'system coverage refuses metal CLOSED')
assert(system.coverage.indexOf('not claim=present') >= 0, 'system coverage refuses claim=present')
assert(Model.declaredOpsHonesty('settings.system.overview').indexOf('readInformation') >= 0, 'system declared ops name tip-true readInformation')
assert(Model.declaredOpsHonesty('settings.system.overview').toLowerCase().indexOf('soft leftover-attaches windows-native.38') >= 0, 'system declared ops soft leftover-attach wn.38')
assert(Model.declaredOpsHonesty('settings.system.overview').indexOf('no preflight, approval, or execution control') >= 0, 'system declared ops stay non-mutating')
assert(Model.authorityFooter().indexOf('system-information-inspect') >= 0, 'authority footer names the session inspect verb')
assertEqual(Model.routeHasLiveWriter('settings.system.overview'), false, 'system information is not a live writer')
assertEqual(Model.coverageBadge('settings.system.overview'), 'CHANGES UNAVAILABLE', 'system information coverage badge stays unavailable')
assertEqual(Model.hostedPanel('settings.system.overview'), null, 'system information is not a hosted Personalization-style panel')
JS

pass "Settings model maps session system-information outcomes and refuses a Fabric invent"

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


def run_inspect(payload):
    stream = io.StringIO()
    status = sa.apply_system_information_inspect(io.StringIO(json.dumps(payload)), stream)
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


if "system-information-inspect" not in sa.ACTIONS:
    failures.append("session apply ACTIONS omitted system-information-inspect")

status, result = run_inspect({})
check("empty payload succeeds", status == 0 and result.get("ok") is True, str(result))
check("empty payload is available", result.get("available") is True, str(result))
check("empty payload names this session", "this session" in str(result.get("explanation") or ""), str(result))
check("empty payload keeps hostname", isinstance(result.get("hostname"), str) and result.get("hostname") != "", str(result))
check("empty payload keeps os name", isinstance((result.get("os") or {}).get("name"), str), str(result))
check("empty payload keeps storage mount", (result.get("storage") or {}).get("mount") == "/", str(result))

status, result = run_inspect({"password": "hunter2"})
check("credential keys are refused", status == 1 and result.get("ok") is False, str(result))
check("credential keys use payload.invalid", result.get("code") == "payload.invalid", str(result))
check("credential refuse does not leak secrets", "hunter2" not in json.dumps(result), str(result))

status, result = run_inspect({"hostname": "evil"})
check("extra keys are refused", status == 1 and result.get("code") == "payload.invalid", str(result))
check("extra keys are not echoed as applied hostname", result.get("hostname") in (None, ""), str(result))

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session system-information reports success and honest payload refuse"

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
info = by_id["system.info.read"]
route = info["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"system.info.read route is {route}")
if route.get("path") != "Settings > System information":
    raise SystemExit(f"system.info.read path is {route}")
if info.get("source", {}).get("file") != "shell/apps/shared/SettingsSessionSystemInformation.qml":
    raise SystemExit(f"system.info.read source is {info.get('source')}")
if info.get("source", {}).get("symbol") != "readInformation":
    raise SystemExit(f"system.info.read source is {info.get('source')}")
if "SettingsSystemInformation.qml" in str(info.get("source", {}).get("file") or ""):
    raise SystemExit("system.info.read must not invent source on SettingsSystemInformation.qml")
if info.get("availability", {}).get("claim") == "present":
    raise SystemExit("system.info.read must not claim present")
if info.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"system.info.read claim is {info.get('availability')}")
if info.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"system.info.read human availability is {info.get('availability')}")
if info.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"system.info.read agent availability is {info.get('availability')}")
if info.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"system.info.read was raised off leftover: {info.get('provider')}")
if info.get("provider", {}).get("id") != "system.provider":
    raise SystemExit(f"system.info.read provider is {info.get('provider')}")
recovery = info.get("recovery") or {}
if recovery.get("mode") != "none":
    raise SystemExit(f"system.info.read recovery mode is {recovery}")
if recovery.get("stateFingerprintRequired") is not False:
    raise SystemExit(f"system.info.read recovery fingerprint invent: {recovery}")
exp = recovery.get("expectation") or ""
for needle in (
    "readInformation",
    "apply_system_information_inspect",
    "no durable mutation",
    "no Fabric fingerprint invent",
):
    if needle not in exp:
        raise SystemExit(f"system.info.read recovery missing {needle!r}: {exp}")

by_job = {job["id"]: job for job in jobs["jobs"]}
native38 = by_job["windows-native.38"]
if native38.get("claim") == "present":
    raise SystemExit("windows-native.38 must not claim present")
if native38.get("claim") != "prototype":
    raise SystemExit(f"windows-native.38 claim is {native38.get('claim')}")
if native38.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.38 sourceStatus is {native38.get('sourceStatus')}")
if native38.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.38 proofStatus is {native38.get('proofStatus')}")
if native38.get("capabilityIds") != ["system.info.read"]:
    raise SystemExit(f"windows-native.38 capabilityIds are {native38.get('capabilityIds')}")
if native38["humanRoute"].get("status") != "visible":
    raise SystemExit(f"windows-native.38 route is {native38.get('humanRoute')}")
if native38["humanRoute"].get("path") != "Settings > System information":
    raise SystemExit(f"windows-native.38 path is {native38.get('humanRoute')}")
rec38 = native38.get("recoveryExpectation") or ""
for needle in ("readInformation", "apply_system_information_inspect"):
    if needle not in rec38:
        raise SystemExit(f"windows-native.38 recovery missing {needle!r}")
if "fingerprint invent" not in rec38.lower() and "no Fabric fingerprint invent" not in rec38:
    raise SystemExit(f"windows-native.38 recovery must refuse Fabric fingerprint invent: {rec38}")

by_debt = {entry["id"]: entry for entry in debt["entries"]}
missing_providers = by_debt["missing.domain.providers"]
if "system.info.read" in missing_providers.get("capabilityIds", []):
    raise SystemExit("system.info.read still sits in missing.domain.providers")
legacy = by_debt["legacy.domain.direct-providers"]
if "system.info.read" not in legacy.get("capabilityIds", []):
    raise SystemExit("system.info.read is not leftover-direct debt")
if "capability:system.info.read" not in legacy.get("surfaceRefs", []):
    raise SystemExit("system.info.read leftover surfaceRef is missing")
agent = by_debt["missing.agent.routes"]
if "system.info.read" not in agent.get("capabilityIds", []):
    raise SystemExit("system.info.read left missing.agent.routes")

if "Honesty addendum 2026-09-06 vs Settings System information leftover plane (windows-native.38)" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must add a dated Settings System information leftover plane addendum")
addendum = gaps.split("Honesty addendum 2026-09-06 vs Settings System information leftover plane (windows-native.38)", 1)[1].split("Honesty addendum", 1)[0]
if "CLOSED leftover:" in addendum:
    raise SystemExit("fleet-doctrine-gaps must not use bare CLOSED leftover invent for system information")
for required in (
    "session leftover recorded",
    "leftover-attach only",
    "not product CLOSED",
    "not metal CLOSED",
    "not claim=present",
    "Settings > System information",
    "system.info.read",
    "legacy-direct",
    "system-information-inspect",
    "readInformation",
    "Soft leftover-attach ACC",
    "Cloud EXIT 0 is not metal leftover CLOSED",
    "Cloud mocks do not close windows-native.38",
    "windows-native.38",
    "Settings Power LIVE",
    "Empty Bin LIVE",
    "End Task LIVE",
):
    if required not in addendum:
        raise SystemExit(f"fleet-doctrine-gaps system-information addendum dropped required honesty: {required}")
if "Do not walk `windows-native.38` to present" not in addendum and "Do not walk windows-native.38 to present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse walking windows-native.38 to present")
if "Do not invent claim=present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse claim=present invent")
if "| `windows-native.38` | prototype/pending | visible: Settings > System information |" not in gaps:
    raise SystemExit("fleet-doctrine-gaps invent-mode must keep windows-native.38 visible Settings > System information")
if "metal CLOSED from Cloud EXIT 0" not in gaps.split("`windows-native.38`", 1)[1].split("`windows-native.39`", 1)[0]:
    raise SystemExit("fleet-doctrine-gaps invent-mode for windows-native.38 must include metal CLOSED from Cloud EXIT 0")
if "session leftover recorded" not in parity:
    raise SystemExit("PARITY System information row must record the session leftover")
if "system.info.read" not in parity:
    raise SystemExit("PARITY System information row must name system.info.read")
if "does not invent a `system-information.provider` durable writer" not in parity and "does not invent a system-information.provider durable writer" not in parity:
    raise SystemExit("PARITY System information row must refuse a Fabric invent")
if "windows-native.38` stays prototype/pending" not in parity and "windows-native.38 stays prototype/pending" not in parity:
    raise SystemExit("PARITY System information row must keep windows-native.38 pending")
if "Cloud mocks do not close windows-native.38" not in parity:
    raise SystemExit("PARITY System information row must refuse Cloud mocks closing windows-native.38")
if "system.info.read" not in settings_api:
    raise SystemExit("settings-service-api must name system.info.read")
if "windows-native.38" not in settings_api:
    raise SystemExit("settings-service-api must keep windows-native.38 pending")
if "session leftover recorded" not in settings_api:
    raise SystemExit("settings-service-api must record the session leftover")
if "system-information-inspect" not in settings_api:
    raise SystemExit("settings-service-api must name system-information-inspect")
if "system-information-inspect" not in handoff:
    raise SystemExit("HANDOFF must name system-information-inspect")
if "session leftover recorded" not in handoff:
    raise SystemExit("HANDOFF must record the session leftover")
if "Cloud mocks do not close windows-native.38" not in handoff:
    raise SystemExit("HANDOFF must refuse Cloud mocks closing windows-native.38")
if "soft leftover-attach" not in handoff.lower() or "windows-native.38" not in handoff:
    raise SystemExit("HANDOFF must soft leftover-attach wn.38")
if "readInformation" not in handoff:
    raise SystemExit("HANDOFF must name tip-true readInformation")
if "soft leftover-attaches" not in parity.lower() or "windows-native.38" not in parity:
    raise SystemExit("PARITY must soft leftover-attach wn.38")
if "readInformation" not in parity:
    raise SystemExit("PARITY must name tip-true readInformation")
PY

pass "system.info.read stays leftover partial with visible Settings System information route"
