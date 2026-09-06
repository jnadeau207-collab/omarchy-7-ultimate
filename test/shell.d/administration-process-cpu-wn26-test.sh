#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

admin_app="$ROOT/shell/apps/ultimate-administration/AdministrationApplication.qml"
admin_model="$ROOT/shell/apps/ultimate-administration/AdministrationModel.js"
admin_routes="$ROOT/shell/apps/ultimate-administration/routes-v1.json"
process_provider="$ROOT/default/fabric/omarchy_fabric/providers/process/provider.py"
readers="$ROOT/default/ultimate/capabilities/catalog-provider-readers-v0.json"
writers="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
controlpanel="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-catalog-controlpanel.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
plan="$ROOT/plans/project-ultimate.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
docs="$ROOT/docs/administration-recovery-providers.md"

[[ -f $admin_app ]] || fail "Administration application exists"
[[ -f $admin_model ]] || fail "Administration model exists"
[[ -f $process_provider ]] || fail "process.provider exists"

grep -Fq 'FixedArgvCommand' "$process_provider" || fail "process.provider uses FixedArgvCommand"
grep -Fq '"/usr/bin/ps"' "$process_provider" || fail "process.provider pins absolute /usr/bin/ps"
grep -Fq 'pcpu=' "$process_provider" || fail "process.provider requests pcpu CPU share"
grep -Fq 'cpuPercent' "$process_provider" || fail "process.provider publishes cpuPercent"
if grep -Eq 'shell=True|bash -c|/bin/sh -c' "$process_provider"; then
  fail "process.provider must not invent shell-string process inspect"
fi
if grep -Eqi 'terminationAuthorized\s*[:=]\s*true' "$admin_app"; then
  fail "Administration must not invent terminationAuthorized=true"
fi
grep -Fq 'readonly property bool terminationAuthorized: false' "$admin_app" ||
  fail "Administration keeps terminationAuthorized=false"

grep -Fq 'resourceCpuPercent' "$admin_model" || fail "Administration model exposes resourceCpuPercent"
grep -Fq 'CPU " + cpuPercent + "%"' "$admin_model" || fail "Administration process subtitle names CPU percent"
grep -Fq 'query.providerId === "process.provider"' "$admin_model" ||
  fail "Administration sorts process.provider records by CPU"
grep -Fq 'FixedArgv /usr/bin/ps' "$admin_model" || fail "Administration coverage names FixedArgv /usr/bin/ps"
grep -Fq 'session leftover recorded' "$admin_model" || fail "Administration coverage records a session leftover"
grep -Fq 'session-UI leftover only' "$admin_model" || fail "Administration coverage names session-UI leftover only"
grep -Fq 'not claim=present' "$admin_model" || fail "Administration coverage refuses claim=present"
grep -Fq 'windows-native.26 stays prototype/pending' "$admin_model" ||
  fail "Administration coverage keeps wn.26 pending"
grep -Fq 'End Task stays OPEN leftover' "$admin_model" || fail "Administration coverage keeps End Task OPEN leftover"
grep -Fq 'terminationAuthorized=false' "$admin_model" || fail "Administration coverage names terminationAuthorized=false"

grep -Fq 'FixedArgv /usr/bin/ps' "$admin_routes" || fail "Administration routes name FixedArgv /usr/bin/ps"
grep -Fq 'End Task stays OPEN leftover' "$admin_routes" || fail "Administration routes keep End Task OPEN leftover"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-administration/AdministrationModel.js')

