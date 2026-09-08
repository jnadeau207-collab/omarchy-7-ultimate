#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

files_app="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"
command_bar="$ROOT/shell/apps/ultimate-files/ExplorerCommandBar.qml"
details="$ROOT/shell/apps/ultimate-files/ExplorerDetailsPane.qml"
nav="$ROOT/shell/apps/ultimate-files/ExplorerNavigationPane.qml"
host="$ROOT/shell/apps/shared/ProductAppHost.qml"
files_entry="$ROOT/shell/ultimate-files.qml"
leftover="$ROOT/test/acceptance.d/leftovers/win7-visual/leftover.json"
settings="$ROOT/shell/apps/ultimate-settings"

[[ -f $files_app ]] || fail "Files application exists"
[[ -f $command_bar ]] || fail "Files command bar exists"
[[ -f $details ]] || fail "Files details pane exists"
[[ -f $nav ]] || fail "Files navigation pane exists"

grep -Fq 'sessionBadge: ""' "$files_app" || fail "Recycle Bin command bar sessionBadge is empty"
grep -Fq 'visible: false' "$command_bar" || fail "command bar session badge stays unpainted"
grep -Fq 'text: ""' "$command_bar" || fail "command bar session badge text is empty"
if grep -Fq 'sessionBadge: "SESSION CONTROL"' "$files_app" "$command_bar"; then
  fail "SESSION CONTROL must not be the painted command-bar badge"
fi
if grep -Fq 'text: "SESSION CONTROL"' "$files_app" "$command_bar"; then
  fail "SESSION CONTROL must not be a painted Text on the Files window"
fi
if grep -Fq 'text: "SESSION CONTROL · READ-ONLY"' "$files_app"; then
  fail "SESSION CONTROL · READ-ONLY must not paint"
fi
grep -Fq 'readonly property string sessionControlMark: "SESSION CONTROL"' "$command_bar" ||
  fail "session control leftover mark stays off the paint path"
grep -Fq 'readonly property string sessionControlReadOnlyMark: "SESSION CONTROL · READ-ONLY"' "$files_app" ||
  fail "session read-only leftover mark stays off the paint path"

grep -Fq 'boundary: ""' "$files_app" || fail "details pane boundary paint is empty"
grep -Fq 'readonly property string sessionBoundaryHonesty:' "$files_app" ||
  fail "content-read boundary stays as unpainted honesty"
grep -Fq 'File contents are never read' "$files_app" || fail "Files keeps the no-content-read boundary off the glass"
if grep -Fq 'text: "File contents are never read' "$details"; then
  fail "details pane paint path must not carry the honesty dump"
fi
grep -Fq 'readonly property bool paintBoundaryDump: false' "$details" ||
  fail "details pane refuses the honesty dump"
grep -Fq 'root.boundary.indexOf("File contents are never read") !== 0' "$details" ||
  fail "details pane paint path rejects the dump prefix"

python3 - "$files_app" "$nav" "$host" "$leftover" << 'PY'
import json
import re
import sys
from pathlib import Path

files_app = Path(sys.argv[1]).read_text(encoding="utf-8")
nav = Path(sys.argv[2]).read_text(encoding="utf-8")
host = Path(sys.argv[3]).read_text(encoding="utf-8")
leftover = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8"))

def strip_fn(src, name):
    start = src.find(f"function {name}()")
    if start < 0:
        raise SystemExit(f"missing {name}")
    brace = src.find("{", start)
    depth = 0
    for index in range(brace, len(src)):
        if src[index] == "{":
            depth += 1
        elif src[index] == "}":
            depth -= 1
            if depth == 0:
                return src[start:index + 1]
    raise SystemExit(f"unclosed {name}")

actions = strip_fn(files_app, "commandActions")
trash = actions.split("if (root.trashRoute)", 1)[1]
trash = trash.split("var list =", 1)[0]
labels = re.findall(r'label: "([^"]+)"', trash)
if labels != ["Organize", "Restore", "Empty Recycle Bin", "Properties"]:
    raise SystemExit(f"Recycle Bin command strip is {labels}")
if "Connect to Server" in trash:
    raise SystemExit("Connect to Server is on the Recycle Bin command strip")
if "Copy" in labels or "Cut" in labels:
    raise SystemExit("Recycle Bin command strip is not Organize-style")

if 'host.placeTitle = title' not in files_app:
    raise SystemExit("caption does not publish the place title")
if "root.routeTitle" not in files_app.split("function syncPlaceCaption", 1)[1].split("function ", 1)[0]:
    raise SystemExit("caption does not use the place title")
if 'title === "Files"' not in files_app:
    raise SystemExit("caption still accepts the Files fallback")
if 'title: root.placeTitle !== "" ? root.placeTitle : root.displayName' not in host:
    raise SystemExit("window caption does not use the place title")

rows = strip_fn(nav, "rows")
if 'label: root.accountName' in rows:
    raise SystemExit("user folder is still a Win7 nav root")
if 'files.overview' in rows and "accountName" in rows:
    raise SystemExit("user folder route is still a nav root")
if 'label.toLowerCase() === "fabric"' not in rows and "fabric" not in rows:
    raise SystemExit("nav does not reject fabric as a Computer child")
if 'label.toLowerCase() === "fabric"' not in rows:
    raise SystemExit("nav does not skip a fabric Computer child")

if leftover.get("win7VisualLeftover") != "OPEN":
    raise SystemExit("win7VisualLeftover must stay OPEN")
wash = leftover.get("surfaces", {}).get("selectionWash", {})
if wash.get("status") != "OPEN":
    raise SystemExit("selectionWash must stay OPEN")
if leftover.get("statusAfterPr112", {}).get("win7VisualLeftover") != "OPEN":
    raise SystemExit("statusAfterPr112 win7VisualLeftover must stay OPEN")
PY

if git -C "$ROOT" diff --name-only -- shell/apps/ultimate-settings | grep -q .; then
  fail "Settings must stay untouched"
fi
if git -C "$ROOT" diff --name-only | grep -Eq 'win7-baseline|\\.png$'; then
  fail "PNG baseline must stay untouched"
fi

grep -Fq 'displayName: "Files"' "$files_entry" || fail "Files app identity stays Files"
pass "Recycle Bin glass drops debug paint; win7VisualLeftover stays OPEN"
