#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
files_app="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"
files_model="$ROOT/shell/apps/ultimate-files/FilesModel.js"
files_session="$ROOT/shell/apps/shared/FilesSessionArchive.qml"
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
files_plane="$ROOT/test/fabric/operations/test_files_plane.py"

[[ -f $helper ]] || fail "session apply helper exists"
[[ -f $files_app ]] || fail "Files application exists"
[[ -f $files_model ]] || fail "Files model exists"
[[ -f $files_session ]] || fail "Files hosts a session archive plane"
[[ -f $command_bar ]] || fail "Files command bar exists"

grep -Fq '"files-archive-create": apply_files_archive_create' "$helper" ||
  fail "session apply owns files-archive-create"
grep -Fq 'files-archive-create' "$files_session" || fail "session archive QML calls files-archive-create"
grep -Fq 'omarchy-fabric-session-apply' "$files_session" ||
  fail "session archive QML uses the session apply helper"
grep -Fq 'OMARCHY_PATH' "$files_session" || fail "session archive QML prefers OMARCHY_PATH"
grep -Fq '/bin/omarchy-fabric-session-apply' "$files_session" ||
  fail "session archive QML spawns omarchy-fabric-session-apply from an absolute bin path"
if grep -Eq 'return "omarchy-fabric-session-apply"|: "omarchy-fabric-session-apply"' "$files_session"; then
  fail "session archive QML must not spawn a bare omarchy-fabric-session-apply PATH name"
fi
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$files_session"; then
  fail "Files Compress session plane must not mint Fabric durable operations"
fi
if grep -Eq 'action: "archive\.|action: "entry\.archive|provider: "files.provider"' "$files_session"; then
  fail "session archive QML must not call a Fabric files.provider archive action"
fi
if grep -Eq 'pkexec|sudo' "$files_session"; then
  fail "Files Compress QML must not spawn privilege"
fi
grep -Fq 'Shared.FilesSessionArchive' "$files_app" || fail "Files hosts the session archive helper"
grep -Fq 'sessionCompressEntry' "$files_app" || fail "Files Compress uses the session archive plane"
grep -Fq 'key: "compress", label: "Compress"' "$files_app" || fail "Files shows a Compress control"
grep -Fq 'SESSION CONTROL' "$files_app" "$command_bar" ||
  fail "Files shows a SESSION CONTROL badge"
if grep -Eq 'LIVE CONTROL' "$files_app" "$files_session" "$command_bar"; then
  fail "Files Compress must not invent Fabric LIVE CONTROL"
fi
if grep -Eqi 'claim=present' "$files_app" "$files_session"; then
  fail "Files Compress must not invent claim=present"
fi
if grep -Eq 'Process[[:space:]]*\{' "$files_app"; then
  fail "Files consumer QML must not host the session Process block"
fi
grep -Fq 'sessionArchivePlan' "$files_model" || fail "Files model plans session archive"
grep -Fq 'sessionCompressableRecord' "$files_model" || fail "Files model gates session Compress"
grep -Fq 'Compress runs through this session' "$files_app" ||
  fail "Files banner names session Compress"
grep -Fq 'does not invent a Fabric SHELL LIVE archive writer' "$files_app" ||
  fail "Files banner refuses a Fabric SHELL LIVE archive writer"
if grep -Eq 'files-archive-create' "$daemon" "$files_plane"; then
  fail "Fabric durable plane invented a files-archive-create writer"
