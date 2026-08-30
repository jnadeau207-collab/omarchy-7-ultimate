echo "Pin Agent Center on the Superbar"

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

center_pin = {
    "id": "org.omarchy.agent-center",
    "desktopId": "org.omarchy.AgentCenter",
    "name": "Agent Center",
    "icon": "system-run",
}

ids = {str(pin.get("id") or "") for pin in pins if isinstance(pin, dict)}
desktop_ids = {str(pin.get("desktopId") or "") for pin in pins if isinstance(pin, dict)}
if "org.omarchy.agent-center" in ids or "org.omarchy.AgentCenter" in desktop_ids:
    raise SystemExit(0)

pins.append(center_pin)
data["pins"] = pins
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
