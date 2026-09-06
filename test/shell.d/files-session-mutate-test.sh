#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
files_app="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"
files_model="$ROOT/shell/apps/ultimate-files/FilesModel.js"
files_session="$ROOT/shell/apps/shared/FilesSessionMutate.qml"
catalog="$ROOT/default/ultimate/capabilities/catalog-system-jobs-v0.json"

[[ -f $helper ]] || fail "session apply helper exists"
[[ -f $files_app ]] || fail "Files application exists"
[[ -f $files_model ]] || fail "Files model exists"

grep -Fq '"files-entry-move": apply_files_entry_move' "$helper" ||
  fail "session apply owns files-entry-move"
grep -Fq '"files-entry-delete": apply_files_entry_delete' "$helper" ||
  fail "session apply owns files-entry-delete"
[[ -f $files_session ]] || fail "Files hosts a session cut/delete plane"
grep -Fq 'files-entry-move' "$files_session" || fail "session mutate QML calls files-entry-move"
grep -Fq 'files-entry-delete' "$files_session" || fail "session mutate QML calls files-entry-delete"
grep -Fq 'omarchy-fabric-session-apply' "$files_session" ||
  fail "session mutate QML uses the session apply helper"
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$files_session"; then
  fail "Files Cut/Delete session plane must not mint Fabric durable operations"
fi
grep -Fq 'Shared.FilesSessionMutate' "$files_app" || fail "Files hosts the session mutate helper"
grep -Fq 'sessionCutEntry' "$files_app" || fail "Files Cut uses the session move plane"
grep -Fq 'sessionDeleteEntry' "$files_app" || fail "Files Permanently delete uses the session delete plane"
grep -Fq 'key: "cut", label: "Cut"' "$files_app" || fail "Files shows a Cut control"
grep -Fq 'key: "permanently-delete", label: "Permanently delete"' "$files_app" || fail "Files shows Permanently delete"
grep -Fq 'this session' "$files_app" || fail "Files names the session cut/delete principal"
if grep -Eq 'action: "entry.move"|action: "entry.delete"' "$files_session"; then
  fail "session mutate QML must not call Fabric files.provider move/delete actions"
fi
grep -Fq 'readonly property bool cutAuthorized: false' "$files_app" ||
  fail "Files keeps cutAuthorized=false for Fabric OperationDialog paths"
grep -Fq 'readonly property bool deleteAuthorized: false' "$files_app" ||
  fail "Files keeps deleteAuthorized=false for Fabric OperationDialog paths"
if grep -Eq 'cutAuthorized:\s*true|deleteAuthorized:\s*true' "$files_app"; then
  fail "Files invents Fabric SHELL authorization for Cut or permanent Delete"
fi
if grep -Eq 'Process[[:space:]]*\{' "$files_app"; then
  fail "Files consumer QML must not host the session Process block"
fi
grep -Fq 'sessionMovePlan' "$files_model" || fail "Files model plans session move"
grep -Fq 'sessionDeletePlan' "$files_model" || fail "Files model plans session delete"
grep -Fq 'Cut and Paste-after-cut run through this session' "$files_app" ||
  fail "Files banner names session LIVE Cut"
grep -Fq 'Permanent Delete runs through this session' "$files_app" ||
  fail "Files banner names session LIVE permanent Delete"
grep -Fq 'The cut/move write plane exists but is not shell-authorizable' "$files_app" ||
  fail "Files banner keeps Fabric cut/move CHANGES UNAVAILABLE"
grep -Fq 'The permanent delete write plane exists but is not shell-authorizable' "$files_app" ||
  fail "Files banner keeps Fabric permanent delete CHANGES UNAVAILABLE"

