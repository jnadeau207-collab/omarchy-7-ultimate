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
for name in ("__init__", "daemon", "protocol", "db", "models", "events", "health", "provider_builtins", "provider_registry", "reference_operation", "managed_runtime", "desktop_context"):
    path = module_directory / f"{name}.py"
    compile(path.read_text(), str(path), "exec")
PY
pass "Fabric Python modules compile"

python3 - \
  "$ROOT/default/fabric/schema/common-v0.json" \
  "$ROOT/default/fabric/schema/rpc-v0.json" \
  "$ROOT/default/fabric/schema/provider-manifest-v0.json" \
  "$ROOT/default/fabric/schema/reference-operation-v0.json" <<'PY'
import json
import pathlib
import re
import sys

common_path, rpc_path, provider_path, reference_path = map(pathlib.Path, sys.argv[1:])
common = json.loads(common_path.read_text())
rpc = json.loads(rpc_path.read_text())
provider = json.loads(provider_path.read_text())
reference = json.loads(reference_path.read_text())

def walk(value):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)

def resolve_pointer(document, pointer):
    current = document
    for part in pointer.removeprefix("/").split("/") if pointer else ():
        current = current[part.replace("~1", "/").replace("~0", "~")]
    return current

assert common["$id"] == "urn:omarchy:fabric:schema:common-v0"
assert rpc["$id"] == "urn:omarchy:fabric:schema:rpc-v0"
assert provider["$id"] == "urn:omarchy:fabric:schema:provider-manifest-v0"
assert reference["$id"] == "urn:omarchy:fabric:schema:reference-operation-v0"
assert "common-v0.json#/$defs/errorEnvelope" in rpc_path.read_text()
assert "reference-operation-v0.json#/$defs/preflightParams" in rpc_path.read_text()
assert {"provider.catalog", "provider.read"} <= set(rpc["$defs"]["request"]["properties"]["method"]["enum"])
assert rpc["$defs"]["typedProviderRead"]["additionalProperties"] is False
assert provider["additionalProperties"] is False
assert provider["$defs"]["action"]["additionalProperties"] is False
assert rpc["$defs"]["protocol"]["const"] == "omarchy.fabric.rpc/v0"
assert rpc["$defs"]["requestId"]["maxLength"] == 128
assert rpc["$defs"]["eventSubscription"]["properties"]["limit"]["maximum"] == 128
reference_methods = {
    "reference.operation.preflight",
    "reference.operation.approve",
    "reference.operation.start",
    "reference.operation.get",
    "reference.operation.cancel",
    "reference.operation.reconcile",
    "reference.operation.ledger",
}
assert reference_methods <= set(rpc["$defs"]["request"]["properties"]["method"]["enum"])
assert "recoveryToken" in reference["$defs"]["preflightParams"]["required"]
assert reference["$defs"]["recoveryToken"]["pattern"] == "^[A-Za-z0-9_-]{43}$"
assert "recoveryToken" not in reference["$defs"]["operation"]["properties"]
assert "recoveryToken" not in reference["$defs"]["evidencePayload"]["properties"]
assert reference["$defs"]["ledgerParams"]["properties"]["limit"]["maximum"] == 8
assert reference["$defs"]["ledger"]["properties"]["entries"]["maxItems"] == 8
assert len(reference["$defs"]["methodResultContract"]["oneOf"]) == 5
for name in ("referenceArguments", "preflightParams", "approveParams", "startParams", "operationParams", "ledgerParams", "approval", "approveResult", "operation", "resource", "resourceState", "preflight", "result", "evidencePayload", "ledgerEntry", "ledger"):
    assert reference["$defs"][name]["type"] == "object", name
    assert reference["$defs"][name]["additionalProperties"] is False, name
for node in walk(reference):
    if not isinstance(node, dict):
        continue
    if node.get("type") == "object":
        assert node.get("additionalProperties") is False, node
    if "pattern" in node:
        re.compile(node["pattern"])
    if "$ref" in node:
        ref = node["$ref"]
        if ref.startswith("#/"):
            resolve_pointer(reference, ref[1:])
        elif ref.startswith("common-v0.json#/"):
            resolve_pointer(common, ref.split("#", 1)[1])
        else:
            raise AssertionError(f"unapproved reference-operation schema ref: {ref}")
