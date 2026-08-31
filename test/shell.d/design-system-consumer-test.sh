#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command python3

python3 - "$ROOT" <<'PY' || exit 1
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
trees = [
    root / "shell/plugins/ultimate-start",
    root / "shell/plugins/ultimate-taskbar",
    root / "shell/plugins/ultimate-settings",
    root / "shell/plugins/osd",
    root / "shell/plugins/polkit",
    root / "shell/plugins/notifications",
    root / "shell/plugins/ultimate-quick-settings",
    root / "shell/plugins/bar/widgets",
    root / "shell/plugins/panels",
]
escape = re.compile(r"\\u[fF][0-9a-fA-F]{3}|\\U000[fF][0-9a-fA-F]{4}|\\ue(?!9)[0-9a-fA-F]{3}")
failures = []
for tree in trees:
    for path in tree.rglob("*"):
        if path.suffix not in {".qml", ".js"}:
            continue
        text = path.read_text(encoding="utf-8")
        for number, line in enumerate(text.splitlines(), 1):
            if escape.search(line):
                failures.append(f"{path.relative_to(root)}:{number}: nerd-font escape")
            for char in line:
                code = ord(char)
                branded = 0xE900 <= code <= 0xE9FF
                pua = (0xE000 <= code <= 0xF8FF and not branded) or 0xF0000 <= code <= 0x10FFFD
                if pua:
                    failures.append(f"{path.relative_to(root)}:{number}: U+{code:04X}")
if failures:
    print("\n".join(failures[:40]), file=sys.stderr)
    raise SystemExit(1)
PY
pass "consumer chrome ships no Nerd Font private-use glyphs"

python3 - "$ROOT" <<'PY' || exit 1
import sys
from pathlib import Path

root = Path(sys.argv[1])
checks = {
    "shell/Ui/Button.qml": "Tokens.chrome.menu",
    "shell/Ui/PanelToolTip.qml": "Tokens.chrome.menu",
    "shell/Ui/Toggle.qml": "Tokens.accent.primary",
    "shell/Ui/ToggleSwitch.qml": "Tokens.text.primary",
    "shell/Ui/TextField.qml": "Tokens.accent.primary",
    "shell/Ui/ConfirmDialog.qml": "Tokens.state.danger",
    "shell/plugins/ultimate-start/Start.qml": "Tokens.typography.family",
    "shell/plugins/ultimate-taskbar/StartButton.qml": "Tokens.caption.close.background",
    "shell/plugins/ultimate-taskbar/Taskbar.qml": "Tokens.chrome.menu",
    "shell/plugins/ultimate-taskbar/TaskButton.qml": "Tokens.border.strong",
    "shell/plugins/ultimate-taskbar/TrayCluster.qml": "Tokens.border.strong",
    "shell/Ui/WidgetButton.qml": "Tokens.border.strong",
    "shell/Ui/WidgetButton.qml": "Tokens.state.danger",
    "shell/plugins/desktop-icons/DesktopIcons.qml": "Tokens.typography.family",
    "shell/plugins/lock/LockView.qml": "Tokens.surface.canvas",
    "shell/plugins/lock/Service.qml": "Tokens.surface.canvas",
    "shell/plugins/notifications/components/NotificationCard.qml": "Tokens.chrome.menu",
    "shell/plugins/panels/clock/Panel.qml": "Tokens.accent.primary",
    "shell/plugins/agents/Panel.qml": "Tokens.chrome.menu",
    "shell/Commons/Tokens.qml": "design-tokens-v0.json",
}
for relative, needle in checks.items():
    text = (root / relative).read_text(encoding="utf-8")
    if needle not in text:
        raise SystemExit(f"{relative} does not bind {needle}")
    if relative.startswith("shell/Ui/") and "Color.foreground" in text:
        raise SystemExit(f"{relative} still defaults through Color.foreground")
    for leak in ("Color.tooltip", "Color.notifications", "Color.urgent", "Color.background"):
        if leak in text and relative != "shell/Commons/Tokens.qml":
            raise SystemExit(f"{relative} still defaults through {leak}")
PY
pass "kit and consumer chrome default through the resolved token pipeline"

grep -Fq '"family": "Liberation Sans"' "$ROOT/default/ultimate/design-system/resolve_tokens.py" \
  || fail "consumer typography defaults to a UI family, not the terminal alias"
grep -Fq 'fontFamily: Tokens.typography.family' "$ROOT/shell/Ui/Button.qml" \
  || fail "kit Button uses the token UI family"
grep -Fq 'font.family: Tokens.typography.family' "$ROOT/shell/Ui/TextField.qml" \
  || fail "kit TextField uses the token UI family"
pass "consumer typography defaults to Liberation Sans"

grep -Fq 'Tokens.accessibility.highContrast' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar glass reads Tokens.accessibility"
grep -Fq 'Tokens.border.strong' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar HC glass edge uses Tokens.border.strong"
grep -Fq 'bar.highContrast' "$ROOT/shell/plugins/ultimate-taskbar/StartButton.qml" \
  || fail "Start orb consumes Superbar high-contrast chrome"
