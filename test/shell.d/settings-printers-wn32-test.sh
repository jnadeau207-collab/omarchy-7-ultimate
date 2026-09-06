#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

settings_page="$ROOT/shell/apps/ultimate-settings/SettingsPrinters.qml"
settings_session="$ROOT/shell/apps/shared/SettingsSessionPrinters.qml"
settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
project="$ROOT/plans/project-ultimate.md"
settings_docs="$ROOT/docs/settings-service-api.md"
acc="$ROOT/WINDOWS_NATIVE_ACCEPTANCE.md"

[[ -f $settings_page ]] || fail "SettingsPrinters exists"
[[ -f $settings_session ]] || fail "SettingsSessionPrinters exists"

grep -Fq 'function setDefault(' "$settings_session" || fail "SettingsSessionPrinters hosts setDefault"
grep -Fq 'function resumeQueue(' "$settings_session" || fail "SettingsSessionPrinters hosts resumeQueue"
grep -Fq 'printer-default-set' "$settings_session" || fail "SettingsSessionPrinters targets printer-default-set"
grep -Fq 'printer-resume' "$settings_session" || fail "SettingsSessionPrinters targets printer-resume"
grep -Fiq 'soft leftover-attach' "$settings_page" || fail "SettingsPrinters honesty soft leftover-attaches"
grep -Fq 'windows-native.32 stays prototype/pending' "$settings_page" ||
  fail "SettingsPrinters honesty keeps windows-native.32 prototype/pending"
grep -Fq 'not product CLOSED' "$settings_page" || fail "SettingsPrinters honesty refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$settings_page" || fail "SettingsPrinters honesty refuses metal CLOSED"
grep -Fq 'not claim=present' "$settings_page" || fail "SettingsPrinters honesty refuses claim=present"
grep -Fq 'SettingsSessionPrinters.setDefault' "$settings_page" ||
  fail "SettingsPrinters coverage names tip-true setDefault"
grep -Fq 'does not invent a printers.provider durable writer' "$settings_page" ||
  fail "SettingsPrinters coverage refuses printers.provider durable writer"

if grep -Eqi 'claim=present' "$settings_page" && ! grep -Eqi 'not claim=present|Never claim=present|never claim=present' "$settings_page"; then
  fail "SettingsPrinters must not invent claim=present"
fi
if grep -Eqi 'LIVE CONTROL' "$settings_session"; then
  fail "SettingsSessionPrinters must not invent LIVE CONTROL"
fi
if grep -Eqi 'Settings Power LIVE' "$settings_page"; then
  fail "SettingsPrinters must not invent Settings Power LIVE"
fi
if grep -Eqi 'End Task LIVE' "$settings_page"; then
  fail "SettingsPrinters must not invent End Task LIVE"
fi
if grep -Eqi 'Win7 visual closed|Win7 visual leftover CLOSED' "$settings_page"; then
  fail "SettingsPrinters must not invent Win7 visual closed"
fi

pass "Settings Printers hosts tip-true setDefault plane without invent"

python3 - "$catalog" "$jobs" "$gaps" "$parity" "$handoff" "$project" "$settings_docs" "$acc" "$settings_page" "$settings_session" "$settings_model" <<'PY'
import json
import sys

catalog = json.loads(open(sys.argv[1], encoding="utf-8").read())
jobs = json.loads(open(sys.argv[2], encoding="utf-8").read())
gaps = open(sys.argv[3], encoding="utf-8").read()
parity = open(sys.argv[4], encoding="utf-8").read()
handoff = open(sys.argv[5], encoding="utf-8").read()
project = open(sys.argv[6], encoding="utf-8").read()
settings_docs = open(sys.argv[7], encoding="utf-8").read()
acc = open(sys.argv[8], encoding="utf-8").read()
settings_page = open(sys.argv[9], encoding="utf-8").read()
settings_session = open(sys.argv[10], encoding="utf-8").read()
settings_model = open(sys.argv[11], encoding="utf-8").read()

