#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

files_app="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"
command_bar="$ROOT/shell/apps/ultimate-files/ExplorerCommandBar.qml"
caption="$ROOT/shell/apps/ultimate-files/ExplorerGlassCaption.qml"
address="$ROOT/shell/apps/ultimate-files/ExplorerAddressBar.qml"
theme="$ROOT/shell/apps/ultimate-files/ExplorerTheme.js"
host="$ROOT/shell/apps/shared/ProductAppHost.qml"
windows="$ROOT/default/hypr/desktop-windows.lua"
csd="$ROOT/default/ultimate/csd-clients.json"
leftover="$ROOT/test/acceptance.d/leftovers/win7-visual/leftover.json"
tokens="$ROOT/default/ultimate/chrome-tokens.json"

[[ -f $files_app ]] || fail "Files application exists"
[[ -f $command_bar ]] || fail "Files command bar exists"
[[ -f $caption ]] || fail "Files glass caption exists"

grep -Fq 'readonly property bool paintsOwnTitleBar: true' "$files_app" ||
  fail "Files paints the one glass caption"
grep -Fq 'readonly property string sharedCaptionPath: "files-glass"' "$files_app" ||
  fail "Files caption path is the glass caption"
if grep -Fq 'text: root.routeTitle' "$files_app"; then
  fail "Files must not paint a second route title"
fi
if grep -Eq 'text: "(×|✕|–|□)"' "$files_app"; then
  fail "Files application must not paint a second caption glyph row"
fi
grep -Fq 'id: captionBar' "$files_app" || fail "Files window hosts the glass caption"
grep -Fq 'title: root.routeTitle' "$files_app" || fail "glass caption uses the place title"
grep -Fq 'anchors.top: captionBar.bottom' "$files_app" ||
  fail "address row sits under the glass caption"
grep -Fq 'horizontalAlignment: Text.AlignLeft' "$caption" ||
  fail "caption title is not a centered desktop label"
python3 - "$caption" "$address" "$theme" "$tokens" << 'PY'
import json
import sys
from pathlib import Path

caption = Path(sys.argv[1]).read_text(encoding="utf-8")
address = Path(sys.argv[2]).read_text(encoding="utf-8")
theme = Path(sys.argv[3]).read_text(encoding="utf-8")
tokens = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8"))
glass = str(tokens["captionGlassHex"]).lower()
text = str(tokens["hyprbarsTextHex"]).lower()
close_bg = str(tokens["captionCloseBgHex"]).lower()
needle_glass = 'var captionGlass = "' + glass + '"'
needle_text = 'var captionText = "' + text + '"'
needle_close = 'var captionCloseBg = "' + close_bg + '"'
if needle_glass not in theme:
    raise SystemExit("caption glass is not the existing captionGlassHex token")
if needle_text not in theme:
    raise SystemExit("caption text is not the existing hyprbarsTextHex token")
if needle_close not in theme:
    raise SystemExit("caption close is not the existing captionCloseBgHex token")
if "Aero.captionGlass" not in caption or "Aero.captionGlassAlpha" not in caption:
    raise SystemExit("caption does not paint the existing Aero glass token")
if "Text.AlignHCenter" in caption or "Text.AlignCenter" in caption:
    raise SystemExit("caption title is centered")
if "Aero.captionGlass" not in address or "Aero.captionGlassAlpha" not in address:
    raise SystemExit("address row is not on the caption glass")
if "id: backButton" not in address or "id: searchField" not in address or "root.crumbs" not in address:
    raise SystemExit("address row is missing back, breadcrumb, or search")
PY

if grep -Fq 'org.omarchy.Files' "$csd"; then
  fail "org.omarchy.Files must not take hyprbars:no_bar from the CSD list"
fi
python3 - "$windows" << 'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
line = next((row for row in text.splitlines() if 'o.window("org.omarchy.Files"' in row), "")
if not line:
    raise SystemExit("Files window rule is missing")
if '["hyprbars:no_bar"] = true' not in line:
    raise SystemExit("Files still leaves the steel hyprbars bar attached")
if "bar_color" in line or "title_color" in line:
    raise SystemExit("Files still uses a class color override on the steel bar")
for banned in ("bar_height", "bar_aero", "bar_text_align", "captionClose", "icon_on_hover"):
    if banned in line:
        raise SystemExit("Files window rule restyles hyprbars globally: " + banned)
if 'bar_text_align = "center"' not in text:
    raise SystemExit("global hyprbars text align was restyled")
if "bar_height = 30" not in text or "bar_aero = true" not in text:
    raise SystemExit("shared hyprbars factory bar was restyled")
PY

grep -Fq 'title: root.placeTitle !== "" ? root.placeTitle : root.displayName' "$host" ||
  fail "host still publishes the place title for the surface"
grep -Fq 'function closeSurface()' "$host" || fail "glass caption cannot close the surface"
grep -Fq 'function minimizeSurface()' "$host" || fail "glass caption cannot minimize the surface"
grep -Fq 'host.placeTitle = title' "$files_app" ||
  fail "Recycle Bin publishes the place title"
grep -Fq 'root.routeTitle' "$files_app" ||
  fail "caption place title comes from the route"

