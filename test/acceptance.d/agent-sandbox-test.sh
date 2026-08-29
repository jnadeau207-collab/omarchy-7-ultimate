#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

command -v bwrap >/dev/null 2>&1 || fail "managed agent sandbox requires bubblewrap" "bubblewrap is missing; managed execution must fail closed"
command -v python3 >/dev/null 2>&1 || fail "managed agent sandbox has its runtime" "python3 is missing"
[[ -x /usr/bin/bwrap ]] || fail "managed agent sandbox requires packaged bubblewrap" "/usr/bin/bwrap is not executable"

sandbox_root=$(mktemp -d)
trap 'rm -rf -- "$sandbox_root"' EXIT

mkdir -p "$sandbox_root/workspace" "$sandbox_root/artifacts" "$sandbox_root/protected" \
  "$sandbox_root/host-home/.ssh" \
  "$sandbox_root/host-home/.config/google-chrome" \
  "$sandbox_root/host-home/.local/share/keyrings" \
  "$sandbox_root/host-home/runtime"
printf '%s\n' "workspace-visible" >"$sandbox_root/workspace/visible.txt"
printf '%s\n' "home-secret" >"$sandbox_root/host-home/secret.txt"
printf '%s\n' "ssh-secret" >"$sandbox_root/host-home/.ssh/id_ed25519"
printf '%s\n' "browser-secret" >"$sandbox_root/host-home/.config/google-chrome/Login Data"
printf '%s\n' "keyring-secret" >"$sandbox_root/host-home/.local/share/keyrings/login.keyring"
printf '%s\n' "not-a-real-socket" >"$sandbox_root/host-home/runtime/fabric.sock"

export PYTHONPATH="$ROOT/default/fabric${PYTHONPATH:+:$PYTHONPATH}"
export OMARCHY_PATH="$ROOT"

if ! probe_output=$(
  python3 - "$sandbox_root" <<'PY'
from pathlib import Path
import json
import sys

from sandbox.runner import run_representative_probe

root = Path(sys.argv[1])
result = run_representative_probe(
    task_id="task.probe",
    workspace=root / "workspace",
    artifacts=root / "artifacts",
    protected_home=root / "protected",
    host_home=root / "host-home",
)
print(json.dumps({
    "returncode": result.returncode,
    "stdout": result.stdout,
    "stderr": result.stderr,
    "argv": list(result.argv),
    "result": result.result,
}))
if result.returncode != 0 or not result.result or result.result.get("ok") is not True:
    raise SystemExit("isolated runner failed")
if "--unshare-all" not in result.argv:
    raise SystemExit("sandbox did not unshare namespaces")
joined = " ".join(result.argv)
if "WAYLAND_DISPLAY=" in joined or "DBUS_SESSION_BUS_ADDRESS=" in joined:
    raise SystemExit("session IPC leaked into sandbox argv")
if "fabric.sock" in joined:
    raise SystemExit("main Fabric socket leaked into sandbox argv")
PY
); then
  fail "managed agent sandbox denies ambient desktop authority" "$probe_output"
fi

artifact="$sandbox_root/artifacts/result.json"
[[ -f $artifact ]] || fail "managed agent sandbox writes only its scoped artifact bind" "missing $artifact probe=$probe_output"
python3 - "$artifact" <<'PY' || fail "managed agent sandbox writes only its scoped artifact bind" "$(cat "$artifact")"
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert payload.get("ok") is True
assert payload.get("isolation") == "bubblewrap"
PY

pass "managed agent sandbox requires real bubblewrap and denies home, desktop IPC, secrets, main Fabric, and network"
pass "managed agent sandbox exposes only the explicit workspace and artifact scopes"
