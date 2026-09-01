echo "Let systemd-oomd kill a runaway app instead of the whole session"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

if systemctl is-enabled --quiet systemd-oomd.service 2>/dev/null; then
  as_root systemctl try-restart systemd-oomd.service >/dev/null 2>&1 || true
else
  as_root systemctl enable --now systemd-oomd.service >/dev/null 2>&1 ||
    echo "Could not enable systemd-oomd.service; memory pressure will still take the session down."
fi

systemctl --user daemon-reload >/dev/null 2>&1 || true
