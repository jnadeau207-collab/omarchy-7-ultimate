echo "Stop waiting for the network before showing the desktop"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

as_root systemctl mask NetworkManager-wait-online.service >/dev/null 2>&1 || true