const low = Model.normalizeLeafResource({
  id: 'process.1.aaaaaaaaaaaaaaaa',
  label: 'idle',
  kind: 'process',
  cpuPercent: 1.5,
  uid: 1000,
  command: 'idle',
  memoryPercent: 0.1,
  residentKb: 1024,
  groupId: 'process-group.aaaaaaaaaaaaaaaa',
  observedCount: 2,
  inventoryTruncated: false,
  state: {
    lifecycle: 'running',
    startDigest: 'aaaaaaaaaaaaaaaa',
    identityRevision: `sha256.${'a'.repeat(64)}`,
    plannedSignal: null
  }
}, 0)
const high = Model.normalizeLeafResource({
  id: 'process.2.bbbbbbbbbbbbbbbb',
  label: 'busy',
  kind: 'process',
  cpuPercent: 87.2,
  uid: 1000,
  command: 'busy',
  memoryPercent: 2.0,
  residentKb: 4096,
  groupId: 'process-group.bbbbbbbbbbbbbbbb',
  observedCount: 2,
  inventoryTruncated: false,
  state: {
    lifecycle: 'running',
    startDigest: 'bbbbbbbbbbbbbbbb',
    identityRevision: `sha256.${'b'.repeat(64)}`,
    plannedSignal: null
  }
}, 1)

assert(low && high, 'process resources with cpuPercent normalize')
assertEqual(low.cpuPercent, 1.5, 'low CPU process keeps typed cpuPercent')
assertEqual(high.cpuPercent, 87.2, 'high CPU process keeps typed cpuPercent')
assertEqual(high.subtitle, 'CPU 87.2%', 'process subtitle surfaces CPU percent')
assertEqual(Model.resourceCpuPercent(high), 87.2, 'resourceCpuPercent reads tip-true cpuPercent')
assertEqual(Model.resourceCpuPercent({ kind: 'service', cpuPercent: 9 }), null, 'non-process resources do not invent CPU')

const query = Model.queryForRoute('administration.processes.overview')
assert(query, 'Processes domain query exists')
assertEqual(query.providerId, 'process.provider', 'Processes query binds process.provider')
assertEqual(query.capability, 'process.inspect', 'Processes query binds process.inspect')
assert(query.coverage.indexOf('FixedArgv /usr/bin/ps') >= 0, 'Processes coverage names FixedArgv /usr/bin/ps')
assert(query.coverage.indexOf('not claim=present') >= 0, 'Processes coverage refuses claim=present')
assert(query.coverage.indexOf('windows-native.26 stays prototype/pending') >= 0, 'Processes coverage keeps wn.26 pending')
assert(query.coverage.indexOf('OPEN leftover') >= 0, 'Processes coverage keeps End Task OPEN leftover')

const value = {
  resources: [
    {
      id: 'process.1.aaaaaaaaaaaaaaaa',
      label: 'idle',
      kind: 'process',
      cpuPercent: 1.5,
      uid: 1000,
      command: 'idle',
      memoryPercent: 0.1,
      residentKb: 1024,
      groupId: 'process-group.aaaaaaaaaaaaaaaa',
      observedCount: 2,
      inventoryTruncated: false,
      state: {
        lifecycle: 'running',
        startDigest: 'aaaaaaaaaaaaaaaa',
        identityRevision: `sha256.${'a'.repeat(64)}`,
        plannedSignal: null
      }
    },
    {
      id: 'process.2.bbbbbbbbbbbbbbbb',
      label: 'busy',
      kind: 'process',
      cpuPercent: 87.2,
      uid: 1000,
      command: 'busy',
      memoryPercent: 2.0,
      residentKb: 4096,
      groupId: 'process-group.bbbbbbbbbbbbbbbb',
      observedCount: 2,
      inventoryTruncated: false,
      state: {
        lifecycle: 'running',
        startDigest: 'bbbbbbbbbbbbbbbb',
        identityRevision: `sha256.${'b'.repeat(64)}`,
        plannedSignal: null
      }
    }
  ]
}
const normalized = Model.normalizedRecords(query, value, '')
assertEqual(normalized.records[0].label, 'busy', 'highest CPU process sorts first')
assertEqual(normalized.records[1].label, 'idle', 'lower CPU process sorts after')
assertEqual(normalized.records[0].subtitle, 'CPU 87.2%', 'sorted process keeps CPU subtitle')
JS
pass "Administration CPU process plane sorts and subtitles from tip-true cpuPercent"

