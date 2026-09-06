#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

settings_app="$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml"
settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
settings_card="$ROOT/shell/apps/ultimate-settings/SettingsPrinters.qml"
settings_session="$ROOT/shell/apps/shared/SettingsSessionPrinters.qml"
settings_routes="$ROOT/shell/apps/ultimate-settings/routes-v1.json"
helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
debt="$ROOT/default/ultimate/capabilities/legacy-debt-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
settings_api="$ROOT/docs/settings-service-api.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
printer_provider="$ROOT/default/fabric/omarchy_fabric/providers/printer/provider.py"
daemon="$ROOT/default/fabric/omarchy_fabric/daemon.py"
desktop="$ROOT/applications/org.omarchy.Settings.desktop"

[[ -f $settings_app ]] || fail "Settings application exists"
[[ -f $settings_model ]] || fail "Settings model exists"
[[ -f $settings_session ]] || fail "Settings hosts a session Printers plane"
[[ -f $settings_card ]] || fail "Settings ships a Printers inventory/queue card"
[[ -f $helper ]] || fail "session apply helper exists"

grep -Fq 'omarchy-fabric-session-apply' "$settings_session" ||
  fail "session Printers QML uses the session apply helper"
grep -Fq 'OMARCHY_PATH' "$settings_session" || fail "session Printers QML prefers OMARCHY_PATH"
grep -Fq '/bin/omarchy-fabric-session-apply' "$settings_session" ||
  fail "session Printers QML spawns omarchy-fabric-session-apply from an absolute bin path"
if grep -Eq 'return "omarchy-fabric-session-apply"|: "omarchy-fabric-session-apply"' "$settings_session"; then
  fail "session Printers QML must not spawn a bare omarchy-fabric-session-apply PATH name"
fi
grep -Fq '"printer-status": apply_printer_status' "$helper" || fail "session apply owns printer-status"
grep -Fq '"printer-default-set": apply_printer_default_set' "$helper" || fail "session apply owns printer-default-set"
grep -Fq '"printer-pause": apply_printer_pause' "$helper" || fail "session apply owns printer-pause"
grep -Fq '"printer-resume": apply_printer_resume' "$helper" || fail "session apply owns printer-resume"
grep -Fq '"printer-test-page": apply_printer_test_page' "$helper" || fail "session apply owns printer-test-page"
grep -Fq 'printer-status' "$settings_session" || fail "session Printers QML calls printer-status"
grep -Fq 'printer-default-set' "$settings_session" || fail "session Printers QML calls printer-default-set"
grep -Fq 'printer-pause' "$settings_session" || fail "session Printers QML calls printer-pause"
grep -Fq 'printer-resume' "$settings_session" || fail "session Printers QML calls printer-resume"
grep -Fq 'printer-test-page' "$settings_session" || fail "session Printers QML calls printer-test-page"
grep -Fq 'function readStatus(' "$settings_session" || fail "session Printers QML exposes readStatus"
grep -Fq 'function setDefault(' "$settings_session" || fail "session Printers QML exposes setDefault"
grep -Fq 'function pauseQueue(' "$settings_session" || fail "session Printers QML exposes pauseQueue"
grep -Fq 'function resumeQueue(' "$settings_session" || fail "session Printers QML exposes resumeQueue"
grep -Fq 'function testPage(' "$settings_session" || fail "session Printers QML exposes testPage"
if grep -Fq 'function readStatus(' "$settings_card"; then
  fail "Printers card must not invent a local readStatus"
fi
if grep -Fq 'function setDefault(' "$settings_card"; then
  fail "Printers card must not invent a local setDefault"
fi
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$settings_session" "$settings_card"; then
  fail "Settings Printers must not mint Fabric durable operations"
fi
if grep -A20 'SettingsComponents.SettingsPrinters' "$settings_app" | grep -Eq 'operation\.(preflight|start|approve)|requestFabric'; then
  fail "Settings Printers host must not mint Fabric durable operations"
