#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
export PYTHONDONTWRITEBYTECODE=1

PYTHONPATH="$ROOT/default/fabric${PYTHONPATH:+:$PYTHONPATH}" \
  python3 -m unittest discover -s "$ROOT/test/fabric/managed_work" -p 'test_*.py' -v
pass "Fabric managed-work restart, isolation, schedule, projection, and Agent Center query contracts pass"

managed_modules=("$ROOT"/default/fabric/omarchy_fabric/managed_work/*.py)
(( ${#managed_modules[@]} >= 6 )) || fail "Managed-work module set is incomplete"

python3 - "${managed_modules[@]}" <<'PY'
import pathlib
import sys

for value in sys.argv[1:]:
    path = pathlib.Path(value)
    compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY
pass "Fabric managed-work Python modules compile"

if grep -En '(^|[^[:alnum:]_])(subprocess|Popen|os\.system|create_subprocess|eval|exec)[[:space:].(]|shell[[:space:]]*=[[:space:]]*True|/bin/(ba)?sh' "${managed_modules[@]}"; then
  fail "Managed work contains no process, shell, or dynamic-code execution path"
fi
pass "Fabric managed work has no process or shell execution authority"

python3 - "$ROOT/default/fabric/schema/managed-work-v0.json" <<'PY'
import json
import pathlib
import sys

schema = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
assert schema["$id"] == "urn:omarchy:fabric:schema:managed-work-v0"
assert schema["x-omarchy-version"] == 0

open_payload_definitions = {"json", "jsonObject"}

def visit(value, path=()):
    if isinstance(value, dict):
        if value.get("type") == "object" and "properties" in value:
            definition = path[1] if len(path) >= 2 and path[0] == "$defs" else None
            if definition not in open_payload_definitions:
                assert value.get("additionalProperties") is False, "/".join(path)
        for key, child in value.items():
            visit(child, (*path, key))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            visit(child, (*path, str(index)))

visit(schema)
PY
pass "Managed-work provisional schema keeps result envelopes closed"
