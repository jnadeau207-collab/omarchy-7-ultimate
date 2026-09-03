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
(home / "Documents" / "archive").mkdir()
os.environ["HOME"] = str(home)
os.environ["USERPROFILE"] = str(home)

from omarchy_fabric.helpers import session_apply as sa

failures = []


def check(label, condition, detail=""):
    if not condition:
        failures.append(f"{label}{': ' + detail if detail else ''}")


def run(payload):
    stream = io.StringIO()
    status = sa.main(["files-entry-move"], io.StringIO(json.dumps(payload)), stream)
    return status, json.loads(stream.getvalue())


def directory_resource(location_id, parent, entry_id):
    return sa.stable_move_directory_id(location_id, parent, entry_id)


def entry_payload(location_id, relative, path, dest_location, dest_parent, dest_name, resource=None):
    info = path.lstat()
    entry_id = sa.stable_entry_id(location_id, info.st_dev, info.st_ino, relative)
    return {
        "resourceId": resource if resource is not None else directory_resource(dest_location, dest_parent, entry_id),
        "locationId": location_id,
        "entryRelativePath": relative,
        "entryId": entry_id,
        "destinationLocationId": dest_location,
        "destinationParentRelativePath": dest_parent,
        "destinationName": dest_name,
    }


source = home / "Documents" / "report.txt"
source.write_text("hello", encoding="utf-8")
payload = entry_payload("files.location.documents", "report.txt", source, "files.location.documents", "archive", "report.txt")
status, result = run(payload)
moved = home / "Documents" / "archive" / "report.txt"
check("a same-location move relocates the file", status == 0 and result.get("ok") and result.get("moved") and moved.is_file(), json.dumps(result))
check("the source leaves its original directory", not source.exists(), str(source.exists()))
check("the destination holds the source bytes", moved.read_text(encoding="utf-8") == "hello", moved.read_text(encoding="utf-8") if moved.exists() else "missing")

status, result = run({**payload, "desired": {"names": []}})
check("rollback desired restores the source path", status == 0 and result.get("ok") and source.is_file() and not moved.exists(), json.dumps(result))
check("rollback restores the source bytes", source.read_text(encoding="utf-8") == "hello" if source.exists() else False, source.read_text(encoding="utf-8") if source.exists() else "missing")

payload = entry_payload("files.location.documents", "report.txt", source, "files.location.desktop", "", "report.txt")
status, result = run(payload)
desktop = home / "Desktop" / "report.txt"
check("a cross-location move writes into the destination location", status == 0 and result.get("ok") and desktop.is_file(), json.dumps(result))
check("cross-location move removes the source", not source.exists(), str(source.exists()))
check("cross-location dest holds the source bytes", desktop.read_text(encoding="utf-8") == "hello" if desktop.exists() else False, desktop.read_text(encoding="utf-8") if desktop.exists() else "missing")

status, result = run({**payload, "desired": {"names": []}})
check("cross-location rollback restores the source", status == 0 and source.is_file() and not desktop.exists(), json.dumps(result))

same = entry_payload("files.location.documents", "report.txt", source, "files.location.documents", "", "report.txt")
status, result = run(same)
check("the same path is a no-op", status == 0 and result.get("ok") and result.get("moved") is False and source.is_file(), json.dumps(result))

rename_shaped = entry_payload("files.location.documents", "report.txt", source, "files.location.documents", "", "memo.txt")
status, result = run(rename_shaped)
check("a same-directory name change refuses", result.get("code") == "payload.invalid", json.dumps(result))
check("same-directory refuse leaves the original", source.is_file() and not (home / "Documents" / "memo.txt").exists(), str(source.exists()))

payload = entry_payload("files.location.documents", "report.txt", source, "files.location.desktop", "", "report.txt")
drifted = dict(payload)
drifted["entryId"] = "files.entry." + "0" * 64
drifted["resourceId"] = directory_resource("files.location.desktop", "", drifted["entryId"])
status, result = run(drifted)
check("a drifted entry identity refuses", result.get("code") == "resource.drifted", json.dumps(result))

traversal = dict(payload)
traversal["entryRelativePath"] = "../etc/passwd"
status, result = run(traversal)
check("a traversal path refuses", result.get("code") in {"payload.invalid", "payload.out-of-range"}, json.dumps(result))

absolute = dict(payload)
absolute["entryRelativePath"] = "/tmp/report.txt"
status, result = run(absolute)
check("an absolute path refuses", result.get("code") == "payload.invalid", json.dumps(result))

nested = dict(payload)
nested["destinationName"] = "nested/memo.txt"
status, result = run(nested)
check("a destination name with a separator refuses", result.get("code") == "payload.invalid", json.dumps(result))

collision = home / "Desktop" / "taken.txt"
collision.write_text("no", encoding="utf-8")
status, result = run(entry_payload("files.location.documents", "report.txt", source, "files.location.desktop", "", "taken.txt"))
check("a collision refuses", result.get("code") == "apply.exists", json.dumps(result))
check("collision leaves the original in place", source.is_file() and collision.read_text(encoding="utf-8") == "no", str(source.exists()))

wrong_resource = dict(payload)
wrong_resource["resourceId"] = sa.stable_directory_id("files.location.desktop", "")
status, result = run(wrong_resource)
check("a parent-only directory resource refuses", result.get("code") == "payload.invalid", json.dumps(result))

workspace = dict(payload)
workspace["resourceId"] = "files.workspace.primary"
status, result = run(workspace)
check("a workspace resource refuses", result.get("code") == "payload.invalid", json.dumps(result))

link = home / "Documents" / "alias.txt"
link.symlink_to(source)
status, result = run(entry_payload("files.location.documents", "alias.txt", link, "files.location.desktop", "", "safe.txt"))
check("a symlink refuses", result.get("code") == "payload.invalid", json.dumps(result))

folder = home / "Documents" / "reports"
folder.mkdir()
status, result = run(entry_payload("files.location.documents", "reports", folder, "files.location.desktop", "", "reports-moved"))
check("a directory refuses", result.get("code") == "payload.invalid", json.dumps(result))

trash_file = home / "Documents" / "trashed.txt"
trash_file.write_text("x", encoding="utf-8")
status, result = run(entry_payload("files.location.trash", "trashed.txt", trash_file, "files.location.desktop", "", "restored.txt"))
check("a Trash source refuses", result.get("code") == "payload.invalid", json.dumps(result))
check("Trash refuse does not move the file", trash_file.is_file() and not (home / "Desktop" / "restored.txt").exists(), str(trash_file.exists()))

status, result = run(entry_payload("files.location.documents", "report.txt", source, "files.location.trash", "", "dumped.txt"))
check("a Trash destination refuses", result.get("code") == "payload.invalid", json.dumps(result))
check("Trash dest refuse leaves the source", source.is_file(), str(source.exists()))

if failures:
    import sys
    print("\n".join(f"not ok - {item}" for item in failures), file=sys.stderr)
    raise SystemExit(1)
PY
pass "the Move helper relocates a scoped file and refuses drift, traversal, collision, rename-shaped same-directory, parent-only scope, symlinks, directories, and Trash"
