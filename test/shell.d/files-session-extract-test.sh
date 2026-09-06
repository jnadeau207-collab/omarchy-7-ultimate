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

grep -Fq '"files-archive-extract": apply_files_archive_extract' "$helper" ||
  fail "session apply owns files-archive-extract"
grep -Fq 'files-archive-extract' "$files_session" || fail "session archive QML calls files-archive-extract"
grep -Fq 'extractArchive' "$files_session" || fail "session archive QML exposes extractArchive"
grep -Fq 'omarchy-fabric-session-apply' "$files_session" ||
  fail "session archive QML uses the session apply helper"
grep -Fq 'OMARCHY_PATH' "$files_session" || fail "session archive QML prefers OMARCHY_PATH"
grep -Fq '/bin/omarchy-fabric-session-apply' "$files_session" ||
  fail "session archive QML spawns omarchy-fabric-session-apply from an absolute bin path"
if grep -Eq 'return "omarchy-fabric-session-apply"|: "omarchy-fabric-session-apply"' "$files_session"; then
  fail "session archive QML must not spawn a bare omarchy-fabric-session-apply PATH name"
fi
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$files_session"; then
  fail "Files Extract session plane must not mint Fabric durable operations"
fi
if grep -Eq 'action: "archive\.|action: "entry\.archive|provider: "files.provider"' "$files_session"; then
  fail "session archive QML must not call a Fabric files.provider archive action"
fi
if grep -Eq 'pkexec|sudo' "$files_session"; then
  fail "Files Extract QML must not spawn privilege"
fi
grep -Fq 'Shared.FilesSessionArchive' "$files_app" || fail "Files hosts the session archive helper"
grep -Fq 'sessionExtractEntry' "$files_app" || fail "Files Extract uses the session archive plane"
grep -Fq 'key: "extract", label: "Extract"' "$files_app" || fail "Files shows an Extract control"
grep -Fq 'SESSION CONTROL' "$files_app" "$command_bar" ||
  fail "Files shows a SESSION CONTROL badge"
if grep -Eq 'LIVE CONTROL' "$files_app" "$files_session" "$command_bar"; then
  fail "Files Extract must not invent Fabric LIVE CONTROL"
fi
if grep -Eqi 'claim=present' "$files_app" "$files_session"; then
  fail "Files Extract must not invent claim=present"
fi
if grep -Eq 'Process[[:space:]]*\{' "$files_app"; then
  fail "Files consumer QML must not host the session Process block"
fi
grep -Fq 'sessionExtractPlan' "$files_model" || fail "Files model plans session extract"
grep -Fq 'sessionExtractableRecord' "$files_model" || fail "Files model gates session Extract"
grep -Fq 'Extract runs through this session' "$files_app" ||
  fail "Files banner names session Extract"
grep -Fq 'does not invent a Fabric SHELL LIVE archive writer' "$files_app" ||
  fail "Files banner refuses a Fabric SHELL LIVE archive writer"
if grep -Eq 'files-archive-extract' "$daemon" "$files_plane"; then
  fail "Fabric durable plane invented a files-archive-extract writer"
