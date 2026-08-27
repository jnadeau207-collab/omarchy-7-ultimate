#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python
require_command rg

for path in \
  "$ROOT/default/fabric/omarchy_fabric/operations/contracts.py" \
  "$ROOT/default/fabric/omarchy_fabric/operations/coordinator.py" \
  "$ROOT/default/fabric/omarchy_fabric/operations/executor.py" \
  "$ROOT/default/fabric/omarchy_fabric/operations/registry_gateway.py" \
  "$ROOT/default/fabric/omarchy_fabric/operations/store.py"; do
  [[ -f $path ]] || fail "operation coordinator module exists: $path"
done
pass "durable operation coordinator modules exist"

for schema in operation-coordinator-v0.json operation-executor-v0.json; do
  [[ -f $ROOT/default/fabric/schema/$schema ]] || fail "operation schema exists: $schema"
done
pass "closed operation schemas exist"

if rg -n 'subprocess\.(run|Popen)|os\.system|shell\s*=\s*True|/usr/bin/(sudo|pkexec)' "$ROOT/default/fabric/omarchy_fabric/operations"; then
  fail "operation coordinator has no process or generic privilege escape"
fi
pass "operation coordinator has no process or generic privilege escape"

python -c 'import jsonschema' >/dev/null 2>&1 || fail "python-jsonschema is installed for Fabric contract tests"

PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s "$ROOT/test/fabric/operations" -p 'test_*.py' -v
pass "operation coordinator lifecycle, security, recovery, storage, and schema tests pass"