python3 - "$ROOT" <<'PY' || fail "catalog and honesty keep process CPU leftover without claim=present"
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
readers = json.loads((root / "default/ultimate/capabilities/catalog-provider-readers-v0.json").read_text(encoding="utf-8"))
writers = json.loads((root / "default/ultimate/capabilities/catalog-system-jobs-v0.json").read_text(encoding="utf-8"))
jobs = json.loads((root / "default/ultimate/parity/jobs.json").read_text(encoding="utf-8"))
by_id = {row["id"]: row for row in readers["capabilities"] + writers["capabilities"]}

inspect = by_id["process.inspect"]
if inspect.get("availability", {}).get("claim") == "present":
    raise SystemExit("process.inspect must not claim present")
if inspect.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"process.inspect claim is {inspect.get('availability')}")
if inspect.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"process.inspect human availability is {inspect.get('availability')}")
if inspect.get("provider", {}).get("state") != "present":
    raise SystemExit(f"process.inspect provider state drifted: {inspect.get('provider')}")
if inspect.get("humanRoute", {}).get("path") != "Administration > Processes":
    raise SystemExit(f"process.inspect route drifted: {inspect.get('humanRoute')}")
if "Task Manager" in str(inspect.get("humanRoute") or {}):
    raise SystemExit(f"process.inspect invents Task Manager route: {inspect.get('humanRoute')}")
if inspect.get("source", {}).get("file") != "default/fabric/omarchy_fabric/providers/process/provider.py":
    raise SystemExit(f"process.inspect source drifted: {inspect.get('source')}")
if inspect.get("source", {}).get("symbol") != "build_provider":
    raise SystemExit(f"process.inspect source symbol drifted: {inspect.get('source')}")

termination = by_id["process.termination.plan"]
if termination.get("availability", {}).get("claim") != "missing":
    raise SystemExit(f"process.termination.plan must stay missing/OPEN leftover: {termination.get('availability')}")
if termination.get("availability", {}).get("human") == "present":
    raise SystemExit("process.termination.plan must not claim human present")
if termination.get("consent", {}).get("mode") != "high-risk":
    raise SystemExit(f"process.termination.plan consent drifted: {termination.get('consent')}")

provider = (root / "default/fabric/omarchy_fabric/providers/process/provider.py").read_text(encoding="utf-8")
if 'PROCESS_COMMAND = FixedArgvCommand(\n    "/usr/bin/ps",\n    ("-ww", "-eo", "pid=,uid=,pcpu=,pmem=,rss=,comm=,cgroup="),\n)' not in provider:
    raise SystemExit("process.provider FixedArgv /usr/bin/ps pcpu argv drifted")
if "shell=True" in provider:
    raise SystemExit("process.provider invented shell=True")

native26 = next(row for row in jobs["jobs"] if row["id"] == "windows-native.26")
if native26.get("sourceStatus") != "pending" or native26.get("claim") != "prototype":
    raise SystemExit(f"windows-native.26 must stay prototype/pending: {native26}")
if native26.get("humanRoute") != {"status": "visible", "surface": "Administration", "path": "Administration > Processes"}:
    raise SystemExit(f"windows-native.26 humanRoute drifted: {native26.get('humanRoute')}")
if native26.get("capabilityIds") != ["process.inspect"]:
    raise SystemExit(f"windows-native.26 capabilityIds drifted: {native26.get('capabilityIds')}")
if "OPEN leftover" not in str(native26.get("recoveryExpectation") or ""):
    raise SystemExit(f"windows-native.26 recoveryExpectation dropped End Task OPEN leftover: {native26.get('recoveryExpectation')}")

parity_task = next(row for row in jobs["jobs"] if row["id"] == "parity.task-manager")
if parity_task.get("claim") != "missing" or parity_task.get("sourceStatus") != "missing as product":
    raise SystemExit(f"parity.task-manager walked off missing as product: {parity_task}")