fi
if grep -Eq 'archive.extract|entry.extract|files.archive.extract' "$files_provider"/*.py "$files_provider"/*.json; then
  fail "files.provider invented a Fabric archive extract writer"
fi
grep -Fq 'MAX_EXTRACT_BYTES' "$helper" || fail "session extract bounds uncompressed bytes"
grep -Fq 'O_NOFOLLOW' "$helper" || fail "session extract opens with O_NOFOLLOW"

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
    if 'key: "extract"' not in body:
        raise SystemExit(f"{name} dropped Extract")
    if "sessionExtractableRecord" not in body.split('key: "extract"', 1)[1][:280]:
        raise SystemExit(f"{name} Extract is not session-extractable gated")
PY

pass "Files wires a session Extract plane instead of a Fabric LIVE archive writer"

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


archive = home / "Documents" / "report.zip"
with zipfile.ZipFile(archive, "w") as zf:
    zf.writestr("report.txt", "hello zip")
    zf.writestr("album/two.txt", "two")
payload = entry_payload("files.location.documents", "report.zip", archive)
status, result = run("files-archive-extract", payload)
folder = home / "Documents" / "report"
check("session extract without a resourceId succeeds", status == 0 and result.get("ok") is True, str(result))
check("session extract writes a folder named after the archive", folder.is_dir(), str(result))
check("session extract reports the folder name", result.get("folderName") == "report", str(result))
check("session extract reports created", result.get("created") is True, str(result))
check("session extract keeps the zip", archive.is_file())
if folder.is_dir():
    check("extract writes the selected file", (folder / "report.txt").read_text(encoding="utf-8") == "hello zip")
    check("extract keeps nested files", (folder / "album" / "two.txt").read_text(encoding="utf-8") == "two")
    check("extract does not write a symlink", not (folder / "report.txt").is_symlink())

status, result = run("files-archive-extract", payload)
second = home / "Documents" / "report (2)"
check("session extract picks a non-colliding folder", status == 0 and result.get("ok") is True, str(result))
check("session extract collision uses report (2)", second.is_dir() and result.get("folderName") == "report (2)", str(result))
check("the first extract folder is untouched", folder.is_dir() and (folder / "report.txt").is_file())

plain = home / "Documents" / "notes.txt"
plain.write_text("notes", encoding="utf-8")
status, result = run("files-archive-extract", entry_payload("files.location.documents", "notes.txt", plain))
check("non-zip is refused", status == 1 and result.get("ok") is False, str(result))
check("non-zip uses payload.invalid", result.get("code") == "payload.invalid", str(result))

slip = home / "Documents" / "slip.zip"
with zipfile.ZipFile(slip, "w") as zf:
    zf.writestr("../Desktop/evil.txt", "nope")
status, result = run("files-archive-extract", entry_payload("files.location.documents", "slip.zip", slip))
check("zip-slip parent traversal is refused", status == 1 and result.get("ok") is False, str(result))
check("zip-slip uses payload.invalid", result.get("code") == "payload.invalid", str(result))
check("zip-slip does not write Desktop", not (home / "Desktop" / "evil.txt").exists())
check("failed zip-slip folder is not left behind", not (home / "Documents" / "slip").exists())

absolute = home / "Documents" / "abs.zip"
with zipfile.ZipFile(absolute, "w") as zf:
    info = zipfile.ZipInfo("/tmp/evil.txt")
    zf.writestr(info, "nope")
status, result = run("files-archive-extract", entry_payload("files.location.documents", "abs.zip", absolute))
check("absolute arcname is refused", status == 1 and result.get("ok") is False, str(result))
check("absolute arcname uses payload.invalid", result.get("code") == "payload.invalid", str(result))
check("absolute extract folder is not left behind", not (home / "Documents" / "abs").exists())

linked = home / "Documents" / "linked.zip"
with zipfile.ZipFile(linked, "w") as zf:
    info = zipfile.ZipInfo("escape")
    info.create_system = 3
    info.external_attr = (stat.S_IFLNK | 0o777) << 16
    zf.writestr(info, str(home / "Desktop"))
status, result = run("files-archive-extract", entry_payload("files.location.documents", "linked.zip", linked))
check("symlink member is refused", status == 1 and result.get("ok") is False, str(result))
check("symlink member uses payload.invalid", result.get("code") == "payload.invalid", str(result))
check("failed symlink extract folder is not left behind", not (home / "Documents" / "linked").exists())

link = home / "Documents" / "alias.zip"
link.symlink_to("report.zip")
status, result = run("files-archive-extract", entry_payload("files.location.documents", "alias.zip", link))
check("symlink zip source is refused", status == 1 and result.get("ok") is False, str(result))
check("symlink zip source uses payload.invalid", result.get("code") == "payload.invalid", str(result))

escaped = {
    "locationId": "files.location.documents",
    "entryRelativePath": "../Desktop/escape.zip",
    "entryId": "files.entry." + "0" * 64,
}
status, result = run("files-archive-extract", escaped)
check("path traversal is refused", status == 1 and result.get("ok") is False, str(result))
check("path traversal uses payload.invalid", result.get("code") == "payload.invalid", str(result))

trash_payload = entry_payload("files.location.documents", "report.zip", archive)
trash_payload["locationId"] = "files.location.trash"
status, result = run("files-archive-extract", trash_payload)
check("session extract refuses Trash", status == 1 and result.get("ok") is False, str(result))
check("session extract Trash uses payload.invalid", result.get("code") == "payload.invalid", str(result))

status, result = run(
    "files-archive-extract",
    {
        "locationId": "files.location.documents",
        "entryRelativePath": "missing.zip",
        "entryId": "files.entry." + "0" * 64,
    },
)
check("missing zip is refused", status == 1 and result.get("ok") is False, str(result))
check("missing zip uses resource.unresolved", result.get("code") == "resource.unresolved", str(result))

status, result = run("files-archive-extract", {"locationId": "files.location.documents"})
check("empty selection is refused", status == 1 and result.get("ok") is False, str(result))
check("empty selection uses payload.invalid", result.get("code") == "payload.invalid", str(result))

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session extract reports success and honest refusal"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-files/FilesModel.js')

const zip = {
  id: 'files.entry.abc',
  kind: 'entry',
  entryKind: 'file',
  status: 'file',
  locationId: 'files.location.documents',
  relativePath: 'report.zip',
  title: 'report.zip'
}

const extract = Model.sessionExtractPlan(zip)
assertEqual(extract.action, 'extract', 'a Documents zip can be extracted')
assertEqual(extract.entryId, 'files.entry.abc', 'extract keeps the entry identity')
assertEqual(extract.locationId, 'files.location.documents', 'extract keeps the location')
assert(Model.sessionExtractCanSubmit(extract), 'Documents extract can submit')

const many = Model.sessionExtractPlan([
  zip,
  { ...zip, id: 'files.entry.def', relativePath: 'notes.zip', title: 'notes.zip' }
])
assertEqual(many.action, 'unavailable', 'multiple zips cannot be extracted together')
assert(!Model.sessionExtractCanSubmit(many), 'multi extract cannot submit')

const text = Model.sessionExtractPlan({ ...zip, relativePath: 'report.txt', title: 'report.txt' })
assertEqual(text.action, 'unavailable', 'a non-zip cannot be extracted')
assert(!Model.sessionExtractCanSubmit(text), 'non-zip extract cannot submit')

const folder = Model.sessionExtractPlan({ ...zip, entryKind: 'directory', title: 'Photos', relativePath: 'Photos' })
assertEqual(folder.action, 'unavailable', 'a folder cannot be extracted')

const symlink = Model.sessionExtractPlan({ ...zip, status: 'symlink' })
assertEqual(symlink.action, 'unavailable', 'a symlink cannot be extracted')
assert(!Model.sessionExtractCanSubmit(symlink), 'symlink extract cannot submit')

const trash = Model.sessionExtractPlan({ ...zip, locationId: 'files.location.trash' })
assertEqual(trash.action, 'unavailable', 'Trash cannot be extracted')
assert(String(trash.reason || '').toLowerCase().indexOf('trash') >= 0, 'Trash extract names the refuse')

const music = Model.sessionExtractPlan({ ...zip, locationId: 'files.location.music' })
assertEqual(music.action, 'unavailable', 'music is outside the session extract locations')

assertEqual(Model.sessionExtractableRecord(zip), true, 'Documents zip is session-extractable')
assertEqual(Model.sessionExtractableRecord({ ...zip, title: 'Report.ZIP' }), true, 'uppercase ZIP is session-extractable')
assertEqual(Model.sessionExtractableRecord({ ...zip, entryKind: 'directory' }), false, 'directories are not session-extractable')
assertEqual(Model.sessionExtractableRecord({ ...zip, title: 'report.txt', relativePath: 'report.txt' }), false, 'plain files are not session-extractable')
assertEqual(Model.sessionExtractableRecord({ ...zip, status: 'symlink' }), false, 'symlinks are not session-extractable')
JS

pass "Files model plans session extract"

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
extract = by_id["files.archive.extract"]
route = extract["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Files":
    raise SystemExit(f"files.archive.extract route is {route}")
if route.get("path") != "Files > Extract":
    raise SystemExit(f"files.archive.extract path is {route}")
if route.get("label") != "Extract a zip archive":
    raise SystemExit(f"files.archive.extract label is {route}")
if extract.get("source", {}).get("file") != "shell/apps/shared/FilesSessionArchive.qml":
    raise SystemExit(f"files.archive.extract source is {extract.get('source')}")
if extract.get("source", {}).get("symbol") != "extractArchive":
    raise SystemExit(f"files.archive.extract source is {extract.get('source')}")
if "nautilus" in str(extract.get("source") or "").lower():
    raise SystemExit(f"files.archive.extract still names Nautilus: {extract.get('source')}")
if extract.get("availability", {}).get("claim") == "present":
    raise SystemExit("files.archive.extract must not claim present")
if extract.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"files.archive.extract claim is {extract.get('availability')}")
if extract.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"files.archive.extract human availability is {extract.get('availability')}")
if extract.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"files.archive.extract agent availability is {extract.get('availability')}")
if extract.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"files.archive.extract was raised off leftover: {extract.get('provider')}")
if extract.get("provider", {}).get("id") != "files.provider":
    raise SystemExit(f"files.archive.extract provider is {extract.get('provider')}")

by_job = {job["id"]: job for job in jobs["jobs"]}
native13 = by_job["windows-native.13"]
if native13.get("claim") == "present":
    raise SystemExit("windows-native.13 must not claim present")
if native13.get("claim") != "prototype":
    raise SystemExit(f"windows-native.13 claim is {native13.get('claim')}")
if "files.archive.extract" in (native13.get("capabilityIds") or []):
    raise SystemExit("windows-native.13 must stay Compress-only; do not walk Extract onto it")
if native13.get("capabilityIds") != ["files.archive.create"]:
    raise SystemExit(f"windows-native.13 capabilityIds are {native13.get('capabilityIds')}")
if native13["humanRoute"].get("path") != "Files > Compress":
    raise SystemExit(f"windows-native.13 path is {native13.get('humanRoute')}")

for job in jobs["jobs"]:
    if "files.archive.extract" in (job.get("capabilityIds") or []):
        raise SystemExit(f"{job.get('id')} invents a windows-native Extract row by naming files.archive.extract")
    label = str(job.get("sourceLabel") or "") + " " + str((job.get("humanRoute") or {}).get("path") or "")
    if job.get("id") != "windows-native.13" and "Extract" in label and job.get("claim") == "present":
        raise SystemExit(f"{job.get('id')} invents an Extract present claim")

explorer = by_job["parity.explorer-this-pc"]
if explorer.get("claim") == "present":
    raise SystemExit("parity.explorer-this-pc must not claim present")
if "files.archive.extract" in (explorer.get("capabilityIds") or []):
    raise SystemExit("parity.explorer-this-pc invents Explorer present by naming files.archive.extract")

by_debt = {entry["id"]: entry for entry in debt["entries"]}
legacy = by_debt["legacy.domain.direct-providers"]
if "files.archive.extract" not in legacy.get("capabilityIds", []):
    raise SystemExit("files.archive.extract is not leftover-direct debt")
if "capability:files.archive.extract" not in legacy.get("surfaceRefs", []):
    raise SystemExit("files.archive.extract leftover surfaceRef is missing")
agent = by_debt["missing.agent.routes"]
if "files.archive.extract" not in agent.get("capabilityIds", []):
    raise SystemExit("files.archive.extract is not agent-unavailable debt")
if "capability:files.archive.extract" not in agent.get("surfaceRefs", []):
    raise SystemExit("files.archive.extract agent surfaceRef is missing")

if "Honesty addendum 2026-09-06 vs Files Extract session plane" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must add a dated Files Extract addendum")
addendum = gaps.split("Honesty addendum 2026-09-06 vs Files Extract session plane", 1)[1].split("Honesty addendum", 1)[0]
if "CLOSED leftover: Files Extract session UI" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name CLOSED leftover as Files Extract session UI")
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
        raise SystemExit(f"fleet-doctrine-gaps Extract addendum dropped OPEN leftover: {required}")
if "Do not invent claim=present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse claim=present invent")
if "Cloud EXIT 0 is not metal leftover CLOSED" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Cloud EXIT 0 as metal leftover CLOSED")
if "No windows-native Extract row" not in addendum and "no windows-native Extract row" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name the missing windows-native Extract row")
if "Files > Extract" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name Files > Extract")
if "this session" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name the session plane")
if "Do not invent Fabric SHELL LIVE archive" not in addendum and "Do not invent Fabric LIVE under SHELL" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Fabric SHELL LIVE archive invent")
if "named after the archive" not in addendum and "folder named after" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must document the beside-archive folder policy")

if "SESSION CONTROL" not in session and "SESSION CONTROL" not in files_app:
    raise SystemExit("session Extract must show SESSION CONTROL")
if "LIVE CONTROL" in session:
    raise SystemExit("session Extract invented LIVE CONTROL")
if "Files > Extract" not in parity:
    raise SystemExit("PARITY must name Files > Extract")
if "does not invent a Fabric SHELL LIVE archive writer" not in parity and "session Extract" not in parity:
    raise SystemExit("PARITY must name session Extract without walking Explorer to present")
explorer_row = ""
for line in parity.splitlines():
    if line.startswith("| Explorer / Computer |"):
        explorer_row = line
        break
if "this row is not present" not in explorer_row or "prototype" not in explorer_row:
    raise SystemExit("PARITY Explorer row must stay not present")
if "files-archive-extract" not in handoff:
    raise SystemExit("HANDOFF must name files-archive-extract")
if "Files Extract session" not in handoff and "session Extract" not in handoff:
    raise SystemExit("HANDOFF must name session Extract")
if "files-archive-extract" not in project and "session Extract" not in project:
    raise SystemExit("project-ultimate must name session Extract")
if "files.archive.extract" not in files_docs:
    raise SystemExit("files-defaults-provider must name files.archive.extract")
if "does not invent a Fabric" not in files_docs.split("files.archive.extract", 1)[1][:800]:
    raise SystemExit("files-defaults-provider must refuse a Fabric archive writer")
if "named after the archive" not in files_docs.split("files.archive.extract", 1)[1][:800]:
    raise SystemExit("files-defaults-provider must document the extract folder policy")
PY

pass "files.archive.extract stays leftover partial with a visible Files Extract route"
