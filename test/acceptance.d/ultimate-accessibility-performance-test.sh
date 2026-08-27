#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

quality_contract="$ROOT/default/ultimate/quality/atspi-feasibility-v0.json"
performance_contract="$ROOT/default/ultimate/quality/performance-baseline-v0.json"
checker="$ROOT/bin/omarchy-dev-quality-baseline"
failures=()
polkit_pid=""
required_surface_classes=("shell" "secure-lock" "oobe" "polkit")

cleanup_quality_acceptance() {
  omarchy-shell -q shell hide omarchy.dev-gallery >/dev/null 2>&1 || true
  omarchy-shell -q lock hidePreview >/dev/null 2>&1 || true
  if [[ -n $polkit_pid ]]; then
    kill "$polkit_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup_quality_acceptance EXIT

record_failure() {
  failures+=("$1")
}

for required in python3 hyprctl jq coredumpctl sha256sum pgrep wtype; do
  require_command "$required"
done

if ! python3 - <<'PY'
import gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
Atspi.init()
assert Atspi.get_desktop(0) is not None
PY
then
  fail "AT-SPI tooling initializes" "Python GI Atspi 2.0 is required; absence is a release failure"
fi
pass "AT-SPI tooling initializes"

OMARCHY_PATH="$ROOT" bash "$checker" check >/dev/null || fail "quality contracts validate before graphical acceptance"
pass "quality contracts validate before graphical acceptance"

for surface_class in "${required_surface_classes[@]}"; do
  jq -e --arg surface "$surface_class" '.surfaceClasses[] | select(.id == $surface)' "$quality_contract" >/dev/null ||
    fail "AT-SPI feasibility records $surface_class"
done
pass "AT-SPI feasibility explicitly records shell, secure lock, OOBE, and Polkit"

OMARCHY_PATH="$ROOT" OMARCHY_QUALITY_DISPOSABLE_VM=1 bash "$checker" probe-surfaces-once ||
  fail "bounded surface reliability probe" "The one-cycle probe detected a compositor restart, new coredump, or missing surface"
pass "bounded surface reliability probe"

if OMARCHY_PATH="$ROOT" python3 - "$performance_contract" "$ARTIFACTS/performance-live.json" <<'PY'
import json
import math
import os
import pathlib
import statistics
import subprocess
import sys
import time

contract = json.load(open(sys.argv[1], encoding="utf-8"))
artifact = pathlib.Path(sys.argv[2])
thresholds = {metric["id"]: metric["threshold"] for metric in contract["metrics"]}
pids = [int(value) for value in subprocess.check_output(["pgrep", "-x", "quickshell"], text=True).split()]
if len(pids) != 1:
    raise SystemExit(f"expected one quickshell process, found {pids}")
pid = pids[0]
ticks_per_second = os.sysconf(os.sysconf_names["SC_CLK_TCK"])

def ticks():
    fields = open(f"/proc/{pid}/stat", encoding="utf-8").read().split()
    return int(fields[13]) + int(fields[14])

def rss():
    for line in open(f"/proc/{pid}/status", encoding="utf-8"):
        if line.startswith("VmRSS:"):
            return int(line.split()[1]) * 1024
    raise RuntimeError("VmRSS is absent")

time.sleep(2)
cpu_samples = []
rss_samples = []
previous_ticks = ticks()
previous_time = time.monotonic()
for _ in range(5):
    time.sleep(1)
    current_time = time.monotonic()
    current_ticks = ticks()
    cpu_samples.append(((current_ticks - previous_ticks) / ticks_per_second) / (current_time - previous_time) * 100)
    rss_samples.append(rss())
    previous_ticks = current_ticks
    previous_time = current_time

ipc_samples = []
command = [str(pathlib.Path(os.environ["OMARCHY_PATH"]) / "bin/omarchy-shell"), "shell", "ping"]
for _ in range(10):
    started = time.perf_counter_ns()
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
    ipc_samples.append((time.perf_counter_ns() - started) / 1_000_000)

cpu_p95 = sorted(cpu_samples)[math.ceil(len(cpu_samples) * 0.95) - 1]
rss_max = max(rss_samples)
ipc_p95 = sorted(ipc_samples)[math.ceil(len(ipc_samples) * 0.95) - 1]
result = {
    "shell-idle-cpu": {"value": cpu_p95, "unit": "percent-one-core", "threshold": thresholds["shell-idle-cpu"]},
    "shell-idle-rss": {"value": rss_max, "unit": "bytes", "threshold": thresholds["shell-idle-rss"]},
    "operation-event-latency": {"value": ipc_p95, "unit": "ms-round-trip", "threshold": thresholds["operation-event-latency"]},
}
artifact.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
failed = [metric for metric, row in result.items() if row["value"] > row["threshold"]]
if failed:
    raise SystemExit("live performance budgets exceeded: " + ", ".join(failed))
PY
then
  pass "live shell CPU, RSS, and operation-event latency stay within provisional budgets"
else
  record_failure "performance: live shell CPU, RSS, or operation-event latency exceeded its provisional budget"
fi

window_title_present() {
  local title="$1"
  hyprctl -j clients | jq -e --arg title "$title" '[.[] | select(.title == $title)] | length > 0' >/dev/null
}

window_title_absent() {
  ! window_title_present "$1"
}

atspi_probe() {
  local mode="$1" required_pattern="$2"
  python3 - "$mode" "$required_pattern" <<'PY'
import re
import sys
import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi

mode = sys.argv[1]
pattern = re.compile(sys.argv[2], re.IGNORECASE)
Atspi.init()
desktop = Atspi.get_desktop(0)
seen = []
stack = [desktop]
while stack and len(seen) < 10000:
    node = stack.pop()
    if node is None:
        continue
    try:
        name = node.get_name() or ""
        role = node.get_role_name() or ""
    except Exception:
        continue
    actions = 0
    has_value = False
    try:
        iface = node.get_action_iface()
        if iface is not None:
            actions = iface.get_n_actions()
    except Exception:
        pass
    try:
        iface = node.get_value_iface()
        if iface is not None:
            iface.get_current_value()
            has_value = True
    except Exception:
        pass
    seen.append((name, role, actions, has_value))
    try:
        for index in range(node.get_child_count()):
            stack.append(node.get_child_at_index(index))
    except Exception:
        pass

matched = [row for row in seen if pattern.search(row[0])]
if not matched:
    applications = [row[0] for row in seen if row[1].lower() == "application"]
    raise SystemExit(f"required accessible name absent: {pattern.pattern}; applications={applications}")

if mode == "quality":
    if not any(row[2] > 0 for row in seen):
        raise SystemExit("no accessible action is exported")
    if not any(row[3] for row in seen):
        raise SystemExit("no accessible value is exported")
elif mode == "auth":
    if not any("password" in row[0].lower() or "password" in row[1].lower() for row in seen):
        raise SystemExit("no accessible password field is exported")
PY
}

omarchy-shell shell summon omarchy.dev-gallery '{"section":"quality-matrix"}' >/dev/null
wait_until "quality gallery window opens" 15 window_title_present "Omarchy shell – dev gallery"
sleep 1
screenshot "quality-accessible-state-gallery"
if atspi_probe quality 'Ultimate quality state matrix'; then
  pass "shell quality matrix exports semantic name, role, value, and action"
else
  record_failure "shell: Quickshell quality matrix semantics are absent from AT-SPI"
fi
omarchy-shell shell hide omarchy.dev-gallery >/dev/null
wait_until "quality gallery window closes" 15 window_title_absent "Omarchy shell – dev gallery"

omarchy-shell lock preview >/dev/null
wait_until "secure lock preview opens" 15 layer_present "omarchy-lock-preview"
sleep 1
screenshot "quality-secure-lock-accessibility"
if atspi_probe auth 'unlock|password'; then
  pass "secure lock exports named password and unlock semantics"
else
  record_failure "secure-lock: named password and unlock semantics are absent from AT-SPI"
fi
omarchy-shell lock hidePreview >/dev/null
wait_until "secure lock preview closes" 15 layer_absent "omarchy-lock-preview"

oobe_status=$(jq -r '.surfaceClasses[] | select(.id == "oobe") | [.implementation, .status] | @tsv' "$quality_contract")
if [[ $oobe_status == $'present\tproved' ]]; then
  pass "OOBE implementation has proved AT-SPI semantics"
else
  record_failure "oobe: graphical OOBE is missing or its AT-SPI semantics are unproved ($oobe_status)"
fi

if command -v pkexec >/dev/null; then
  pkexec /usr/bin/true >/dev/null 2>&1 &
  polkit_pid=$!
  if wait_until "Polkit prompt opens" 15 layer_present "omarchy-polkit"; then
    sleep 1
    screenshot "quality-polkit-accessibility"
    if atspi_probe auth 'authenticate|authentication|password'; then
      pass "Polkit exports named password and authenticate semantics"
    else
      record_failure "polkit: named password and authenticate semantics are absent from AT-SPI"
    fi
    wtype -k Escape
    wait_until "Polkit prompt closes" 15 layer_absent "omarchy-polkit"
  else
    record_failure "polkit: the authentication surface did not appear"
  fi
else
  record_failure "polkit: pkexec tooling is absent"
fi

while IFS=$'\t' read -r surface status blocker; do
  if [[ $status != "proved" ]]; then
    record_failure "$surface: feasibility status is $status — $blocker"
  fi
done < <(jq -r '.surfaceClasses[] | [.id, .status, .blocker] | @tsv' "$quality_contract")

while IFS=$'\t' read -r metric status blocker; do
  if [[ $status != "measured" ]]; then
    record_failure "$metric: performance observation is $status — $blocker"
  fi
done < <(jq -r '.metrics[] | [.id, .observation.status, (.observation.blocker // "")] | @tsv' "$performance_contract")

if (( ${#failures[@]} > 0 )); then
  failure_detail=$(printf '%s\n' "${failures[@]}")
  fail "Ultimate accessibility and performance release gate" "$failure_detail"
fi

pass "Ultimate accessibility and performance release gate"