fi
if grep -Eq 'pkexec|sudo' "$settings_session" "$settings_card"; then
  fail "Settings Printers QML must not spawn privilege"
fi
if grep -Eq 'provider: "printers.provider"|action: "queue.plan"|"queue\.plan"' "$settings_session" "$settings_card"; then
  fail "Settings Printers must not invent a Fabric queue.plan writer"
fi
if grep -Eq 'lpstat|lpoptions|cupsdisable|cupsenable|bash -c' "$settings_session"; then
  fail "session Printers QML must use the session apply verb instead of a parallel cups writer"
fi
if grep -Eq 'command:[[:space:]]*\[.*(lpstat|lpoptions|cupsdisable|cupsenable|["'\'']lp["'\''])' "$settings_card"; then
  fail "Printers card must not spawn cups tools directly"
fi
grep -Fq 'SettingsComponents.SettingsPrinters' "$settings_app" ||
  fail "Settings Printers hosts the session inventory/queue card"
grep -Fq 'settings.printers.overview' "$settings_app" || fail "Settings still owns the Printers route"
grep -Fq 'settings.printers.overview' "$settings_routes" || fail "Settings routes publish Printers"
grep -Fq 'this session' "$settings_card" || fail "Settings Printers names the session principal"
grep -Fq '/usr/bin/lpstat' "$settings_card" || fail "Settings Printers names absolute lpstat"
grep -Fq 'session leftover recorded' "$settings_card" || fail "Settings Printers records a session leftover"
grep -Fq 'session-UI leftover only' "$settings_card" || fail "Settings Printers names session-UI leftover only"
grep -Fq 'not product CLOSED' "$settings_card" || fail "Settings Printers refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$settings_card" || fail "Settings Printers refuses metal CLOSED"
grep -Fq 'not claim=present' "$settings_card" || fail "Settings Printers refuses claim=present"
grep -Fq 'Add a printer stays OPEN leftover' "$settings_card" || fail "Settings Printers names Add as OPEN leftover"
if grep -Eq 'CLOSED leftover:' "$settings_card"; then
  fail "Settings Printers must not use bare CLOSED leftover invent"
fi
if grep -Eqi 'Devices and Printers product-complete|Win7 printer wizard present' "$settings_card" "$settings_app" && ! grep -Eqi 'not Devices and Printers product-complete|not product-complete' "$settings_card"; then
  fail "Settings Printers must not invent Devices and Printers product-complete"
fi
if grep -Eqi 'claim=present' "$settings_card" "$settings_app" && ! grep -Eqi 'not claim=present' "$settings_card"; then
  fail "Settings Printers must not invent claim=present"
fi
if grep -Eqi 'LIVE CONTROL' "$settings_card"; then
  fail "Settings Printers must not invent LIVE CONTROL"
fi
if grep -Eqi 'Settings Power LIVE|Empty Bin LIVE' "$settings_card"; then
  fail "Settings Printers must not invent unrelated LIVE surfaces"
fi
grep -Fq 'sessionPrinters' "$settings_model" || fail "Settings model normalizes session Printers outcomes"
grep -Fq 'printer-default-set' "$settings_model" || fail "Settings coverage names the session default verb"
grep -Fq 'does not invent a printers.provider durable writer' "$settings_model" ||
  fail "Settings coverage refuses a Fabric printers durable writer"
grep -Fq 'Network Add / driver wizard remains OPEN leftover' "$settings_model" ||
  fail "Settings coverage keeps Network Add OPEN"
if grep -Eq 'printer-status|printer-default-set|printer-pause|printer-resume|printer-test-page' "$daemon"; then
  fail "Fabric durable plane invented a session Printers writer"
fi
grep -Fq 'LPSTAT = "/usr/bin/lpstat"' "$helper" || fail "session apply pins absolute /usr/bin/lpstat"
grep -Fq 'LPOPTIONS = "/usr/bin/lpoptions"' "$helper" || fail "session apply pins absolute /usr/bin/lpoptions"
grep -Fq 'CUPSDISABLE = "/usr/sbin/cupsdisable"' "$helper" || fail "session apply pins absolute /usr/sbin/cupsdisable"
grep -Fq 'CUPSENABLE = "/usr/sbin/cupsenable"' "$helper" || fail "session apply pins absolute /usr/sbin/cupsenable"
grep -Fq 'LP = "/usr/bin/lp"' "$helper" || fail "session apply pins absolute /usr/bin/lp"
grep -Fq 'no CUPS mutation is executed' "$printer_provider" || fail "tip printer.provider stays plan-only"
grep -Fq 'settings.printers.overview' "$desktop" || fail "Settings desktop Printers opens settings.printers.overview"

pass "Settings Printers hosts the session inventory/queue plane instead of a Fabric LIVE writer"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-settings/SettingsModel.js')

const idle = Model.sessionPrintersIdle()
assertEqual(idle.phase, 'idle', 'session printers starts idle')
assertEqual(idle.printers.length, 0, 'session printers starts without printers')
assertEqual(idle.known, false, 'session printers starts unknown')

const goodId = 'printer.' + 'a'.repeat(24)
const otherId = 'printer.' + 'b'.repeat(24)
const printers = [
  { resourceId: goodId, label: 'Office', connection: 'network', endpoint: 'printer.local', accepting: true, default: true },
  { resourceId: otherId, label: 'USB', connection: 'local', endpoint: 'usb', accepting: false, default: false }
]
assertEqual(Model.sessionPrintersCanSubmit(goodId, printers), true, 'tip-true printer is allowed')
assertEqual(Model.sessionPrintersCanSubmit(otherId, printers), true, 'second tip-true printer is allowed')
assertEqual(Model.sessionPrintersCanSubmit('printer.short', printers), false, 'malformed identity is refused')
assertEqual(Model.sessionPrintersCanSubmit('audio.sink.' + 'a'.repeat(64), printers), false, 'foreign identity is refused')
assertEqual(Model.sessionPrintersCanSubmit(goodId, []), false, 'empty inventory cannot submit')

const on = Model.sessionPrintersFinished(idle, {
  ok: true,
  printers: printers,
  defaultResourceId: goodId,
  known: true,
  explanation: 'Typed printers through this session.'
})
assertEqual(on.phase, 'succeeded', 'successful status is succeeded')
assertEqual(on.known, true, 'successful status is known')
assertEqual(on.printers.length, 2, 'successful status keeps printers')
assertEqual(on.defaultResourceId, goodId, 'successful status keeps default')

const refused = Model.sessionPrintersFinished(idle, {
  ok: false,
  code: 'payload.invalid',
  explanation: 'Default printer must name one tip-true printer identity from this session inventory.'
})
assertEqual(refused.phase, 'failed', 'whitelist refuse is failed')
assertEqual(refused.code, 'payload.invalid', 'whitelist refuse keeps payload.invalid')
assertEqual(refused.known, false, 'whitelist refuse stays unknown')

const empty = Model.sessionPrintersFinished(idle, {
  ok: true,
  printers: [],
  defaultResourceId: '',
  known: true,
  explanation: 'No printers reported through this session.'
})
assertEqual(empty.phase, 'succeeded', 'honest empty status can succeed')
assertEqual(empty.known, false, 'empty status stays unknown')
assertEqual(empty.empty, true, 'empty status is empty')

const page = Model.queryForRoute('settings.printers.overview')
assert(page.coverage.indexOf('printer-default-set') >= 0, 'printers coverage names the session default verb')
assert(page.coverage.indexOf('printer-pause') >= 0, 'printers coverage names pause')
assert(page.coverage.indexOf('does not invent a printers.provider durable writer') >= 0,
  'printers coverage refuses a Fabric durable writer')
assert(page.coverage.indexOf('Network Add / driver wizard remains OPEN leftover') >= 0, 'printers coverage keeps Add OPEN')
assert(page.coverage.indexOf('session leftover recorded') >= 0, 'printers coverage records a session leftover')
assert(page.coverage.indexOf('not product CLOSED') >= 0, 'printers coverage refuses product CLOSED')
assert(page.coverage.indexOf('not metal CLOSED') >= 0, 'printers coverage refuses metal CLOSED')
assert(page.coverage.indexOf('not claim=present') >= 0, 'printers coverage refuses claim=present')
assert(page.coverage.indexOf('windows-native.32 stays pending') >= 0, 'printers coverage keeps wn.32 pending')
assert(Model.declaredOpsHonesty('settings.printers.overview').indexOf('printer-default-set') >= 0, 'printers declared ops name default')
assert(Model.declaredOpsHonesty('settings.printers.overview').indexOf('does not invent') >= 0, 'printers declared ops refuse Fabric invent')
assert(Model.authorityFooter().indexOf('Printers inventory and queue controls') >= 0, 'authority footer names session Printers')
assertEqual(Model.routeHasLiveWriter('settings.printers.overview'), true, 'printers route is a session writer route')
JS

pass "Settings model maps session Printers outcomes and refuses a Fabric invent"

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


OFFICE = "Office_Laser"
USB = "USB_Inkjet"
OFFICE_ID = "printer." + hashlib.sha256(OFFICE.encode()).hexdigest()[:24]
USB_ID = "printer." + hashlib.sha256(USB.encode()).hexdigest()[:24]
TESTPRINT = pathlib.Path(tempfile.mkdtemp()) / "testprint"
TESTPRINT.write_text("test\n", encoding="utf-8")


def run_status(payload, runner=None):
    stream = io.StringIO()
    status = sa.apply_printer_status(io.StringIO(json.dumps(payload)), stream, run=runner or default_run)
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


def run_default(payload, runner=None):
    stream = io.StringIO()
    status = sa.apply_printer_default_set(io.StringIO(json.dumps(payload)), stream, run=runner or default_run)
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


def run_pause(payload, runner=None):
    stream = io.StringIO()
    status = sa.apply_printer_pause(io.StringIO(json.dumps(payload)), stream, run=runner or default_run)
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


def run_resume(payload, runner=None):
    stream = io.StringIO()
    status = sa.apply_printer_resume(io.StringIO(json.dumps(payload)), stream, run=runner or default_run)
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


def run_test(payload, runner=None):
    stream = io.StringIO()
    status = sa.apply_printer_test_page(io.StringIO(json.dumps(payload)), stream, run=runner or default_run)
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


state = {"default": OFFICE, "accepting": {OFFICE: True, USB: True}, "uris": {
    OFFICE: "ipp://printer.local/ipp/print",
    USB: "usb://Example/Printer",
}}
calls = []


def default_run(argv, **kwargs):
    calls.append(list(argv))
    if argv[:2] == [sa.LPSTAT, "-v"]:
        body = "\n".join(f"device for {name}: {uri}" for name, uri in state["uris"].items()) + "\n"
        return Result(stdout=body)
    if argv[:2] == [sa.LPSTAT, "-d"]:
        return Result(stdout=f"system default destination: {state['default']}\n")
    if argv[:2] == [sa.LPSTAT, "-a"]:
        lines = []
        for name, accepting in state["accepting"].items():
            if accepting:
                lines.append(f"{name} accepting requests since Jan 01 00:00")
            else:
                lines.append(f"{name} not accepting requests since Jan 01 00:00")
        return Result(stdout="\n".join(lines) + "\n")
    if argv[:2] == [sa.LPOPTIONS, "-d"]:
        state["default"] = argv[2]
        return Result()
    if argv[:1] == [sa.CUPSDISABLE]:
        state["accepting"][argv[1]] = False
        return Result()
    if argv[:1] == [sa.CUPSENABLE]:
        state["accepting"][argv[1]] = True
        return Result()
    if argv[:3] == [sa.LP, "-d", OFFICE] or (len(argv) >= 3 and argv[0] == sa.LP and argv[1] == "-d"):
        return Result()
    raise AssertionError(argv)


for action in ("printer-status", "printer-default-set", "printer-pause", "printer-resume", "printer-test-page"):
    if action not in sa.ACTIONS:
        failures.append(f"session apply ACTIONS omitted {action}")

check("lpstat helper absolute", sa.printer_lpstat() == "/usr/bin/lpstat", sa.printer_lpstat())
check("lpoptions helper absolute", sa.printer_lpoptions() == "/usr/bin/lpoptions", sa.printer_lpoptions())
check("cupsdisable helper absolute", sa.printer_cupsdisable() == "/usr/sbin/cupsdisable", sa.printer_cupsdisable())
check("cupsenable helper absolute", sa.printer_cupsenable() == "/usr/sbin/cupsenable", sa.printer_cupsenable())
check("lp helper absolute", sa.printer_lp() == "/usr/bin/lp", sa.printer_lp())
check("LPSTAT constant absolute", sa.LPSTAT == "/usr/bin/lpstat", sa.LPSTAT)
check("identity matches tip provider", sa.stable_printer_id(OFFICE) == OFFICE_ID, sa.stable_printer_id(OFFICE))

status, result = run_status({})
check("status ok", status == 0 and result.get("ok") is True, str(result))
check("status known", result.get("known") is True, str(result))
check("status default", result.get("defaultResourceId") == OFFICE_ID, str(result))
check("status printers", len(result.get("printers") or []) == 2, str(result))

status, result = run_default({})
check("empty default payload refused", status == 1 and result.get("code") == "payload.invalid", str(result))

status, result = run_default({"resourceId": USB_ID, "password": "x"})
check("credential key refused", status == 1 and result.get("code") == "payload.invalid", str(result))

status, result = run_default({"resourceId": "printer." + "c" * 24})
check("unknown identity refused", status == 1 and result.get("code") == "payload.invalid", str(result))

status, result = run_default({"resourceId": USB_ID})
check("default set ok", status == 0 and result.get("ok") is True, str(result))
check("default applied", result.get("defaultResourceId") == USB_ID, str(result))
check("default argv absolute", any(c[:3] == [sa.LPOPTIONS, "-d", USB] for c in calls), str(calls))

status, result = run_pause({"resourceId": OFFICE_ID})
check("pause ok", status == 0 and result.get("ok") is True, str(result))
check("pause argv absolute", any(c[:2] == [sa.CUPSDISABLE, OFFICE] for c in calls), str(calls))

status, result = run_pause({"resourceId": OFFICE_ID})
check("already paused refused", status == 1 and result.get("code") == "payload.invalid", str(result))

status, result = run_resume({"resourceId": OFFICE_ID})
check("resume ok", status == 0 and result.get("ok") is True, str(result))
check("resume argv absolute", any(c[:2] == [sa.CUPSENABLE, OFFICE] for c in calls), str(calls))

sa.CUPS_TESTPRINT = str(TESTPRINT)
status, result = run_test({"resourceId": OFFICE_ID})
check("test page ok", status == 0 and result.get("ok") is True, str(result))
check("test page argv absolute", any(c[:3] == [sa.LP, "-d", OFFICE] and c[3] == str(TESTPRINT) for c in calls), str(calls))

cred_state = {
    "default": "Bad",
    "accepting": {"Bad": True},
    "uris": {"Bad": "ipp://user:secret@printer.local/ipp/print"},
}


def cred_run(argv, **kwargs):
    if argv[:2] == [sa.LPSTAT, "-v"]:
        return Result(stdout="device for Bad: ipp://user:secret@printer.local/ipp/print\n")
    if argv[:2] == [sa.LPSTAT, "-d"]:
        return Result(stdout="system default destination: Bad\n")
    if argv[:2] == [sa.LPSTAT, "-a"]:
        return Result(stdout="Bad accepting requests since Jan 01 00:00\n")
    raise AssertionError(argv)


status, result = run_status({}, cred_run)
check("credentialed URI refused", status == 1 and result.get("code") == "probe.invalid", str(result))
check("credentialed URI explanation", "credentials" in str(result.get("explanation") or "").lower(), str(result))


def missing_command_run(argv, **kwargs):
    raise FileNotFoundError(argv[0])


status, result = run_default({"resourceId": USB_ID}, missing_command_run)
check("missing helper is command.unavailable", status == 1 and result.get("code") == "command.unavailable", str(result))

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session Printers reports success and honest whitelist refuse"

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
manage = by_id["printers.manage"]
route = manage["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"printers.manage route is {route}")
if route.get("path") != "Settings > Printers":
    raise SystemExit(f"printers.manage path is {route}")
if manage.get("source", {}).get("file") != "default/fabric/omarchy_fabric/helpers/session_apply.py":
    raise SystemExit(f"printers.manage source is {manage.get('source')}")
if manage.get("source", {}).get("symbol") != "apply_printer_default_set":
    raise SystemExit(f"printers.manage source is {manage.get('source')}")
if "SettingsPrinters.qml" in str(manage.get("source", {}).get("file") or ""):
    raise SystemExit("printers.manage must not invent source on SettingsPrinters.qml")
if manage.get("availability", {}).get("claim") == "present":
    raise SystemExit("printers.manage must not claim present")
if manage.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"printers.manage claim is {manage.get('availability')}")
if manage.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"printers.manage human is {manage.get('availability')}")
if manage.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"printers.manage was raised off leftover: {manage.get('provider')}")
if manage.get("provider", {}).get("id") != "printer.provider":
    raise SystemExit(f"printers.manage provider id drifted: {manage.get('provider')}")
