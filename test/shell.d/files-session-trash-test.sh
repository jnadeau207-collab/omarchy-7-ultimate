#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
files_app="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"
files_model="$ROOT/shell/apps/ultimate-files/FilesModel.js"
files_session="$ROOT/shell/apps/shared/FilesSessionTrash.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"

[[ -f $helper ]] || fail "session apply helper exists"
[[ -f $files_app ]] || fail "Files application exists"
[[ -f $files_model ]] || fail "Files model exists"

grep -Fq '"files-entry-trash": apply_files_entry_trash' "$helper" ||
  fail "session apply owns files-entry-trash"
grep -Fq '"files-trash-restore": apply_files_trash_restore' "$helper" ||
  fail "session apply owns files-trash-restore"
grep -Fq '"files-trash-manage": apply_files_trash_manage' "$helper" ||
  fail "session apply owns files-trash-manage"
[[ -f $files_session ]] || fail "Files hosts a session recycle plane"
grep -Fq 'files-entry-trash' "$files_session" || fail "session recycle QML calls files-entry-trash"
grep -Fq 'files-trash-restore' "$files_session" || fail "session recycle QML calls files-trash-restore"
grep -Fq 'files-trash-manage' "$files_session" || fail "session recycle QML calls files-trash-manage"
grep -Fq 'omarchy-fabric-session-apply' "$files_session" ||
  fail "session recycle QML uses the session apply helper"
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$files_session"; then
  fail "Files Recycle session plane must not mint Fabric durable operations"
fi
grep -Fq 'Shared.FilesSessionTrash' "$files_app" || fail "Files hosts the session recycle helper"
grep -Fq 'sessionTrashEntry' "$files_app" || fail "Files Delete uses the session trash plane"
grep -Fq 'sessionRestoreEntry' "$files_app" || fail "Files Restore uses the session restore plane"
grep -Fq 'sessionEmptyBin' "$files_app" || fail "Files Empty Recycle Bin uses the session manage plane"
grep -Fq 'key: "restore", label: "Restore"' "$files_app" || fail "Files shows a Restore control on Trash"
grep -Fq 'key: "empty-bin", label: "Empty Recycle Bin"' "$files_app" || fail "Files shows Empty Recycle Bin"
grep -Fq 'this session' "$files_app" || fail "Files names the session recycle principal"
grep -Fq 'Delete, Restore, and Empty Recycle Bin run through this session' "$files_app" ||
  fail "Files banner names session Delete/Restore/Empty LIVE"
grep -Fq 'Fabric Restore UI and Empty Bin LIVE remain unavailable under SHELL' "$files_app" ||
  fail "Files banner keeps Fabric Restore/Empty unavailable under SHELL"
if grep -Fq 'Restore UI, Empty Bin LIVE, and Recycle product remain unavailable' "$files_app"; then
  fail "Files banner must not self-contradict session Restore/Empty as unavailable"
fi
if grep -Eq 'operation\.(preflight|start|approve)' "$files_session"; then
  fail "session recycle QML must not mint Fabric durable operations"
fi
if grep -Eq 'action: "entry.trash"|action: "trash.restore"|action: "trash.manage"' "$files_session"; then
  fail "session recycle QML must not call Fabric files.provider trash actions"
fi
grep -Fq 'readonly property bool trashAuthorized: false' "$files_app" ||
  fail "Files keeps trashAuthorized=false for Fabric OperationDialog paths"
grep -Fq 'readonly property bool emptyBinAuthorized: false' "$files_app" ||
  fail "Files keeps emptyBinAuthorized=false for Fabric OperationDialog paths"
if grep -Eq 'trashAuthorized:\s*true|emptyBinAuthorized:\s*true' "$files_app"; then
  fail "Files invents Fabric SHELL authorization for Trash or Empty Bin"
fi
if grep -Eq 'Process[[:space:]]*\{' "$files_app"; then
  fail "Files consumer QML must not host the session Process block"
fi
grep -Fq 'sessionTrashPlan' "$files_model" || fail "Files model plans session trash"
grep -Fq 'sessionRestorePlan' "$files_model" || fail "Files model plans session restore"
grep -Fq 'sessionEmptyPlan' "$files_model" || fail "Files model plans session empty"

pass "Files wires a session recycle plane instead of a Fabric LIVE button"

cd "$ROOT/default/fabric"
PYTHONPATH="$ROOT/default/fabric" PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import io
import json
import os
import pathlib
import tempfile

os.environ.pop("XDG_DATA_HOME", None)
home = pathlib.Path(tempfile.mkdtemp()) / "home"
(home / "Documents").mkdir(parents=True)
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


def directory_resource(location_id, relative):
    parent = relative.rsplit("/", 1)[0] if "/" in relative else ""
    return sa.stable_directory_id(location_id, parent)


