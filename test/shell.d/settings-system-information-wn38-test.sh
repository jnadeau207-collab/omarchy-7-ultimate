#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

settings_model="$ROOT/shell/apps/ultimate-settings/SettingsModel.js"
settings_card="$ROOT/shell/apps/ultimate-settings/SettingsSystemInformation.qml"
session_info="$ROOT/shell/apps/shared/SettingsSessionSystemInformation.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
project="$ROOT/plans/project-ultimate.md"
settings_api="$ROOT/docs/settings-service-api.md"
acc="$ROOT/WINDOWS_NATIVE_ACCEPTANCE.md"

[[ -f $settings_model ]] || fail "Settings model exists"
[[ -f $settings_card ]] || fail "SettingsSystemInformation exists"
[[ -f $session_info ]] || fail "SettingsSessionSystemInformation exists"

grep -Fq 'function readInformation(' "$session_info" || fail "SettingsSessionSystemInformation hosts readInformation"
grep -Fq 'system-information-inspect' "$session_info" || fail "SettingsSessionSystemInformation targets system-information-inspect"
grep -Fq 'sessionHost.readInformation' "$settings_card" || fail "SettingsSystemInformation routes through readInformation"
grep -Fiq 'soft leftover-attaches windows-native.38' "$settings_model" ||
  fail "System honesty soft leftover-attaches wn.38"
grep -Fq 'windows-native.38 stays prototype/pending' "$settings_model" ||
  fail "System honesty keeps windows-native.38 prototype/pending"
grep -Fq 'not product CLOSED' "$settings_model" || fail "System honesty refuses product CLOSED"
grep -Fq 'not metal CLOSED' "$settings_model" || fail "System honesty refuses metal CLOSED"
grep -Fq 'not claim=present' "$settings_model" || fail "System honesty refuses claim=present"
grep -Fq 'SettingsSessionSystemInformation.readInformation' "$settings_model" ||
  fail "System coverage names tip-true readInformation"
grep -Fq 'apply_system_information_inspect' "$settings_model" ||
  fail "System coverage names apply_system_information_inspect"
grep -Fq 'does not invent a system-information.provider durable writer' "$settings_model" ||
  fail "System coverage refuses Fabric system-information writer"
grep -Eqi 'soft leftover-attaches windows-native.38' "$settings_card" ||
  fail "SettingsSystemInformation honesty soft leftover-attaches wn.38"
grep -Fq 'windows-native.38 stays prototype/pending' "$settings_card" ||
  fail "SettingsSystemInformation honesty keeps wn.38 prototype/pending"

if grep -Eqi 'claim=present' "$settings_model" && ! grep -Eqi 'not claim=present|Never claim=present|never claim=present' "$settings_model"; then
  fail "System must not invent claim=present"
fi
if grep -Eqi 'Settings Power LIVE' "$settings_model"; then
  fail "System must not invent Settings Power LIVE"
fi
if grep -Eqi 'Empty Bin LIVE' "$settings_model"; then
  fail "System must not invent Empty Bin LIVE"
fi
if grep -Eqi 'End Task LIVE' "$settings_model"; then
  fail "System must not invent End Task LIVE"
fi
if grep -Eqi 'Win7 visual closed|Win7 visual leftover CLOSED' "$settings_model"; then
  fail "System must not invent Win7 visual closed"
fi
if grep -Eqi 'phase 5' "$settings_model"; then
  fail "System must not invent a Phase 5 fence"
fi

pass "Settings System information hosts tip-true readInformation plane without invent"

python3 - "$catalog" "$jobs" "$gaps" "$parity" "$handoff" "$project" "$settings_api" "$acc" "$settings_model" "$settings_card" "$session_info" <<'PY'
import json
import sys

catalog = json.loads(open(sys.argv[1], encoding="utf-8").read())
jobs = json.loads(open(sys.argv[2], encoding="utf-8").read())
gaps = open(sys.argv[3], encoding="utf-8").read()
parity = open(sys.argv[4], encoding="utf-8").read()
handoff = open(sys.argv[5], encoding="utf-8").read()
project = open(sys.argv[6], encoding="utf-8").read()
settings_api = open(sys.argv[7], encoding="utf-8").read()
acc = open(sys.argv[8], encoding="utf-8").read()
settings_model = open(sys.argv[9], encoding="utf-8").read()
settings_card = open(sys.argv[10], encoding="utf-8").read()
session_info = open(sys.argv[11], encoding="utf-8").read()

by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
info = by_id["system.info.read"]
route = info["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Settings":
    raise SystemExit(f"system.info.read route is {route}")
if route.get("path") != "Settings > System information":
    raise SystemExit(f"system.info.read path is {route}")
if route.get("label") != "System information":
    raise SystemExit(f"system.info.read label is {route}")
if info.get("availability", {}).get("claim") == "present":
    raise SystemExit("system.info.read must not claim present")
if info.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"system.info.read claim is {info.get('availability')}")
if info.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"system.info.read human is {info.get('availability')}")
if info.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"system.info.read agent is {info.get('availability')}")
if info.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"system.info.read provider state is {info.get('provider')}")
if info.get("provider", {}).get("id") != "system.provider":
    raise SystemExit(f"system.info.read provider is {info.get('provider')}")
