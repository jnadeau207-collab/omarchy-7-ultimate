echo "Repair the Copy URL shortcut for profiles that predate its pinned extension id"

pinned_id="bgpiichlckmfanooecilcjemknkcpngb"

repair_py=$(cat <<'PY'
import json
import shutil
import sys
from pathlib import Path

path = Path(sys.argv[1])
pinned_id = sys.argv[2]
mode = sys.argv[3]

try:
    preferences = json.loads(path.read_text())
except (OSError, ValueError):
    sys.exit(1)

extensions = preferences.get("extensions", {})
commands = extensions.get("commands", {})
settings = extensions.get("settings", {})

def ghost_id(command):
    if command.get("command_name") != "copy-url":
        return None
    extension = command.get("extension")
    if not extension or extension == pinned_id:
        return None
    # An installed extension records its install path in settings; only the
    # ghosts of Copy URL itself may be rebound.
    install_path = settings.get(extension, {}).get("path", "")
    if install_path and not install_path.endswith("/default/chromium/extensions/copy-url"):
        return None
    return extension

if mode == "check":
    sys.exit(0 if any(ghost_id(c) for c in commands.values()) else 1)

# Chromium keeps one shortcut per command, so a ghost may only be rebound
# when the pinned extension holds no copy-url binding of its own; further
# ghosts are dropped rather than doubled up.
pinned_bound = any(
    c.get("command_name") == "copy-url" and c.get("extension") == pinned_id
    for c in commands.values()
)

changed = False
for accelerator in list(commands):
    ghost = ghost_id(commands[accelerator])
    if not ghost:
        continue
    if pinned_bound:
        del commands[accelerator]
    else:
        commands[accelerator]["extension"] = pinned_id
        pinned_bound = True
        pinned_command = settings.get(pinned_id, {}).get("commands", {}).get("copy-url", {})
        if pinned_command:
            pinned_command["was_assigned"] = True
    settings.pop(ghost, None)
    changed = True

if changed:
    shutil.copy2(path, path.with_name(path.name + ".omarchy-copy-url-repair.bak"))
    path.write_text(json.dumps(preferences, separators=(",", ":")))
PY
)

profile_roots=(
  "$HOME/.config/chromium"
  "$HOME/.config/google-chrome"
  "$HOME/.config/google-chrome-beta"
  "$HOME/.config/google-chrome-unstable"
  "$HOME/.config/BraveSoftware/Brave-Browser"
  "$HOME/.config/BraveSoftware/Brave-Browser-Beta"
  "$HOME/.config/BraveSoftware/Brave-Browser-Nightly"
  "$HOME/.config/microsoft-edge"
  "$HOME/.config/microsoft-edge-beta"
  "$HOME/.config/microsoft-edge-dev"
  "$HOME/.config/vivaldi"
  "$HOME/.config/opera"
  "$HOME/.config/helium"
)

find_pending() {
  pending=()
  for profile_root in "${profile_roots[@]}"; do
    [[ -d $profile_root ]] || continue

    for preferences in "$profile_root"/*/Preferences; do
      [[ -f $preferences ]] || continue
      python3 -c "$repair_py" "$preferences" "$pinned_id" check || continue
      pending+=("$preferences")
    done
  done
}

unverified_repairs_exist() {
  local profile_root backup

  for profile_root in "${profile_roots[@]}"; do
    for backup in "$profile_root"/*/Preferences.omarchy-copy-url-repair.bak; do
      [[ -f $backup ]] && return 0
    done
  done

  return 1
}

profile_open() {
  [[ -L $1/SingletonLock || -e $1/SingletonLock || -S $1/SingletonSocket ]]
}

affected_profile_open() {
  local preferences backup profile_root

  for preferences in "${pending[@]}"; do
    profile_open "$(dirname "$(dirname "$preferences")")" && return 0
  done

  for profile_root in "${profile_roots[@]}"; do
    for backup in "$profile_root"/*/Preferences.omarchy-copy-url-repair.bak; do
      [[ -f $backup ]] || continue
      profile_open "$(dirname "$(dirname "$backup")")" && return 0
    done
  done

  return 1
}

find_pending
if (( ! ${#pending[@]} )) && ! unverified_repairs_exist; then
  exit 0
fi

while affected_profile_open; do
  if ! gum confirm "Close the browser windows to repair the Copy URL shortcut, then continue"; then
    echo "A running browser would undo the Copy URL shortcut repair." >&2
    echo "Close the browser windows, then run: omarchy-migrate" >&2
    exit 1
  fi
done

find_pending

for preferences in "${pending[@]}"; do
  python3 -c "$repair_py" "$preferences" "$pinned_id" repair
done

if affected_profile_open; then
  echo "A browser started during the Copy URL shortcut repair and may undo it on exit." >&2
  echo "Close the browser windows, then run: omarchy-migrate" >&2
  exit 1
fi

for preferences in "${pending[@]}"; do
  if python3 -c "$repair_py" "$preferences" "$pinned_id" check; then
    echo "A browser undid the Copy URL shortcut repair on exit." >&2
    echo "Close the browser windows, then run: omarchy-migrate" >&2
    exit 1
  fi
done