grep -Fq 'GradientStop { position: 0; color: Aero.commandTop }' "$command_bar" ||
  fail "command bar uses Aero.commandTop"
grep -Fq 'GradientStop { position: 1; color: Aero.commandBottom }' "$command_bar" ||
  fail "command bar uses Aero.commandBottom"
grep -Fq 'implicitHeight: Aero.commandHeight' "$command_bar" ||
  fail "command bar uses the Aero command height"
grep -Fq 'var commandHeight = 36' "$theme" ||
  fail "command height stays 36"
if grep -Fq 'id: commandButtonFrame' "$command_bar" "$files_app"; then
  fail "command items still paint a command button frame"
fi
if grep -Fq 'commandButton: true' "$files_app" "$command_bar"; then
  fail "Recycle Bin still marks toolbar items as boxed command buttons"
fi
grep -Fq 'id: commandDropdownChevron' "$command_bar" ||
  fail "Organize paints a dropdown chevron"
grep -Fq 'visible: modelData.dropdown === true' "$command_bar" ||
  fail "Organize is the only chevron"
grep -Fq 'icon: "organize"' "$files_app" || fail "Organize is missing its toolbar icon"
grep -Fq 'icon: "restore"' "$files_app" || fail "Restore is missing its toolbar icon"
grep -Fq 'icon: "trash"' "$files_app" || fail "Empty Recycle Bin is missing the trash icon"
grep -Fq 'icon: "file"' "$files_app" || fail "Properties is missing its toolbar icon"

python3 - "$files_app" "$leftover" << 'PY'
import json
import re
import sys
from pathlib import Path

files_app = Path(sys.argv[1]).read_text(encoding="utf-8")
leftover = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

def strip_fn(src, name):
    start = src.find("function %s()" % name)
    if start < 0:
        raise SystemExit("missing " + name)
    brace = src.find("{", start)
    depth = 0
    for index in range(brace, len(src)):
        if src[index] == "{":
            depth += 1
        elif src[index] == "}":
            depth -= 1
            if depth == 0:
                return src[start:index + 1]
    raise SystemExit("unclosed " + name)

actions = strip_fn(files_app, "commandActions")
trash = actions.split("if (root.trashRoute)", 1)[1]
trash = trash.split("var list =", 1)[0]
labels = re.findall(r'label: "([^"]+)"', trash)
if labels != ["Organize", "Restore", "Empty Recycle Bin", "Properties"]:
    raise SystemExit("Recycle Bin command strip is %s" % labels)
if "Connect to Server" in trash:
    raise SystemExit("Connect to Server is on the Recycle Bin command strip")
if "SESSION CONTROL" in trash:
    raise SystemExit("SESSION CONTROL is on the Recycle Bin command strip")
organize = trash.split("Organize", 1)[1].split("},", 1)[0]
if "dropdown: true" not in organize:
    raise SystemExit("Organize is not the dropdown")
if "commandButton" in organize:
    raise SystemExit("Organize is still a boxed command button")
if 'icon: "organize"' not in organize:
    raise SystemExit("Organize is not an icon toolbar item")
for label, icon in (("Restore", "restore"), ("Empty Recycle Bin", "trash"), ("Properties", "file")):
    item = trash.split('label: "%s"' % label, 1)[1].split("}", 1)[0]
    if "commandButton" in item:
        raise SystemExit(label + " is still a boxed command button")
    if "dropdown: false" not in item:
        raise SystemExit(label + " is a dropdown")
    if "dropdown: true" in item:
        raise SystemExit(label + " has a chevron")
    if 'icon: "%s"' % icon not in item:
        raise SystemExit(label + " is not an icon toolbar item")
if trash.count("dropdown: true") != 1:
    raise SystemExit("Organize is not the only dropdown on the Recycle Bin strip")

if leftover.get("win7VisualLeftover") != "OPEN":
    raise SystemExit("win7VisualLeftover must stay OPEN")
wash = leftover.get("surfaces", {}).get("selectionWash", {})
if wash.get("status") != "OPEN":
    raise SystemExit("selectionWash must stay OPEN")
PY

if grep -Fq 'sessionBadge: "SESSION CONTROL"' "$files_app" "$command_bar"; then
  fail "SESSION CONTROL must not be the painted command-bar badge"
fi
if grep -Fq 'text: "SESSION CONTROL"' "$files_app" "$command_bar" "$caption"; then
  fail "SESSION CONTROL must not be a painted Text on the Files window"
fi

if git -C "$ROOT" diff --name-only -- shell/apps/ultimate-settings | grep -q .; then
  fail "Settings must stay untouched"
fi
if git -C "$ROOT" diff --name-only | grep -Eq 'win7-baseline|\.png$'; then
  fail "PNG baseline must stay untouched"
fi
if git -C "$ROOT" diff --name-only | grep -Fq 'default/hypr/plugins/hyprbars/'; then
  fail "hyprbars global theme must stay untouched"
fi
if git -C "$ROOT" diff --name-only | grep -Eq 'leftover\.json$'; then
  fail "leftover docs must stay untouched"
fi

pass "Recycle Bin top chrome is the glass caption, address row, and icon toolbar; leftover stays OPEN; not pixel proof; not metal CLOSED"
