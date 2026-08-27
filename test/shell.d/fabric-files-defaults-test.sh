#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
export PYTHONDONTWRITEBYTECODE=1

PYTHONPATH="$ROOT/default/fabric${PYTHONPATH:+:$PYTHONPATH}" \
  python3 -m unittest discover -s "$ROOT/test/fabric/files" -p 'test_*.py' -v
pass "Fabric Files, This PC, Desktop, Trash, mount, search, and recent contracts pass"

PYTHONPATH="$ROOT/default/fabric${PYTHONPATH:+:$PYTHONPATH}" \
  python3 -m unittest discover -s "$ROOT/test/fabric/defaults" -p 'test_*.py' -v
pass "Fabric default application, MIME, and protocol contracts pass"

domain_modules=(
  "$ROOT"/default/fabric/omarchy_fabric/providers/files/*.py
  "$ROOT"/default/fabric/omarchy_fabric/providers/defaults/*.py
)
(( ${#domain_modules[@]} >= 5 )) || fail "Files and Defaults provider modules are incomplete"

python3 - "${domain_modules[@]}" <<'PY'
import pathlib
import sys

for value in sys.argv[1:]:
    path = pathlib.Path(value)
    compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY
pass "Files and Defaults provider Python modules compile"

if grep -En 'create_subprocess_shell|shell[[:space:]]*=[[:space:]]*True|os\.system|bash[[:space:]]+-c|/bin/(ba)?sh' "${domain_modules[@]}"; then
  fail "Files and Defaults providers contain no shell or arbitrary-command execution path"
fi
pass "Files and Defaults provider execution is shell-free"

python3 - "$ROOT/default/fabric/omarchy_fabric/providers/defaults/provider.py" <<'PY'
import ast
import pathlib
import sys

tree = ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for node in ast.walk(tree):
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "FixedArgvCommand":
        assert isinstance(node.args[0], ast.Constant) and node.args[0].value == "/usr/bin/xdg-mime"
PY
pass "Default association probes use only the code-owned xdg-mime executable"

schema_files=(
  "$ROOT"/default/fabric/schema/files-*.json
  "$ROOT"/default/fabric/schema/defaults-*.json
)
(( ${#schema_files[@]} >= 20 )) || fail "Files and Defaults closed schema set is incomplete"
pass "Files and Defaults schema bundles are present"
