#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command node

helper="$ROOT/default/fabric/omarchy_fabric/helpers/session_apply.py"
files_app="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"
files_model="$ROOT/shell/apps/ultimate-files/FilesModel.js"
files_session="$ROOT/shell/apps/shared/FilesSessionProperties.qml"
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
[[ -f $files_session ]] || fail "Files hosts a session Properties plane"
[[ -f $command_bar ]] || fail "Files command bar exists"

grep -Fq '"files-entry-properties": apply_files_entry_properties' "$helper" ||
  fail "session apply owns files-entry-properties"
grep -Fq 'files-entry-properties' "$files_session" || fail "session Properties QML calls files-entry-properties"
grep -Fq 'readProperties' "$files_session" || fail "session Properties QML exposes readProperties"
grep -Fq 'omarchy-fabric-session-apply' "$files_session" ||
  fail "session Properties QML uses the session apply helper"
grep -Fq 'OMARCHY_PATH' "$files_session" || fail "session Properties QML prefers OMARCHY_PATH"
grep -Fq '/bin/omarchy-fabric-session-apply' "$files_session" ||
  fail "session Properties QML spawns omarchy-fabric-session-apply from an absolute bin path"
if grep -Eq 'return "omarchy-fabric-session-apply"|: "omarchy-fabric-session-apply"' "$files_session"; then
  fail "session Properties QML must not spawn a bare omarchy-fabric-session-apply PATH name"
fi
if grep -Eq 'operation\.(preflight|start|approve)|requestFabric' "$files_session"; then
  fail "Files Properties session plane must not mint Fabric durable operations"
fi
if grep -Eq 'action: "properties\.|action: "entry\.properties|provider: "files.provider"' "$files_session"; then
  fail "session Properties QML must not call a Fabric files.provider Properties action"
fi
if grep -Eq 'pkexec|sudo' "$files_session"; then
  fail "Files Properties QML must not spawn privilege"
fi
grep -Fq 'Shared.FilesSessionProperties' "$files_app" || fail "Files hosts the session Properties helper"
grep -Fq 'sessionReadProperties' "$files_app" || fail "Files Properties uses the session Properties plane"
grep -Fq 'key: "properties", label: "Properties"' "$files_app" || fail "Files shows a Properties control"
grep -Fq 'SESSION CONTROL' "$files_app" "$command_bar" ||
  fail "Files shows a SESSION CONTROL badge"
grep -Fq 'READ-ONLY' "$files_app" || fail "Files Properties shows a READ-ONLY badge"
if grep -Eq 'LIVE CONTROL' "$files_app" "$files_session" "$command_bar"; then
  fail "Files Properties must not invent Fabric LIVE CONTROL"
fi
if grep -Eqi 'claim=present' "$files_app" "$files_session"; then
  fail "Files Properties must not invent claim=present"
fi
if grep -Eq 'Process[[:space:]]*\{' "$files_app"; then
  fail "Files consumer QML must not host the session Process block"
fi
grep -Fq 'sessionPropertiesPlan' "$files_model" || fail "Files model plans session Properties"
grep -Fq 'sessionPropertiesReadableRecord' "$files_model" || fail "Files model gates session Properties"
grep -Fq 'Properties runs through this session' "$files_app" ||
  fail "Files banner names session Properties"
grep -Fq 'does not invent a Fabric SHELL LIVE Properties writer' "$files_app" ||
  fail "Files banner refuses a Fabric SHELL LIVE Properties writer"
if grep -Eq 'files-entry-properties' "$daemon" "$files_plane"; then
  fail "Fabric durable plane invented a files-entry-properties writer"