grep -Fq 'Tokens.border.strong' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml" \
  || fail "task buttons consume Tokens.border.strong under high contrast"
grep -Fq 'Tokens.border.strong' "$ROOT/shell/plugins/ultimate-taskbar/TrayCluster.qml" \
  || fail "tray cluster consumes Tokens.border.strong under high contrast"
grep -Fq 'Tokens.border.strong' "$ROOT/shell/Ui/WidgetButton.qml" \
  || fail "Superbar clock and tray marks consume Tokens.border.strong under high contrast"
grep -Fq 'Tokens.accessibility.highContrast' "$ROOT/shell/plugins/ultimate-quick-settings/BarWidget.qml" \
  || fail "Quick Settings Superbar mark consumes Tokens.accessibility"
grep -Fq 'Tokens.accessibility.highContrast' "$ROOT/shell/plugins/notifications/BarWidget.qml" \
  || fail "Notification Center Superbar mark consumes Tokens.accessibility"
if grep -Eq 'property color chrome[A-Za-z]*:.*(Qt\.rgba|"#)' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml"; then
  fail "Superbar has no private high-contrast chrome color"
fi
pass "Superbar consumer chrome binds Tokens.accessibility and Tokens.border.strong"

grep -Fq 'LayoutMirroring.enabled: productProfile.rtl' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start mirrors through the product SemanticProfile"
grep -Fq 'payload.rtl === true' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start RTL can be summoned on the existing SemanticProfile without a locale pack"
grep -Fq 'root.summonedRtl || (root.shell && root.shell.summonedRtl) || Qt.application.layoutDirection === Qt.RightToLeft' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start RTL keeps the Qt layoutDirection bind"
grep -Fq 'property bool summonedRtl: false' "$ROOT/shell/shell.qml" \
  || fail "shell owns the shared Start RTL summon flag"
grep -Fq 'LayoutMirroring.enabled: root.rtl' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar mirrors through the shared RTL path"
grep -Fq 'shell.summonedRtl' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar reads the shared Start RTL summon flag"
if grep -Fq 'id: "omarchy.start.accessibility"' "$ROOT/shell/plugins/ultimate-start/Start.qml"; then
  fail "Start RTL is not an invented Accessibility Settings surface"
fi
pass "Start RTL binds the existing SemanticProfile path"

grep -Fq 'payload.pseudoLocale === true' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start pseudo-locale can be summoned on the existing SemanticProfile without a translation pack"
grep -Fq 'pseudoLocale: root.summonedPseudoLocale || (root.shell && root.shell.summonedPseudoLocale) || root.summonedLocale === "pseudo"' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start pseudo-locale binds the product SemanticProfile"
grep -Fq 'property bool summonedPseudoLocale: false' "$ROOT/shell/shell.qml" \
  || fail "shell owns the shared Start pseudo-locale summon flag"
grep -Fq 'root.shell.summonedPseudoLocale = root.summonedPseudoLocale' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start publishes pseudo-locale onto the shared shell flag"
grep -Fq 'pseudoLocale: !!(shell && shell.summonedPseudoLocale)' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar reads the shared Start pseudo-locale summon flag"
grep -Fq 'function chromeText(value)' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar chrome text uses the shared SemanticProfile"
grep -Fq 'Semantics.text(root.productProfile, "Quick Settings")' "$ROOT/shell/plugins/ultimate-quick-settings/Panel.qml" \
  || fail "Quick Settings heading consumes Semantics.text"
grep -Fq 'Semantics.text(root.productProfile, "Notification Center")' "$ROOT/shell/plugins/notifications/Center.qml" \
  || fail "Notification Center heading consumes Semantics.text"
grep -Fq 'text: "Clear"' "$ROOT/shell/plugins/notifications/Center.qml" \
  || fail "Notification Center Clear stays a chrome verb"
grep -B3 -A1 'text: "Clear"' "$ROOT/shell/plugins/notifications/Center.qml" | grep -Fq 'semanticProfile: root.productProfile' \
  || fail "Notification Center Clear consumes Semantics.text"
grep -Fq 'Semantics.text(root.semanticProfile, root.tooltipText)' "$ROOT/shell/Ui/WidgetButton.qml" \
  || fail "Superbar WidgetButton tooltips consume Semantics.text"
grep -Fq 'function chromeText(value)' "$ROOT/shell/plugins/panels/clock/Panel.qml" \
  || fail "Calendar chrome text uses the shared Superbar SemanticProfile"
grep -Fq 'root.chromeText("Calendar")' "$ROOT/shell/plugins/panels/clock/Panel.qml" \
  || fail "Calendar heading consumes Semantics.text"
grep -Fq 'pseudoLocale: !!(shell && shell.summonedPseudoLocale)' "$ROOT/shell/plugins/lock/LockView.qml" \
  || fail "lock chrome reads the shared Start pseudo-locale summon flag"
grep -Fq 'Semantics.text(chromeProfile, root.placeholderText)' "$ROOT/shell/plugins/lock/LockView.qml" \
  || fail "lock password chrome consumes Semantics.text"
grep -Fq 'text: "Refresh"' "$ROOT/shell/apps/ultimate-agent-center/AgentCenterApplication.qml" \
  || fail "Agent Center Refresh stays a chrome verb"
