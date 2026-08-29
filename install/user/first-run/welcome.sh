# Desktop Mode is the default product. Do not teach Power User chords that
# desktop.lua does not bind. Power User keeps the cheatsheet toast.
mode=desktop
mode_file="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/ultimate/mode"
if [[ -f $mode_file ]]; then
  mode=$(<"$mode_file")
  mode=${mode//$'\n'/}
fi

if [[ $mode == "power-user" ]]; then
  omarchy-notification-send -u critical -g  "Learn Keybindings" \
    $'Super + K for cheatsheet.\nSuper + Space for Omarchy Menu.' \
    --exec omarchy-menu-keybindings
else
  omarchy-notification-send -u critical "Your desktop" \
    $'Click Start for apps and places.\nFiles and Settings are on the Superbar.'
fi
