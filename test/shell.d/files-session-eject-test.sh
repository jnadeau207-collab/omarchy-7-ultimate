#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
files_app="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"
files_model="$ROOT/shell/apps/ultimate-files/FilesModel.js"
files_session="$ROOT/shell/apps/shared/FilesSessionEject.qml"
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
[[ -f $files_session ]] || fail "Files hosts a session Eject plane"
[[ -f $command_bar ]] || fail "Files command bar exists"

grep -Fq '"storage-removable-eject": apply_storage_removable_eject' "$helper" ||
  fail "session apply owns storage-removable-eject"
grep -Fq 'storage-removable-eject' "$files_session" || fail "session Eject QML calls storage-removable-eject"
grep -Fq 'ejectDevice' "$files_session" || fail "session Eject QML exposes ejectDevice"
grep -Fq 'omarchy-fabric-session-apply' "$files_session" ||
  fail "session Eject QML uses the session apply helper"
grep -Fq 'OMARCHY_PATH' "$files_session" || fail "session Eject QML prefers OMARCHY_PATH"
grep -Fq '/bin/omarchy-fabric-session-apply' "$files_session" ||
  fail "session Eject QML spawns omarchy-fabric-session-apply from an absolute bin path"
if grep -Eq 'return "omarchy-fabric-session-apply"|: "omarchy-fabric-session-apply"' "$files_session"; then
  fail "session Eject QML must not spawn a bare omarchy-fabric-session-apply PATH name"
fi
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$files_session"; then
  fail "Files Eject session plane must not mint Fabric durable operations"
fi
if grep -Eq 'action: "eject\.|action: "mount\.disconnect|provider: "files.provider"|provider: "storage.provider"' "$files_session"; then
  fail "session Eject QML must not call a Fabric storage or files.provider eject action"
fi
if grep -Eq 'pkexec|sudo' "$files_session"; then
  fail "Files Eject QML must not spawn privilege"
fi
grep -Fq 'Shared.FilesSessionEject' "$files_app" || fail "Files hosts the session Eject helper"
grep -Fq 'sessionEjectDevice' "$files_app" || fail "Files Eject uses the session Eject plane"
grep -Fq 'key: "eject", label: "Eject"' "$files_app" || fail "Files shows an Eject control"
grep -Fq 'SESSION CONTROL' "$files_app" "$command_bar" ||
  fail "Files shows a SESSION CONTROL badge"
grep -Fq 'ejectAuthorized: false' "$files_app" || fail "Files pins ejectAuthorized leftover Fabric SHELL refuse"
if grep -Eq 'LIVE CONTROL' "$files_app" "$files_session" "$command_bar"; then
  fail "Files Eject must not invent Fabric LIVE CONTROL"
fi
if grep -Eqi 'claim=present' "$files_app" "$files_session"; then
  fail "Files Eject must not invent claim=present"
fi
if grep -Eq 'Process[[:space:]]*\{' "$files_app"; then
  fail "Files consumer QML must not host the session Process block"
fi
grep -Fq 'sessionEjectPlan' "$files_model" || fail "Files model plans session Eject"
grep -Fq 'sessionEjectableRecord' "$files_model" || fail "Files model gates session Eject"
grep -Fq 'Eject runs through this session' "$files_app" ||
  fail "Files banner names session Eject"
grep -Fq 'does not invent a Fabric SHELL LIVE eject writer' "$files_app" ||
  fail "Files banner refuses a Fabric SHELL LIVE eject writer"
grep -Fq '/usr/bin/udisksctl' "$helper" || fail "session Eject pins udisksctl to an absolute path"
grep -Fq '/usr/bin/gio' "$helper" || fail "session Eject pins gio to an absolute path"
grep -Fq 'device.busy' "$helper" || fail "session Eject names device.busy"
if grep -Eq 'storage-removable-eject' "$daemon" "$files_plane"; then
  fail "Fabric durable plane invented a storage-removable-eject writer"
