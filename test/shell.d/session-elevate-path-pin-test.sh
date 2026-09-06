#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
[[ -f $helper ]] || fail "session apply helper exists"

pins=(
  'OMARCHY_PKG_ADD = "/usr/bin/omarchy-pkg-add"'
  'OMARCHY_PKG_DROP = "/usr/bin/omarchy-pkg-drop"'
  'OMARCHY_VERSION_CHANNEL = "/usr/bin/omarchy-version-channel"'
  'OMARCHY_UPDATE = "/usr/bin/omarchy-update"'
  'OMARCHY_UPDATE_AVAILABLE = "/usr/bin/omarchy-update-available"'
  'OMARCHY_UPDATE_FREE_SPACE = "/usr/bin/omarchy-update-requires-free-space"'
)

for pin in "${pins[@]}"; do
  grep -Fq "$pin" "$helper" || fail "session apply pins $pin"
done

if grep -Eq 'OMARCHY_(PKG_ADD|PKG_DROP|VERSION_CHANNEL|UPDATE|UPDATE_AVAILABLE|UPDATE_FREE_SPACE) = "[^/]' "$helper"; then
  fail "session elevating helpers must not use bare PATH names"
fi

pass "session apply source-locks elevating helpers to /usr/bin"

cd "$ROOT/default/fabric"
PYTHONPATH="$ROOT/default/fabric" PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import io
import json

from omarchy_fabric.helpers import session_apply as sa

failures = []


def check(label, condition, detail=""):
    if not condition:
        failures.append(f"{label}{': ' + detail if detail else ''}")


PINNED = {
    "OMARCHY_PKG_ADD": "/usr/bin/omarchy-pkg-add",
    "OMARCHY_PKG_DROP": "/usr/bin/omarchy-pkg-drop",
    "OMARCHY_VERSION_CHANNEL": "/usr/bin/omarchy-version-channel",
    "OMARCHY_UPDATE": "/usr/bin/omarchy-update",
    "OMARCHY_UPDATE_AVAILABLE": "/usr/bin/omarchy-update-available",
    "OMARCHY_UPDATE_FREE_SPACE": "/usr/bin/omarchy-update-requires-free-space",
}

for name, expected in PINNED.items():
    value = getattr(sa, name)
    check(f"{name} is the shipped /usr/bin pin", value == expected, repr(value))
    check(f"{name} is absolute", value.startswith("/usr/bin/"), repr(value))
    check(f"{name} is not a bare PATH name", "/" in value, repr(value))


class Result:
    def __init__(self, returncode=0, stdout="", stderr=""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


calls = []


def fake_run(argv, **kwargs):
    calls.append(list(argv))
    if not argv:
        raise AssertionError(argv)
    name = argv[0]
    if name == sa.OMARCHY_PKG_ADD:
        return Result(stdout="installed")
    if name == sa.OMARCHY_PKG_DROP:
        return Result(stdout="removed")
    if name == sa.OMARCHY_VERSION_CHANNEL:
        return Result(stdout="stable\n")
    if name == sa.OMARCHY_UPDATE_AVAILABLE:
        return Result(stdout="omarchy 1.0.0-1 -> 1.0.1-1\n")
    if name == sa.OMARCHY_UPDATE_FREE_SPACE:
        return Result()
    if name == sa.OMARCHY_UPDATE:
        return Result(stdout="updated\n")
    raise AssertionError(argv)


def run_action(handler, payload, **kwargs):
    stream = io.StringIO()
    status = handler(io.StringIO(json.dumps(payload)), stream, run=fake_run, **kwargs)
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


calls.clear()
status, result = run_action(sa.apply_software_install, {"packageId": "software.curated.neovim"})
check("install succeeds under the absolute pin", status == 0 and result.get("ok") is True, str(result))
check(
    "install argv[0] is /usr/bin/omarchy-pkg-add",
    any(call and call[0] == "/usr/bin/omarchy-pkg-add" and "neovim" in call for call in calls),
    str(calls),
)
check(
    "install does not spawn a bare omarchy-pkg-add",
    all(call[0] != "omarchy-pkg-add" for call in calls),
    str(calls),
)

calls.clear()
status, result = run_action(sa.apply_software_remove, {"packageId": "software.curated.neovim"})
check("remove succeeds under the absolute pin", status == 0 and result.get("ok") is True, str(result))
check(
    "remove argv[0] is /usr/bin/omarchy-pkg-drop",
    any(call and call[0] == "/usr/bin/omarchy-pkg-drop" and "neovim" in call for call in calls),
    str(calls),
)
check(
    "remove does not spawn a bare omarchy-pkg-drop",
    all(call[0] != "omarchy-pkg-drop" for call in calls),
    str(calls),
)

calls.clear()
status, result = run_action(sa.apply_system_update_status, {}, lock_held=lambda: False)
check("status succeeds under the absolute pin", status == 0 and result.get("ok") is True, str(result))
check(
    "status probes /usr/bin/omarchy-version-channel",
    any(call and call[0] == "/usr/bin/omarchy-version-channel" for call in calls),
    str(calls),
)
check(
    "status probes /usr/bin/omarchy-update-available",
    any(call and call[0] == "/usr/bin/omarchy-update-available" for call in calls),
    str(calls),
)
check(
    "status probes /usr/bin/omarchy-update-requires-free-space",
    any(call and call[0] == "/usr/bin/omarchy-update-requires-free-space" for call in calls),
    str(calls),
)
check(
    "status does not spawn a bare update helper",
    all(
        call[0]
        not in {
            "omarchy-version-channel",
            "omarchy-update-available",
            "omarchy-update-requires-free-space",
            "omarchy-update",
        }
        for call in calls
    ),
    str(calls),
)

calls.clear()
status, result = run_action(sa.apply_system_update, {"channel": "stable"}, lock_held=lambda: False)
check("apply succeeds under the absolute pin", status == 0 and result.get("ok") is True, str(result))
check(
    "apply argv[0] is /usr/bin/omarchy-update",
    any(call and call[0] == "/usr/bin/omarchy-update" and "-y" in call for call in calls),
    str(calls),
)
check(
    "apply does not spawn a bare omarchy-update",
    all(call[0] != "omarchy-update" for call in calls),
    str(calls),
)

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session software and update apply spawn only /usr/bin elevating helpers"
