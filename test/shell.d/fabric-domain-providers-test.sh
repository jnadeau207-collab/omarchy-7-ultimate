#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
export PYTHONDONTWRITEBYTECODE=1

PYTHONPATH="$ROOT/default/fabric${PYTHONPATH:+:$PYTHONPATH}" \
  python3 -m unittest discover -s "$ROOT/test/fabric/providers" -p 'test_*.py' -v
pass "Fabric Display, Audio, Network, Bluetooth, Input, and Power provider contracts pass"

shopt -s globstar nullglob
provider_modules=("$ROOT"/default/fabric/omarchy_fabric/providers/**/*.py)
(( ${#provider_modules[@]} > 6 )) || fail "Fabric domain provider modules are present"

python3 - "${provider_modules[@]}" <<'PY'
import pathlib
import sys

for value in sys.argv[1:]:
    path = pathlib.Path(value)
    compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY
pass "Fabric domain provider Python modules compile"

if grep -En 'create_subprocess_shell|shell[[:space:]]*=[[:space:]]*True|os\.system|bash[[:space:]]+-c' "${provider_modules[@]}"; then
  fail "Fabric domain providers contain no shell or arbitrary-command execution path"
fi
grep -q 'shell=False' "$ROOT/default/fabric/omarchy_fabric/providers/_probe.py" || \
  fail "Fabric provider probe runner explicitly disables shell execution"
pass "Fabric domain providers expose only fixed-argv real probes"