fi
if grep -Eq 'storage-removable-eject|files-mount-eject' "$files_provider"/*.py "$files_provider"/*.json "$storage_provider"/*.py "$storage_provider"/*.json; then
  fail "Fabric storage or files provider invented a session eject writer"
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
    if 'key: "eject"' not in body:
        raise SystemExit(f"{name} dropped Eject")
    if "sessionEjectableRecord" not in body.split('key: "eject"', 1)[1][:320]:
        raise SystemExit(f"{name} Eject is not session-ejectable gated")
PY

pass "Files wires a session Eject plane instead of a Fabric LIVE eject writer"

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


def mount_line(source, mount_point, filesystem="vfat"):
    return f"36 1 8:17 / {mount_point} rw,relatime - {filesystem} {source} rw"


usb_mount = "/run/media/tester/USBKEY"
usb_source = "/dev/sdb1"
usb_id = sa.stable_files_mount_id(usb_source, usb_mount)
optical_mount = "/run/media/tester/CDROM"
optical_source = "/dev/sr0"
optical_id = sa.stable_files_mount_id(optical_source, optical_mount)
system_id = sa.stable_files_mount_id("/dev/sda2", "/")
smb_id = sa.stable_files_mount_id("//host/share", "/run/media/tester/share")

usb_info = "\n".join(
    [
        mount_line("/dev/sda2", "/"),
        mount_line(usb_source, usb_mount),
        mount_line("//host/share", "/run/media/tester/share", "cifs"),
    ]
)
optical_info = mount_line(optical_source, optical_mount, "iso9660")


def run_main(payload):
    stream = io.StringIO()
    status = sa.main(["storage-removable-eject"], io.StringIO(json.dumps(payload)), stream)
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


def run(payload, runner=None, mountinfo_text=None, home_path=None):
    stream = io.StringIO()
    status = sa.apply_storage_removable_eject(
        io.StringIO(json.dumps(payload)),
        stream,
        run=runner or (lambda *args, **kwargs: Result()),
        mountinfo_text=mountinfo_text,
        home=home_path if home_path is not None else home,
    )
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


missing = {"mountId": "files.mount." + ("0" * 64)}
status, result = run_main(missing)
check("missing removable device is refused first", status == 1 and result.get("ok") is False, str(result))
check("missing removable device uses resource.unresolved", result.get("code") == "resource.unresolved", str(result))
check("missing removable device does not pretend eject succeeded", result.get("ejected") is not True, str(result))

busy_calls = []


def busy_run(argv, **kwargs):
    busy_calls.append(list(argv))
    if argv[:3] == [sa.UDISKSCTL, "unmount", "-b"]:
        return Result(
            returncode=1,
            stderr="Error unmounting /dev/sdb1: GDBus.Error:org.freedesktop.UDisks2.Error.DeviceBusy: Device is busy\n",
        )
    raise AssertionError(f"busy mock should stop at unmount: {argv}")


status, result = run({"mountId": usb_id}, busy_run, usb_info)
check("busy unmount is refused", status == 1 and result.get("ok") is False, str(result))
check("busy unmount uses device.busy", result.get("code") == "device.busy", str(result))
check("busy unmount does not pretend eject succeeded", result.get("ejected") is not True, str(result))
check("busy unmount explanation stays honest", "busy" in str(result.get("explanation") or "").lower(), str(result))
check("busy unmount uses absolute udisksctl", busy_calls and busy_calls[0][0] == sa.UDISKSCTL, str(busy_calls))

ok_calls = []


def ok_run(argv, **kwargs):
    ok_calls.append(list(argv))
    if argv[:3] == [sa.LSBLK, "--noheadings", "--output"]:
        return Result(stdout="sdb\n")
    return Result()


status, result = run({"mountId": usb_id}, ok_run, usb_info)
check("mocked USB eject succeeds after refuse", status == 0 and result.get("ok") is True, str(result))
check("mocked USB eject reports ejected", result.get("ejected") is True, str(result))
check("mocked USB eject reports unmounted", result.get("unmounted") is True, str(result))
check("mocked USB eject uses power-off", result.get("method") == "power-off", str(result))
check("mocked USB eject names usb-volume scope", result.get("scope") == "usb-volume", str(result))
check("mocked USB eject keeps the mount identity", result.get("mountId") == usb_id, str(result))
check("mocked USB eject names this session", "this session" in str(result.get("explanation") or ""), str(result))
check("mocked USB eject does not leak auth secrets", "password" not in json.dumps(result).lower(), str(result))
check(
    "mocked USB eject unmounts then powers off the parent disk",
    ok_calls[:2] == [[sa.UDISKSCTL, "unmount", "-b", "/dev/sdb1"], [sa.LSBLK, "--noheadings", "--output", "PKNAME", "/dev/sdb1"]]
    and ok_calls[2] == [sa.UDISKSCTL, "power-off", "-b", "/dev/sdb"],
    str(ok_calls),
)

optical_calls = []


def optical_run(argv, **kwargs):
    optical_calls.append(list(argv))
    return Result()


status, result = run({"mountId": optical_id}, optical_run, optical_info)
check("mocked optical eject succeeds", status == 0 and result.get("ok") is True, str(result))
check("mocked optical eject uses eject", result.get("method") == "eject", str(result))
check("mocked optical eject names optical scope", result.get("scope") == "optical", str(result))
check(
    "mocked optical eject does not power-off",
    optical_calls == [
        [sa.UDISKSCTL, "unmount", "-b", "/dev/sr0"],
        [sa.UDISKSCTL, "eject", "-b", "/dev/sr0"],
    ],
    str(optical_calls),
)

power_busy_calls = []


def power_busy_run(argv, **kwargs):
    power_busy_calls.append(list(argv))
    if argv[:3] == [sa.UDISKSCTL, "power-off", "-b"]:
        return Result(returncode=1, stderr="Error powering off: Device or resource busy\n")
    if argv[:3] == [sa.LSBLK, "--noheadings", "--output"]:
        return Result(stdout="sdb\n")
    return Result()


status, result = run({"mountId": usb_id}, power_busy_run, usb_info)
check("busy power-off is refused after unmount", status == 1 and result.get("ok") is False, str(result))
check("busy power-off uses device.busy", result.get("code") == "device.busy", str(result))
check("busy power-off does not pretend eject succeeded", result.get("ejected") is not True, str(result))

unsupported_run_calls = []


def unsupported_run(argv, **kwargs):
    unsupported_run_calls.append(list(argv))
    if argv[:3] == [sa.UDISKSCTL, "power-off", "-b"]:
        return Result(returncode=1, stderr="Error: power-off is not supported for this device\n")
    if argv[:3] == [sa.LSBLK, "--noheadings", "--output"]:
        return Result(stdout="sdb\n")
    return Result()


status, result = run({"mountId": usb_id}, unsupported_run, usb_info)
check("unsupported power-off still unmounts honestly", status == 0 and result.get("ok") is True, str(result))
check("unsupported power-off does not claim ejected", result.get("ejected") is False, str(result))
check("unsupported power-off names unmount method", result.get("method") == "unmount", str(result))
check("unsupported power-off names the unavailable drive action", "power-off is unavailable" in str(result.get("explanation") or ""), str(result))

status, result = run({"mountId": system_id}, lambda *args, **kwargs: Result(), usb_info)
check("system disks are refused", status == 1 and result.get("ok") is False, str(result))
check("system disks use payload.invalid", result.get("code") == "payload.invalid", str(result))

status, result = run({"mountId": smb_id}, lambda *args, **kwargs: Result(), usb_info)
check("SMB mounts are refused", status == 1 and result.get("ok") is False, str(result))
check("SMB mounts use payload.invalid", result.get("code") == "payload.invalid", str(result))

escaped = usb_info.replace("/dev/sdb1", "../etc/passwd")
escaped_id = sa.stable_files_mount_id("../etc/passwd", usb_mount)
status, result = run({"mountId": escaped_id}, lambda *args, **kwargs: Result(), escaped)
check("escaped device paths are refused", status == 1 and result.get("ok") is False, str(result))
check("escaped device paths use payload.invalid", result.get("code") == "payload.invalid", str(result))

status, result = run({}, lambda *args, **kwargs: Result(), usb_info)
check("empty selection is refused", status == 1 and result.get("ok") is False, str(result))
check("empty selection uses payload.invalid", result.get("code") == "payload.invalid", str(result))

status, result = run({"mountId": "storage." + ("0" * 24)}, lambda *args, **kwargs: Result(), usb_info)
check("storage.provider identities are refused", status == 1 and result.get("code") == "payload.invalid", str(result))


def missing_command_run(argv, **kwargs):
    raise FileNotFoundError(argv[0])


status, result = run({"mountId": usb_id}, missing_command_run, usb_info)
check("missing udisksctl and gio is command.unavailable", status == 1 and result.get("code") == "command.unavailable", str(result))

auth_calls = []


def auth_run(argv, **kwargs):
    auth_calls.append(list(argv))
    return Result(returncode=1, stderr="polkit: a password is required\nsecret=hunter2\n")


status, result = run({"mountId": usb_id}, auth_run, usb_info)
check("auth denial does not pretend eject succeeded", status == 1 and result.get("ok") is False, str(result))
check("auth denial uses eject.auth-denied", result.get("code") == "eject.auth-denied", str(result))
check("auth denial does not leak secrets", "hunter2" not in json.dumps(result) and "password is required" not in json.dumps(result), str(result))

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session Eject reports success and honest busy refuse"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-files/FilesModel.js')

const removable = {
  id: 'files.mount.abc',
  kind: 'mount',
  mountKind: 'removable',
  mountState: 'mounted',
  title: 'USBKEY'
}

const plan = Model.sessionEjectPlan(removable)
assertEqual(plan.action, 'eject', 'a removable mount can eject through this session')
assertEqual(plan.mountId, 'files.mount.abc', 'Eject keeps the mount identity')
assert(Model.sessionEjectCanSubmit(plan), 'removable Eject can submit')
assertEqual(Model.sessionEjectableRecord(removable), true, 'removable mount is session-ejectable')

const empty = Model.sessionEjectPlan(null)
assertEqual(empty.action, 'unavailable', 'empty selection cannot eject')
assert(!Model.sessionEjectCanSubmit(empty), 'empty Eject cannot submit')
assert(String(empty.reason || '').toLowerCase().indexOf('select') >= 0, 'empty Eject names the empty state')

const system = Model.sessionEjectPlan({
  id: 'files.mount.sys',
  kind: 'mount',
  mountKind: 'system',
  title: 'Windows7'
})
assertEqual(system.action, 'unavailable', 'system disks cannot eject')
assert(String(system.reason || '').toLowerCase().indexOf('system') >= 0, 'system Eject names the refuse')

const smb = Model.sessionEjectPlan({
  id: 'files.mount.net',
  kind: 'mount',
  mountKind: 'smb',
  title: 'Share'
})
assertEqual(smb.action, 'unavailable', 'SMB mounts cannot eject')
assert(String(smb.reason || '').toLowerCase().indexOf('network') >= 0, 'SMB Eject names the refuse')

const file = Model.sessionEjectPlan({
  id: 'files.entry.abc',
  kind: 'entry',
  entryKind: 'file',
  title: 'notes.txt',
  locationId: 'files.location.documents',
  relativePath: 'notes.txt'
})
assertEqual(file.action, 'unavailable', 'files cannot eject')
assertEqual(Model.sessionEjectableRecord(file), false, 'files are not session-ejectable')
JS

pass "Files model plans session Eject"

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
eject = by_id["storage.removable.eject"]
route = eject["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Files":
    raise SystemExit(f"storage.removable.eject route is {route}")
if route.get("path") != "Files > Devices > Eject":
    raise SystemExit(f"storage.removable.eject path is {route}")
if route.get("label") != "Safely eject storage":
    raise SystemExit(f"storage.removable.eject label is {route}")
if eject.get("source", {}).get("file") != "shell/apps/shared/FilesSessionEject.qml":
    raise SystemExit(f"storage.removable.eject source is {eject.get('source')}")
if eject.get("source", {}).get("symbol") != "ejectDevice":
    raise SystemExit(f"storage.removable.eject source is {eject.get('source')}")
if "nautilus" in str(eject.get("source") or "").lower():
    raise SystemExit(f"storage.removable.eject still names Nautilus: {eject.get('source')}")
if eject.get("availability", {}).get("claim") == "present":
    raise SystemExit("storage.removable.eject must not claim present")
if eject.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"storage.removable.eject claim is {eject.get('availability')}")
if eject.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"storage.removable.eject human availability is {eject.get('availability')}")
if eject.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"storage.removable.eject agent availability is {eject.get('availability')}")
if eject.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"storage.removable.eject was raised off leftover: {eject.get('provider')}")
if eject.get("provider", {}).get("id") != "storage.provider":
    raise SystemExit(f"storage.removable.eject provider is {eject.get('provider')}")

mount = by_id["storage.removable.mount"]
if mount.get("availability", {}).get("claim") == "present":
    raise SystemExit("storage.removable.mount must not claim present")
if "nautilus" not in str(mount.get("source") or "").lower():
    raise SystemExit("storage.removable.mount leftover source should stay honest leftover")

by_job = {job["id"]: job for job in jobs["jobs"]}
native15 = by_job["windows-native.15"]
if native15.get("claim") == "present":
    raise SystemExit("windows-native.15 must not claim present")
if native15.get("claim") != "prototype":
    raise SystemExit(f"windows-native.15 claim is {native15.get('claim')}")
if native15.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.15 sourceStatus is {native15.get('sourceStatus')}")
if native15.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.15 proofStatus is {native15.get('proofStatus')}")
if native15.get("capabilityIds") != ["storage.removable.eject"]:
    raise SystemExit(f"windows-native.15 capabilityIds are {native15.get('capabilityIds')}")
if native15["humanRoute"].get("path") != "Files > Devices > Eject":
    raise SystemExit(f"windows-native.15 path is {native15.get('humanRoute')}")

explorer = by_job["parity.explorer-this-pc"]
if explorer.get("claim") == "present":
    raise SystemExit("parity.explorer-this-pc must not claim present")
if "storage.removable.eject" in (explorer.get("capabilityIds") or []):
    raise SystemExit("parity.explorer-this-pc invents Explorer present by naming storage.removable.eject")

for forbidden in (
    "parity.devices-printers",
    "windows-native.28",
    "windows-native.27",
):
    job = by_job[forbidden]
    if job.get("claim") == "present":
        raise SystemExit(f"{forbidden} must not claim present")

by_debt = {entry["id"]: entry for entry in debt["entries"]}
legacy = by_debt["legacy.domain.direct-providers"]
if "storage.removable.eject" not in legacy.get("capabilityIds", []):
    raise SystemExit("storage.removable.eject is not leftover-direct debt")
if "capability:storage.removable.eject" not in legacy.get("surfaceRefs", []):
    raise SystemExit("storage.removable.eject leftover surfaceRef is missing")
agent = by_debt["missing.agent.routes"]
if "storage.removable.eject" not in agent.get("capabilityIds", []):
    raise SystemExit("storage.removable.eject is not agent-unavailable debt")
if "capability:storage.removable.eject" not in agent.get("surfaceRefs", []):
    raise SystemExit("storage.removable.eject agent surfaceRef is missing")

if "Honesty addendum 2026-09-06 vs Files Devices Eject session plane" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must add a dated Files Devices Eject addendum")
addendum = gaps.split("Honesty addendum 2026-09-06 vs Files Devices Eject session plane", 1)[1].split("Honesty addendum", 1)[0]
if "CLOSED leftover: Files Devices Eject session UI" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name CLOSED leftover as Files Devices Eject session UI")
for required in (
    "metal proof",
    "mount if unfinished",
    "Files LIVE metal",
    "Win7 visual",
    "Explorer present",
    "Fabric LIVE under SHELL",
    "Settings Power LIVE",
    "End Task LIVE",
    "Software Center present",
    "Update present",
    "claim=present",
):
    if required not in addendum:
        raise SystemExit(f"fleet-doctrine-gaps Eject addendum dropped OPEN leftover: {required}")
if "Do not invent claim=present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse claim=present invent")
if "Cloud EXIT 0 is not metal leftover CLOSED" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Cloud EXIT 0 as metal leftover CLOSED")
if "Files > Devices > Eject" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name Files > Devices > Eject")
if "this session" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name the session plane")
if "device.busy" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name device.busy")
if "windows-native.15" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.15 pending")
if "Do not invent Fabric LIVE under SHELL" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Fabric LIVE under SHELL invent")

if "SESSION CONTROL" not in session and "SESSION CONTROL" not in files_app:
    raise SystemExit("session Eject must show SESSION CONTROL")
if "LIVE CONTROL" in session:
    raise SystemExit("session Eject invented LIVE CONTROL")
if "Files > Devices > Eject" not in parity:
    raise SystemExit("PARITY must name Files > Devices > Eject")
if "session Eject" not in parity and "storage-removable-eject" not in parity:
    raise SystemExit("PARITY must name session Eject without walking Explorer to present")
explorer_row = ""
for line in parity.splitlines():
    if line.startswith("| Explorer / Computer |"):
        explorer_row = line
        break
if "this row is not present" not in explorer_row or "prototype" not in explorer_row:
    raise SystemExit("PARITY Explorer row must stay not present")
if "storage-removable-eject" not in handoff:
    raise SystemExit("HANDOFF must name storage-removable-eject")
if "session Eject" not in handoff and "Files Devices Eject session" not in handoff:
    raise SystemExit("HANDOFF must name session Eject")
if "storage-removable-eject" not in project and "session Eject" not in project:
    raise SystemExit("project-ultimate must name session Eject")
if "storage.removable.eject" not in files_docs:
    raise SystemExit("files-defaults-provider must name storage.removable.eject")
docs_slice = files_docs.split("storage.removable.eject", 1)[1][:1200]
if "does not invent a Fabric" not in docs_slice:
    raise SystemExit("files-defaults-provider must refuse a Fabric eject writer")
if "USB" not in docs_slice or "optical" not in docs_slice.lower():
    raise SystemExit("files-defaults-provider must document USB vs optical scope")
if "device.busy" not in docs_slice:
    raise SystemExit("files-defaults-provider must name device.busy")
PY

pass "storage.removable.eject stays leftover partial with a visible Files Devices Eject route"
