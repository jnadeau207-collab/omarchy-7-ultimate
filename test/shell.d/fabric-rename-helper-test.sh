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
os.environ["HOME"] = str(home)
os.environ["USERPROFILE"] = str(home)

from omarchy_fabric.helpers import session_apply as sa

failures = []


def check(label, condition, detail=""):
    if not condition:
        failures.append(f"{label}{': ' + detail if detail else ''}")


def run(payload):
    stream = io.StringIO()
    status = sa.main(["files-entry-rename"], io.StringIO(json.dumps(payload)), stream)
    return status, json.loads(stream.getvalue())


def directory_resource(location_id, relative, entry_id):
    parent = relative.rsplit("/", 1)[0] if "/" in relative else ""
    return sa.stable_rename_directory_id(location_id, parent, entry_id)


def entry_payload(location_id, relative, path, new_name, resource=None):
    info = path.lstat()
    entry_id = sa.stable_entry_id(location_id, info.st_dev, info.st_ino, relative)
    return {
        "resourceId": resource if resource is not None else directory_resource(location_id, relative, entry_id),
        "locationId": location_id,
        "entryRelativePath": relative,
        "entryId": entry_id,
        "newName": new_name,
    }


target = home / "Documents" / "report.txt"
target.write_text("hello", encoding="utf-8")
payload = entry_payload("files.location.documents", "report.txt", target, "memo.txt")
status, result = run(payload)
moved = home / "Documents" / "memo.txt"
check("a same-directory rename moves the file", status == 0 and result.get("ok") and result.get("renamed") and moved.is_file(), json.dumps(result))
check("the original name is gone", not target.exists(), str(target.exists()))
check("contents are preserved", moved.read_text(encoding="utf-8") == "hello", moved.read_text(encoding="utf-8") if moved.exists() else "missing")

status, result = run({**payload, "desired": {"names": ["report.txt"]}})
check("rollback desired restores the original name", status == 0 and result.get("ok") and target.is_file() and not moved.exists(), json.dumps(result))

payload = entry_payload("files.location.documents", "report.txt", target, "memo.txt")
drifted = dict(payload)
drifted["entryId"] = "files.entry." + "0" * 64
drifted["resourceId"] = directory_resource("files.location.documents", "report.txt", drifted["entryId"])
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
nested["newName"] = "nested/memo.txt"
status, result = run(nested)
check("a new name with a separator refuses", result.get("code") == "payload.invalid", json.dumps(result))

collision = home / "Documents" / "taken.txt"
collision.write_text("no", encoding="utf-8")
status, result = run(entry_payload("files.location.documents", "report.txt", target, "taken.txt"))
check("a collision refuses", result.get("code") == "apply.exists", json.dumps(result))
check("collision leaves the original in place", target.is_file() and collision.read_text(encoding="utf-8") == "no", str(target.exists()))

wrong_resource = dict(payload)
wrong_resource["resourceId"] = sa.stable_directory_id("files.location.documents", "")
status, result = run(wrong_resource)
check("a parent-only directory resource refuses", result.get("code") == "payload.invalid", json.dumps(result))

workspace = dict(payload)
workspace["resourceId"] = "files.workspace.primary"
status, result = run(workspace)
check("a workspace resource refuses", result.get("code") == "payload.invalid", json.dumps(result))

link = home / "Documents" / "alias.txt"
link.symlink_to(target)
status, result = run(entry_payload("files.location.documents", "alias.txt", link, "safe.txt"))
check("a symlink refuses", result.get("code") == "payload.invalid", json.dumps(result))

trash_file = home / "Documents" / "trashed.txt"
trash_file.write_text("x", encoding="utf-8")
status, result = run(entry_payload("files.location.trash", "trashed.txt", trash_file, "restored.txt"))
check("a Trash location refuses", result.get("code") == "payload.invalid", json.dumps(result))
check("Trash refuse does not move the file", trash_file.is_file(), str(trash_file.exists()))

if failures:
    print("\n".join(f"not ok - {item}" for item in failures), file=sys.stderr)
    raise SystemExit(1)
PY
pass "the Rename helper moves in-place and refuses drift, traversal, collision, parent-only scope, symlinks, and Trash"
