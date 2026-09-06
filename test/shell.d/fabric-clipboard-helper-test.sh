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
import subprocess
import tempfile

os.environ.pop("XDG_DATA_HOME", None)
home = pathlib.Path(tempfile.mkdtemp()) / "home"
(home / "Documents").mkdir(parents=True)
(home / "Desktop").mkdir(parents=True)
os.environ["HOME"] = str(home)
os.environ["USERPROFILE"] = str(home)

from omarchy_fabric.helpers import session_apply as sa

failures = []
clipboard = {"offered": "", "paste": ""}


def check(label, condition, detail=""):
    if not condition:
        failures.append(f"{label}{': ' + detail if detail else ''}")


class Result:
    def __init__(self, returncode=0, stdout="", stderr=""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def fake_run(argv, **kwargs):
    if argv and argv[0] == sa.WL_COPY:
        clipboard["offered"] = kwargs.get("input") or ""
        return Result()
    if argv and argv[0] == sa.WL_PASTE:
        mime = argv[argv.index("--type") + 1] if "--type" in argv else ""
        if mime == "text/uri-list" and clipboard["paste"]:
            return Result(stdout=clipboard["paste"])
        return Result(returncode=1)
    raise AssertionError(argv)


def run_copy(payload):
    stream = io.StringIO()
    status = sa.apply_files_clipboard_copy(io.StringIO(json.dumps(payload)), stream, run=fake_run)
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


def run_paste(payload):
    stream = io.StringIO()
    status = sa.apply_files_clipboard_paste(io.StringIO(json.dumps(payload)), stream, run=fake_run)
    raw = stream.getvalue().strip()
    return status, json.loads(raw) if raw else {}


def copy_payload(location_id, relative, path):
    info = path.lstat()
    return {
        "entryId": sa.stable_entry_id(location_id, info.st_dev, info.st_ino, relative),
        "locationId": location_id,
        "entryRelativePath": relative,
    }


source = home / "Documents" / "memo.txt"
source.write_text("hello", encoding="utf-8")
payload = copy_payload("files.location.documents", "memo.txt", source)
status, result = run_copy(payload)
check("clipboard copy offers a file URI", status == 0 and result.get("ok") and result.get("offered") and "file:///" in clipboard["offered"], json.dumps(result) + " offered=" + clipboard["offered"])
check("clipboard copy output does not leak an absolute path", "/home/" not in json.dumps(result) and str(home) not in json.dumps(result), json.dumps(result))

folder = home / "Documents" / "notes"
folder.mkdir()
(folder / "page.txt").write_text("page", encoding="utf-8")
status, result = run_copy(copy_payload("files.location.documents", "notes", folder))
check("clipboard copy offers a directory", status == 0 and result.get("ok") and result.get("offered"), json.dumps(result))

link = home / "Documents" / "alias.txt"
link.symlink_to(source)
try:
    sa.apply_files_clipboard_copy(io.StringIO(json.dumps(copy_payload("files.location.documents", "alias.txt", link))), io.StringIO(), run=fake_run)
    check("clipboard copy refuses a symlink", False, "succeeded")
except sa.ApplyError as error:
    check("clipboard copy refuses a symlink", error.code == "payload.invalid", error.code)

trash_payload = copy_payload("files.location.documents", "memo.txt", source)
trash_payload["locationId"] = "files.location.trash"
try:
    sa.apply_files_clipboard_copy(io.StringIO(json.dumps(trash_payload)), io.StringIO(), run=fake_run)
    check("clipboard copy refuses Trash", False, "succeeded")
except sa.ApplyError as error:
    check("clipboard copy refuses Trash", error.code == "payload.invalid", error.code)

clipboard["paste"] = source.as_uri() + "\r\n"
status, result = run_paste({"destinationLocationId": "files.location.desktop", "destinationParentRelativePath": ""})
replica = home / "Desktop" / "memo.txt"
check("clipboard paste copies into the destination location", status == 0 and result.get("ok") and result.get("copied") and replica.is_file(), json.dumps(result))
check("clipboard paste keeps the source", source.is_file() and source.read_text(encoding="utf-8") == "hello", str(source.exists()))
check("clipboard paste replica holds the source bytes", replica.read_text(encoding="utf-8") == "hello" if replica.exists() else False, replica.read_text(encoding="utf-8") if replica.exists() else "missing")

clipboard["paste"] = "copy\n" + source.as_uri() + "\n"
status, result = run_paste({"destinationLocationId": "files.location.desktop", "destinationParentRelativePath": ""})
second = home / "Desktop" / "memo (2).txt"
check("gnome copy format pastes with a collision-free name", status == 0 and second.is_file(), json.dumps(result))

outside = pathlib.Path(tempfile.mkdtemp()) / "secret.txt"
outside.write_text("no", encoding="utf-8")
clipboard["paste"] = outside.as_uri() + "\n"
try:
    sa.apply_files_clipboard_paste(io.StringIO(json.dumps({"destinationLocationId": "files.location.documents", "destinationParentRelativePath": ""})), io.StringIO(), run=fake_run)
    check("clipboard paste refuses a path outside Files locations", False, "succeeded")
except sa.ApplyError as error:
    check("clipboard paste refuses a path outside Files locations", error.code == "payload.invalid", error.code)

clipboard["paste"] = ""
try:
    sa.apply_files_clipboard_paste(io.StringIO(json.dumps({"destinationLocationId": "files.location.documents", "destinationParentRelativePath": ""})), io.StringIO(), run=fake_run)
    check("empty clipboard refuses", False, "succeeded")
except sa.ApplyError as error:
    check("empty clipboard refuses", error.code == "resource.unresolved", error.code)

try:
    sa.apply_files_clipboard_paste(io.StringIO(json.dumps({"destinationLocationId": "files.location.trash", "destinationParentRelativePath": ""})), io.StringIO(), run=fake_run)
    check("clipboard paste refuses Trash destination", False, "succeeded")
except sa.ApplyError as error:
    check("clipboard paste refuses Trash destination", error.code == "payload.invalid", error.code)

check("uri-list parser skips comments", sa.parse_file_uri_list("# comment\n" + source.as_uri()) == [source], str(sa.parse_file_uri_list("# comment\n" + source.as_uri())))
try:
    sa.parse_file_uri_list("file:///home/../etc/passwd")
    check("uri-list parser rejects traversal", False, "accepted")
except sa.ApplyError as error:
    check("uri-list parser rejects traversal", error.code == "payload.invalid", error.code)

if failures:
    raise SystemExit("\n".join(failures))
PY
pass "files clipboard helper copy-out and paste-in keep identity and location honesty"
