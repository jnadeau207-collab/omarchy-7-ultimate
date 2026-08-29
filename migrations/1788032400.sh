echo "Retarget the shipped Files pin to the product host and pin Agent"

pins_path="$HOME/.local/state/omarchy/ultimate/taskbar-pins.json"
[[ -f $pins_path ]] || exit 0

python3 - "$pins_path" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
pins = data.get("pins")
if not isinstance(pins, list):
    raise SystemExit(0)

changed = False
files_pin = {
    "id": "org.omarchy.files",
    "desktopId": "org.omarchy.Files",
    "name": "Files",
    "icon": "system-file-manager",
}
agent_pin = {
    "id": "org.omarchy.agent",
    "desktopId": "org.omarchy.Agent",
    "name": "Agent",
    "icon": "system-run",
}

for index, pin in enumerate(pins):
    if not isinstance(pin, dict):
        continue
    desktop_id = str(pin.get("desktopId") or pin.get("id") or "")
    if desktop_id in {"org.gnome.Nautilus", "org.gnome.nautilus"} and str(pin.get("name") or "") in {"Files", ""}:
        pins[index] = files_pin
        changed = True

ids = {str(pin.get("id") or "") for pin in pins if isinstance(pin, dict)}
desktop_ids = {str(pin.get("desktopId") or "") for pin in pins if isinstance(pin, dict)}
if "org.omarchy.agent" not in ids and "org.omarchy.Agent" not in desktop_ids:
    pins.append(agent_pin)
    changed = True

if changed:
    data["pins"] = pins
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
