#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

application="$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml"
chrome="$ROOT/shell/apps/ultimate-settings/SettingsHostChrome.qml"
card="$ROOT/shell/apps/ultimate-settings/SettingsRecordCard.qml"
panel="$ROOT/shell/Ui/SettingsHostedPanel.qml"
theme="$ROOT/shell/apps/ultimate-files/ExplorerTheme.js"
leftover="$ROOT/test/acceptance.d/leftovers/win7-visual/leftover.json"

[[ -f $application ]] || fail "SettingsApplication exists"
[[ -f $chrome ]] || fail "Settings host chrome exists"
[[ -f $theme ]] || fail "ExplorerTheme token source exists"
[[ -f $leftover ]] || fail "win7 visual leftover exists"

python3 - "$application" "$chrome" "$card" "$panel" "$theme" "$leftover" << 'PY'
import json
import re
import sys
from pathlib import Path

application = Path(sys.argv[1]).read_text(encoding="utf-8")
chrome = Path(sys.argv[2]).read_text(encoding="utf-8")
card = Path(sys.argv[3]).read_text(encoding="utf-8")
panel = Path(sys.argv[4]).read_text(encoding="utf-8")
theme = Path(sys.argv[5]).read_text(encoding="utf-8")
leftover = json.loads(Path(sys.argv[6]).read_text(encoding="utf-8"))

required_names = [
    "contentFill",
    "fieldFill",
    "fieldBorder",
    "fieldFocusBorder",
    "fontFamily",
    "commandTop",
    "commandBottom",
    "commandBorder",
    "navHeaderText",
    "linkText",
    "headerBorder",
    "textPrimary",
    "crumbSeparator",
]

def theme_has(name):
    return re.search(rf"^var {re.escape(name)} = ", theme, re.M) is not None

missing = [name for name in required_names if not theme_has(name)]
if missing:
    raise SystemExit("ExplorerTheme missing token names: " + ", ".join(missing))

if "monospace" in application or "monospace" in chrome or "monospace" in card or "monospace" in panel:
    raise SystemExit("Settings shell still names monospace")
if "Tokens.typography.family" in application or "Tokens.typography.family" in chrome or "Tokens.typography.family" in card or "Tokens.typography.family" in panel:
    raise SystemExit("Settings body still falls back through Tokens.typography.family")
if "Aero.fontFamily" not in application or "bodyFontFamily: Aero.fontFamily" not in application:
    raise SystemExit("Settings body font must reuse Aero.fontFamily")
if "font.family: Aero.fontFamily" not in chrome or "font.family: Aero.fontFamily" not in card:
    raise SystemExit("Settings host chrome and record card must use Aero.fontFamily")
if "fontFamily: Aero.fontFamily" not in panel:
    raise SystemExit("Settings hosted panel font fallback must reuse Aero.fontFamily")

if "Tokens.surface" in application or "Tokens.surface" in card:
    raise SystemExit("Settings shell still uses Tokens.surface cards")
for name in ("contentFill", "fieldFill", "headerBorder", "navHeaderText", "linkText"):
    if f"Aero.{name}" not in application and f"Aero.{name}" not in chrome:
        raise SystemExit(f"Settings shell does not reuse Aero.{name}")
if "Aero.contentFill" not in application or "Aero.contentFill" not in card:
    raise SystemExit("Settings shell fill must reuse Aero.contentFill")

hexes = re.findall(r"#[0-9A-Fa-f]{3,8}", chrome + "\n" + application)
if hexes:
    raise SystemExit("Settings shell invented hex: " + ", ".join(sorted(set(hexes))))

if "Layout.minimumWidth: 196" in application or "Layout.maximumWidth: 320" in application:
    raise SystemExit("Settings nav 196-320 shell remains")
if "ApplicationNavigation" in application:
    raise SystemExit("Settings default shell still hosts the dark navigation pane")
if "SettingsHostChrome" not in application:
    raise SystemExit("Settings host must use SettingsHostChrome")
if "Search Control Panel" not in chrome:
    raise SystemExit("Settings host search is missing")
if "Control Panel" not in application or "settingsCrumbs" not in application:
    raise SystemExit("Settings host breadcrumb is missing")
if "crumbActivated" not in chrome or "searchChanged" not in chrome:
    raise SystemExit("Settings host chrome does not expose breadcrumb and search")

if leftover.get("win7VisualLeftover") != "OPEN":
    raise SystemExit("win7VisualLeftover must stay OPEN")
if leftover.get("productClosed") is True or leftover.get("metalClosed") is True:
    raise SystemExit("visual leftover must not claim product or metal CLOSED")
status = leftover.get("statusAfterPr112") or {}
if status.get("win7VisualLeftover") != "OPEN":
    raise SystemExit("statusAfterPr112 win7VisualLeftover must stay OPEN")
if status.get("productClosed") is not False or status.get("metalClosed") is not False:
    raise SystemExit("statusAfterPr112 must keep product and metal open")
if "Settings card shell" not in json.dumps(status.get("stillOpen") or []):
    raise SystemExit("visual leftover stillOpen must keep Settings card shell OPEN")

forbidden = ("win7VisualLeftover CLOSED", "product CLOSED", "metal CLOSED", "Win7 visual leftover CLOSED")
for blob, label in ((application, "SettingsApplication"), (chrome, "SettingsHostChrome")):
    for phrase in forbidden:
        if phrase in blob and "not " + phrase not in blob and "Not " + phrase not in blob:
            raise SystemExit(f"{label} claims {phrase}")
PY

pass "Settings body drops the monospace Tokens.typography.family fallback (source chrome only)"
pass "Settings host reuses existing Explorer client token names for a light category page (not new hex, not pixel proof)"
pass "win7VisualLeftover stays OPEN (not metal CLOSED, not product CLOSED)"
