#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

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
    return status, json.loads(stream.getvalue())


def manage_payload(resource=None):
    return {
        "resourceId": resource if resource is not None else sa.stable_directory_id("files.location.trash", ""),
        "locationId": "files.location.trash",
        "parentRelativePath": "",
    }


def entry_payload(location_id, relative, path):
    info = path.lstat()
    parent = "/".join(relative.split("/")[:-1])
    return {
        "resourceId": sa.stable_directory_id(location_id, parent),
        "locationId": location_id,
        "entryRelativePath": relative,
        "entryId": sa.stable_entry_id(location_id, info.st_dev, info.st_ino, relative),
    }


source = home / "Documents" / "report.txt"
source.write_text("hello", encoding="utf-8")
status, result = run("files-entry-trash", entry_payload("files.location.documents", "report.txt", source))
check("an ordinary file can be moved to Trash first", status == 0 and result.get("ok"), json.dumps(result))
trash_file = home / ".local" / "share" / "Trash" / "files" / "report.txt"
info_file = home / ".local" / "share" / "Trash" / "info" / "report.txt.trashinfo"
check("Trash holds the file and trashinfo", trash_file.is_file() and info_file.is_file(), str(trash_file.exists()))

status, result = run("files-trash-manage", manage_payload())
check("Empty Bin unlinks a regular Trash file", status == 0 and result.get("ok") and result.get("emptied") and result.get("count") == 1, json.dumps(result))
check("Empty Bin removes the file and trashinfo", not trash_file.exists() and not info_file.exists(), str(trash_file.exists()))

status, result = run("files-trash-manage", manage_payload())
check("an already empty Trash is a no-op", status == 0 and result.get("ok") and result.get("emptied") is False and result.get("count") == 0, json.dumps(result))

wrong_location = manage_payload()
wrong_location["locationId"] = "files.location.documents"
status, result = run("files-trash-manage", wrong_location)
check("a non-Trash location refuses", result.get("code") == "payload.invalid", json.dumps(result))

wrong_resource = manage_payload(sa.stable_directory_id("files.location.documents", ""))
status, result = run("files-trash-manage", wrong_resource)
check("a non-Trash directory resource refuses", result.get("code") == "payload.invalid", json.dumps(result))

nested = manage_payload()
nested["parentRelativePath"] = "nested"
status, result = run("files-trash-manage", nested)
check("a nested Trash path refuses", result.get("code") == "payload.invalid", json.dumps(result))

empty = home / "Documents" / "empty-folder"
empty.mkdir()
status, result = run("files-entry-trash", entry_payload("files.location.documents", "empty-folder", empty))
check("an empty directory can be moved to Trash", status == 0 and result.get("ok"), json.dumps(result))
status, result = run("files-trash-manage", manage_payload())
check("Empty Bin rmdirs an empty Trash directory", status == 0 and result.get("ok") and result.get("emptied"), json.dumps(result))

folder = home / "Documents" / "reports"
folder.mkdir()
(folder / "notes.txt").write_text("keep", encoding="utf-8")
status, result = run("files-entry-trash", entry_payload("files.location.documents", "reports", folder))
check("a directory tree can be moved to Trash", status == 0 and result.get("ok"), json.dumps(result))
tree = home / ".local" / "share" / "Trash" / "files" / "reports"
status, result = run("files-trash-manage", manage_payload())
check("a non-empty Trash tree refuses", result.get("code") == "payload.invalid", json.dumps(result))
check("tree refuse leaves the Trash folder", tree.is_dir() and (tree / "notes.txt").is_file(), str(tree.exists()))

link_target = home / "Documents" / "keep.txt"
link_target.write_text("keep", encoding="utf-8")
status, result = run("files-entry-trash", entry_payload("files.location.documents", "keep.txt", link_target))
check("a second file can be moved to Trash for the symlink case", status == 0 and result.get("ok"), json.dumps(result))
# The leftover tree still refuses Empty Bin; isolate a symlink-only Trash.
import shutil
shutil.rmtree(home / ".local" / "share" / "Trash")
(home / ".local" / "share" / "Trash" / "files").mkdir(parents=True)
(home / ".local" / "share" / "Trash" / "info").mkdir(parents=True)
alias = home / ".local" / "share" / "Trash" / "files" / "alias.txt"
alias.symlink_to(home / "Documents")
status, result = run("files-trash-manage", manage_payload())
check("a symlink refuses", result.get("code") == "payload.invalid", json.dumps(result))
check("symlink refuse leaves the alias", alias.is_symlink(), str(alias.exists()))

if failures:
    import sys
    print("\n".join(f"not ok - {item}" for item in failures), file=sys.stderr)
    raise SystemExit(1)
PY
pass "the Empty Bin helper unlinks scoped Trash files, rmdirs empty Trash directories, and refuses drift, nested paths, non-Trash locations, symlinks, and non-empty trees"