by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
manage = by_id["printers.manage"]
route = manage["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"printers.manage route is {route}")
if route.get("path") != "Settings > Printers":
    raise SystemExit(f"printers.manage path is {route}")
if manage.get("availability", {}).get("claim") == "present":
    raise SystemExit("printers.manage must not claim present")
if manage.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"printers.manage claim is {manage.get('availability')}")
if manage.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"printers.manage human is {manage.get('availability')}")
if manage.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"printers.manage agent is {manage.get('availability')}")
if manage.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"printers.manage provider state is {manage.get('provider')}")
if manage.get("provider", {}).get("id") != "printer.provider":
    raise SystemExit(f"printers.manage provider is {manage.get('provider')}")
if manage.get("source", {}).get("file") != "shell/apps/shared/SettingsSessionPrinters.qml":
    raise SystemExit(f"printers.manage source is {manage.get('source')}")
if manage.get("source", {}).get("symbol") != "setDefault":
    raise SystemExit(f"printers.manage source symbol is {manage.get('source')}")
recovery = manage.get("recovery") or {}
if recovery.get("mode") != "compensating":
    raise SystemExit(f"printers.manage recovery mode is {recovery}")
if recovery.get("stateFingerprintRequired") is not False:
    raise SystemExit(f"printers.manage recovery fingerprint invent: {recovery}")
exp = recovery.get("expectation") or ""
for needle in (
    "setDefault",
    "printer-default-set",
    "resumeQueue",
    "printer-resume",
    "SettingsSessionPrinters",
    "no Fabric durable undo fingerprint invent",
    "no timed auto-rollback",
):
    if needle not in exp:
        raise SystemExit(f"printers.manage recovery missing {needle!r}: {exp}")
if "state-fingerprint-guarded" in exp:
    raise SystemExit(f"printers.manage still invents fingerprint-guarded compensating path: {exp}")

by_job = {job["id"]: job for job in jobs["jobs"]}
native32 = by_job["windows-native.32"]
if native32.get("claim") == "present":
    raise SystemExit("windows-native.32 must not claim present")
if native32.get("claim") != "prototype":
    raise SystemExit(f"windows-native.32 claim is {native32.get('claim')}")
if native32.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.32 sourceStatus is {native32.get('sourceStatus')}")
if native32.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.32 proofStatus is {native32.get('proofStatus')}")
if native32.get("capabilityIds") != ["printers.manage"]:
    raise SystemExit(f"windows-native.32 capabilityIds are {native32.get('capabilityIds')}")
if native32.get("humanRoute", {}).get("path") != "Settings > Printers":
    raise SystemExit(f"windows-native.32 path is {native32.get('humanRoute')}")
if native32.get("humanRoute", {}).get("status") != "visible":
    raise SystemExit(f"windows-native.32 route is {native32.get('humanRoute')}")
if native32.get("humanRoute", {}).get("surface") != "Settings":
    raise SystemExit(f"windows-native.32 surface is {native32.get('humanRoute')}")
rec32 = native32.get("recoveryExpectation") or ""
for needle in ("setDefault", "printer-default-set", "resumeQueue", "printer-resume", "Settings > Printers", "no timed auto-rollback", "no Add-setup"):
    if needle not in rec32:
        raise SystemExit(f"windows-native.32 recovery missing {needle!r}")
if "fingerprint invent" not in rec32.lower() and "no Fabric durable undo fingerprint invent" not in rec32:
    raise SystemExit(f"windows-native.32 recovery must refuse Fabric fingerprint invent: {rec32}")
if "Cancel setup" in rec32 or "newly added printer" in rec32.lower():
    raise SystemExit(f"windows-native.32 recovery still invents Add-setup: {rec32}")

devices = by_job["parity.devices-printers"]
if devices.get("claim") == "present":
    raise SystemExit("parity.devices-printers must not claim present")

if "| 32 | Add a printer | pending |" not in acc:
    raise SystemExit("WINDOWS_NATIVE_ACCEPTANCE must keep wn.32 pending")

