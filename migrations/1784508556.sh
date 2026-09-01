echo "Pin browser password store to gnome-libsecret (prevents cookie/login loss on Hyprland)"

for conf in ~/.config/{chromium,brave,chrome,microsoft-edge-stable}-flags.conf; do
  if [[ -f $conf ]] && ! grep -q -- '--password-store=' "$conf"; then
    [[ -n $(tail -c1 "$conf") ]] && echo >>"$conf"
    echo '--password-store=gnome-libsecret' >>"$conf"
  fi
done