pass "Files wires a session cut/delete plane instead of a Fabric LIVE button"

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
source.write_text("hello", encoding="utf-8")
payload = entry_payload("files.location.documents", "report.txt", source)
payload.update({
    "destinationLocationId": "files.location.desktop",
    "destinationParentRelativePath": "",
    "destinationName": "report.txt",
})
status, result = run("files-entry-move", payload)
desktop = home / "Desktop" / "report.txt"
check("session move without a resourceId succeeds", status == 0 and result.get("ok") is True, str(result))
check("session move relocates the file", desktop.is_file() and not source.exists())
check("session move keeps the bytes", desktop.read_text(encoding="utf-8") == "hello" if desktop.exists() else False)

trash_payload = dict(payload)
trash_payload["locationId"] = "files.location.trash"
status, result = run("files-entry-move", trash_payload)
check("session move refuses a Trash source", status == 1 and result.get("ok") is False, str(result))
check("session move Trash source uses payload.invalid", result.get("code") == "payload.invalid", str(result))

trash_dest = dict(payload)
trash_dest["destinationLocationId"] = "files.location.trash"
status, result = run("files-entry-move", trash_dest)
check("session move refuses a Trash destination", status == 1 and result.get("ok") is False, str(result))
check("session move Trash dest uses payload.invalid", result.get("code") == "payload.invalid", str(result))

folder = home / "Documents" / "empty-folder"
folder.mkdir()
delete_payload = entry_payload("files.location.documents", "empty-folder", folder)
status, result = run("files-entry-delete", delete_payload)
check("session delete without a resourceId removes an empty directory", status == 0 and result.get("ok") is True, str(result))
check("session delete removes the empty directory", not folder.exists())

keep = home / "Documents" / "keep.txt"
keep.write_text("stay", encoding="utf-8")
status, result = run("files-entry-delete", entry_payload("files.location.documents", "keep.txt", keep))
check("session delete unlinks a regular file", status == 0 and result.get("ok") is True and not keep.exists(), str(result))

nested = home / "Documents" / "nested"
nested.mkdir()
(nested / "child.txt").write_text("keep", encoding="utf-8")
status, result = run("files-entry-delete", entry_payload("files.location.documents", "nested", nested))
check("session delete refuses a non-empty directory", status == 1 and result.get("ok") is False, str(result))
check("session delete non-empty uses payload.invalid", result.get("code") == "payload.invalid", str(result))
check("the nested tree is untouched", (nested / "child.txt").is_file())

status, result = run("files-entry-delete", {"locationId": "files.location.trash", "entryRelativePath": "gone.txt", "entryId": "files.entry." + "0" * 64})
check("session delete refuses Trash location misuse", status == 1 and result.get("ok") is False, str(result))
check("session delete Trash misuse uses payload.invalid", result.get("code") == "payload.invalid", str(result))

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session move and permanent delete report success and honest refusal"

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
const move = Model.sessionMovePlan(document, 'files.location.desktop', '', 'report.txt')
assertEqual(move.action, 'move', 'a Documents file can cut to Desktop')
assertEqual(move.entryId, 'files.entry.abc', 'move keeps the entry identity')
assertEqual(move.destinationLocationId, 'files.location.desktop', 'move names the destination location')
assertEqual(move.destinationParentRelativePath, '', 'move names the destination parent')
assertEqual(move.destinationName, 'report.txt', 'move keeps the source name')
assert(Model.sessionMutateCanSubmit(move), 'Documents cut can submit')

const symlink = Model.sessionMovePlan({ ...document, status: 'symlink' }, 'files.location.desktop', '', 'report.txt')
assertEqual(symlink.action, 'unavailable', 'a symlink cannot be cut')
assert(!Model.sessionMutateCanSubmit(symlink), 'symlink cut cannot submit')

const folder = Model.sessionMovePlan({ ...document, entryKind: 'directory' }, 'files.location.desktop', '', 'report.txt')
assertEqual(folder.action, 'unavailable', 'a directory cannot be cut')
assert(String(folder.reason || '').indexOf('regular files') >= 0, 'directory cut names the regular-file bound')