if parity_task["humanRoute"].get("path"):
    raise SystemExit(f"parity.task-manager invents a product path: {parity_task['humanRoute']}")

parity = (root / "WINDOWS_7_ULTIMATE_PARITY.md").read_text(encoding="utf-8")
if "availability.claim=partial" not in parity and "availability.claim=partial / human=partial" not in parity:
    raise SystemExit("parity must soft leftover-attach process.inspect claim=partial")
if "windows-native.26` stays prototype/pending" not in parity and "`windows-native.26` stays prototype/pending" not in parity:
    raise SystemExit("parity must keep windows-native.26 pending")
if "End Task stays OPEN leftover" not in parity and "End Task stays OPEN leftover / hidden" not in parity:
    raise SystemExit("parity must keep End Task OPEN leftover")
if "claim=present" in parity and "not claim=present" not in parity:
    raise SystemExit("parity must not invent claim=present for process CPU plane")
if "Task Manager present" in parity and "honest-unavailable as Task Manager product" not in parity:
    raise SystemExit("parity invented Task Manager present")

gaps = (root / "plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md").read_text(encoding="utf-8")
if "process CPU leftover plane" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must record process CPU leftover plane")
if "windows-native.26" not in gaps or "prototype/pending" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.26 prototype/pending")
if "/usr/bin/ps" not in gaps or "pcpu" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must name FixedArgv /usr/bin/ps pcpu")
if "OPEN leftover" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must keep End Task OPEN leftover")
if "Cloud EXIT 0 is not metal leftover CLOSED" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must refuse Cloud EXIT 0 as metal CLOSED")

controlpanel = (root / "plans/win7-ultimate-ground-truth/fleet/fleet-catalog-controlpanel.md").read_text(encoding="utf-8")
if "claim=**partial**" not in controlpanel and "claim=partial" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must soft leftover-attach process.inspect claim=partial")
if "windows-native.26 stays prototype/pending" not in controlpanel and "`windows-native.26` stays prototype/pending" not in controlpanel:
    raise SystemExit("fleet-catalog-controlpanel must keep windows-native.26 pending")

plan = (root / "plans/project-ultimate.md").read_text(encoding="utf-8")
if "claim=partial / human=partial" not in plan:
    raise SystemExit("project-ultimate must soft leftover-attach process.inspect claim=partial")
if "windows-native.26 stays prototype/pending" not in plan and "`windows-native.26` stays prototype/pending" not in plan:
    raise SystemExit("project-ultimate must keep windows-native.26 pending")
if "honest-unavailable as Task Manager" not in plan:
    raise SystemExit("project-ultimate must keep Task Manager product honest-unavailable")

handoff = (root / "HANDOFF_WRITERS_2026-09-01.md").read_text(encoding="utf-8")
if "windows-native.26" not in handoff or "process CPU leftover plane" not in handoff:
    raise SystemExit("handoff must record process CPU leftover plane")
if "terminationAuthorized=false" not in handoff:
    raise SystemExit("handoff must keep terminationAuthorized=false")
if "not claim=present" not in handoff:
    raise SystemExit("handoff must refuse claim=present")

docs = (root / "docs/administration-recovery-providers.md").read_text(encoding="utf-8")
if "/usr/bin/ps" not in docs or "pcpu" not in docs:
    raise SystemExit("administration-recovery-providers must name FixedArgv /usr/bin/ps pcpu")
if "claim=partial" not in docs:
    raise SystemExit("administration-recovery-providers must name process.inspect claim=partial")
if "OPEN leftover" not in docs:
    raise SystemExit("administration-recovery-providers must keep End Task OPEN leftover")
PY
pass "catalog and honesty keep process CPU leftover-direct without claim=present"

pass "administration process CPU wn.26 leftover plane locked"