def entry_payload(location_id, relative, path, include_resource=True):
    info = path.lstat()
    payload = {
        "locationId": location_id,
        "entryRelativePath": relative,
        "entryId": sa.stable_entry_id(location_id, info.st_dev, info.st_ino, relative),
    }
    if include_resource:
        payload["resourceId"] = directory_resource(location_id, relative)
    return payload


def restore_payload(location_id, relative, trash_file, include_resource=True):
    info = trash_file.lstat()
    payload = {
        "locationId": location_id,
        "entryRelativePath": relative,
        "entryId": sa.stable_entry_id("files.location.trash", info.st_dev, info.st_ino, trash_file.name),
    }
    if include_resource:
        payload["resourceId"] = directory_resource(location_id, relative)
    return payload


trash = home / ".local" / "share" / "Trash"
target = home / "Documents" / "report.txt"
target.write_text("hello", encoding="utf-8")

status, result = run("files-entry-trash", entry_payload("files.location.documents", "report.txt", target, include_resource=False))
check("session trash without a resourceId succeeds", status == 0 and result.get("ok") is True, str(result))
check("session trash moves the original", not target.exists())
check("session trash lands in Trash files", (trash / "files" / "report.txt").is_file())

moved = trash / "files" / "report.txt"
status, result = run("files-trash-restore", restore_payload("files.location.documents", "report.txt", moved, include_resource=False))
check("session restore without a resourceId succeeds", status == 0 and result.get("ok") is True, str(result))
check("session restore returns the original", target.is_file())
check("session restore keeps the content", target.read_text(encoding="utf-8") == "hello")

status, result = run("files-entry-trash", entry_payload("files.location.documents", "report.txt", target, include_resource=False))
check("second session trash succeeds", status == 0 and result.get("ok") is True, str(result))

status, result = run("files-trash-manage", {"locationId": "files.location.trash"})
check("session empty bin without a resourceId succeeds", status == 0 and result.get("ok") is True, str(result))
check("session empty bin reports a removal", result.get("emptied") is True and result.get("count") == 1, str(result))
check("session empty bin removes the file", not (trash / "files" / "report.txt").exists())
check("session empty bin removes the trashinfo", not (trash / "info" / "report.txt.trashinfo").exists())

status, result = run("files-trash-manage", {"locationId": "files.location.documents"})
check("empty bin refuses a non-Trash location", status == 1 and result.get("ok") is False, str(result))
check("empty bin non-Trash uses payload.invalid", result.get("code") == "payload.invalid", str(result))

nested = home / "Documents" / "nested"
nested.mkdir()
(nested / "child.txt").write_text("keep", encoding="utf-8")
info = nested.lstat()
payload = {
    "locationId": "files.location.documents",
    "entryRelativePath": "nested",
    "entryId": sa.stable_entry_id("files.location.documents", info.st_dev, info.st_ino, "nested"),
}
status, result = run("files-entry-trash", payload)
check("a non-empty directory can still be moved to Trash", status == 0 and result.get("ok") is True, str(result))
status, result = run("files-trash-manage", {"locationId": "files.location.trash"})
check("empty bin refuses a non-empty trash tree", status == 1 and result.get("ok") is False, str(result))
check("empty bin non-empty tree uses payload.invalid", result.get("code") == "payload.invalid", str(result))
check("the nested trash tree is untouched", (trash / "files" / "nested" / "child.txt").is_file())

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session trash, restore, and empty report success and honest refusal"

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
const trash = Model.sessionTrashPlan(document)
assertEqual(trash.action, 'trash', 'a Documents file can move to Trash')
assertEqual(trash.entryId, 'files.entry.abc', 'trash keeps the entry identity')
assertEqual(trash.locationId, 'files.location.documents', 'trash keeps the location')
assertEqual(trash.entryRelativePath, 'report.txt', 'trash keeps the relative path')
assert(Model.sessionTrashCanSubmit(trash), 'Documents trash can submit')

const symlink = Model.sessionTrashPlan({ ...document, status: 'symlink' })
assertEqual(symlink.action, 'unavailable', 'a symlink cannot move to Trash')
assert(!Model.sessionTrashCanSubmit(symlink), 'symlink trash cannot submit')

const music = Model.sessionTrashPlan({ ...document, locationId: 'files.location.music' })
assertEqual(music.action, 'unavailable', 'music is outside the session trash locations')

