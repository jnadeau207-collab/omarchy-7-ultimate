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
    status = sa.main(["files-entry-copy"], io.StringIO(json.dumps(payload)), stream)
    return status, json.loads(stream.getvalue())


def directory_resource(location_id, parent, entry_id):
    return sa.stable_copy_directory_id(location_id, parent, entry_id)


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
payload = entry_payload("files.location.documents", "report.txt", source, "files.location.documents", "", "report (2).txt")
status, result = run(payload)
replica = home / "Documents" / "report (2).txt"
check("a same-directory copy writes a new file", status == 0 and result.get("ok") and result.get("copied") and replica.is_file(), json.dumps(result))
check("the source stays in place", source.is_file() and source.read_text(encoding="utf-8") == "hello", str(source.exists()))
check("the replica holds the source bytes", replica.read_text(encoding="utf-8") == "hello", replica.read_text(encoding="utf-8") if replica.exists() else "missing")

status, result = run({**payload, "desired": {"names": ["report.txt"]}})
check("rollback desired removes the replica", status == 0 and result.get("ok") and source.is_file() and not replica.exists(), json.dumps(result))

payload = entry_payload("files.location.documents", "report.txt", source, "files.location.desktop", "", "report.txt")
status, result = run(payload)
desktop_copy = home / "Desktop" / "report.txt"
check("a cross-location copy writes into the destination location", status == 0 and result.get("ok") and desktop_copy.is_file(), json.dumps(result))
check("cross-location copy keeps the source", source.is_file() and source.read_text(encoding="utf-8") == "hello", str(source.exists()))
check("cross-location replica holds the source bytes", desktop_copy.read_text(encoding="utf-8") == "hello" if desktop_copy.exists() else False, desktop_copy.read_text(encoding="utf-8") if desktop_copy.exists() else "missing")

payload = entry_payload("files.location.documents", "report.txt", source, "files.location.documents", "", "report (2).txt")
drifted = dict(payload)
drifted["entryId"] = "files.entry." + "0" * 64
drifted["resourceId"] = directory_resource("files.location.documents", "", drifted["entryId"])
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

collision = home / "Documents" / "taken.txt"
collision.write_text("no", encoding="utf-8")
status, result = run(entry_payload("files.location.documents", "report.txt", source, "files.location.documents", "", "taken.txt"))
check("a collision refuses", result.get("code") == "apply.exists", json.dumps(result))
check("collision leaves the original in place", source.is_file() and collision.read_text(encoding="utf-8") == "no", str(source.exists()))

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
status, result = run(entry_payload("files.location.documents", "alias.txt", link, "files.location.documents", "", "safe.txt"))
check("a symlink refuses", result.get("code") == "payload.invalid", json.dumps(result))

folder = home / "Documents" / "reports"
folder.mkdir()
status, result = run(entry_payload("files.location.documents", "reports", folder, "files.location.documents", "", "reports-copy"))
check("a directory refuses", result.get("code") == "payload.invalid", json.dumps(result))

trash_file = home / "Documents" / "trashed.txt"
trash_file.write_text("x", encoding="utf-8")
status, result = run(entry_payload("files.location.trash", "trashed.txt", trash_file, "files.location.documents", "", "restored.txt"))
check("a Trash source refuses", result.get("code") == "payload.invalid", json.dumps(result))
check("Trash refuse does not copy the file", trash_file.is_file() and not (home / "Documents" / "restored.txt").exists(), str(trash_file.exists()))

status, result = run(entry_payload("files.location.documents", "report.txt", source, "files.location.trash", "", "dumped.txt"))
check("a Trash destination refuses", result.get("code") == "payload.invalid", json.dumps(result))

if failures:
    print("\n".join(f"not ok - {item}" for item in failures), file=sys.stderr)
    raise SystemExit(1)
PY
pass "the Copy helper writes a scoped replica and refuses drift, traversal, collision, parent-only scope, symlinks, directories, and Trash"
