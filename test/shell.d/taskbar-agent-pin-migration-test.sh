#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
if ! command -v python3 >/dev/null; then
  require_command python
  mkdir -p "$test_tmp/bin"
  ln -s "$(command -v python)" "$test_tmp/bin/python3"
  PATH="$test_tmp/bin:$PATH"
fi
require_command python3
HOME="$test_tmp/home"
mkdir -p "$HOME/.local/state/omarchy/ultimate"

cat >"$HOME/.local/state/omarchy/ultimate/taskbar-pins.json" <<'JSON'
{
  "pins": [
    {
      "id": "google-chrome",
      "desktopId": "google-chrome",
      "name": "Chrome",
      "icon": "google-chrome"
    },
    {
      "id": "org.gnome.nautilus",
      "desktopId": "org.gnome.Nautilus",
      "name": "Files",
      "icon": "org.gnome.Nautilus"
    }
  ]
}
JSON

bash -euo pipefail "$ROOT/migrations/1788032400.sh"

python - <<'PY'
import json, os, pathlib
path = pathlib.Path(os.environ["HOME"]) / ".local/state/omarchy/ultimate/taskbar-pins.json"
pins = json.loads(path.read_text())["pins"]
ids = [p["desktopId"] for p in pins]
assert ids[0] == "google-chrome"
assert ids[1] == "org.omarchy.Files", ids
assert "org.omarchy.Agent" in ids, ids
assert "org.gnome.Nautilus" not in ids
PY

pass "existing shipped Files pin becomes the product host and Agent is added"

mkdir -p "$HOME/.local/state/omarchy/ultimate"
printf '%s\n' '{"pins":[{"id":"steam","desktopId":"steam","name":"Steam","icon":"steam"}]}' \
  >"$HOME/.local/state/omarchy/ultimate/taskbar-pins.json"
bash -euo pipefail "$ROOT/migrations/1788032400.sh"
python - <<'PY'
import json, os, pathlib
pins = json.loads((pathlib.Path(os.environ["HOME"]) / ".local/state/omarchy/ultimate/taskbar-pins.json").read_text())["pins"]
assert pins[0]["desktopId"] == "steam"
assert pins[1]["desktopId"] == "org.omarchy.Agent"
assert len(pins) == 2
PY
pass "custom pins keep their first entries and only gain Agent"