fi
if grep -Eq 'entry.properties|files.properties|properties.read' "$files_provider"/*.py "$files_provider"/*.json; then
  fail "files.provider invented a Fabric Properties writer"
fi
grep -Fq 'O_NOFOLLOW' "$helper" || fail "session Properties opens with O_NOFOLLOW"
grep -Fq 'MAX_PROPERTIES_PATH' "$helper" || fail "session Properties bounds location path reads"

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
    if 'key: "properties"' not in body:
        raise SystemExit(f"{name} dropped Properties")
PY

pass "Files wires a session Properties plane instead of a Fabric LIVE Properties writer"

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


notes = home / "Documents" / "notes.txt"
notes.write_text("hello", encoding="utf-8")
payload = entry_payload("files.location.documents", "notes.txt", notes)
status, result = run("files-entry-properties", payload)
check("session Properties without a resourceId succeeds", status == 0 and result.get("ok") is True, str(result))
check("session Properties reports the name", result.get("name") == "notes.txt", str(result))
check("session Properties reports a regular file", result.get("kind") == "file", str(result))
check("session Properties reports size for a regular file", result.get("sizeBytes") == 5, str(result))
check("session Properties reports modifiedMs", isinstance(result.get("modifiedMs"), int) and result.get("modifiedMs") > 0, str(result))
check("session Properties reports the location path", result.get("locationPath") == str(home / "Documents"), str(result))
check("session Properties does not invent permissions", "mode" not in result and "owner" not in result, str(result))
check("session Properties does not invent attributes", "attributes" not in result and "readonly" not in result, str(result))

album = home / "Documents" / "Album"
album.mkdir()
status, result = run("files-entry-properties", entry_payload("files.location.documents", "Album", album))
check("session Properties reads a folder", status == 0 and result.get("ok") is True, str(result))
check("session Properties names the folder", result.get("name") == "Album", str(result))
check("session Properties reports a directory", result.get("kind") == "directory", str(result))
check("session Properties omits size for a folder", result.get("sizeBytes") is None, str(result))
check("session Properties reports the folder location", result.get("locationPath") == str(home / "Documents"), str(result))

nested = album / "inside.txt"
nested.write_text("in", encoding="utf-8")
status, result = run("files-entry-properties", entry_payload("files.location.documents", "Album/inside.txt", nested))
check("session Properties reads a nested file", status == 0 and result.get("ok") is True, str(result))
check("session Properties nested location is the parent folder", result.get("locationPath") == str(album), str(result))

link = home / "Documents" / "alias.txt"
link.symlink_to("notes.txt")
status, result = run("files-entry-properties", entry_payload("files.location.documents", "alias.txt", link))
check("symlink Properties does not follow", status == 0 and result.get("ok") is True, str(result))
check("symlink Properties reports symlink kind", result.get("kind") == "symlink", str(result))
check("symlink Properties omits followed size", result.get("sizeBytes") is None, str(result))
check("symlink Properties does not invent a target path", "symlinkTarget" not in result and "target" not in result, str(result))

escaped = {
    "locationId": "files.location.documents",
    "entryRelativePath": "../Desktop/escape.txt",
    "entryId": "files.entry." + "0" * 64,
}
status, result = run("files-entry-properties", escaped)
check("path traversal is refused", status == 1 and result.get("ok") is False, str(result))
check("path traversal uses payload.invalid", result.get("code") == "payload.invalid", str(result))

trash_payload = entry_payload("files.location.documents", "notes.txt", notes)
trash_payload["locationId"] = "files.location.trash"
status, result = run("files-entry-properties", trash_payload)
check("session Properties refuses Trash", status == 1 and result.get("ok") is False, str(result))
check("session Properties Trash uses payload.invalid", result.get("code") == "payload.invalid", str(result))

status, result = run(
    "files-entry-properties",
    {
        "locationId": "files.location.documents",
        "entryRelativePath": "missing.txt",
        "entryId": "files.entry." + "0" * 64,
    },
)
check("missing entry is refused", status == 1 and result.get("ok") is False, str(result))
check("missing entry uses resource.unresolved", result.get("code") == "resource.unresolved", str(result))

status, result = run("files-entry-properties", {"locationId": "files.location.documents"})
check("empty selection is refused", status == 1 and result.get("ok") is False, str(result))
check("empty selection uses payload.invalid", result.get("code") == "payload.invalid", str(result))

status, result = run(
    "files-entry-properties",
    entry_payload("files.location.music", "notes.txt", notes),
)
check("music is outside session Properties locations", status == 1 and result.get("ok") is False, str(result))

if failures:
    raise SystemExit("\n".join(failures))
PY

pass "session Properties reports success and honest refusal"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-files/FilesModel.js')

const file = {
  id: 'files.entry.abc',
  kind: 'entry',
  entryKind: 'file',
  status: 'file',
  locationId: 'files.location.documents',
  relativePath: 'notes.txt',
  title: 'notes.txt'
}

const plan = Model.sessionPropertiesPlan(file)
assertEqual(plan.action, 'properties', 'a Documents file can show session Properties')
assertEqual(plan.entryId, 'files.entry.abc', 'Properties keeps the entry identity')
assertEqual(plan.locationId, 'files.location.documents', 'Properties keeps the location')
assert(Model.sessionPropertiesCanSubmit(plan), 'Documents Properties can submit')

const folder = Model.sessionPropertiesPlan({
  ...file,
  id: 'files.entry.dir',
  entryKind: 'directory',
  status: 'directory',
  relativePath: 'Album',
  title: 'Album'
})
assertEqual(folder.action, 'properties', 'a Documents folder can show session Properties')
assert(Model.sessionPropertiesCanSubmit(folder), 'folder Properties can submit')

const empty = Model.sessionPropertiesPlan(null)
assertEqual(empty.action, 'unavailable', 'empty selection cannot show Properties')
assert(!Model.sessionPropertiesCanSubmit(empty), 'empty Properties cannot submit')
assert(String(empty.reason || '').toLowerCase().indexOf('select') >= 0, 'empty Properties names the empty state')

const trash = Model.sessionPropertiesPlan({ ...file, locationId: 'files.location.trash' })
assertEqual(trash.action, 'unavailable', 'Trash cannot show session Properties')
assert(String(trash.reason || '').toLowerCase().indexOf('trash') >= 0, 'Trash Properties names the refuse')

const music = Model.sessionPropertiesPlan({ ...file, locationId: 'files.location.music' })
assertEqual(music.action, 'unavailable', 'music is outside the session Properties locations')

const mount = Model.sessionPropertiesPlan({ id: 'files.mount.disk', kind: 'mount', title: 'Windows7' })
assertEqual(mount.action, 'unavailable', 'This PC mounts cannot show session Properties')

assertEqual(Model.sessionPropertiesReadableRecord(file), true, 'Documents file is session-readable')
assertEqual(Model.sessionPropertiesReadableRecord({ ...file, entryKind: 'directory' }), true, 'directories are session-readable')
assertEqual(Model.sessionPropertiesReadableRecord({ ...file, locationId: 'files.location.trash' }), false, 'Trash is not session-readable')
assertEqual(Model.sessionPropertiesReadableRecord({ ...file, locationId: 'files.location.music' }), false, 'music is not session-readable')

const rows = Model.sessionPropertiesRows({
  ok: true,
  name: 'notes.txt',
  kind: 'file',
  sizeBytes: 5,
  modifiedMs: Date.parse('2026-09-06T12:00:00Z'),
  locationPath: '/tmp/home/Documents'
})
assertEqual(rows.length, 5, 'file Properties shows name, type, size, modified, location')
assertEqual(rows[0].label, 'Name', 'first row is Name')
assertEqual(rows[0].value, 'notes.txt', 'Name is the entry name')
assertEqual(rows[1].label, 'Type', 'second row is Type')
assertEqual(rows[2].label, 'Size', 'regular files include Size')
assertEqual(rows[3].label, 'Date modified', 'fourth row is Date modified')
assertEqual(rows[4].label, 'Location', 'fifth row is Location')
assertEqual(rows[4].value, '/tmp/home/Documents', 'Location is the helper path')

const folderRows = Model.sessionPropertiesRows({
  ok: true,
  name: 'Album',
  kind: 'directory',
  sizeBytes: null,
  modifiedMs: Date.parse('2026-09-06T12:00:00Z'),
  locationPath: '/tmp/home/Documents'
})
assertEqual(folderRows.some(function (row) { return row.label === 'Size' }), false, 'folders omit Size')
assertEqual(folderRows[1].value, 'File folder', 'folders use File folder type')

const errorRows = Model.sessionPropertiesRows({ ok: false, explanation: 'nope' })
assertEqual(errorRows.length, 0, 'failed Properties has no field rows')
JS

pass "Files model plans session Properties"

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
props = by_id["files.properties.read"]
route = props["humanRoute"]
if route.get("status") != "visible" or route.get("surface") != "Files":
    raise SystemExit(f"files.properties.read route is {route}")
if route.get("path") != "Files > right-click > Properties":
    raise SystemExit(f"files.properties.read path is {route}")
if route.get("label") != "View Properties":
    raise SystemExit(f"files.properties.read label is {route}")
if props.get("source", {}).get("file") != "shell/apps/shared/FilesSessionProperties.qml":
    raise SystemExit(f"files.properties.read source is {props.get('source')}")
if props.get("source", {}).get("symbol") != "readProperties":
    raise SystemExit(f"files.properties.read source is {props.get('source')}")
if "nautilus" in str(props.get("source") or "").lower():
    raise SystemExit(f"files.properties.read still names Nautilus: {props.get('source')}")
if props.get("availability", {}).get("claim") == "present":
    raise SystemExit("files.properties.read must not claim present")
if props.get("availability", {}).get("claim") != "partial":
    raise SystemExit(f"files.properties.read claim is {props.get('availability')}")
if props.get("availability", {}).get("human") != "partial":
    raise SystemExit(f"files.properties.read human availability is {props.get('availability')}")
if props.get("availability", {}).get("agent") != "unavailable":
    raise SystemExit(f"files.properties.read agent availability is {props.get('availability')}")
if props.get("provider", {}).get("state") != "legacy-direct":
    raise SystemExit(f"files.properties.read was raised off leftover: {props.get('provider')}")
if props.get("provider", {}).get("id") != "files.provider":
    raise SystemExit(f"files.properties.read provider is {props.get('provider')}")

by_job = {job["id"]: job for job in jobs["jobs"]}
parity_props = by_job["parity.properties"]
if parity_props.get("claim") == "present":
    raise SystemExit("parity.properties must not claim present")
if parity_props.get("claim") != "missing":
    raise SystemExit(f"parity.properties claim is {parity_props.get('claim')}")
if parity_props.get("sourceStatus") != "missing as product":
    raise SystemExit(f"parity.properties sourceStatus is {parity_props.get('sourceStatus')}")
if "files.properties.read" not in (parity_props.get("capabilityIds") or []):
    raise SystemExit("parity.properties dropped files.properties.read")
if parity_props["humanRoute"].get("path") != "Files > right-click > Properties":
    raise SystemExit(f"parity.properties path is {parity_props.get('humanRoute')}")
if "nautilus" in str(parity_props.get("humanRoute") or "").lower():
    raise SystemExit(f"parity.properties still names Nautilus: {parity_props.get('humanRoute')}")

explorer = by_job["parity.explorer-this-pc"]
if explorer.get("claim") == "present":
    raise SystemExit("parity.explorer-this-pc must not claim present")

by_debt = {entry["id"]: entry for entry in debt["entries"]}
legacy = by_debt["legacy.domain.direct-providers"]
if "files.properties.read" not in legacy.get("capabilityIds", []):
    raise SystemExit("files.properties.read is not leftover-direct debt")
if "capability:files.properties.read" not in legacy.get("surfaceRefs", []):
    raise SystemExit("files.properties.read leftover surfaceRef is missing")
agent = by_debt["missing.agent.routes"]
if "files.properties.read" not in agent.get("capabilityIds", []):
    raise SystemExit("files.properties.read is not agent-unavailable debt")
if "capability:files.properties.read" not in agent.get("surfaceRefs", []):
    raise SystemExit("files.properties.read agent surfaceRef is missing")

if "Honesty addendum 2026-09-06 vs Files Properties session plane" not in gaps:
    raise SystemExit("fleet-doctrine-gaps must add a dated Files Properties addendum")
addendum = gaps.split("Honesty addendum 2026-09-06 vs Files Properties session plane", 1)[1].split("Honesty addendum", 1)[0]
if "CLOSED leftover: session Properties sheet UI" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name CLOSED leftover as session Properties sheet UI")
for required in (
    "full Properties product",
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
        raise SystemExit(f"fleet-doctrine-gaps Properties addendum dropped OPEN leftover: {required}")
if "Do not invent claim=present" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse claim=present invent")
if "Cloud EXIT 0 is not metal leftover CLOSED" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Cloud EXIT 0 as metal leftover CLOSED")
if "Files > right-click > Properties" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name Files > right-click > Properties")
if "this session" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must name the session plane")
if "Do not invent Fabric SHELL LIVE Properties" not in addendum and "Do not invent Fabric LIVE under SHELL" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must refuse Fabric SHELL LIVE Properties invent")
if "parity.properties" not in addendum:
    raise SystemExit("fleet-doctrine-gaps must keep parity.properties named")

if "SESSION CONTROL" not in session and "SESSION CONTROL" not in files_app:
    raise SystemExit("session Properties must show SESSION CONTROL")
if "READ-ONLY" not in files_app:
    raise SystemExit("session Properties must show READ-ONLY")
if "LIVE CONTROL" in session:
    raise SystemExit("session Properties invented LIVE CONTROL")
if "Files > right-click > Properties" not in parity:
    raise SystemExit("PARITY must name Files > right-click > Properties")
if "session Properties" not in parity and "files-entry-properties" not in parity:
    raise SystemExit("PARITY must name session Properties without walking Explorer to present")
explorer_row = ""
properties_row = ""
for line in parity.splitlines():
    if line.startswith("| Explorer / Computer |"):
        explorer_row = line
    if line.startswith("| Properties |"):
        properties_row = line
if "this row is not present" not in explorer_row or "prototype" not in explorer_row:
    raise SystemExit("PARITY Explorer row must stay not present")
if "missing as product" not in properties_row:
    raise SystemExit("PARITY Properties row must stay missing as product")
status = properties_row.split("|")[2].strip()
if status != "missing as product":
    raise SystemExit(f"PARITY Properties row walked off missing as product: {status}")
if "files-entry-properties" not in handoff:
    raise SystemExit("HANDOFF must name files-entry-properties")
if "session Properties" not in handoff and "Files Properties session" not in handoff:
    raise SystemExit("HANDOFF must name session Properties")
if "files-entry-properties" not in project and "session Properties" not in project:
    raise SystemExit("project-ultimate must name session Properties")
if "files.properties.read" not in files_docs:
    raise SystemExit("files-defaults-provider must name files.properties.read")
if "does not invent a Fabric" not in files_docs.split("files.properties.read", 1)[1][:900]:
    raise SystemExit("files-defaults-provider must refuse a Fabric Properties writer")
PY

pass "files.properties.read stays leftover partial with a visible Files Properties route"
