echo "Supervise fcitx5 so CapsLock compose sequences can't silently die"

systemctl --user daemon-reload >/dev/null 2>&1 || true

if ! systemctl --user enable omarchy-fcitx5.service >/dev/null 2>&1; then
  wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  ln -sfn /usr/lib/systemd/user/omarchy-fcitx5.service \
    "$wants_dir/omarchy-fcitx5.service"
fi

if systemctl --user is-active --quiet graphical-session.target; then
  pkill -x fcitx5 >/dev/null 2>&1 || true

  if ! error=$(systemctl --user start omarchy-fcitx5.service 2>&1); then
    echo "Could not start omarchy-fcitx5.service: $error"
    echo "Compose sequences (CapsLock m s) will not work until the next login."
  fi
fi
