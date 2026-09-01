echo "Only check for pending migrations at login, not on every package update"

wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"

systemctl --user daemon-reload >/dev/null 2>&1 || true

systemctl --user stop omarchy-update-user-notify.path >/dev/null 2>&1 || true

if ! systemctl --user enable omarchy-migrate-notify.service >/dev/null 2>&1; then
  mkdir -p "$wants_dir"
  ln -sfn /usr/lib/systemd/user/omarchy-migrate-notify.service \
    "$wants_dir/omarchy-migrate-notify.service"
fi

rm -f "$wants_dir/omarchy-update-user-notify.path" \
  "$wants_dir/omarchy-update-user-notify.service"

systemctl --user reset-failed omarchy-update-user-notify.path >/dev/null 2>&1 || true
systemctl --user daemon-reload >/dev/null 2>&1 || true
