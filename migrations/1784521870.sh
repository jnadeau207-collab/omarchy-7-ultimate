echo "Stop the migration notifier from re-triggering itself in a loop"

systemctl --user daemon-reload >/dev/null 2>&1 || true
systemctl --user reset-failed omarchy-update-user-notify.path >/dev/null 2>&1 || true
systemctl --user restart omarchy-update-user-notify.path >/dev/null 2>&1 || true
systemctl --user enable omarchy-update-user-notify.service >/dev/null 2>&1 || true
