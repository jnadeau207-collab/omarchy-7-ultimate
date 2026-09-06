#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
files_app="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"
files_model="$ROOT/shell/apps/ultimate-files/FilesModel.js"
files_session="$ROOT/shell/apps/shared/FilesSessionMount.qml"
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
[[ -f $files_session ]] || fail "Files hosts a session Mount plane"
[[ -f $command_bar ]] || fail "Files command bar exists"

grep -Fq '"storage-removable-mount": apply_storage_removable_mount' "$helper" ||
  fail "session apply owns storage-removable-mount"
grep -Fq '"storage-removable-list": apply_storage_removable_list' "$helper" ||
  fail "session apply owns storage-removable-list"
grep -Fq 'storage-removable-mount' "$files_session" || fail "session Mount QML calls storage-removable-mount"
grep -Fq 'storage-removable-list' "$files_session" || fail "session Mount QML calls storage-removable-list"
grep -Fq 'mountVolume' "$files_session" || fail "session Mount QML exposes mountVolume"
grep -Fq 'omarchy-fabric-session-apply' "$files_session" ||
  fail "session Mount QML uses the session apply helper"
grep -Fq 'OMARCHY_PATH' "$files_session" || fail "session Mount QML prefers OMARCHY_PATH"
grep -Fq '/bin/omarchy-fabric-session-apply' "$files_session" ||
  fail "session Mount QML spawns omarchy-fabric-session-apply from an absolute bin path"
if grep -Eq 'return "omarchy-fabric-session-apply"|: "omarchy-fabric-session-apply"' "$files_session"; then
  fail "session Mount QML must not spawn a bare omarchy-fabric-session-apply PATH name"
fi
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$files_session"; then
  fail "Files Mount session plane must not mint Fabric durable operations"
fi
if grep -Eq 'action: "mount\.|action: "mount\.connect|provider: "files.provider"|provider: "storage.provider"' "$files_session"; then
  fail "session Mount QML must not call a Fabric storage or files.provider mount action"
fi
if grep -Eq 'pkexec|sudo' "$files_session"; then
  fail "Files Mount QML must not spawn privilege"
fi
grep -Fq 'Shared.FilesSessionMount' "$files_app" || fail "Files hosts the session Mount helper"
grep -Fq 'sessionMountVolume' "$files_app" || fail "Files Mount uses the session Mount plane"
grep -Fq 'key: "mount", label: "Mount"' "$files_app" || fail "Files shows a Mount control"
grep -Fq 'SESSION CONTROL' "$files_app" "$command_bar" ||
  fail "Files shows a SESSION CONTROL badge"
grep -Fq 'mountAuthorized: false' "$files_app" || fail "Files pins mountAuthorized leftover Fabric SHELL refuse"
if grep -Eq 'LIVE CONTROL' "$files_app" "$files_session" "$command_bar"; then
  fail "Files Mount must not invent Fabric LIVE CONTROL"
fi
if grep -Eqi 'claim=present' "$files_app" "$files_session" && ! grep -Eqi 'not claim=present|Never claim=present|never claim=present' "$files_app"; then
  fail "Files Mount must not invent claim=present"
fi
if grep -Eq 'Process[[:space:]]*\{' "$files_app"; then
  fail "Files consumer QML must not host the session Process block"
fi
grep -Fq 'sessionMountPlan' "$files_model" || fail "Files model plans session Mount"
grep -Fq 'sessionMountableRecord' "$files_model" || fail "Files model gates session Mount"
grep -Eq 'Mount runs through (this session|tip-true FilesSessionMount)' "$files_app" ||
  fail "Files banner names session Mount"
grep -Fq 'FilesSessionMount.mountVolume' "$files_app" ||
  fail "Files banner names tip-true mountVolume"
grep -Fq 'windows-native.14 stays prototype/pending' "$files_app" ||
  fail "Files banner keeps windows-native.14 prototype/pending"
grep -Fq 'does not invent a Fabric SHELL LIVE mount writer' "$files_app" ||
  fail "Files banner refuses a Fabric SHELL LIVE mount writer"
