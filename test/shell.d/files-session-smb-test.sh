#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
files_app="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"
files_model="$ROOT/shell/apps/ultimate-files/FilesModel.js"
files_session="$ROOT/shell/apps/shared/FilesSessionSmb.qml"
command_bar="$ROOT/shell/apps/ultimate-files/ExplorerCommandBar.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"
debt="$ROOT/default/ultimate/capabilities/legacy-debt-v0.json"
jobs="$ROOT/default/ultimate/parity/jobs.json"
gaps="$ROOT/plans/win7-ultimate-ground-truth/fleet/fleet-doctrine-gaps.md"
parity="$ROOT/WINDOWS_7_ULTIMATE_PARITY.md"
files_docs="$ROOT/docs/files-defaults-provider.md"
handoff="$ROOT/HANDOFF_WRITERS_2026-09-01.md"
project="$ROOT/plans/project-ultimate.md"
daemon="$ROOT/default/fabric/omarchy_fabric/daemon.py"
files_provider="$ROOT/default/fabric/omarchy_fabric/providers/files"
storage_provider="$ROOT/default/fabric/omarchy_fabric/providers/storage"
files_plane="$ROOT/test/fabric/operations/test_files_plane.py"

[[ -f $helper ]] || fail "session apply helper exists"
[[ -f $files_app ]] || fail "Files application exists"
[[ -f $files_model ]] || fail "Files model exists"
[[ -f $files_session ]] || fail "Files hosts a session Connect plane"
[[ -f $command_bar ]] || fail "Files command bar exists"

grep -Fq '"sharing-smb-connect": apply_sharing_smb_connect' "$helper" ||
  fail "session apply owns sharing-smb-connect"
grep -Fq 'sharing-smb-connect' "$files_session" || fail "session Connect QML calls sharing-smb-connect"
grep -Fq 'connectShare' "$files_session" || fail "session Connect QML exposes connectShare"
grep -Fq 'omarchy-fabric-session-apply' "$files_session" ||
  fail "session Connect QML uses the session apply helper"
grep -Fq 'OMARCHY_PATH' "$files_session" || fail "session Connect QML prefers OMARCHY_PATH"
grep -Fq '/bin/omarchy-fabric-session-apply' "$files_session" ||
  fail "session Connect QML spawns omarchy-fabric-session-apply from an absolute bin path"
if grep -Eq 'return "omarchy-fabric-session-apply"|: "omarchy-fabric-session-apply"' "$files_session"; then
  fail "session Connect QML must not spawn a bare omarchy-fabric-session-apply PATH name"
fi
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$files_session"; then
  fail "Files Connect session plane must not mint Fabric durable operations"
fi
if grep -Eq 'action: "mount\.|action: "mount\.connect|provider: "files.provider"|provider: "sharing.provider"' "$files_session"; then
  fail "session Connect QML must not call a Fabric sharing or files.provider mount action"
fi
if grep -Eq 'pkexec|sudo' "$files_session"; then
  fail "Files Connect QML must not spawn privilege"
fi
grep -Fq 'Shared.FilesSessionSmb' "$files_app" || fail "Files hosts the session Connect helper"
grep -Fq 'sessionConnectShare' "$files_app" || fail "Files Connect uses the session Connect plane"
grep -Fq 'key: "connect", label: "Connect to Server"' "$files_app" || fail "Files shows a Connect to Server control"
grep -Fq 'SESSION CONTROL' "$files_app" "$command_bar" ||
  fail "Files shows a SESSION CONTROL badge"
grep -Fq 'smbAuthorized: false' "$files_app" || fail "Files pins smbAuthorized leftover Fabric SHELL refuse"
if grep -Eq 'LIVE CONTROL' "$files_app" "$files_session" "$command_bar"; then
  fail "Files Connect must not invent Fabric LIVE CONTROL"
fi
if grep -Eqi 'claim=present' "$files_app" "$files_session"; then
  fail "Files Connect must not invent claim=present"
fi
if grep -Eq 'Process[[:space:]]*\{' "$files_app"; then
  fail "Files consumer QML must not host the session Process block"
fi
grep -Fq 'sessionSmbPlan' "$files_model" || fail "Files model plans session Connect"
grep -Fq 'Connect to Server runs through this session' "$files_app" ||
  fail "Files banner names session Connect"