required_gaps = [
    "Honesty addendum 2026-09-06 vs Settings Printers leftover plane (windows-native.32)",
    "| `windows-native.32` | prototype/pending | visible: Settings > Printers |",
    "setDefault",
    "SettingsSessionPrinters",
    "printers.manage",
    "not product CLOSED",
    "not metal CLOSED",
    "not claim=present",
    "Do not invent Settings Power LIVE",
    "Do not invent End Task LIVE",
    "claims: missing=29, partial=6, plumbing=4, present=0, prototype=43",
]
for needle in required_gaps:
    if needle not in gaps:
        raise SystemExit(f"fleet-doctrine-gaps missing {needle!r}")
if "CLOSED leftover: Settings Printers" in gaps.split(
    "Honesty addendum 2026-09-06 vs Settings Printers leftover plane (windows-native.32)", 1
)[1].split("Honesty addendum", 1)[0]:
    raise SystemExit("fleet-doctrine-gaps invents CLOSED leftover for soft leftover-attach ACC wn.32")
if "windows-native.32 stays prototype/pending" not in gaps.replace("`", ""):
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.32 prototype/pending")

required_handoff = [
    "Honesty addendum 2026-09-06 vs Settings Printers leftover plane (windows-native.32)",
    "Settings > Printers",
    "printers.manage",
    "setDefault",
    "SettingsSessionPrinters",
    "not claim=present",
]
for needle in required_handoff:
    if needle not in handoff:
        raise SystemExit(f"HANDOFF_WRITERS missing {needle!r}")
if "windows-native.32 stays prototype/pending" not in handoff.replace("`", ""):
    raise SystemExit("HANDOFF_WRITERS must keep windows-native.32 prototype/pending")
if "`printers.manage` stays leftover" not in handoff:
    raise SystemExit("HANDOFF_WRITERS must tip-align printers.manage debt honesty")

if "soft leftover-attaches" not in parity.lower() or "windows-native.32" not in parity:
    raise SystemExit("PARITY must soft leftover-attach wn.32")
if "setDefault" not in parity or "SettingsSessionPrinters" not in parity:
    raise SystemExit("PARITY must name tip-true SettingsSessionPrinters.setDefault")

if "windows-native.32" not in project:
    raise SystemExit("project-ultimate must keep windows-native.32")
if "setDefault" not in project or "SettingsSessionPrinters" not in project:
    raise SystemExit("project-ultimate must name tip-true SettingsSessionPrinters.setDefault plane")

if "windows-native.32" not in settings_docs:
    raise SystemExit("settings-service-api must keep windows-native.32")
if "prototype/pending" not in settings_docs:
    raise SystemExit("settings-service-api must keep windows-native.32 prototype/pending")
if "setDefault" not in settings_docs and "SettingsSessionPrinters" not in settings_docs:
    raise SystemExit("settings-service-api must name tip-true printers plane")

if "function setDefault(" not in settings_session:
    raise SystemExit("SettingsSessionPrinters must host setDefault")
if "printer-default-set" not in settings_session:
    raise SystemExit("SettingsSessionPrinters must call printer-default-set")
if "soft leftover-attach" not in settings_page.lower() or "windows-native.32" not in settings_page:
    raise SystemExit("SettingsPrinters must soft leftover-attach wn.32")
if "windows-native.32 stays prototype/pending" not in settings_page:
    raise SystemExit("SettingsPrinters must keep wn.32 prototype/pending")
if "SettingsSessionPrinters.setDefault" not in settings_model and "setDefault" not in settings_model:
    raise SystemExit("SettingsModel must tip-align SettingsSessionPrinters.setDefault")
if "windows-native.32 stays prototype/pending" not in settings_model:
    raise SystemExit("SettingsModel must keep wn.32 prototype/pending")
PY

pass "printers.manage stays partial with visible Settings > Printers soft leftover-attached to wn.32"
