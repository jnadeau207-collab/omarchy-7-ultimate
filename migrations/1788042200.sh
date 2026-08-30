echo "Publish the Agent Center mark so Superbar and Start do not share system-run with Agent"

src="$OMARCHY_PATH/default/icons/hicolor/scalable/apps/org.omarchy.AgentCenter.svg"
dest_dir="$HOME/.local/share/icons/hicolor/scalable/apps"
dest="$dest_dir/org.omarchy.AgentCenter.svg"
launcher_src="$OMARCHY_PATH/applications/org.omarchy.AgentCenter.desktop"
launcher_dest="$HOME/.local/share/applications/org.omarchy.AgentCenter.desktop"
pins="$HOME/.local/state/omarchy/ultimate/taskbar-pins.json"

[[ -f $src ]] || exit 0
mkdir -p "$dest_dir"
cp "$src" "$dest"

if [[ -f $launcher_src ]]; then
  mkdir -p "$HOME/.local/share/applications"
  cp "$launcher_src" "$launcher_dest"
fi

if [[ -f $pins ]]; then
  python3 - "$pins" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
pins = data.get("pins")
if not isinstance(pins, list):
    raise SystemExit(0)
changed = False
for pin in pins:
    if not isinstance(pin, dict):
        continue
    if pin.get("desktopId") == "org.omarchy.AgentCenter" and pin.get("icon") != "org.omarchy.AgentCenter":
        pin["icon"] = "org.omarchy.AgentCenter"
        changed = True
if changed:
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
fi

PATH="$OMARCHY_PATH/bin:$PATH"
if omarchy-cmd-present gtk-update-icon-cache; then
  gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
fi
if omarchy-cmd-present update-desktop-database; then
  update-desktop-database "$HOME/.local/share/applications"
fi
