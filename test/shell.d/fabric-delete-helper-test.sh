#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python

cd "$ROOT/default/fabric"
PYTHONPATH="$ROOT/default/fabric" PYTHONDONTWRITEBYTECODE=1 python - <<'PY'
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


def run(payload):
    stream = io.StringIO()
    status = sa.main(["files-entry-delete"], io.StringIO(json.dumps(payload)), stream)
    return status, json.loads(stream.getvalue())


def directory_resource(location_id, parent, entry_id):
    return sa.stable_delete_directory_id(location_id, parent, entry_id)


def entry_payload(location_id, relative, path, resource=None):
    info = path.lstat()
    entry_id = sa.stable_entry_id(location_id, info.st_dev, info.st_ino, relative)
    parent = "/".join(relative.split("/")[:-1])
    return {
        "resourceId": resource if resource is not None else directory_resource(location_id, parent, entry_id),
        "locationId": location_id,
        "entryRelativePath": relative,
        "entryId": entry_id,
    }


source = home / "Documents" / "report.txt"
source.write_text("hello", encoding="utf-8")
payload = entry_payload("files.location.documents", "report.txt", source)
status, result = run(payload)
check("a regular file is unlinked", status == 0 and result.get("ok") and result.get("deleted") and not source.exists(), json.dumps(result))

source.write_text("hello", encoding="utf-8")
payload = entry_payload("files.location.documents", "report.txt", source)
drifted = dict(payload)
drifted["entryId"] = "files.entry." + "0" * 64
drifted["resourceId"] = directory_resource("files.location.documents", "", drifted["entryId"])
status, result = run(drifted)
check("a drifted entry identity refuses", result.get("code") == "resource.drifted", json.dumps(result))
check("drift refuse leaves the file", source.is_file(), str(source.exists()))

traversal = dict(payload)
traversal["entryRelativePath"] = "../etc/passwd"
status, result = run(traversal)
check("a traversal path refuses", result.get("code") in {"payload.invalid", "payload.out-of-range"}, json.dumps(result))

absolute = dict(payload)
absolute["entryRelativePath"] = "/tmp/report.txt"
status, result = run(absolute)
check("an absolute path refuses", result.get("code") == "payload.invalid", json.dumps(result))

wrong_resource = dict(payload)
wrong_resource["resourceId"] = sa.stable_directory_id("files.location.documents", "")
status, result = run(wrong_resource)
check("a parent-only directory resource refuses", result.get("code") == "payload.invalid", json.dumps(result))

workspace = dict(payload)
workspace["resourceId"] = "files.workspace.primary"
status, result = run(workspace)
check("a workspace resource refuses", result.get("code") == "payload.invalid", json.dumps(result))

link = home / "Documents" / "alias.txt"
link.symlink_to(source)
status, result = run(entry_payload("files.location.documents", "alias.txt", link))
check("a symlink refuses", result.get("code") == "payload.invalid", json.dumps(result))
check("symlink refuse leaves the target", source.is_file() and link.is_symlink(), str(source.exists()))

folder = home / "Documents" / "reports"
folder.mkdir()
(folder / "notes.txt").write_text("keep", encoding="utf-8")
status, result = run(entry_payload("files.location.documents", "reports", folder))
check("a non-empty directory refuses", result.get("code") == "payload.invalid", json.dumps(result))
check("non-empty refuse leaves the tree", folder.is_dir() and (folder / "notes.txt").is_file(), str(folder.exists()))

empty = home / "Documents" / "empty-folder"
empty.mkdir()
status, result = run(entry_payload("files.location.documents", "empty-folder", empty))
check("an empty directory is removed with rmdir", status == 0 and result.get("ok") and result.get("deleted") and not empty.exists(), json.dumps(result))

trash_file = home / "Documents" / "trashed.txt"
trash_file.write_text("x", encoding="utf-8")
status, result = run(entry_payload("files.location.trash", "trashed.txt", trash_file))
check("a Trash location refuses", result.get("code") == "payload.invalid", json.dumps(result))
check("Trash refuse leaves the file", trash_file.is_file(), str(trash_file.exists()))

if failures:
    import sys
    print("\n".join(f"not ok - {item}" for item in failures), file=sys.stderr)
    raise SystemExit(1)
PY
pass "the Delete helper unlinks a scoped file, rmdirs an empty directory, and refuses drift, traversal, parent-only scope, symlinks, non-empty trees, and Trash"