PY
pass "Fabric RPC and closed reference-operation schemas consume the root common vocabulary"

for command in omarchy-fabricd omarchy-fabricctl; do
  grep -q '^# omarchy:summary=' "$ROOT/bin/$command" || fail "$command declares a summary"
  grep -q '^# omarchy:hidden=true$' "$ROOT/bin/$command" || fail "$command remains provisional and hidden"
done
pass "Fabric daemon and diagnostics commands carry hidden provisional metadata"

fabric_core_modules=(
  "$ROOT/default/fabric/omarchy_fabric/__init__.py"
  "$ROOT/default/fabric/omarchy_fabric/daemon.py"
  "$ROOT/default/fabric/omarchy_fabric/protocol.py"
  "$ROOT/default/fabric/omarchy_fabric/db.py"
  "$ROOT/default/fabric/omarchy_fabric/models.py"
  "$ROOT/default/fabric/omarchy_fabric/events.py"
  "$ROOT/default/fabric/omarchy_fabric/health.py"
  "$ROOT/default/fabric/omarchy_fabric/provider_builtins.py"
  "$ROOT/default/fabric/omarchy_fabric/provider_registry.py"
  "$ROOT/default/fabric/omarchy_fabric/reference_operation.py"
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
assert health["providers"]["typed"] == 22
assert health["providers"]["availableTyped"] == 20
assert health["providers"]["degradedTyped"] == 2
assert health["providers"]["usableTyped"] == 22
assert doctor["status"] == "healthy"
assert all(check["status"] == "pass" for check in doctor["checks"])
PY
pass "Fabric health and doctor CLIs exercise the live hello/RPC path"

create_payload='{"title":"CLI inspect","intent":{"goal":"inventory","readOnly":true,"capability":"system.info.read"},"budget":{"timeSeconds":60,"outputBytes":1024,"costMicrounits":0,"network":false},"idempotencyKey":"task.cli-create"}'
task_json=$(OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-fabricctl" \
  --socket "$socket_path" --json task create "$create_payload")
list_json=$(OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-fabricctl" \
  --socket "$socket_path" --json task list '{"limit":10}')
context_payload='{"source":"open-windows","idempotencyKey":"context.cli-windows","snapshot":{"windows":[{"class":"foot","title":"term","address":"0x1","focused":true}],"focus":{"class":"foot","title":"term","address":"0x1"},"selection":{"text":""}}}'
context_json=$(OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-fabricctl" \
  --socket "$socket_path" --json context capture "$context_payload")
python3 - "$task_json" "$list_json" "$context_json" <<'PY'
import json
import sys

created = json.loads(sys.argv[1])
listed = json.loads(sys.argv[2])
captured = json.loads(sys.argv[3])
assert created.get("state") == "draft", created
assert created.get("taskId")
assert any(item.get("task", {}).get("taskId") == created["taskId"] for item in listed["items"])
assert captured["source"] == "open-windows"
assert [item["class"] for item in captured["content"]["windows"]] == ["foot"]
PY
task_id=$(python3 - "$task_json" <<'PY'
import json
import sys
print(json.loads(sys.argv[1])["taskId"])
PY
)
set +e
execute_json=$(OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-fabricctl" \
  --socket "$socket_path" --json run execute "{\"taskId\":\"$task_id\",\"idempotencyKey\":\"run.cli-execute\"}")
execute_status=$?
set -e
python3 - "$execute_json" "$execute_status" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
status = int(sys.argv[2])
if status == 0:
    assert payload["kind"] == "sandboxed-run"
    assert payload["result"]["capability"] == "system.info.read"
    assert payload["task"]["state"] == "succeeded"
else:
    assert payload["status"] == "unavailable"
    assert payload["error"]["code"] == "sandbox.unavailable"
PY
pass "Fabricctl task, context, and execute verbs return the RPC result object"

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