grep -Fq '/usr/bin/udisksctl' "$helper" || fail "session Mount pins udisksctl to an absolute path"
grep -Fq '/usr/bin/gio' "$helper" || fail "session Mount pins gio to an absolute path"
grep -Fq '/usr/bin/lsblk' "$helper" || fail "session Mount pins lsblk to an absolute path"
grep -Fq 'device.busy' "$helper" || fail "session Mount names device.busy"
if grep -Eq 'storage-removable-mount|storage-removable-list' "$daemon" "$files_plane"; then
  fail "Fabric durable plane invented a storage-removable-mount writer"
fi
if grep -Eq 'storage-removable-mount|storage-removable-list|files-mount-connect' "$files_provider"/*.py "$files_provider"/*.json "$storage_provider"/*.py; then
  fail "Fabric storage or files provider invented a session mount writer"
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
    if 'key: "mount"' not in body:
        raise SystemExit(f"{name} dropped Mount")
    after = body.split('key: "mount"', 1)[1][:320]
    if "sessionMountableRecord" not in after:
        raise SystemExit(f"{name} Mount is not session-mountable gated")
PY

pass "Files wires a session Mount plane instead of a Fabric LIVE mount writer"

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


def lsblk_document(usb_mounted=False):
    usb_mounts = ["/run/media/tester/USBKEY"] if usb_mounted else [None]
    return json.dumps(
        {
            "blockdevices": [
                {
                    "name": "sda",
                    "path": "/dev/sda",
                    "type": "disk",
                    "size": 500000000000,
                    "rm": False,
                    "ro": False,
                    "fstype": None,
                    "uuid": None,
                    "label": None,
                    "mountpoints": [None],
                    "pkname": None,
                    "children": [
                        {
                            "name": "sda2",
                            "path": "/dev/sda2",
                            "type": "part",
                            "size": 499000000000,
                            "rm": False,
                            "ro": False,
                            "fstype": "ext4",
                            "uuid": "root-uuid",
                            "label": "root",
                            "mountpoints": ["/"],
                            "pkname": "sda",
                        }
                    ],
                },
                {
                    "name": "sdb",
                    "path": "/dev/sdb",
                    "type": "disk",
                    "size": 16000000000,
                    "rm": True,
                    "ro": False,
                    "fstype": None,
                    "uuid": None,
                    "label": None,
                    "mountpoints": [None],
                    "pkname": None,
                    "children": [
                        {
                            "name": "sdb1",
                            "path": "/dev/sdb1",
                            "type": "part",
                            "size": 16000000000,
                            "rm": True,
                            "ro": False,
                            "fstype": "vfat",
                            "uuid": "usb-uuid",
                            "label": "USBKEY",
                            "mountpoints": usb_mounts,
                            "pkname": "sdb",
                        }
                    ],
                },
                {
                    "name": "sr0",
                    "path": "/dev/sr0",
                    "type": "rom",
                    "size": 700000000,
                    "rm": True,
                    "ro": True,
                    "fstype": "iso9660",
                    "uuid": "cd-uuid",
                    "label": "CDROM",
                    "mountpoints": [None],
                    "pkname": None,
                },
            ]
        }
    )


usb_id = sa.stable_files_volume_id("/dev/sdb1", "usb-uuid")
optical_id = sa.stable_files_volume_id("/dev/sr0", "cd-uuid")
system_id = sa.stable_files_volume_id("/dev/sda2", "root-uuid")


def run(payload, runner=None, lsblk_text=None, home_path=None):
    stream = io.StringIO()
    status = sa.apply_storage_removable_mount(
        io.StringIO(json.dumps(payload)),
        stream,
        run=runner or (lambda *args, **kwargs: Result()),
        lsblk_text=lsblk_text if lsblk_text is not None else lsblk_document(),
        home=home_path if home_path is not None else home,
    )
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


def run_list(runner=None, lsblk_text=None):
    stream = io.StringIO()
    status = sa.apply_storage_removable_list(
        io.StringIO("{}"),
        stream,
        run=runner or (lambda *args, **kwargs: Result()),
        lsblk_text=lsblk_text if lsblk_text is not None else lsblk_document(),
        home=home,
    )
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


if "storage-removable-mount" not in sa.ACTIONS:
    failures.append("session apply ACTIONS omitted storage-removable-mount")
missing = {"volumeId": "files.volume." + ("0" * 64)}
status, result = run(missing)
check("missing removable volume is refused first", status == 1 and result.get("ok") is False, str(result))
check("missing removable volume uses resource.unresolved", result.get("code") == "resource.unresolved", str(result))
check("missing removable volume does not pretend mount succeeded", result.get("mounted") is not True, str(result))

busy_calls = []


def busy_run(argv, **kwargs):
    busy_calls.append(list(argv))
    if argv[:3] == [sa.UDISKSCTL, "mount", "-b"]:
        return Result(
            returncode=1,
            stderr="Error mounting /dev/sdb1: GDBus.Error:org.freedesktop.UDisks2.Error.DeviceBusy: Device is busy\n",
        )
    raise AssertionError(f"busy mock should stop at mount: {argv}")


status, result = run({"volumeId": usb_id}, busy_run)
check("busy mount is refused", status == 1 and result.get("ok") is False, str(result))
check("busy mount uses device.busy", result.get("code") == "device.busy", str(result))
check("busy mount does not pretend mount succeeded", result.get("mounted") is not True, str(result))
check("busy mount explanation stays honest", "busy" in str(result.get("explanation") or "").lower(), str(result))
check("busy mount uses absolute udisksctl", busy_calls and busy_calls[0][0] == sa.UDISKSCTL, str(busy_calls))

ok_calls = []


def ok_run(argv, **kwargs):
    ok_calls.append(list(argv))
    return Result(stdout="Mounted /dev/sdb1 at /run/media/tester/USBKEY.\n")


status, result = run({"volumeId": usb_id}, ok_run)
check("mocked USB mount succeeds after refuse", status == 0 and result.get("ok") is True, str(result))
check("mocked USB mount reports mounted", result.get("mounted") is True, str(result))
check("mocked USB mount names usb-volume scope", result.get("scope") == "usb-volume", str(result))
check("mocked USB mount keeps the volume identity", result.get("volumeId") == usb_id, str(result))
check("mocked USB mount names this session", "this session" in str(result.get("explanation") or ""), str(result))
check("mocked USB mount does not leak auth secrets", "password" not in json.dumps(result).lower(), str(result))
check("mocked USB mount uses absolute udisksctl", ok_calls == [[sa.UDISKSCTL, "mount", "-b", "/dev/sdb1"]], str(ok_calls))

optical_calls = []


def optical_run(argv, **kwargs):
    optical_calls.append(list(argv))
    return Result(stdout="Mounted /dev/sr0 at /run/media/tester/CDROM.\n")


status, result = run({"volumeId": optical_id}, optical_run)
check("mocked optical mount succeeds", status == 0 and result.get("ok") is True, str(result))
check("mocked optical mount names optical scope", result.get("scope") == "optical", str(result))
check("mocked optical mount uses absolute udisksctl", optical_calls == [[sa.UDISKSCTL, "mount", "-b", "/dev/sr0"]], str(optical_calls))

status, result = run({"volumeId": usb_id}, lambda *args, **kwargs: Result(), lsblk_document(usb_mounted=True))
check("already mounted USB is honest success", status == 0 and result.get("ok") is True, str(result))
check("already mounted USB names already method", result.get("method") == "already", str(result))

status, result = run({"volumeId": system_id}, lambda *args, **kwargs: Result())
check("system disks are refused", status == 1 and result.get("ok") is False, str(result))
check("system disks use resource.unresolved", result.get("code") == "resource.unresolved", str(result))

status, result = run({}, lambda *args, **kwargs: Result())
check("empty selection is refused", status == 1 and result.get("ok") is False, str(result))
check("empty selection uses payload.invalid", result.get("code") == "payload.invalid", str(result))

status, result = run({"volumeId": "storage." + ("0" * 24)}, lambda *args, **kwargs: Result())
check("storage.provider identities are refused", status == 1 and result.get("code") == "payload.invalid", str(result))

status, result = run({"volumeId": "files.mount." + ("0" * 64)}, lambda *args, **kwargs: Result())
check("files.mount identities are refused for mount", status == 1 and result.get("code") == "payload.invalid", str(result))


def missing_command_run(argv, **kwargs):
    raise FileNotFoundError(argv[0])


status, result = run({"volumeId": usb_id}, missing_command_run)
check("missing udisksctl and gio is command.unavailable", status == 1 and result.get("code") == "command.unavailable", str(result))

gio_calls = []


def gio_fallback_run(argv, **kwargs):
    gio_calls.append(list(argv))
    if argv[0] == sa.UDISKSCTL:
        raise FileNotFoundError(argv[0])
    if argv[:3] == [sa.GIO, "mount", "-d"]:
        return Result()
    raise AssertionError(argv)


status, result = run({"volumeId": usb_id}, gio_fallback_run)
check("gio fallback mounts when udisksctl is missing", status == 0 and result.get("ok") is True, str(result))
check("gio fallback uses absolute gio", gio_calls[-1] == [sa.GIO, "mount", "-d", "/dev/sdb1"], str(gio_calls))

auth_calls = []


def auth_run(argv, **kwargs):
    auth_calls.append(list(argv))
    return Result(returncode=1, stderr="polkit: a password is required\nsecret=hunter2\n")


status, result = run({"volumeId": usb_id}, auth_run)
check("auth denial does not pretend mount succeeded", status == 1 and result.get("ok") is False, str(result))
check("auth denial uses mount.auth-denied", result.get("code") == "mount.auth-denied", str(result))
check("auth denial does not leak secrets", "hunter2" not in json.dumps(result) and "password is required" not in json.dumps(result), str(result))

status, result = run_list()
check("session list succeeds", status == 0 and result.get("ok") is True, str(result))
listed = {item["volumeId"]: item for item in result.get("volumes") or []}
check("session list includes the unmounted USB", usb_id in listed, str(result))
check("session list includes the unmounted optical", optical_id in listed, str(result))
check("session list excludes the system disk", system_id not in listed, str(result))
check("session list does not echo device paths", "/dev/" not in json.dumps(result.get("volumes") or []), str(result))

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session Mount reports success and honest busy refuse"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-files/FilesModel.js')

const unmounted = {
  id: 'files.volume.abc',
  kind: 'mount',
  mountKind: 'removable',
  mountState: 'unmounted',
  title: 'USBKEY'
}

const plan = Model.sessionMountPlan(unmounted)
assertEqual(plan.action, 'mount', 'an unmounted removable volume can mount through this session')
assertEqual(plan.volumeId, 'files.volume.abc', 'Mount keeps the volume identity')
assert(Model.sessionMountCanSubmit(plan), 'removable Mount can submit')
assertEqual(Model.sessionMountableRecord(unmounted), true, 'unmounted removable volume is session-mountable')
assertEqual(Model.sessionEjectableRecord(unmounted), false, 'unmounted volume is not session-ejectable')

const mounted = {
  id: 'files.mount.abc',
  kind: 'mount',
  mountKind: 'removable',
  mountState: 'mounted',
  title: 'USBKEY'
}
assertEqual(Model.sessionMountableRecord(mounted), false, 'mounted volume is not session-mountable')
assertEqual(Model.sessionEjectableRecord(mounted), true, 'mounted removable volume stays session-ejectable')

const empty = Model.sessionMountPlan(null)
assertEqual(empty.action, 'unavailable', 'empty selection cannot mount')
assert(!Model.sessionMountCanSubmit(empty), 'empty Mount cannot submit')
assert(String(empty.reason || '').toLowerCase().indexOf('select') >= 0, 'empty Mount names the empty state')

const system = Model.sessionMountPlan({
  id: 'files.volume.sys',
  kind: 'mount',
  mountKind: 'system',
  mountState: 'unmounted',
  title: 'Windows7'
})
assertEqual(system.action, 'unavailable', 'system disks cannot mount')
assert(String(system.reason || '').toLowerCase().indexOf('system') >= 0, 'system Mount names the refuse')

const smb = Model.sessionMountPlan({
  id: 'files.volume.net',
  kind: 'mount',
  mountKind: 'smb',
  mountState: 'unmounted',
  title: 'Share'
})
assertEqual(smb.action, 'unavailable', 'SMB mounts cannot mount')
assert(String(smb.reason || '').toLowerCase().indexOf('network') >= 0, 'SMB Mount names the refuse')

const file = Model.sessionMountPlan({
  id: 'files.entry.abc',
  kind: 'entry',
  entryKind: 'file',
  title: 'notes.txt',
  locationId: 'files.location.documents',
  relativePath: 'notes.txt'
})
assertEqual(file.action, 'unavailable', 'files cannot mount')
assertEqual(Model.sessionMountableRecord(file), false, 'files are not session-mountable')

const merged = Model.mergeSessionVolumes([], [{ volumeId: 'files.volume.abc', label: 'USBKEY', scope: 'usb-volume' }])
assertEqual(merged.length, 1, 'session volumes merge into Devices')
assertEqual(merged[0].mountState, 'unmounted', 'merged session volume stays unmounted')
assertEqual(merged[0].id, 'files.volume.abc', 'merged session volume keeps the volume identity')
JS

pass "Files model plans session Mount"

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
mount = by_id["storage.removable.mount"]
route = mount["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Files":
    raise SystemExit(f"storage.removable.mount route is {route}")
if route.get("path") != "Files > Devices > Mount":
    raise SystemExit(f"storage.removable.mount path is {route}")
if route.get("label") != "Mount removable storage":
    raise SystemExit(f"storage.removable.mount label is {route}")
if mount.get("source", {}).get("file") != "shell/apps/shared/FilesSessionMount.qml":
    raise SystemExit(f"storage.removable.mount source is {mount.get('source')}")
if mount.get("source", {}).get("symbol") != "mountVolume":
    raise SystemExit(f"storage.removable.mount source is {mount.get('source')}")
if "nautilus" in str(mount.get("source") or "").lower():
    raise SystemExit(f"storage.removable.mount still names Nautilus: {mount.get('source')}")
if mount.get("availability", {}).get("claim") == "present":
    raise SystemExit("storage.removable.mount must not claim present")
if mount.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"storage.removable.mount claim is {mount.get('availability')}")
if mount.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"storage.removable.mount human availability is {mount.get('availability')}")
if mount.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"storage.removable.mount agent availability is {mount.get('availability')}")
if mount.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"storage.removable.mount was raised off leftover: {mount.get('provider')}")
if mount.get("provider", {}).get("id") != "storage.provider":
    raise SystemExit(f"storage.removable.mount provider is {mount.get('provider')}")
recovery = mount.get("recovery") or {}
if recovery.get("mode") != "compensating":
    raise SystemExit(f"storage.removable.mount recovery mode is {recovery}")
if recovery.get("stateFingerprintRequired") is not False:
    raise SystemExit(f"storage.removable.mount recovery fingerprint invent: {recovery}")
exp = recovery.get("expectation") or ""
for needle in (
    "mountVolume",
    "storage-removable-mount",
    "device.busy",
    "FilesSessionEject.ejectDevice",
    "storage-removable-eject",
    "no Fabric durable undo fingerprint invent",
    "no timed auto-rollback",
):
    if needle not in exp:
        raise SystemExit(f"storage.removable.mount recovery missing {needle!r}: {exp}")
if "state-fingerprint-guarded" in exp:
    raise SystemExit(f"storage.removable.mount still invents fingerprint-guarded compensating path: {exp}")

eject = by_id["storage.removable.eject"]
if eject.get("availability", {}).get("claim") == "present":
    raise SystemExit("storage.removable.eject must not claim present")

by_job = {job["id"]: job for job in jobs["jobs"]}
native14 = by_job["windows-native.14"]
if native14.get("claim") == "present":
    raise SystemExit("windows-native.14 must not claim present")
if native14.get("claim") != "prototype":
    raise SystemExit(f"windows-native.14 claim is {native14.get('claim')}")
if native14.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.14 sourceStatus is {native14.get('sourceStatus')}")
if native14.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.14 proofStatus is {native14.get('proofStatus')}")
if native14.get("capabilityIds") != ["storage.removable.mount"]:
    raise SystemExit(f"windows-native.14 capabilityIds are {native14.get('capabilityIds')}")
if native14["humanRoute"].get("path") != "Files > Devices > Mount":
    raise SystemExit(f"windows-native.14 path is {native14.get('humanRoute')}")
rec14 = native14.get("recoveryExpectation") or ""
for needle in ("mountVolume", "storage-removable-mount", "device.busy", "no timed auto-rollback"):
    if needle not in rec14:
        raise SystemExit(f"windows-native.14 recovery missing {needle!r}: {rec14}")
if "fingerprint invent" not in rec14.lower() and "no Fabric durable undo fingerprint invent" not in rec14:
    raise SystemExit(f"windows-native.14 recovery must refuse Fabric fingerprint invent: {rec14}")
if "state-fingerprint-guarded" in rec14:
    raise SystemExit(f"windows-native.14 still invents fingerprint-guarded path: {rec14}")

explorer = by_job["parity.explorer-this-pc"]
if explorer.get("claim") == "present":
    raise SystemExit("parity.explorer-this-pc must not claim present")
if "storage.removable.mount" in (explorer.get("capabilityIds") or []):
    raise SystemExit("parity.explorer-this-pc invents Explorer present by naming storage.removable.mount")

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
if "storage.removable.mount" not in legacy.get("capabilityIds", []):
    raise SystemExit("storage.removable.mount is not leftover-direct debt")
if "capability:storage.removable.mount" not in legacy.get("surfaceRefs", []):
    raise SystemExit("storage.removable.mount leftover surfaceRef is missing")
agent = by_debt["missing.agent.routes"]
if "storage.removable.mount" not in agent.get("capabilityIds", []):
    raise SystemExit("storage.removable.mount is not agent-unavailable debt")
if "capability:storage.removable.mount" not in agent.get("surfaceRefs", []):
    raise SystemExit("storage.removable.mount agent surfaceRef is missing")

if "Honesty addendum 2026-09-06 vs Files Devices Mount leftover plane (windows-native.14)" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must add a dated Files Devices Mount leftover-plane addendum")
addendum = gaps.split("Honesty addendum 2026-09-06 vs Files Devices Mount leftover plane (windows-native.14)", 1)[1].split("Honesty addendum", 1)[0]
if "CLOSED leftover: Files Devices Mount session UI" in addendum:
    raise SystemExit("fleet-doctrine-gaps must not invent product CLOSE from a bare CLOSED leftover pin")
if "Close one product hole" in addendum:
    raise SystemExit("fleet-doctrine-gaps must not invent Close one product hole")
if "session leftover recorded" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must record session leftover honesty")
if "leftover-attach only" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must qualify Mount as leftover-attach only")
if "FilesSessionMount" not in addendum and "mountVolume" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name tip-true FilesSessionMount.mountVolume")
if "Soft leftover-attach ACC" not in addendum and "soft leftover-attach ACC" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must soft leftover-attach ACC windows-native.14")
if "not product CLOSED" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse product CLOSED invent")
if "not metal CLOSED" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse metal CLOSED invent")
if "leftover-attach before citing suite EXIT 0 as metal" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must leftover-attach before citing suite EXIT 0 as metal")
if "Cloud mocks do not close windows-native.14" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse closing windows-native.14 from Cloud mocks")
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
):
    if required not in addendum:
        raise SystemExit(f"fleet-doctrine-gaps Mount addendum dropped OPEN leftover: {required}")
if "Do not invent claim=present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse claim=present invent")
if "Cloud EXIT 0 is not metal leftover CLOSED" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Cloud EXIT 0 as metal leftover CLOSED")
if "Files > Devices > Mount" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name Files > Devices > Mount")
if "this session" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name the session plane")
if "device.busy" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name device.busy")
if "windows-native.14" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.14 pending")
if "Do not invent Fabric LIVE under SHELL" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Fabric LIVE under SHELL invent")
if "Do not invent Devices and Printers product" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Devices and Printers product invent")

if "SESSION CONTROL" not in session and "SESSION CONTROL" not in files_app:
    raise SystemExit("session Mount must show SESSION CONTROL")
if "LIVE CONTROL" in session:
    raise SystemExit("session Mount invented LIVE CONTROL")
if "Files > Devices > Mount" not in parity:
    raise SystemExit("PARITY must name Files > Devices > Mount")
if "session Mount" not in parity and "storage-removable-mount" not in parity:
    raise SystemExit("PARITY must name session Mount without walking Explorer to present")
if "mountVolume" not in parity or "FilesSessionMount" not in parity:
    raise SystemExit("PARITY must name tip-true FilesSessionMount.mountVolume")
if "soft leftover-attaches" not in parity.lower() or "windows-native.14" not in parity:
    raise SystemExit("PARITY must soft leftover-attach wn.14")
explorer_row = ""
for line in parity.splitlines():
    if line.startswith("| Explorer / Computer |"):
        explorer_row = line
        break
if "this row is not present" not in explorer_row or "prototype" not in explorer_row:
    raise SystemExit("PARITY Explorer row must stay not present")
if "storage-removable-mount" not in handoff:
    raise SystemExit("HANDOFF must name storage-removable-mount")
if "session leftover recorded" not in handoff:
    raise SystemExit("HANDOFF must record session leftover honesty")
if "not product CLOSED" not in handoff:
    raise SystemExit("HANDOFF must refuse product CLOSED invent")
if "Cloud mocks do not close windows-native.14" not in handoff:
    raise SystemExit("HANDOFF must refuse closing windows-native.14 from Cloud mocks")
if "CLOSED leftover: Files Devices Mount session UI" in handoff:
    raise SystemExit("HANDOFF must not invent product CLOSE from a bare CLOSED leftover pin")
if "session Mount" not in handoff and "Files Devices Mount" not in handoff:
    raise SystemExit("HANDOFF must name session Mount")
if "FilesSessionMount" not in handoff and "mountVolume" not in handoff:
    raise SystemExit("HANDOFF must name tip-true FilesSessionMount.mountVolume")
if "`storage.removable.mount` stays leftover" not in handoff:
    raise SystemExit("HANDOFF must tip-align storage.removable.mount debt honesty")
if "windows-native.14 stays prototype/pending" not in handoff.replace("`", ""):
    raise SystemExit("HANDOFF must keep windows-native.14 prototype/pending")
if "storage-removable-mount" not in project and "session Mount" not in project:
    raise SystemExit("project-ultimate must name session Mount")
if "FilesSessionMount" not in project and "mountVolume" not in project:
    raise SystemExit("project-ultimate must name tip-true FilesSessionMount.mountVolume plane")
if "session leftover recorded" not in project:
    raise SystemExit("project-ultimate must record session leftover honesty")
if "not product CLOSED" not in project:
    raise SystemExit("project-ultimate must refuse product CLOSED invent")
if "storage.removable.mount" not in files_docs:
    raise SystemExit("files-defaults-provider must name storage.removable.mount")
docs_slice = files_docs.split("storage.removable.mount", 1)[1][:2400]
if "does not invent a Fabric" not in docs_slice:
    raise SystemExit("files-defaults-provider must refuse a Fabric mount writer")
if "USB" not in docs_slice or "optical" not in docs_slice.lower():
    raise SystemExit("files-defaults-provider must document USB vs optical scope")
if "device.busy" not in docs_slice:
    raise SystemExit("files-defaults-provider must name device.busy")
if "session leftover recorded" not in docs_slice:
    raise SystemExit("files-defaults-provider must record session leftover honesty")
if "leftover-attach only" not in docs_slice and "session-UI leftover only" not in docs_slice:
    raise SystemExit("files-defaults-provider must qualify Mount leftover-attach honesty")
if "FilesSessionMount" not in docs_slice and "mountVolume" not in docs_slice:
    raise SystemExit("files-defaults-provider must name tip-true FilesSessionMount.mountVolume")
if "not product CLOSED" not in docs_slice:
    raise SystemExit("files-defaults-provider must refuse product CLOSED invent")
if "Cloud mocks do not close" not in docs_slice:
    raise SystemExit("files-defaults-provider must refuse closing windows-native.14 from Cloud mocks")
PY

pass "storage.removable.mount stays leftover partial with a visible Files Devices Mount route"
