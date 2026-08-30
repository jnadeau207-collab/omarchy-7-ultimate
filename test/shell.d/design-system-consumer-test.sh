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
