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
import sys
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


def directory_resource(location_id, relative):
    parent = relative.rsplit("/", 1)[0] if "/" in relative else ""
    return sa.stable_directory_id(location_id, parent)


def entry_payload(location_id, relative, path, resource=None):
    info = path.lstat()
    return {
        "resourceId": resource if resource is not None else directory_resource(location_id, relative),
        "locationId": location_id,
        "entryRelativePath": relative,
        "entryId": sa.stable_entry_id(location_id, info.st_dev, info.st_ino, relative),
    }


def restore_payload(location_id, relative, trash_file):
    info = trash_file.lstat()
    return {
        "resourceId": directory_resource(location_id, relative),
        "locationId": location_id,
        "entryRelativePath": relative,
        "entryId": sa.stable_entry_id("files.location.trash", info.st_dev, info.st_ino, trash_file.name),
    }


import atexit


def report():
    for failure in failures:
        print(f"not ok - {failure}", file=sys.stderr)


atexit.register(report)

trash = home / ".local" / "share" / "Trash"
target = home / "Documents" / "report.txt"
target.write_text("hello", encoding="utf-8")

status, result = run("files-entry-trash", entry_payload("files.location.documents", "report.txt", target))
check("an ordinary entry moves to Trash", status == 0 and result.get("ok"), json.dumps(result))
check("the original is gone", not target.exists())
check("the entry is in the Trash files directory", (trash / "files" / "report.txt").is_file())

record = (trash / "info" / "report.txt.trashinfo").read_text(encoding="utf-8")
check("the Trash record is a freedesktop record", record.startswith("[Trash Info]\nPath="), record)
check("the Trash record carries a deletion date", "\nDeletionDate=" in record, record)

moved = (trash / "files" / "report.txt")
status, result = run("files-trash-restore", restore_payload("files.location.documents", "report.txt", moved))
check("a trashed entry restores", status == 0 and result.get("ok"), json.dumps(result))
check("the entry is back where it was", target.is_file())
check("the restored content is intact", target.read_text(encoding="utf-8") == "hello")
check("the Trash record is cleaned up", not (trash / "info" / "report.txt.trashinfo").exists())

def fresh(name, body="x"):
    path = home / "Documents" / name
    path.write_text(body, encoding="utf-8")
    return path


second = fresh("drift.txt")
drifted = entry_payload("files.location.documents", "drift.txt", second)
drifted["entryId"] = "files.entry." + "0" * 64
status, result = run("files-entry-trash", drifted)
check("an entry id that does not match the inode refuses", result.get("code") == "resource.drifted", json.dumps(result))
check("the drifted entry is untouched", second.is_file())

traversal = entry_payload("files.location.documents", "drift.txt", second)
traversal["entryRelativePath"] = "../../../etc/passwd"
status, result = run("files-entry-trash", traversal)
check("a traversal path refuses", result.get("code") == "payload.invalid", json.dumps(result))

absolute = entry_payload("files.location.documents", "drift.txt", second)
absolute["entryRelativePath"] = "/etc/passwd"
status, result = run("files-entry-trash", absolute)
check("an absolute path refuses", result.get("code") == "payload.invalid", json.dumps(result))

unwritable = entry_payload("files.location.documents", "drift.txt", second)
unwritable["locationId"] = "files.location.trash"
status, result = run("files-entry-trash", unwritable)
check("a non-writable location refuses", result.get("code") == "resource.unresolved", json.dumps(result))

wrong_resource = entry_payload("files.location.documents", "drift.txt", second)
wrong_resource["resourceId"] = "audio.sink." + "a" * 64
status, result = run("files-entry-trash", wrong_resource)
check("a foreign resource kind refuses", result.get("code") == "payload.invalid", json.dumps(result))

workspace_resource = entry_payload("files.location.documents", "drift.txt", second)
workspace_resource["resourceId"] = "files.workspace.primary"
status, result = run("files-entry-trash", workspace_resource)
check("a workspace resource refuses", result.get("code") == "payload.invalid", json.dumps(result))
check("the workspace-scoped entry is untouched", second.is_file())

status, result = run("files-trash-restore", entry_payload("files.location.documents", "drift.txt", second))
check("restoring an entry that is not in Trash refuses", result.get("code") == "resource.unresolved", json.dumps(result))

run("files-entry-trash", entry_payload("files.location.documents", "report.txt", target))
occupant = home / "Documents" / "report.txt"
occupant.write_text("newer", encoding="utf-8")
trashed = trash / "files" / "report.txt"
status, result = run("files-trash-restore", restore_payload("files.location.documents", "report.txt", trashed))
check("restoring onto an occupied original location refuses", result.get("code") == "apply.exists", json.dumps(result))
check("the occupant is untouched", occupant.read_text(encoding="utf-8") == "newer")

collision = home / "Documents" / "report.txt"
status, result = run("files-entry-trash", entry_payload("files.location.documents", "report.txt", collision))
check("a colliding Trash name is given a distinct name", result.get("trashName") not in (None, "report.txt"), json.dumps(result))
check("the earlier trashed entry is not overwritten", trashed.read_text(encoding="utf-8") == "hello")

escaped = trash / "info" / "escaped.trashinfo"
escaped.parent.mkdir(parents=True, exist_ok=True)
(trash / "files" / "escaped").write_text("x", encoding="utf-8")
escaped.write_text(sa.trash_info_document(pathlib.Path(tempfile.mkdtemp()) / "outside.txt", "2026-01-01T00:00:00"), encoding="utf-8")
outside = trash / "files" / "escaped"
status, result = run("files-trash-restore", restore_payload("files.location.documents", "escaped.txt", outside))
check("a Trash record pointing outside home refuses", result.get("code") == "payload.invalid", json.dumps(result))

if failures:
    raise SystemExit(1)
PY
pass "the Trash helper moves, records, restores, and refuses drift, traversal, escape, and collision"
