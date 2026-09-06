#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

start_qml="$ROOT/shell/plugins/ultimate-start/Start.qml"
shutdown_bin="$ROOT/bin/omarchy-system-shutdown"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
project="$ROOT/plans/project-ultimate.md"
controlpanel="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-catalog-controlpanel.md"
acc="$ROOT/WINDOWS_NATIVE_ACCEPTANCE.md"

[[ -f $start_qml ]] || fail "Start.qml exists"
[[ -f $shutdown_bin ]] || fail "omarchy-system-shutdown exists"

grep -Fq 'text: "Shut down"' "$start_qml" || fail "Start hosts Shut down button"
grep -Fq 'Util.execDetached("omarchy-system-shutdown")' "$start_qml" ||
  fail "Start Shut down calls omarchy-system-shutdown"
grep -Fq 'command: "omarchy-system-shutdown"' "$start_qml" ||
  fail "Start power flyout includes omarchy-system-shutdown"
grep -Fq 'label: "Shut down"' "$start_qml" || fail "Start power flyout labels Shut down"
grep -Fq 'systemctl poweroff' "$shutdown_bin" || fail "omarchy-system-shutdown schedules systemctl poweroff"
grep -Fq 'systemd-run --user' "$shutdown_bin" || fail "omarchy-system-shutdown uses systemd-run --user"

if grep -Eqi 'claim=present' "$start_qml"; then
  fail "Start must not invent claim=present"
fi
if grep -Eqi 'Settings Power LIVE' "$start_qml"; then
  fail "Start must not invent Settings Power LIVE"
fi
if grep -Eqi 'Empty Bin LIVE' "$start_qml"; then
  fail "Start must not invent Empty Bin LIVE"
fi
if grep -Eqi 'End Task LIVE' "$start_qml"; then
  fail "Start must not invent End Task LIVE"
fi
if grep -Eqi 'Win7 visual closed|Win7 visual leftover CLOSED' "$start_qml"; then
  fail "Start must not invent Win7 visual closed"
fi
if grep -Eqi 'phase 5' "$start_qml"; then
  fail "Start must not invent a Phase 5 fence"
fi

pass "Start hosts tip-true Shut down → omarchy-system-shutdown plane without invent"

python3 - "$catalog" "$jobs" "$gaps" "$parity" "$handoff" "$project" "$controlpanel" "$acc" "$start_qml" "$shutdown_bin" <<'PY'
import json
import sys

catalog = json.loads(open(sys.argv[1], encoding="utf-8").read())
jobs = json.loads(open(sys.argv[2], encoding="utf-8").read())
gaps = open(sys.argv[3], encoding="utf-8").read()
parity = open(sys.argv[4], encoding="utf-8").read()
handoff = open(sys.argv[5], encoding="utf-8").read()
project = open(sys.argv[6], encoding="utf-8").read()
controlpanel = open(sys.argv[7], encoding="utf-8").read()
acc = open(sys.argv[8], encoding="utf-8").read()
start_qml = open(sys.argv[9], encoding="utf-8").read()
shutdown_bin = open(sys.argv[10], encoding="utf-8").read()

by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
shutdown = by_id["power.shutdown"]
route = shutdown["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Start":
    raise SystemExit(f"power.shutdown route is {route}")
if route.get("path") != "Start > Shut down":
    raise SystemExit(f"power.shutdown path is {route}")
if route.get("label") != "Shut down":
    raise SystemExit(f"power.shutdown label is {route}")
if shutdown.get("availability", {}).get("claim") == "present":
    raise SystemExit("power.shutdown must not claim present")
if shutdown.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"power.shutdown claim is {shutdown.get('availability')}")
if shutdown.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"power.shutdown human is {shutdown.get('availability')}")
if shutdown.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"power.shutdown agent is {shutdown.get('availability')}")
if shutdown.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"power.shutdown provider state is {shutdown.get('provider')}")
if shutdown.get("provider", {}).get("id") != "power.provider":
    raise SystemExit(f"power.shutdown provider is {shutdown.get('provider')}")
if shutdown.get("source", {}).get("file") != "shell/plugins/ultimate-start/Start.qml":
    raise SystemExit(f"power.shutdown source is {shutdown.get('source')}")
if shutdown.get("source", {}).get("symbol") != "Start.shutdown":
    raise SystemExit(f"power.shutdown source symbol is {shutdown.get('source')}")
recovery = shutdown.get("recovery") or {}
if recovery.get("mode") != "none":
    raise SystemExit(f"power.shutdown recovery mode is {recovery}")
if recovery.get("stateFingerprintRequired") is not False:
    raise SystemExit(f"power.shutdown recovery fingerprint is {recovery}")
exp = recovery.get("expectation") or ""
for needle in (
    "Start.shutdown",
    "omarchy-system-shutdown",
    "systemctl poweroff",
    "irreversible poweroff",
    "no undo",
    "no compensating fingerprint invent",
    "visible Shut down choice",
):
    if needle not in exp:
        raise SystemExit(f"power.shutdown recovery missing {needle!r}: {exp}")

by_job = {job["id"]: job for job in jobs["jobs"]}
native40 = by_job["windows-native.40"]
if native40.get("claim") == "present":
    raise SystemExit("windows-native.40 must not claim present")