fi
if grep -Eq 'archive.create|entry.archive|files.archive' "$files_provider"/*.py "$files_provider"/*.json; then
  fail "files.provider invented a Fabric archive writer"
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
    if 'key: "compress"' not in body:
        raise SystemExit(f"{name} dropped Compress")
    if "sessionCompressableRecord" not in body.split('key: "compress"', 1)[1][:280]:
        raise SystemExit(f"{name} Compress is not session-compressable gated")
PY

pass "Files wires a session Compress plane instead of a Fabric LIVE archive writer"

cd "$ROOT/default/fabric"
PYTHONPATH="$ROOT/default/fabric" PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import io
import json
import os
import pathlib
import stat
import tempfile
import zipfile

os.environ.pop("XDG_DATA_HOME", None)
home = pathlib.Path(tempfile.mkdtemp()) / "home"
(home / "Documents").mkdir(parents=True)
(home / "Desktop").mkdir(parents=True)
os.environ["HOME"] = str(home)
os.environ["USERPROFILE"] = str(home)

from omarchy_fabric.helpers import session_apply as sa

failures = []


def check(label, condition, detail=""):
    if not condition:
        failures.append(f"{label}{': ' + detail if detail else ''}")


def run(action, payload):
    stream = io.StringIO()
    status = sa.main([action], io.StringIO(json.dumps(payload)), stream)
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


def entry_payload(location_id, relative, path):
    info = path.lstat()
    return {
        "locationId": location_id,
        "entryRelativePath": relative,
        "entryId": sa.stable_entry_id(location_id, info.st_dev, info.st_ino, relative),
    }


source = home / "Documents" / "report.txt"
source.write_text("hello zip", encoding="utf-8")
payload = entry_payload("files.location.documents", "report.txt", source)
status, result = run("files-archive-create", payload)
archive = home / "Documents" / "report.zip"
check("session archive without a resourceId succeeds", status == 0 and result.get("ok") is True, str(result))
check("session archive writes a zip beside the file", archive.is_file(), str(result))
check("session archive keeps the source", source.is_file() and source.read_text(encoding="utf-8") == "hello zip")
check("session archive reports the zip name", result.get("archiveName") == "report.zip", str(result))
check("session archive reports created", result.get("created") is True, str(result))
if archive.is_file():
    with zipfile.ZipFile(archive) as zf:
        names = zf.namelist()
        check("zip contains the selected file", "report.txt" in names, str(names))
        check("zip bytes match", zf.read("report.txt") == b"hello zip")

status, result = run("files-archive-create", payload)
second = home / "Documents" / "report (2).zip"
check("session archive picks a non-colliding name", status == 0 and result.get("ok") is True, str(result))
check("session archive collision uses report (2).zip", second.is_file() and result.get("archiveName") == "report (2).zip", str(result))
check("the first zip is untouched", archive.is_file())

folder = home / "Documents" / "Photos"
folder.mkdir()
(folder / "one.txt").write_text("one", encoding="utf-8")
nested = folder / "album"
nested.mkdir()
(nested / "two.txt").write_text("two", encoding="utf-8")
folder_payload = entry_payload("files.location.documents", "Photos", folder)
status, result = run("files-archive-create", folder_payload)
folder_zip = home / "Documents" / "Photos.zip"
check("session archive zips a folder", status == 0 and result.get("ok") is True, str(result))
check("folder zip lands beside the folder", folder_zip.is_file(), str(result))
if folder_zip.is_file():
    with zipfile.ZipFile(folder_zip) as zf:
        names = set(zf.namelist())
        check("folder zip keeps the folder root", "Photos/one.txt" in names, str(sorted(names)))
        check("folder zip keeps nested files", "Photos/album/two.txt" in names, str(sorted(names)))
        check("folder zip bytes match", zf.read("Photos/one.txt") == b"one")

other = home / "Documents" / "notes.txt"
other.write_text("notes", encoding="utf-8")
multi = {
    "locationId": "files.location.documents",
    "entries": [
        {
            "entryRelativePath": "report.txt",
            "entryId": entry_payload("files.location.documents", "report.txt", source)["entryId"],
        },
        {
            "entryRelativePath": "notes.txt",
            "entryId": entry_payload("files.location.documents", "notes.txt", other)["entryId"],
        },
    ],
}
status, result = run("files-archive-create", multi)
multi_zip = home / "Documents" / "Archive.zip"
check("session archive zips multiple regular files", status == 0 and result.get("ok") is True, str(result))
check("multi zip uses Archive.zip", multi_zip.is_file() and result.get("archiveName") == "Archive.zip", str(result))
if multi_zip.is_file():
    with zipfile.ZipFile(multi_zip) as zf:
        names = set(zf.namelist())
        check("multi zip contains both files", "report.txt" in names and "notes.txt" in names, str(sorted(names)))

escaped = {
    "locationId": "files.location.documents",
    "entryRelativePath": "../Desktop/escape.txt",
    "entryId": "files.entry." + "0" * 64,
}
status, result = run("files-archive-create", escaped)
check("path traversal is refused", status == 1 and result.get("ok") is False, str(result))
check("path traversal uses payload.invalid", result.get("code") == "payload.invalid", str(result))

link = home / "Documents" / "link.txt"
link.symlink_to("report.txt")
status, result = run("files-archive-create", entry_payload("files.location.documents", "link.txt", link))
check("symlink source is refused", status == 1 and result.get("ok") is False, str(result))
check("symlink source uses payload.invalid", result.get("code") == "payload.invalid", str(result))

sneaky = home / "Documents" / "sneaky"
sneaky.mkdir()
(sneaky / "ok.txt").write_text("ok", encoding="utf-8")
(sneaky / "out").symlink_to(home / "Desktop")
status, result = run("files-archive-create", entry_payload("files.location.documents", "sneaky", sneaky))
check("symlink children are refused", status == 1 and result.get("ok") is False, str(result))
check("symlink children use payload.invalid", result.get("code") == "payload.invalid", str(result))
check("failed folder zip is not left behind", not (home / "Documents" / "sneaky.zip").exists())

trash_payload = entry_payload("files.location.documents", "report.txt", source)
trash_payload["locationId"] = "files.location.trash"
status, result = run("files-archive-create", trash_payload)
check("session archive refuses Trash", status == 1 and result.get("ok") is False, str(result))
check("session archive Trash uses payload.invalid", result.get("code") == "payload.invalid", str(result))

outside = home / "outside.txt"
outside.write_text("nope", encoding="utf-8")
status, result = run(
    "files-archive-create",
    {
        "locationId": "files.location.documents",
        "entryRelativePath": "missing.txt",
        "entryId": "files.entry." + "0" * 64,
    },
)
check("missing entry is refused", status == 1 and result.get("ok") is False, str(result))
check("missing entry uses resource.unresolved", result.get("code") == "resource.unresolved", str(result))

status, result = run("files-archive-create", {"locationId": "files.location.documents"})
check("empty selection is refused", status == 1 and result.get("ok") is False, str(result))
check("empty selection uses payload.invalid", result.get("code") == "payload.invalid", str(result))

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session archive reports success and honest refusal"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-files/FilesModel.js')

const document = {
  id: 'files.entry.abc',
  kind: 'entry',
  entryKind: 'file',
  status: 'file',
  locationId: 'files.location.documents',
  relativePath: 'report.txt',
  title: 'report.txt'
}

const archive = Model.sessionArchivePlan(document)
assertEqual(archive.action, 'archive', 'a Documents file can be compressed')
assertEqual(archive.entryId, 'files.entry.abc', 'archive keeps the entry identity')
assertEqual(archive.locationId, 'files.location.documents', 'archive keeps the location')
assert(Model.sessionArchiveCanSubmit(archive), 'Documents compress can submit')

const folder = Model.sessionArchivePlan({ ...document, entryKind: 'directory', title: 'Photos', relativePath: 'Photos' })
assertEqual(folder.action, 'archive', 'a Documents folder can be compressed')
assert(Model.sessionArchiveCanSubmit(folder), 'Documents folder compress can submit')

const many = Model.sessionArchivePlan([
  document,
  { ...document, id: 'files.entry.def', relativePath: 'notes.txt', title: 'notes.txt' }
])
assertEqual(many.action, 'archive', 'multiple Documents files can be compressed')
assertEqual(many.entries.length, 2, 'multi archive keeps both identities')
assert(Model.sessionArchiveCanSubmit(many), 'multi compress can submit')

const symlink = Model.sessionArchivePlan({ ...document, status: 'symlink' })
assertEqual(symlink.action, 'unavailable', 'a symlink cannot be compressed')
assert(!Model.sessionArchiveCanSubmit(symlink), 'symlink compress cannot submit')

const trash = Model.sessionArchivePlan({ ...document, locationId: 'files.location.trash' })
assertEqual(trash.action, 'unavailable', 'Trash cannot be compressed')
assert(String(trash.reason || '').toLowerCase().indexOf('trash') >= 0, 'Trash compress names the refuse')

const music = Model.sessionArchivePlan({ ...document, locationId: 'files.location.music' })
assertEqual(music.action, 'unavailable', 'music is outside the session archive locations')

assertEqual(Model.sessionCompressableRecord(document), true, 'Documents file is session-compressable')
assertEqual(Model.sessionCompressableRecord({ ...document, entryKind: 'directory' }), true, 'directories are session-compressable')
assertEqual(Model.sessionCompressableRecord({ ...document, status: 'symlink' }), false, 'symlinks are not session-compressable')
JS

pass "Files model plans session archive"

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
archive = by_id["files.archive.create"]
route = archive["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Files":
    raise SystemExit(f"files.archive.create route is {route}")
if route.get("path") != "Files > Compress":
    raise SystemExit(f"files.archive.create path is {route}")
if route.get("label") != "Create a zip archive":
    raise SystemExit(f"files.archive.create label is {route}")
if archive.get("source", {}).get("file") != "shell/apps/shared/FilesSessionArchive.qml":
    raise SystemExit(f"files.archive.create source is {archive.get('source')}")
if archive.get("source", {}).get("symbol") != "createArchive":
    raise SystemExit(f"files.archive.create source is {archive.get('source')}")
if "nautilus" in str(archive.get("source") or "").lower():
    raise SystemExit(f"files.archive.create still names Nautilus: {archive.get('source')}")
if archive.get("availability", {}).get("claim") == "present":
    raise SystemExit("files.archive.create must not claim present")
if archive.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"files.archive.create claim is {archive.get('availability')}")
if archive.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"files.archive.create human availability is {archive.get('availability')}")
if archive.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"files.archive.create agent availability is {archive.get('availability')}")
if archive.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"files.archive.create was raised off leftover: {archive.get('provider')}")
if archive.get("provider", {}).get("id") != "files.provider":
    raise SystemExit(f"files.archive.create provider is {archive.get('provider')}")

by_job = {job["id"]: job for job in jobs["jobs"]}
native13 = by_job["windows-native.13"]
if native13.get("claim") == "present":
    raise SystemExit("windows-native.13 must not claim present")
if native13.get("claim") != "prototype":
    raise SystemExit(f"windows-native.13 claim is {native13.get('claim')}")
if native13.get("sourceStatus") != "pending":
    raise SystemExit(f"windows-native.13 sourceStatus is {native13.get('sourceStatus')}")
if native13.get("proofStatus") != "pending":
    raise SystemExit(f"windows-native.13 proofStatus is {native13.get('proofStatus')}")
if native13.get("capabilityIds") != ["files.archive.create"]:
    raise SystemExit(f"windows-native.13 capabilityIds are {native13.get('capabilityIds')}")
if native13["humanRoute"].get("path") != "Files > Compress":
    raise SystemExit(f"windows-native.13 path is {native13.get('humanRoute')}")
if native13["humanRoute"].get("status") != "visible":
    raise SystemExit(f"windows-native.13 route is {native13.get('humanRoute')}")

explorer = by_job["parity.explorer-this-pc"]
if explorer.get("claim") == "present":
    raise SystemExit("parity.explorer-this-pc must not claim present")
if "files.archive.create" in (explorer.get("capabilityIds") or []):
    raise SystemExit("parity.explorer-this-pc invents Explorer present by naming files.archive.create")

by_debt = {entry["id"]: entry for entry in debt["entries"]}
legacy = by_debt["legacy.domain.direct-providers"]
if "files.archive.create" not in legacy.get("capabilityIds", []):
    raise SystemExit("files.archive.create is not leftover-direct debt")
if "capability:files.archive.create" not in legacy.get("surfaceRefs", []):
    raise SystemExit("files.archive.create leftover surfaceRef is missing")

if "Honesty addendum 2026-09-06 vs Files Compress session plane" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must add a dated Files Compress addendum")
addendum = gaps.split("Honesty addendum 2026-09-06 vs Files Compress session plane", 1)[1].split("Honesty addendum", 1)[0]
if "CLOSED leftover: Files Compress session UI" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name CLOSED leftover as Files Compress session UI")
for required in (
    "Files LIVE metal",
    "Win7 visual",
    "Explorer present",
    "Fabric LIVE under SHELL",
    "Settings Power LIVE",
    "End Task LIVE",
    "Software Center present",
    "Update present",
):
    if required not in addendum:
        raise SystemExit(f"fleet-doctrine-gaps Compress addendum dropped OPEN leftover: {required}")
if "Do not invent claim=present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse claim=present invent")
if "Cloud EXIT 0 is not metal leftover CLOSED" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Cloud EXIT 0 as metal leftover CLOSED")
if "windows-native.13" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must keep windows-native.13 pending")
if "Files > Compress" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name Files > Compress")
if "this session" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name the session plane")
if "Do not invent Fabric SHELL LIVE archive" not in addendum and "Do not invent Fabric LIVE under SHELL" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Fabric SHELL LIVE archive invent")

if "SESSION CONTROL" not in session and "SESSION CONTROL" not in files_app:
    raise SystemExit("session Compress must show SESSION CONTROL")
if "LIVE CONTROL" in session:
    raise SystemExit("session Compress invented LIVE CONTROL")
if "Files > Compress" not in parity:
    raise SystemExit("PARITY must name Files > Compress")
if "does not invent a Fabric SHELL LIVE archive writer" not in parity and "session Compress" not in parity:
    raise SystemExit("PARITY must name session Compress without walking Explorer to present")
explorer_row = ""
for line in parity.splitlines():
    if line.startswith("| Explorer / Computer |"):
        explorer_row = line
        break
if "this row is not present" not in explorer_row or "prototype" not in explorer_row:
    raise SystemExit("PARITY Explorer row must stay not present")
if "files-archive-create" not in handoff:
    raise SystemExit("HANDOFF must name files-archive-create")
if "Files Compress session" not in handoff and "session Compress" not in handoff:
    raise SystemExit("HANDOFF must name session Compress")
if "files-archive-create" not in project and "session Compress" not in project:
    raise SystemExit("project-ultimate must name session Compress")
if "files.archive.create" not in files_docs:
    raise SystemExit("files-defaults-provider must name files.archive.create")
if "does not invent a Fabric" not in files_docs.split("files.archive.create", 1)[1][:800]:
    raise SystemExit("files-defaults-provider must refuse a Fabric archive writer")
PY

pass "files.archive.create stays leftover partial with a visible Files Compress route"
