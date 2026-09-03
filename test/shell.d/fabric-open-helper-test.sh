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
import sys
import tempfile

os.environ.pop("XDG_DATA_HOME", None)
home = pathlib.Path(tempfile.mkdtemp()) / "home"
(home / "Documents").mkdir(parents=True)
os.environ["HOME"] = str(home)
os.environ["USERPROFILE"] = str(home)

from omarchy_fabric.helpers import session_apply as sa

failures = []
opened = []


def check(label, condition, detail=""):
    if not condition:
        failures.append(f"{label}{': ' + detail if detail else ''}")


def fake_open(path, run=None):
    opened.append(str(path))


sa.apply_open = fake_open


def run(payload):
    stream = io.StringIO()
    status = sa.main(["files-entry-open"], io.StringIO(json.dumps(payload)), stream)
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


target = home / "Documents" / "report.txt"
target.write_text("hello", encoding="utf-8")
payload = entry_payload("files.location.documents", "report.txt", target)
status, result = run(payload)
check("a regular file launches xdg-open", status == 0 and result.get("ok") and result.get("launched"), json.dumps(result))
check("xdg-open receives the resolved path", opened == [str(target)], str(opened))

drifted = dict(payload)
drifted["entryId"] = "files.entry." + "0" * 64
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

folder = home / "Documents" / "Reports"
folder.mkdir()
status, result = run(entry_payload("files.location.documents", "Reports", folder))
check("a directory refuses", result.get("code") == "payload.invalid", json.dumps(result))

link = home / "Documents" / "alias.txt"
link.symlink_to(target)
status, result = run(entry_payload("files.location.documents", "alias.txt", link))
check("a symlink refuses", result.get("code") == "payload.invalid", json.dumps(result))

trash_file = home / "Documents" / "trashed.txt"
trash_file.write_text("x", encoding="utf-8")
status, result = run(entry_payload("files.location.trash", "trashed.txt", trash_file))
check("a Trash location refuses", result.get("code") == "payload.invalid", json.dumps(result))

before = len(opened)
status, result = run({**payload, "desired": {"names": ["report.txt"]}})
check("rollback desired does not launch", status == 0 and result.get("launched") is False, json.dumps(result))
check("rollback does not call xdg-open", len(opened) == before, str(opened))

if failures:
    print("\n".join(f"not ok - {item}" for item in failures), file=sys.stderr)
    raise SystemExit(1)
PY
pass "the Open helper launches by path and refuses drift, traversal, directories, symlinks, and Trash"