const restored = {
  id: 'files.entry.trash1',
  kind: 'entry',
  entryKind: 'file',
  status: 'file',
  locationId: 'files.location.trash',
  relativePath: 'report.txt',
  title: 'report.txt',
  trash: {
    originalLocationId: 'files.location.documents',
    originalParentId: null,
    originalRelativePath: 'report.txt'
  }
}
const restore = Model.sessionRestorePlan(restored)
assertEqual(restore.action, 'restore', 'a Trash record with original path can restore')
assertEqual(restore.locationId, 'files.location.documents', 'restore targets the original location')
assertEqual(restore.entryRelativePath, 'report.txt', 'restore keeps the original path')
assertEqual(restore.entryId, 'files.entry.trash1', 'restore keeps the Trash entry identity')
assert(Model.sessionTrashCanSubmit(restore), 'Trash restore can submit')

const noMeta = Model.sessionRestorePlan({ ...restored, trash: null })
assertEqual(noMeta.action, 'unavailable', 'a Trash row without original path cannot restore')

const empty = Model.sessionEmptyPlan()
assertEqual(empty.action, 'empty', 'Empty Recycle Bin plans trash-manage')
assertEqual(empty.locationId, 'files.location.trash', 'empty only names Trash')
assertEqual(empty.parentRelativePath, '', 'empty only targets the Trash root')
assert(Model.sessionTrashCanSubmit(empty), 'empty can submit')

assertEqual(Model.sessionTrashableRecord(document), true, 'Documents file is session-trashable')
assertEqual(Model.sessionRestorableRecord(restored), true, 'Trash record with original path is restorable')
assertEqual(Model.sessionRestorableRecord(document), false, 'Documents file is not restorable')
JS

pass "Files model plans session trash, restore, and empty"

python3 - "$catalog" <<'PY'
import json
import sys

catalog = json.loads(open(sys.argv[1], encoding="utf-8").read())
by_id = {entry["id"]: entry for entry in catalog["capabilities"]}

trash = by_id["files.entry.trash"]
route = trash["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Files":
    raise SystemExit(f"files.entry.trash route is {route}")
if route.get("path") != "Files > Delete":
    raise SystemExit(f"files.entry.trash path is {route}")
if trash.get("source", {}).get("file") != "shell/apps/shared/FilesSessionTrash.qml":
    raise SystemExit(f"files.entry.trash source is {trash.get('source')}")
if trash.get("source", {}).get("symbol") != "trashRecord":
    raise SystemExit(f"files.entry.trash source is {trash.get('source')}")
if trash.get("availability", {}).get("claim") == "present":
    raise SystemExit("files.entry.trash must not claim present")
if trash.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"files.entry.trash human availability is {trash.get('availability')}")

restore = by_id["files.trash.restore"]
route = restore["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Files":
    raise SystemExit(f"files.trash.restore route is {route}")
if route.get("path") != "Files > Restore":
    raise SystemExit(f"files.trash.restore path is {route}")
if restore.get("source", {}).get("file") != "shell/apps/shared/FilesSessionTrash.qml":
    raise SystemExit(f"files.trash.restore source is {restore.get('source')}")
if restore.get("source", {}).get("symbol") != "restoreRecord":
    raise SystemExit(f"files.trash.restore source is {restore.get('source')}")
if restore.get("availability", {}).get("claim") == "present":
    raise SystemExit("files.trash.restore must not claim present")
if restore.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"files.trash.restore claim is {restore.get('availability')}")

manage = by_id["files.trash.manage"]
route = manage["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Files":
    raise SystemExit(f"files.trash.manage route is {route}")
if route.get("path") != "Files > Empty Recycle Bin":
    raise SystemExit(f"files.trash.manage path is {route}")
if manage.get("source", {}).get("file") != "shell/apps/shared/FilesSessionTrash.qml":
    raise SystemExit(f"files.trash.manage source is {manage.get('source')}")
if manage.get("source", {}).get("symbol") != "emptyBin":
    raise SystemExit(f"files.trash.manage source is {manage.get('source')}")
if manage.get("availability", {}).get("claim") == "present":
    raise SystemExit("files.trash.manage must not claim present")
if manage.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"files.trash.manage claim is {manage.get('availability')}")
PY

pass "recycle writers stay leftover partial with visible Files routes"

plan="$ROOT/plans/project-ultimate.md"
grep -Fq 'session Trash/Restore/Empty (#76)' "$plan" ||
  fail "project-ultimate Files LIVE column names session Trash/Restore/Empty"
if grep -Fq 'Restore UI (do not invent Restore LIVE), Empty Bin LIVE' "$plan"; then
  fail "project-ultimate Files row must not list bare Restore UI / Empty Bin LIVE as if the session plane is missing"
fi
grep -Fq 'Fabric Restore LIVE under SHELL' "$plan" ||
  fail "project-ultimate Files unavailable column names Fabric Restore LIVE under SHELL"
grep -Fq 'Fabric Empty Bin LIVE under SHELL' "$plan" ||
  fail "project-ultimate Files unavailable column names Fabric Empty Bin LIVE under SHELL"

pass "project-ultimate Files row names session Trash/Restore/Empty and Fabric leftovers"