if native40.get("claim") != "prototype":
    raise SystemExit(f"windows-native.40 claim is {native40.get('claim')}")
if native40.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.40 sourceStatus is {native40.get('sourceStatus')}")
if native40.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.40 proofStatus is {native40.get('proofStatus')}")
if native40.get("capabilityIds") != ["power.shutdown"]:
    raise SystemExit(f"windows-native.40 capabilityIds are {native40.get('capabilityIds')}")
if native40.get("humanRoute", {}).get("path") != "Start > Shut down":
    raise SystemExit(f"windows-native.40 path is {native40.get('humanRoute')}")
if native40.get("humanRoute", {}).get("status") != "visible":
    raise SystemExit(f"windows-native.40 route is {native40.get('humanRoute')}")
if native40.get("humanRoute", {}).get("surface") != "Start":
    raise SystemExit(f"windows-native.40 surface is {native40.get('humanRoute')}")
rec40 = native40.get("recoveryExpectation") or ""
for needle in ("Start.shutdown", "omarchy-system-shutdown", "irreversible poweroff", "no undo"):
    if needle not in rec40:
        raise SystemExit(f"windows-native.40 recovery missing {needle!r}")

parity_start = by_job["parity.start"]
if parity_start.get("claim") == "present":
    raise SystemExit("parity.start must not claim present")
if parity_start.get("claim") != "prototype":
    raise SystemExit(f"parity.start claim is {parity_start.get('claim')}")
if "power.shutdown" not in (parity_start.get("capabilityIds") or []):
    raise SystemExit("parity.start must name power.shutdown")
rec_start = parity_start.get("recoveryExpectation") or ""
for needle in ("windows-native.40", "Start.shutdown", "omarchy-system-shutdown"):
    if needle not in rec_start:
        raise SystemExit(f"parity.start recovery missing {needle!r}")

if "| 40 | Shut down | pending |" not in acc:
    raise SystemExit("WINDOWS_NATIVE_ACCEPTANCE must keep wn.40 pending")

required_gaps = [
    "Honesty addendum 2026-09-06 vs Start Shut down leftover plane (windows-native.40)",
    "| `windows-native.40` | prototype/pending | visible: Start > Shut down |",
    "Start.shutdown",
    "omarchy-system-shutdown",
    "power.shutdown",
    "not product CLOSED",
    "not metal CLOSED",
    "not claim=present",
    "Do not invent Settings Power LIVE",
    "Do not invent Empty Bin LIVE",
    "Do not invent End Task LIVE",
]
for needle in required_gaps:
    if needle not in gaps:
        raise SystemExit(f"fleet-doctrine-gaps missing {needle!r}")
if "| `windows-native.40` | prototype/pending | visible: Start > Shut down | **Shut down.** Shut down from Start power flyout with mouse. | OK if Start power works. |" in gaps:
    raise SystemExit("fleet-doctrine-gaps still has tip-false wn.40 invent OK if Start power works")
if "windows-native.40 stays prototype/pending" not in gaps.replace("`", ""):
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.40 prototype/pending")
if "claims: missing=30, partial=6, plumbing=4, present=0, prototype=42" not in gaps:
    raise SystemExit("fleet-doctrine-gaps job header must match jobs.json claims after wn.40 soft leftover-attach")

required_handoff = [
    "Honesty addendum 2026-09-06 vs Start Shut down leftover plane (windows-native.40)",
    "Start > Shut down",
    "power.shutdown",
    "not claim=present",
    "Start.shutdown",
    "omarchy-system-shutdown",
]
for needle in required_handoff:
    if needle not in handoff:
        raise SystemExit(f"HANDOFF_WRITERS missing {needle!r}")
if "windows-native.40 stays prototype/pending" not in handoff.replace("`", ""):
    raise SystemExit("HANDOFF_WRITERS must keep windows-native.40 prototype/pending")

if "soft leftover-attaches `windows-native.40`" not in parity and "soft leftover-attaches windows-native.40" not in parity:
    raise SystemExit("PARITY must soft leftover-attach wn.40")
if 'Forty-task "Shut down" stays pending' not in parity and "Forty-task \"Shut down\" stays pending" not in parity:
    raise SystemExit("PARITY must keep forty-task Shut down pending")
if "Start.shutdown" not in parity or "omarchy-system-shutdown" not in parity:
    raise SystemExit("PARITY must name tip-true Start.shutdown → omarchy-system-shutdown")

if "windows-native.40" not in project:
    raise SystemExit("project-ultimate must keep windows-native.40")
if "Start.shutdown" not in project and "omarchy-system-shutdown" not in project:
    raise SystemExit("project-ultimate must name Start Shut down plane")

if "windows-native.40" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must keep windows-native.40")
if "Start.shutdown" not in controlpanel and "omarchy-system-shutdown" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must name Start.shutdown plane")

if 'Util.execDetached("omarchy-system-shutdown")' not in start_qml:
    raise SystemExit("Start.qml must keep Shut down → omarchy-system-shutdown")
if "systemctl poweroff" not in shutdown_bin:
    raise SystemExit("omarchy-system-shutdown must keep systemctl poweroff")
if "systemd-run --user" not in shutdown_bin:
    raise SystemExit("omarchy-system-shutdown must keep systemd-run --user")
PY

pass "power.shutdown stays partial with visible Start > Shut down soft leftover-attached to wn.40"
