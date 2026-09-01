echo "Save incoming Taildrop files to ~/Downloads"

if omarchy-cmd-present tailscale; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true

  if ! error=$(systemctl --user enable --now omarchy-tailscale-receive.service 2>&1); then
    echo "Could not enable omarchy-tailscale-receive.service: $error"
  fi
fi
