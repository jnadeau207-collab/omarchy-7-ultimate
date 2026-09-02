#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python

dispatcher="$ROOT/default/fabric/libexec/omarchy-fabric-system-executor"
policy="$ROOT/default/polkit-1/actions/org.omarchy.fabric.policy"
helper="$ROOT/default/fabric/omarchy_fabric/helpers/system_apply.py"

for path in "$dispatcher" "$policy" "$helper"; do
  [[ -f $path ]] || fail "system executor component exists: $path"
done
[[ -x $dispatcher ]] || fail "system executor dispatcher is executable in a source checkout"
pass "root system executor, dispatcher, and Polkit policy ship in the tree"

if grep -qE 'subprocess\.(run|Popen)|os\.system|shell[[:space:]]*=[[:space:]]*True|/usr/bin/(sudo|pkexec)' \
  "$ROOT/default/fabric/omarchy_fabric/operations"/*.py; then
  fail "operation coordinator regained a process or generic privilege escape"
fi
pass "privileged execution stays out of the operation coordinator"

cd "$ROOT/default/fabric"
OMARCHY_POLICY_PATH="$policy" OMARCHY_DISPATCHER_PATH="$dispatcher" \
  PYTHONDONTWRITEBYTECODE=1 python - <<'PY'
import os
import pathlib
import re
import sys

from omarchy_fabric.helpers.system_apply import ACTIONS
from omarchy_fabric.security.system_executor import SYSTEM_ACTIONS

policy = pathlib.Path(os.environ["OMARCHY_POLICY_PATH"]).read_text(encoding="utf-8")
dispatcher = pathlib.Path(os.environ["OMARCHY_DISPATCHER_PATH"]).read_text(encoding="utf-8")
libexec = pathlib.Path(os.environ["OMARCHY_DISPATCHER_PATH"]).parent / "omarchy-fabric"

failures = []
for name in sorted(ACTIONS):
    action_id = SYSTEM_ACTIONS[name].polkit_action
    if f'<action id="{action_id}">' not in policy:
        failures.append(f"Polkit policy is missing the contract action {action_id}")

declared = sorted(set(re.findall(r"/usr/libexec/omarchy-fabric/[a-z-]+", policy)))
if len(declared) != len(ACTIONS):
    failures.append(f"Polkit declares {len(declared)} programs for {len(ACTIONS)} implemented actions")
for path in declared:
    if path not in dispatcher:
        failures.append(f"dispatcher does not route to the Polkit-declared program {path}")
    if not (libexec / pathlib.PurePosixPath(path).name).is_file():
        failures.append(f"Polkit-declared program is absent from the tree: {path}")

for failure in failures:
    print(f"not ok - {failure}", file=sys.stderr)
if failures:
    raise SystemExit(1)
PY
pass "every implemented root action has its own Polkit action id and code-owned program"

for program in "$ROOT/default/fabric/libexec/omarchy-fabric"/*; do
  [[ -x $program ]] || fail "Polkit-declared program is executable in a source checkout: $program"
done
pass "each Polkit-declared program is executable"

OMARCHY_DISPATCHER_PATH="$dispatcher" PYTHONDONTWRITEBYTECODE=1 python - <<'PY'
import os
import pathlib
import re
import sys

text = pathlib.Path(os.environ["OMARCHY_DISPATCHER_PATH"]).read_text(encoding="utf-8")

failures = []
assignments = re.findall(r"(?:^|[)]\s)target=(\S+)", text)
if not assignments:
    failures.append("dispatcher names no privileged program")
for value in assignments:
    if not re.fullmatch(r"/usr/libexec/omarchy-fabric/[a-z-]+", value.rstrip(";")):
        failures.append(f"dispatcher builds a privileged path from non-literal material: {value}")

for line in text.splitlines():
    if "pkexec" not in line:
        continue
    if not re.fullmatch(r'\s*exec /usr/bin/pkexec "\$target"\s*', line):
        failures.append(f"dispatcher invokes pkexec with unfixed argv: {line.strip()}")

for failure in failures:
    print(f"not ok - {failure}", file=sys.stderr)
if failures:
    raise SystemExit(1)
PY
pass "request data cannot select or build the privileged program path"

cd "$ROOT/default/fabric"
PYTHONDONTWRITEBYTECODE=1 python - <<'PY'
import io
import json
import sys
import uuid

from omarchy_fabric.helpers import system_apply


def outcome(argv, arguments, action="packages.install"):
    document = {
        "schemaVersion": "v0",
        "requestId": str(uuid.uuid4()),
        "operationId": str(uuid.uuid4()),
        "action": action,
        "arguments": arguments,
        "providerVersion": "v0",
        "stateRevision": "sha256." + "0" * 64,
        "approvalBinding": "a" * 64,
        "consentNonce": str(uuid.uuid4()),
    }
    stream = io.StringIO()
    status = system_apply.main(argv, io.StringIO(json.dumps(document)), stream)
    payload = json.loads(stream.getvalue())
    assert status != 0 or payload["ok"], payload
    return payload["code"] if not payload["ok"] else "ok"


def expect(label, actual, wanted):
    if actual != wanted:
        print(f"not ok - {label}: expected {wanted}, got {actual}", file=sys.stderr)
        raise SystemExit(1)


curated = {"package_ids": ["software.curated.neovim"]}

expect("unknown action refused", outcome(["packages.nope"], curated), "action.unknown")
expect("argv arity enforced", outcome([], curated), "action.argv")
expect("argv must match the document", outcome(["packages.remove"], curated), "action.mismatch")
expect(
    "arbitrary execution refused",
    outcome(["packages.install"], {**curated, "command": "id"}),
    "executor.arbitrary-execution",
)
expect(
    "uncatalogued package refused",
    outcome(["packages.install"], {"package_ids": ["software.curated.absent"]}),
    "package.unknown",
)
for package_id in (
    "software.flatpak.spotify",
    "software.aur.visual-studio-code",
    "software.appimage.obsidian",
    "software.webapp.figma",
):
    expect(
        f"non-pacman channel refused: {package_id}",
        outcome(["packages.install"], {"package_ids": [package_id]}),
        "package.source-unsupported",
    )
expect("a channel this machine does not track is refused", outcome(["system.update"], {"channel": "candidate", "allow_without_restore_point": False}, "system.update"), "command.unavailable")
expect("an unknown channel is refused by the contract", outcome(["system.update"], {"channel": "nightly", "allow_without_restore_point": False}, "system.update"), "executor.choice")
expect("a missing restore-point decision is refused", outcome(["system.update"], {"channel": "stable"}, "system.update"), "executor.argument-fields")
expect("an update argv naming a package is refused", outcome(["system.update"], {"channel": "stable", "allow_without_restore_point": False, "package_ids": ["x"]}, "system.update"), "executor.argument-fields")

expect(
    "oversized payload refused",
    outcome(["packages.install"], {"package_ids": ["software.curated.neovim"] * 300}),
    "executor.package-list",
)
PY
pass "the root executor refuses unknown actions, argv drift, arbitrary execution, and uncatalogued packages"

PYTHONDONTWRITEBYTECODE=1 python - <<'PY'
import sys

from omarchy_fabric.helpers import system_apply

recorded = []


def capture(argv):
    recorded.append(argv)
    return ""


system_apply.run_fixed = capture


class Request:
    action = "packages.install"
    arguments = {"package_ids": ["software.curated.neovim", "software.repo.libreoffice"]}


system_apply.apply_packages_install(Request())
Request.action = "packages.remove"
Request.arguments = {**Request.arguments, "preserve_data": True}
system_apply.apply_packages_remove(Request())
Request.arguments = {**Request.arguments, "preserve_data": False}
system_apply.apply_packages_remove(Request())

expected = [
    ("/usr/bin/pacman", "-S", "--noconfirm", "--needed", "--", "neovim", "libreoffice-fresh"),
    ("/usr/bin/pacman", "-R", "--noconfirm", "--", "neovim", "libreoffice-fresh"),
    ("/usr/bin/pacman", "-Rns", "--noconfirm", "--", "neovim", "libreoffice-fresh"),
]
if recorded != expected:
    print(f"not ok - fixed argv drifted: {recorded}", file=sys.stderr)
    raise SystemExit(1)
PY
pass "package argv is code-owned and carries only catalog-resolved references"
