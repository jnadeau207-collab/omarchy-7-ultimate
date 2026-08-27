#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
export PYTHONDONTWRITEBYTECODE=1

PYTHONPATH="$ROOT/default/fabric${PYTHONPATH:+:$PYTHONPATH}" \
  python3 -m unittest discover -s "$ROOT/test/fabric/core" -p 'test_*.py' -v
pass "Fabric core Python protocol, database, daemon, and reconnect suite passes"

python3 - "$ROOT/default/fabric/omarchy_fabric" <<'PY'
import pathlib
import sys

module_directory = pathlib.Path(sys.argv[1])
for name in ("__init__", "daemon", "protocol", "db", "models", "events", "health"):
    path = module_directory / f"{name}.py"
    compile(path.read_text(), str(path), "exec")
PY
pass "Fabric Python modules compile"

python3 - "$ROOT/default/fabric/schema/common-v0.json" "$ROOT/default/fabric/schema/rpc-v0.json" <<'PY'
import json
import pathlib
import sys

common_path, rpc_path = map(pathlib.Path, sys.argv[1:])
common = json.loads(common_path.read_text())
rpc = json.loads(rpc_path.read_text())
assert common["$id"] == "urn:omarchy:fabric:schema:common-v0"
assert rpc["$id"] == "urn:omarchy:fabric:schema:rpc-v0"
assert "common-v0.json#/$defs/errorEnvelope" in rpc_path.read_text()
assert rpc["$defs"]["protocol"]["const"] == "omarchy.fabric.rpc/v0"
assert rpc["$defs"]["requestId"]["maxLength"] == 128
assert rpc["$defs"]["eventSubscription"]["properties"]["limit"]["maximum"] == 128
PY
pass "Fabric RPC schema is valid JSON and consumes the root common vocabulary"

for command in omarchy-fabricd omarchy-fabricctl; do
  grep -q '^# omarchy:summary=' "$ROOT/bin/$command" || fail "$command declares a summary"
  grep -q '^# omarchy:hidden=true$' "$ROOT/bin/$command" || fail "$command remains provisional and hidden"
done
pass "Fabric daemon and diagnostics commands carry hidden provisional metadata"

grep -q '^ExecStart=/usr/bin/omarchy-fabricd$' \
  "$ROOT/test/fabric/core/fixtures/omarchy-fabric.service" || \
  fail "Fabric service fixture uses a fixed daemon argv"
! grep -Eq '(/bin/(ba)?sh|-c[[:space:]])' \
  "$ROOT/test/fabric/core/fixtures/omarchy-fabric.service" || \
  fail "Fabric service fixture does not launch a shell"
[[ ! -e $ROOT/default/systemd/user/omarchy-fabric.service ]] || \
  fail "Fabric Core does not install the packaging owner's service"
pass "Fabric service work remains a fixed-argv test contract, not an installed unit"

fabric_core_modules=(
  "$ROOT/default/fabric/omarchy_fabric/__init__.py"
  "$ROOT/default/fabric/omarchy_fabric/daemon.py"
  "$ROOT/default/fabric/omarchy_fabric/protocol.py"
  "$ROOT/default/fabric/omarchy_fabric/db.py"
  "$ROOT/default/fabric/omarchy_fabric/models.py"
  "$ROOT/default/fabric/omarchy_fabric/events.py"
  "$ROOT/default/fabric/omarchy_fabric/health.py"
)
! grep -En 'create_subprocess_shell|shell[[:space:]]*=[[:space:]]*True|os\.system|popen\(' \
  "${fabric_core_modules[@]}" || \
  fail "Fabric Core contains no shell execution path"
grep -q 'shell=False' "$ROOT/default/fabric/omarchy_fabric/models.py" || \
  fail "fixed argv helper explicitly disables shell execution"
pass "Fabric Core exposes no arbitrary shell execution"

fabric_test_root=$(mktemp -d)
fabric_pid=""
cleanup() {
  if [[ -n $fabric_pid ]] && kill -0 "$fabric_pid" 2>/dev/null; then
    kill "$fabric_pid"
    wait "$fabric_pid" || true
  fi
  rm -rf "$fabric_test_root"
}
trap cleanup EXIT

runtime_dir="$fabric_test_root/runtime/omarchy"
state_dir="$fabric_test_root/state"
socket_path="$runtime_dir/fabric.sock"
database_path="$state_dir/fabric.db"
mkdir -p "$runtime_dir" "$state_dir"
chmod 700 "$runtime_dir" "$state_dir"

OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-fabricd" \
  --socket "$socket_path" \
  --database "$database_path" &
fabric_pid=$!

for attempt in {1..160}; do
  if [[ -S $socket_path ]]; then
    break
  fi
  if ! kill -0 "$fabric_pid" 2>/dev/null; then
    wait "$fabric_pid"
    fail "Fabric daemon remains alive while creating its socket"
  fi
  sleep 0.05
done
[[ -S $socket_path ]] || fail "Fabric daemon creates its owner socket"
pass "Fabric daemon starts through its real bin command"

health_json=$(OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-fabricctl" \
  --socket "$socket_path" --json health)
doctor_json=$(OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-fabricctl" \
  --socket "$socket_path" --json doctor)
python3 - "$health_json" "$doctor_json" <<'PY'
import json
import sys

health = json.loads(sys.argv[1])
doctor = json.loads(sys.argv[2])
assert health["status"] == "healthy"
assert health["socket"]["ownerOnly"] is True
assert health["socket"]["mode"] == "0600"
assert health["database"]["journalMode"] == "wal"
assert health["database"]["integrity"] == "ok"
assert doctor["status"] == "healthy"
assert all(check["status"] == "pass" for check in doctor["checks"])
PY
pass "Fabric health and doctor CLIs exercise the live hello/RPC path"

kill "$fabric_pid"
wait "$fabric_pid"
fabric_pid=""
[[ ! -e $socket_path ]] || fail "Fabric daemon removes its socket after graceful shutdown"
pass "Fabric daemon shuts down cleanly through SIGTERM"

if OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-fabricctl" \
  --socket "$socket_path" --json health >/dev/null; then
  fail "Fabric diagnostics fail when the daemon is unavailable"
fi
pass "Fabric diagnostics report daemon unavailability honestly"
