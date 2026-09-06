#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
software_app="$ROOT/shell/apps/ultimate-software/SoftwareApplication.qml"
software_card="$ROOT/shell/apps/ultimate-software/SoftwareRecordCard.qml"
software_session="$ROOT/shell/apps/shared/SoftwareSessionInstall.qml"
software_model="$ROOT/shell/apps/ultimate-software/SoftwareModel.js"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"

[[ -f $helper ]] || fail "session apply helper exists"
[[ -f $software_app ]] || fail "Software Center application exists"
[[ -f $software_model ]] || fail "Software Center model exists"

grep -Fq '"software-install": apply_software_install' "$helper" ||
  fail "session apply owns software-install"
grep -Fq '"software-remove": apply_software_remove' "$helper" ||
  fail "session apply owns software-remove"
[[ -f $software_session ]] || fail "Software Center hosts a session install plane"
grep -Fq 'software-install' "$software_session" || fail "session install QML calls software-install"
grep -Fq 'software-remove' "$software_session" || fail "session install QML calls software-remove"
grep -Fq 'omarchy-fabric-session-apply' "$software_session" ||
  fail "session install QML uses the session apply helper"
if grep -Eq 'operation\.(preflight|start|approve)' "$software_session" "$software_app"; then
  fail "Software install must not mint Fabric durable operations"
fi
grep -Fq 'this session' "$software_app" || fail "Software Center names the session principal"
grep -Fq 'Fabric' "$software_app" || fail "Software Center keeps Fabric inspect honest"
if grep -Fq 'This surface never invokes a package manager' "$software_app"; then
  fail "Software Center no longer claims it never installs"
fi
grep -Fq 'Install' "$software_card" || fail "catalog cards expose Install"
grep -Fq 'sessionMutationPlan' "$software_model" || fail "Software model plans session mutations"
grep -Fq 'installRecord({ id: plan.packageId })' "$software_app" ||
  fail "install submits the admitted plan identity"
grep -Fq 'removeRecord({ id: plan.packageId })' "$software_app" ||
  fail "remove submits the admitted plan identity"

pass "Software Center wires a session install plane instead of a Fabric LIVE button"

cd "$ROOT/default/fabric"
PYTHONPATH="$ROOT/default/fabric" PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import io
import json

from omarchy_fabric.helpers import session_apply as sa

failures = []


def check(label, condition, detail=""):
    if not condition:
        failures.append(f"{label}{': ' + detail if detail else ''}")