grep -Fq 'semanticProfile: root.productProfile' "$ROOT/shell/apps/ultimate-agent-center/AgentCenterApplication.qml" \
  || fail "Agent Center chrome verbs consume Semantics.text"
grep -Fq 'semanticProfile: root.productProfile' "$ROOT/shell/apps/ultimate-settings/SettingsApplication.qml" \
  || fail "Settings chrome verbs consume the host SemanticProfile"
grep -Fq 'function chromeText(value)' "$ROOT/shell/plugins/agents/Panel.qml" \
  || fail "agents panel chrome text uses the shared Superbar SemanticProfile"
grep -Fq 'semanticProfile: root.productProfile' "$ROOT/shell/plugins/agents/Panel.qml" \
  || fail "agents panel Open Agent Center consumes Semantics.text"
grep -Fq 'pseudoLocale: !!(shell && shell.summonedPseudoLocale)' "$ROOT/shell/plugins/ultimate-task-switcher/Switcher.qml" \
  || fail "Task View chrome reads the shared Start pseudo-locale summon flag"
grep -Fq 'root.chromeText("Task View")' "$ROOT/shell/plugins/ultimate-task-switcher/Switcher.qml" \
  || fail "Task View heading consumes Semantics.text"
grep -Fq 'function chromeText(value)' "$ROOT/shell/plugins/bar/widgets/Tray.qml" \
  || fail "tray manage chrome text uses the shared Superbar SemanticProfile"
grep -Fq 'root.chromeText("Tray icons")' "$ROOT/shell/plugins/bar/widgets/Tray.qml" \
  || fail "tray manage heading consumes Semantics.text"
grep -Fq 'function chromeText(value)' "$ROOT/shell/plugins/ultimate-run/Run.qml" \
  || fail "Run chrome text uses the shared Start SemanticProfile"
grep -Fq 'root.chromeText("Run")' "$ROOT/shell/plugins/ultimate-run/Run.qml" \
  || fail "Run heading consumes Semantics.text"
grep -Fq 'function chromeText(value)' "$ROOT/shell/plugins/ultimate-snap-chooser/Chooser.qml" \
  || fail "Snap chooser chrome text uses the shared Start SemanticProfile"
grep -Fq 'root.chromeText("Snap")' "$ROOT/shell/plugins/ultimate-snap-chooser/Chooser.qml" \
  || fail "Snap chooser heading consumes Semantics.text"
grep -Fq 'productProfile.text(modelData.name)' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start places consume Semantics.text through the product profile"
grep -Fq 'semanticPlaceholderText: "Search programs"' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start search placeholder consumes the SemanticProfile text transform"
if grep -Fq 'id: "omarchy.start.accessibility"' "$ROOT/shell/plugins/ultimate-start/Start.qml"; then
  fail "Start pseudo-locale is not an invented Accessibility Settings surface"
fi
if grep -Fq 'id: "omarchy.start.accessibility"' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml"; then
  fail "Superbar pseudo-locale is not an invented Accessibility Settings surface"
fi
pass "Start pseudo-locale binds the existing SemanticProfile path"

grep -Fq 'Semantics.duration(null, 140)' "$ROOT/shell/Ui/WidgetButton.qml" \
  || fail "Superbar WidgetButton opacity uses Semantics.duration"
grep -Fq 'Semantics.duration(null, 160)' "$ROOT/shell/Ui/WidgetButton.qml" \
  || fail "Superbar WidgetButton color uses Semantics.duration"
if grep -Eq 'duration: (100|140|160)(;| )' "$ROOT/shell/Ui/WidgetButton.qml"; then
  fail "Superbar WidgetButton does not hard-code hover duration"
fi
grep -Fq 'Semantics.duration(null, 140)' "$ROOT/shell/Ui/KeyboardPanel.qml" \
  || fail "QS, NC, and calendar KeyboardPanel fade uses Semantics.duration"
if grep -Eq 'duration: 140;' "$ROOT/shell/Ui/KeyboardPanel.qml"; then
  fail "KeyboardPanel does not hard-code panel fade duration"
fi
grep -Fq 'Semantics.duration(null, 100)' "$ROOT/shell/plugins/notifications/components/NotificationCard.qml" \
  || fail "Notification card hover uses Semantics.duration"
if grep -Eq 'duration: 100' "$ROOT/shell/plugins/notifications/components/NotificationCard.qml"; then
  fail "Notification card does not hard-code hover duration"
fi
grep -Fq 'Semantics.duration(null, 160)' "$ROOT/shell/plugins/panels/clock/Panel.qml" \
  || fail "calendar year and life bars use Semantics.duration"
if grep -Eq 'duration: 160;' "$ROOT/shell/plugins/panels/clock/Panel.qml"; then
  fail "calendar panel does not hard-code bar duration"
fi
if grep -Fq 'id: "omarchy.start.accessibility"' "$ROOT/shell/Ui/WidgetButton.qml"; then
  fail "reduced motion is not an invented Accessibility Settings surface"
fi
pass "Superbar, QS, NC, and calendar motion bind Semantics.duration"