if info.get("kind") != "reader":
    raise SystemExit(f"system.info.read kind is {info.get('kind')}")
if info.get("source", {}).get("file") != "shell/apps/shared/SettingsSessionSystemInformation.qml":
    raise SystemExit(f"system.info.read source is {info.get('source')}")
if info.get("source", {}).get("symbol") != "readInformation":
    raise SystemExit(f"system.info.read source symbol is {info.get('source')}")
if "SettingsSystemInformation.qml" in str(info.get("source", {}).get("file") or ""):
    raise SystemExit("system.info.read must not invent source on SettingsSystemInformation.qml")
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
if native38.get("humanRoute", {}).get("path") != "Settings > System information":
    raise SystemExit(f"windows-native.38 path is {native38.get('humanRoute')}")
if native38.get("humanRoute", {}).get("status") != "visible":
    raise SystemExit(f"windows-native.38 route is {native38.get('humanRoute')}")
if native38.get("humanRoute", {}).get("surface") != "Settings":
    raise SystemExit(f"windows-native.38 surface is {native38.get('humanRoute')}")
rec38 = native38.get("recoveryExpectation") or ""
for needle in ("readInformation", "apply_system_information_inspect"):
    if needle not in rec38:
        raise SystemExit(f"windows-native.38 recovery missing {needle!r}")
if "fingerprint invent" not in rec38.lower() and "no Fabric fingerprint invent" not in rec38:
    raise SystemExit(f"windows-native.38 recovery must refuse Fabric fingerprint invent: {rec38}")

if "| 38 | Find system/storage information | pending |" not in acc:
    raise SystemExit("WINDOWS_NATIVE_ACCEPTANCE must keep wn.38 pending")

required_gaps = [
    "Honesty addendum 2026-09-06 vs Settings System information leftover plane (windows-native.38)",
    "| `windows-native.38` | prototype/pending | visible: Settings > System information |",
    "readInformation",
    "apply_system_information_inspect",
    "system.info.read",
    "not product CLOSED",
    "not metal CLOSED",
    "not claim=present",
    "Do not invent Settings Power LIVE",
    "Do not invent Empty Bin LIVE",
    "Do not invent End Task LIVE",
    "claims: missing=29, partial=6, plumbing=4, present=0, prototype=43",
]
for needle in required_gaps:
    if needle not in gaps:
        raise SystemExit(f"fleet-doctrine-gaps missing {needle!r}")
if "CLOSED leftover: Settings System information" in gaps.split(
    "Honesty addendum 2026-09-06 vs Settings System information leftover plane (windows-native.38)", 1
)[1].split("Honesty addendum", 1)[0]:
    raise SystemExit("fleet-doctrine-gaps invents CLOSED leftover for soft leftover-attach ACC wn.38")
if "windows-native.38 stays prototype/pending" not in gaps.replace("`", ""):
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.38 prototype/pending")
if "soft leftover-attach acc" not in gaps.lower():
    raise SystemExit("fleet-doctrine-gaps must soft leftover-attach ACC wn.38")

required_handoff = [
    "Honesty addendum 2026-09-06 vs Settings System information leftover plane (windows-native.38)",
    "Settings > System information",
    "system.info.read",
    "readInformation",
    "apply_system_information_inspect",
    "not claim=present",
]
for needle in required_handoff:
    if needle not in handoff:
        raise SystemExit(f"HANDOFF_WRITERS missing {needle!r}")
if "windows-native.38 stays prototype/pending" not in handoff.replace("`", ""):
    raise SystemExit("HANDOFF_WRITERS must keep windows-native.38 prototype/pending")

if "soft leftover-attaches" not in parity.lower() or "windows-native.38" not in parity:
    raise SystemExit("PARITY must soft leftover-attach wn.38")
if "readInformation" not in parity or "apply_system_information_inspect" not in parity:
    raise SystemExit("PARITY must name tip-true readInformation → apply_system_information_inspect")

if "windows-native.38" not in project:
    raise SystemExit("project-ultimate must keep windows-native.38")
if "readInformation" not in project or "apply_system_information_inspect" not in project:
    raise SystemExit("project-ultimate must name tip-true readInformation → apply_system_information_inspect plane")

if "windows-native.38" not in settings_api:
    raise SystemExit("settings-service-api must keep windows-native.38")
if "prototype/pending" not in settings_api:
    raise SystemExit("settings-service-api must keep windows-native.38 prototype/pending")
if "readInformation" not in settings_api and "apply_system_information_inspect" not in settings_api:
    raise SystemExit("settings-service-api must name tip-true system-information plane")

if "function readInformation(" not in session_info:
    raise SystemExit("SettingsSessionSystemInformation must host readInformation")
if "system-information-inspect" not in session_info:
    raise SystemExit("SettingsSessionSystemInformation must call system-information-inspect")
if "sessionHost.readInformation" not in settings_card:
    raise SystemExit("SettingsSystemInformation must route through readInformation")
if "soft leftover-attaches windows-native.38" not in settings_model.lower():
    raise SystemExit("SettingsModel must soft leftover-attach wn.38")
if "windows-native.38 stays prototype/pending" not in settings_model:
    raise SystemExit("SettingsModel must keep wn.38 prototype/pending")
PY

pass "system.info.read stays partial with visible Settings > System information soft leftover-attached to wn.38"