class Result:
    def __init__(self, returncode=0, stdout="", stderr=""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


calls = []


def fake_run(argv, **kwargs):
    calls.append(list(argv))
    if argv and argv[0] == sa.OMARCHY_PKG_ADD:
        if "missing-pkg" in argv:
            return Result(returncode=1, stderr="Error: Package 'missing-pkg' did not install")
        return Result(returncode=0, stdout="installed")
    if argv and argv[0] == sa.OMARCHY_PKG_DROP:
        return Result(returncode=0, stdout="removed")
    raise AssertionError(argv)


def run_action(handler, payload):
    stream = io.StringIO()
    status = handler(io.StringIO(json.dumps(payload)), stream, run=fake_run)
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


calls.clear()
status, result = run_action(sa.apply_software_install, {"packageId": "software.curated.neovim"})
check("install neovim succeeds", status == 0 and result.get("ok") is True, str(result))
check("install reports neovim", result.get("packageRef") == "neovim", str(result))
check("pkg-add is /usr/bin pinned", sa.OMARCHY_PKG_ADD == "/usr/bin/omarchy-pkg-add", sa.OMARCHY_PKG_ADD)
check("pkg-drop is /usr/bin pinned", sa.OMARCHY_PKG_DROP == "/usr/bin/omarchy-pkg-drop", sa.OMARCHY_PKG_DROP)
check(
    "install uses /usr/bin/omarchy-pkg-add",
    any(call and call[0] == "/usr/bin/omarchy-pkg-add" and "neovim" in call for call in calls),
    str(calls),
)

calls.clear()
status, result = run_action(sa.apply_software_install, {"packageId": "software.curated.neovim"})
check("second install is a successful no-op", status == 0 and result.get("ok") is True, str(result))

status, result = run_action(sa.apply_software_install, {"packageId": "software.flatpak.spotify"})
check("flatpak install is refused", status == 1 and result.get("ok") is False, str(result))
check(
    "flatpak refusal names the source",
    "source" in str(result.get("explanation") or "").lower() or result.get("code") == "package.source-unsupported",
    str(result),
)

status, result = run_action(sa.apply_software_install, {"packageId": "software.missing.nope"})
check("unknown catalog id is refused", status == 1 and result.get("ok") is False, str(result))

status, result = run_action(sa.apply_software_install, {"packageId": "neovim; rm -rf /"})
check("shell package id is refused", status == 1 and result.get("ok") is False, str(result))

status, result = run_action(sa.apply_software_remove, {"packageId": "software.curated.neovim"})
check("remove neovim succeeds", status == 0 and result.get("ok") is True, str(result))

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session software-install and software-remove report success and honest refusal"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-software/SoftwareModel.js')

const neovim = {
  id: 'software.curated.neovim',
  kind: 'software',
  title: 'Neovim',
  details: [
    { label: 'Source', value: 'curated' },
    { label: 'Package', value: 'neovim' }
  ]
}
const spotify = {
  id: 'software.flatpak.spotify',
  kind: 'software',
  title: 'Spotify',
  details: [
    { label: 'Source', value: 'flatpak' },
    { label: 'Package', value: 'com.spotify.Client' }
  ]
}

const install = Model.sessionMutationPlan(neovim, 'install')
assertEqual(install.action, 'install', 'curated catalog rows can install')
assertEqual(install.packageId, 'software.curated.neovim', 'install keeps the catalog identity')
assertEqual(install.packageRef, 'neovim', 'install keeps the package ref')
assert(Model.sessionMutationCanSubmit(install), 'curated install can submit')

const refused = Model.sessionMutationPlan(spotify, 'install')
assertEqual(refused.action, 'unavailable', 'flatpak rows stay unavailable')
assert(!Model.sessionMutationCanSubmit(refused), 'flatpak install cannot submit')

const installed = {
  id: 'install.local.neovim',
  kind: 'installation',
  title: 'neovim',
  subtitle: 'software.curated.neovim',
  details: [
    { label: 'Source', value: 'curated' },
    { label: 'Package', value: 'neovim' }
  ]
}
const installedPlan = Model.sessionMutationPlan(installed, 'remove')
assertEqual(installedPlan.action, 'remove', 'installation rows can remove')
assertEqual(installedPlan.packageId, 'software.curated.neovim', 'installation rows admit the catalog identity, not the install id')
assert(Model.sessionMutationCanSubmit(installedPlan), 'admitted installation remove can submit')

const idle = Model.sessionMutationIdle()
assertEqual(idle.phase, 'idle', 'session mutation starts idle')
const running = Model.sessionMutationAccepted(idle, install)
assertEqual(running.phase, 'running', 'submit moves to running')
const ok = Model.sessionMutationFinished(running, { ok: true, packageRef: 'neovim', explanation: 'Installed neovim.' })
assertEqual(ok.phase, 'succeeded', 'helper success is succeeded')
assertEqual(ok.message, 'Installed neovim.', 'success keeps the helper explanation')
const failed = Model.sessionMutationFinished(running, { ok: false, code: 'command.failed', explanation: 'pacman refused.' })
assertEqual(failed.phase, 'failed', 'helper failure is failed')
assertEqual(failed.message, 'pacman refused.', 'failure keeps the helper explanation')
JS

pass "Software model plans session install and maps helper outcomes"

python3 - "$catalog" <<'PY'
import json
import sys

catalog = json.loads(open(sys.argv[1], encoding="utf-8").read())
by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
install = by_id["software.install"]
route = install["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Software Center":
    raise SystemExit(f"software.install route is {route}")
if route.get("path") != "Software Center > Catalog":
    raise SystemExit(f"software.install path is {route}")
if route.get("label") != "Install software":
    raise SystemExit(f"software.install label is {route}")
if install.get("source", {}).get("file") != "shell/apps/shared/SoftwareSessionInstall.qml":
    raise SystemExit(f"software.install source is {install.get('source')}")
if install.get("source", {}).get("symbol") != "installRecord":
    raise SystemExit(f"software.install source is {install.get('source')}")
if install.get("availability", {}).get("claim") == "present":
    raise SystemExit("software.install must not claim present")
if install.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"software.install human availability is {install.get('availability')}")
if install.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"software.install was raised off leftover: {install.get('provider')}")
remove = by_id["software.uninstall"]
if remove["humanRoute"].get("path") != "Software Center > Catalog":
    raise SystemExit(f"software.uninstall path is {remove.get('humanRoute')}")
if remove.get("availability", {}).get("claim") == "present":
    raise SystemExit("software.uninstall must not claim present")
if remove.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"software.uninstall was raised off leftover: {remove.get('provider')}")
PY

pass "software.install stays leftover partial with a visible Software Center route"