native32 = next(row for row in jobs["jobs"] if row["id"] == "windows-native.32")
if native32.get("sourceStatus") != "pending" or native32.get("claim") != "prototype":
    raise SystemExit(f"windows-native.32 must stay prototype/pending: {native32}")
if native32.get("humanRoute", {}).get("path") != "Settings > Printers":
    raise SystemExit(f"windows-native.32 humanRoute drifted: {native32.get('humanRoute')}")
if "printers.manage" not in (native32.get("capabilityIds") or []):
    raise SystemExit("windows-native.32 dropped printers.manage")
if "printer-default-set" not in parity or "Settings > Printers" not in parity:
    raise SystemExit("parity must record Settings Printers session leftover")
if "windows-native.32 stays prototype/pending" not in parity and "`windows-native.32` stays prototype/pending" not in parity:
    raise SystemExit("parity must keep windows-native.32 pending")
if "OPEN leftover" not in parity and "Network Add" not in parity:
    raise SystemExit("parity must keep Network Add OPEN")
if "claim=present" in parity and "not claim=present" not in parity:
    raise SystemExit("parity must not invent claim=present for Printers")
if "printer-default-set" not in settings_api or "printer-status" not in settings_api:
    raise SystemExit("settings-service-api must name session Printers verbs")
if "not product CLOSED" not in settings_api or "not metal CLOSED" not in settings_api:
    raise SystemExit("settings-service-api must refuse product/metal CLOSED for Printers leftover")
if "printer-default-set" not in handoff or "windows-native.32" not in handoff:
    raise SystemExit("handoff must record session Printers leftover")
if "printers.manage" not in gaps or "windows-native.32" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep printers.manage / wn.32 honesty")
if "OPEN leftover" not in gaps and "Network Add" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep Network Add OPEN")
debt_blob = json.dumps(debt)
if "printers.manage" not in debt_blob:
    raise SystemExit("legacy-debt must keep printers.manage")
legacy = next(e for e in debt["entries"] if e["id"] == "legacy.domain.direct-providers")
missing = next(e for e in debt["entries"] if e["id"] == "missing.domain.providers")
if "printers.manage" not in legacy.get("capabilityIds", []):
    raise SystemExit("legacy-debt did not soft leftover-attach printers.manage")
if "printers.manage" in missing.get("capabilityIds", []):
    raise SystemExit("legacy-debt still lists printers.manage as provider-missing")
print("catalog and honesty pins ok")
PY

pass "catalog and honesty keep Printers leftover-direct without claim=present"