const music = Model.sessionMovePlan({ ...document, locationId: 'files.location.music' }, 'files.location.desktop', '', 'report.txt')
assertEqual(music.action, 'unavailable', 'music is outside the session move locations')

const trashSource = Model.sessionMovePlan({ ...document, locationId: 'files.location.trash' }, 'files.location.desktop', '', 'report.txt')
assertEqual(trashSource.action, 'unavailable', 'Trash cannot be cut')

const trashDest = Model.sessionMovePlan(document, 'files.location.trash', '', 'report.txt')
assertEqual(trashDest.action, 'unavailable', 'Trash is not a move destination')
assert(String(trashDest.reason || '').toLowerCase().indexOf('trash') >= 0, 'Trash dest names the refuse')

const sameRename = Model.sessionMovePlan(document, 'files.location.documents', '', 'renamed.txt')
assertEqual(sameRename.action, 'unavailable', 'same-directory name changes stay on Rename')

const deletePlan = Model.sessionDeletePlan(document)
assertEqual(deletePlan.action, 'delete', 'a Documents file can be permanently deleted')
assertEqual(deletePlan.entryId, 'files.entry.abc', 'delete keeps the entry identity')
assert(Model.sessionMutateCanSubmit(deletePlan), 'Documents delete can submit')

const trashDelete = Model.sessionDeletePlan({ ...document, locationId: 'files.location.trash' })
assertEqual(trashDelete.action, 'unavailable', 'Trash cannot be permanently deleted')
assert(String(trashDelete.reason || '').indexOf('Empty') >= 0, 'Trash delete points at Empty Bin')

assertEqual(Model.sessionMovableRecord(document), true, 'Documents file is session-movable')
assertEqual(Model.sessionDeletableRecord(document), true, 'Documents file is session-deletable')
assertEqual(Model.sessionMovableRecord({ ...document, entryKind: 'directory' }), false, 'directories are not session-movable')
assertEqual(Model.sessionDeletableRecord({ ...document, entryKind: 'directory' }), true, 'directories may be planned for permanent delete')
JS

pass "Files model plans session move and permanent delete"

python3 - "$catalog" <<'PY'
import json
import sys

catalog = json.loads(open(sys.argv[1], encoding="utf-8").read())
by_id = {entry["id"]: entry for entry in catalog["capabilities"]}

move = by_id["files.entry.move"]
route = move["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Files":
    raise SystemExit(f"files.entry.move route is {route}")
if route.get("path") != "Files > Cut":
    raise SystemExit(f"files.entry.move path is {route}")
if move.get("source", {}).get("file") != "shell/apps/shared/FilesSessionMutate.qml":
    raise SystemExit(f"files.entry.move source is {move.get('source')}")
if move.get("source", {}).get("symbol") != "moveRecord":
    raise SystemExit(f"files.entry.move source is {move.get('source')}")
if move.get("availability", {}).get("claim") == "present":
    raise SystemExit("files.entry.move must not claim present")
if move.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"files.entry.move claim is {move.get('availability')}")
if move.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"files.entry.move human availability is {move.get('availability')}")

delete = by_id["files.entry.delete"]
route = delete["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Files":
    raise SystemExit(f"files.entry.delete route is {route}")
if route.get("path") != "Files > Permanently delete":
    raise SystemExit(f"files.entry.delete path is {route}")
if delete.get("source", {}).get("file") != "shell/apps/shared/FilesSessionMutate.qml":
    raise SystemExit(f"files.entry.delete source is {delete.get('source')}")
if delete.get("source", {}).get("symbol") != "deleteRecord":
    raise SystemExit(f"files.entry.delete source is {delete.get('source')}")
if delete.get("availability", {}).get("claim") == "present":
    raise SystemExit("files.entry.delete must not claim present")
if delete.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"files.entry.delete claim is {delete.get('availability')}")
PY

pass "cut/delete writers stay leftover partial with visible Files routes"
