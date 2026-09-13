#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

files_app="$ROOT/shell/apps/ultimate-files/FilesApplication.qml"
command_bar="$ROOT/shell/apps/ultimate-files/ExplorerCommandBar.qml"
address="$ROOT/shell/apps/ultimate-files/ExplorerAddressBar.qml"
nav="$ROOT/shell/apps/ultimate-files/ExplorerNavigationPane.qml"
computer="$ROOT/shell/apps/ultimate-files/ExplorerComputerView.qml"
details="$ROOT/shell/apps/ultimate-files/ExplorerDetailsPane.qml"
theme="$ROOT/shell/apps/ultimate-files/ExplorerTheme.js"
settings_app="$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml"
cp_home="$ROOT/shell/apps/ultimate-settings/ControlPanelHome.qml"

[[ -f $command_bar ]] || fail "command bar exists"
[[ -f $cp_home ]] || fail "Control Panel home exists"

grep -Fq 'label: "Organize"' "$files_app" || fail "Organize is on the Explorer command band"
grep -Fq 'label: "Include in library"' "$files_app" || fail "Include in library is a Win7 Explorer verb"
grep -Fq 'label: "Share with"' "$files_app" || fail "Share with is a Win7 Explorer verb"
grep -Fq 'label: "System properties"' "$files_app" || fail "Computer command band has System properties"
grep -Fq 'label: "Open Control Panel"' "$files_app" || fail "Computer command band has Open Control Panel"
grep -Fq 'Show the preview pane' "$command_bar" || fail "command bar trailing Preview control"
grep -Fq 'Help' "$command_bar" || fail "command bar trailing Help control"
grep -Fq 'sessionBadge: ""' "$files_app" || fail "Files does not paint the SESSION CONTROL badge"
grep -Fq 'boundary: ""' "$files_app" || fail "details pane does not paint the leftover essay"
grep -Fq 'label: "Favorites"' "$nav" || fail "nav pane has Favorites"
grep -Fq 'label: "Libraries"' "$nav" || fail "nav pane has Libraries"
grep -Fq 'label: "Homegroup"' "$nav" || fail "nav pane has Homegroup"
grep -Fq 'label: "Computer"' "$nav" || fail "nav pane has Computer"
grep -Fq 'label: "Network"' "$nav" || fail "nav pane has Network"
if grep -Fq 'label: "Recycle Bin"' "$nav"; then
  fail "Win7 default nav pane does not include Recycle Bin"
fi
grep -Fq 'Hard Disk Drives' "$computer" || fail "Computer groups Hard Disk Drives"
grep -Fq 'Devices with Removable Storage' "$computer" || fail "Computer groups removable storage"
grep -Fq 'ControlPanelHome' "$settings_app" || fail "Settings hosts Control Panel category home"
grep -Fq 'System and Security' "$cp_home" || fail "Control Panel has System and Security"
grep -Fq 'Adjust your computer'\''s settings' "$cp_home" || fail "Control Panel page instruction"
grep -Fq 'var commandHeight = 36' "$theme" || fail "commandHeight stays cheat-sheet 36"
grep -Fq 'var detailsHeight = 54' "$theme" || fail "detailsHeight stays cheat-sheet 54"
grep -Fq 'var navPaneWidth = 200' "$theme" || fail "nav pane default width is 200"
grep -Fq 'implicitHeight: Aero.commandHeight' "$command_bar" || fail "command bar uses token height"
grep -Fq 'implicitHeight: Math.max(Aero.detailsHeight, boundaryBanner.visible ? boundaryBanner.implicitHeight + 8 : 0)' "$details" \
  || fail "details pane height formula unchanged"

pass "Explorer command band uses Win7 Folder Band verbs"
pass "Explorer nav pane is Favorites / Libraries / Homegroup / Computer / Network"
pass "Control Panel home is the Win7 eight-category view"
pass "leftover honesty is not painted on Explorer chrome"