grep -Fq 'does not invent a Fabric SHELL LIVE SMB writer' "$files_app" ||
  fail "Files banner refuses a Fabric SHELL LIVE SMB writer"
grep -Fq '/usr/bin/gio' "$helper" || fail "session Connect pins gio to an absolute path"
grep -Fq 'share.auth-required' "$helper" || fail "session Connect names share.auth-required"
if grep -Eq 'sharing-smb-connect' "$daemon" "$files_plane"; then
  fail "Fabric durable plane invented a sharing-smb-connect writer"
fi
if grep -Eq 'sharing-smb-connect|files-smb-connect' "$files_provider"/*.py "$files_provider"/*.json "$storage_provider"/*.py; then
  fail "Fabric storage or files provider invented a session SMB writer"
fi

python3 - "$files_app" <<'PY'
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
for name in ("commandActions", "organizeMenuItems", "contextMenuItems"):
    match = re.search(rf"function {name}\(\) \{{(.*?)\n  \}}", src, re.S)
    if not match:
        raise SystemExit(f"{name} is missing")
    body = match.group(1)
    if 'key: "connect"' not in body:
        raise SystemExit(f"{name} dropped Connect to Server")
    after = body.split('key: "connect"', 1)[1][:320]
    if "sessionBusy" not in after:
        raise SystemExit(f"{name} Connect is not session-busy gated")
PY

pass "Files wires a session Connect plane instead of a Fabric LIVE SMB writer"

cd "$ROOT/default/fabric"
PYTHONPATH="$ROOT/default/fabric" PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import io
import json
import os
import pathlib
import tempfile

os.environ.pop("XDG_DATA_HOME", None)
root = pathlib.Path(tempfile.mkdtemp())
home = root / "tester"
home.mkdir(parents=True)
os.environ["HOME"] = str(home)
os.environ["USERPROFILE"] = str(home)

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


def run(payload, runner=None):
    stream = io.StringIO()
    status = sa.apply_sharing_smb_connect(
        io.StringIO(json.dumps(payload)),
        stream,
        run=runner or (lambda *args, **kwargs: Result()),
    )
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


if "sharing-smb-connect" not in sa.ACTIONS:
    failures.append("session apply ACTIONS omitted sharing-smb-connect")

status, result = run({})
check("empty payload is refused first", status == 1 and result.get("ok") is False, str(result))
check("empty payload uses payload.invalid", result.get("code") == "payload.invalid", str(result))
check("empty payload does not pretend connect succeeded", result.get("connected") is not True, str(result))

secret_payload = {"host": "fileserver", "share": "public", "password": "hunter2", "user": "alice"}
status, result = run(secret_payload)
check("credential keys are refused", status == 1 and result.get("ok") is False, str(result))
check("credential keys use payload.invalid", result.get("code") == "payload.invalid", str(result))
encoded = json.dumps(result)
check("credential refuse does not leak secrets", "hunter2" not in encoded and "alice" not in encoded, str(result))

status, result = run({"host": "user@fileserver", "share": "public"})
check("userinfo host is refused", status == 1 and result.get("code") == "payload.invalid", str(result))

status, result = run({"host": "fileserver:445", "share": "public"})
check("port-bearing host is refused", status == 1 and result.get("code") == "payload.invalid", str(result))

status, result = run({"host": "fileserver/public", "share": "public"})
check("path-bearing host is refused", status == 1 and result.get("code") == "payload.invalid", str(result))

status, result = run({"host": "fileserver", "share": "../secret"})
check("traversal share is refused", status == 1 and result.get("code") == "payload.invalid", str(result))

status, result = run({"host": "fileserver", "share": "public/nested"})
check("nested share is refused", status == 1 and result.get("code") == "payload.invalid", str(result))

auth_calls = []


def auth_run(argv, **kwargs):
    auth_calls.append(list(argv))
    return Result(returncode=1, stderr="Authentication required\nPassword: hunter2\n")


status, result = run({"host": "fileserver", "share": "private"}, auth_run)
check("password share is refused first", status == 1 and result.get("ok") is False, str(result))
check("password share uses share.auth-required", result.get("code") == "share.auth-required", str(result))
check("password share does not pretend connect succeeded", result.get("connected") is not True, str(result))
check("password share does not leak secrets", "hunter2" not in json.dumps(result), str(result))
check("password share uses absolute gio", auth_calls and auth_calls[0][0] == sa.GIO, str(auth_calls))

ok_calls = []


def ok_run(argv, **kwargs):
    ok_calls.append(list(argv))
    return Result(stdout="Mounted smb://fileserver/public at /run/user/1000/gvfs/smb-share:server=fileserver,share=public\n")


status, result = run({"host": "fileserver", "share": "public"}, ok_run)
check("mocked guest connect succeeds after refuse", status == 0 and result.get("ok") is True, str(result))
check("mocked guest connect reports connected", result.get("connected") is True, str(result))
check("mocked guest connect names smb-guest scope", result.get("scope") == "smb-guest", str(result))
check("mocked guest connect keeps host", result.get("host") == "fileserver", str(result))
check("mocked guest connect keeps share", result.get("share") == "public", str(result))
check("mocked guest connect names this session", "this session" in str(result.get("explanation") or ""), str(result))
check("mocked guest connect does not leak auth secrets", "password" not in json.dumps(result).lower(), str(result))
check(
    "mocked guest connect uses absolute gio anonymous",
    ok_calls == [[sa.GIO, "mount", "--anonymous", "smb://fileserver/public"]],
    str(ok_calls),
)

already_calls = []


def already_run(argv, **kwargs):
    already_calls.append(list(argv))
    return Result(returncode=1, stderr="Location is already mounted\n")


status, result = run({"host": "fileserver", "share": "public"}, already_run)
check("already mounted share is honest success", status == 0 and result.get("ok") is True, str(result))
check("already mounted share names already method", result.get("method") == "already", str(result))
check("already mounted share reports connected", result.get("connected") is True, str(result))


def missing_command_run(argv, **kwargs):
    raise FileNotFoundError(argv[0])


status, result = run({"host": "fileserver", "share": "public"}, missing_command_run)
check("missing gio is command.unavailable", status == 1 and result.get("code") == "command.unavailable", str(result))

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session Connect reports success and honest auth refuse"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-files/FilesModel.js')

const plan = Model.sessionSmbPlan('fileserver', 'public')
assertEqual(plan.action, 'connect', 'a guest host and share can connect through this session')
assertEqual(plan.host, 'fileserver', 'Connect keeps the host')
assertEqual(plan.share, 'public', 'Connect keeps the share')
assert(Model.sessionSmbCanSubmit(plan), 'guest Connect can submit')

const ipv4 = Model.sessionSmbPlan('192.168.1.10', 'Public')
assertEqual(ipv4.action, 'connect', 'an IPv4 host can connect through this session')
assertEqual(ipv4.host, '192.168.1.10', 'Connect keeps the IPv4 host')

const empty = Model.sessionSmbPlan('', '')
assertEqual(empty.action, 'unavailable', 'empty host and share cannot connect')
assert(!Model.sessionSmbCanSubmit(empty), 'empty Connect cannot submit')
assert(String(empty.reason || '').toLowerCase().indexOf('host') >= 0, 'empty Connect names the empty state')

const userinfo = Model.sessionSmbPlan('alice@fileserver', 'public')
assertEqual(userinfo.action, 'unavailable', 'userinfo hosts cannot connect')

const nested = Model.sessionSmbPlan('fileserver', 'public/nested')
assertEqual(nested.action, 'unavailable', 'nested shares cannot connect')

const traversal = Model.sessionSmbPlan('fileserver', '../secret')
assertEqual(traversal.action, 'unavailable', 'traversal shares cannot connect')
JS

pass "Files model plans session Connect"

python3 - "$catalog" "$jobs" "$debt" "$gaps" "$parity" "$files_docs" "$handoff" "$project" "$files_session" "$files_app" <<'PY'
import json
import sys

catalog = json.loads(open(sys.argv[1], encoding="utf-8").read())
jobs = json.loads(open(sys.argv[2], encoding="utf-8").read())
debt = json.loads(open(sys.argv[3], encoding="utf-8").read())
gaps = open(sys.argv[4], encoding="utf-8").read()
parity = open(sys.argv[5], encoding="utf-8").read()
files_docs = open(sys.argv[6], encoding="utf-8").read()
handoff = open(sys.argv[7], encoding="utf-8").read()
project = open(sys.argv[8], encoding="utf-8").read()
session = open(sys.argv[9], encoding="utf-8").read()
files_app = open(sys.argv[10], encoding="utf-8").read()

by_id = {entry["id"]: entry for entry in catalog["capabilities"]}
connect = by_id["sharing.smb.connect"]
route = connect["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Files":
    raise SystemExit(f"sharing.smb.connect route is {route}")
if route.get("path") != "Files > Connect to Server":
    raise SystemExit(f"sharing.smb.connect path is {route}")
if route.get("label") != "Connect to network share":
    raise SystemExit(f"sharing.smb.connect label is {route}")
if connect.get("source", {}).get("file") != "shell/apps/shared/FilesSessionSmb.qml":
    raise SystemExit(f"sharing.smb.connect source is {connect.get('source')}")
if connect.get("source", {}).get("symbol") != "connectShare":
    raise SystemExit(f"sharing.smb.connect source is {connect.get('source')}")
if connect.get("availability", {}).get("claim") == "present":
    raise SystemExit("sharing.smb.connect must not claim present")
if connect.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"sharing.smb.connect claim is {connect.get('availability')}")
if connect.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"sharing.smb.connect human availability is {connect.get('availability')}")
if connect.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"sharing.smb.connect agent availability is {connect.get('availability')}")
if connect.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"sharing.smb.connect was raised off leftover: {connect.get('provider')}")
if connect.get("provider", {}).get("id") != "sharing.provider":
    raise SystemExit(f"sharing.smb.connect provider is {connect.get('provider')}")

by_job = {job["id"]: job for job in jobs["jobs"]}
native16 = by_job["windows-native.16"]
if native16.get("claim") == "present":
    raise SystemExit("windows-native.16 must not claim present")
if native16.get("claim") != "missing":
    raise SystemExit(f"windows-native.16 claim is {native16.get('claim')}")
if native16.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.16 sourceStatus is {native16.get('sourceStatus')}")
if native16.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.16 proofStatus is {native16.get('proofStatus')}")
if native16.get("capabilityIds") != ["sharing.smb.connect"]:
    raise SystemExit(f"windows-native.16 capabilityIds are {native16.get('capabilityIds')}")
if native16["humanRoute"].get("path") != "Files > Connect to Server":
    raise SystemExit(f"windows-native.16 path is {native16.get('humanRoute')}")
if native16["humanRoute"].get("status") != "visible":
    raise SystemExit(f"windows-native.16 humanRoute status is {native16.get('humanRoute')}")

explorer = by_job["parity.explorer-this-pc"]
if explorer.get("claim") == "present":
    raise SystemExit("parity.explorer-this-pc must not claim present")
if "sharing.smb.connect" in (explorer.get("capabilityIds") or []):
    raise SystemExit("parity.explorer-this-pc invents Explorer present by naming sharing.smb.connect")

sharing = by_job["parity.sharing"]
if sharing.get("claim") == "present":
    raise SystemExit("parity.sharing must not claim present")
if sharing.get("claim") != "missing":
    raise SystemExit(f"parity.sharing claim is {sharing.get('claim')}")

by_debt = {entry["id"]: entry for entry in debt["entries"]}
legacy = by_debt["legacy.domain.direct-providers"]
if "sharing.smb.connect" not in legacy.get("capabilityIds", []):
    raise SystemExit("sharing.smb.connect is not leftover-direct debt")
if "capability:sharing.smb.connect" not in legacy.get("surfaceRefs", []):
    raise SystemExit("sharing.smb.connect leftover surfaceRef is missing")
missing_domain = by_debt["missing.domain.providers"]
if "sharing.smb.connect" in missing_domain.get("capabilityIds", []):
    raise SystemExit("sharing.smb.connect stayed in missing.domain.providers")
agent = by_debt["missing.agent.routes"]
if "sharing.smb.connect" not in agent.get("capabilityIds", []):
    raise SystemExit("sharing.smb.connect is not agent-unavailable debt")
if "capability:sharing.smb.connect" not in agent.get("surfaceRefs", []):
    raise SystemExit("sharing.smb.connect agent surfaceRef is missing")

if "Honesty addendum 2026-09-06 vs Files Connect to Server session plane" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must add a dated Files Connect to Server addendum")
addendum = gaps.split("Honesty addendum 2026-09-06 vs Files Connect to Server session plane", 1)[1].split("Honesty addendum", 1)[0]
if "CLOSED leftover: Files Connect" in addendum:
    raise SystemExit("fleet-doctrine-gaps must not invent product CLOSE from a bare CLOSED leftover pin")
if "Close one product hole" in addendum:
    raise SystemExit("fleet-doctrine-gaps must not invent Close one product hole")
if "session leftover recorded" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must record session leftover honesty")
if "session-UI leftover only" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must qualify Connect as session-UI leftover only")
if "not product CLOSED" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse product CLOSED invent")
if "not metal CLOSED" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse metal CLOSED invent")
if "leftover-attach before citing suite EXIT 0 as metal" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must leftover-attach before citing suite EXIT 0 as metal")
if "Cloud mocks do not close windows-native.16" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse closing windows-native.16 from Cloud mocks")
for required in (
    "metal proof",
    "Files LIVE metal",
    "Win7 visual",
    "Explorer present",
    "Fabric LIVE under SHELL",
    "Settings Power LIVE",
    "End Task LIVE",
    "Software Center present",
    "Update present",
    "claim=present",
    "password-share / keyring UI",
):
    if required not in addendum:
        raise SystemExit(f"fleet-doctrine-gaps Connect addendum dropped OPEN leftover: {required}")
if "Do not invent claim=present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse claim=present invent")
if "Cloud EXIT 0 is not metal leftover CLOSED" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Cloud EXIT 0 as metal leftover CLOSED")
if "Files > Connect to Server" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name Files > Connect to Server")
if "this session" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name the session plane")
if "share.auth-required" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name share.auth-required")
if "windows-native.16" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.16 pending")
if "Do not invent Fabric LIVE under SHELL" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Fabric LIVE under SHELL invent")
if "Do not invent Network Places product" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Network Places product invent")

if "SESSION CONTROL" not in session and "SESSION CONTROL" not in files_app:
    raise SystemExit("session Connect must show SESSION CONTROL")
if "LIVE CONTROL" in session:
    raise SystemExit("session Connect invented LIVE CONTROL")
if "Files > Connect to Server" not in parity:
    raise SystemExit("PARITY must name Files > Connect to Server")
if "session Connect" not in parity and "sharing-smb-connect" not in parity:
    raise SystemExit("PARITY must name session Connect without walking Explorer to present")
explorer_row = ""
for line in parity.splitlines():
    if line.startswith("| Explorer / Computer |"):
        explorer_row = line
        break
if "this row is not present" not in explorer_row or "prototype" not in explorer_row:
    raise SystemExit("PARITY Explorer row must stay not present")
if "sharing-smb-connect" not in handoff:
    raise SystemExit("HANDOFF must name sharing-smb-connect")
if "session leftover recorded" not in handoff:
    raise SystemExit("HANDOFF must record session leftover honesty")
if "not product CLOSED" not in handoff:
    raise SystemExit("HANDOFF must refuse product CLOSED invent")
if "Cloud mocks do not close windows-native.16" not in handoff:
    raise SystemExit("HANDOFF must refuse closing windows-native.16 from Cloud mocks")
if "CLOSED leftover: Files Connect" in handoff:
    raise SystemExit("HANDOFF must not invent product CLOSE from a bare CLOSED leftover pin")
if "session Connect" not in handoff and "Files Connect to Server session" not in handoff:
    raise SystemExit("HANDOFF must name session Connect")
if "sharing-smb-connect" not in project and "session Connect" not in project:
    raise SystemExit("project-ultimate must name session Connect")
if "session leftover recorded" not in project:
    raise SystemExit("project-ultimate must record session leftover honesty")
if "not product CLOSED" not in project:
    raise SystemExit("project-ultimate must refuse product CLOSED invent")
if "sharing.smb.connect" not in files_docs:
    raise SystemExit("files-defaults-provider must name sharing.smb.connect")
docs_slice = files_docs.split("sharing.smb.connect", 1)[1][:1800]
if "does not invent a Fabric" not in docs_slice:
    raise SystemExit("files-defaults-provider must refuse a Fabric SMB writer")
if "share.auth-required" not in docs_slice:
    raise SystemExit("files-defaults-provider must name share.auth-required")
if "session leftover recorded" not in docs_slice:
    raise SystemExit("files-defaults-provider must record session leftover honesty")
if "not product CLOSED" not in docs_slice:
    raise SystemExit("files-defaults-provider must refuse product CLOSED invent")
if "Cloud mocks do not close" not in docs_slice:
    raise SystemExit("files-defaults-provider must refuse closing windows-native.16 from Cloud mocks")
PY

pass "sharing.smb.connect stays leftover partial with a visible Files Connect to Server route"
