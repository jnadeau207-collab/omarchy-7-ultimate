notify_update() {
  omarchy-notification-send -u critical -g  "Update System" "Click to update the system." \
    --exec omarchy-launch-floating-terminal-with-presentation omarchy-update
}

notify_wifi() {
  omarchy-notification-send -u critical -g 󰖩 "Setup Wi-Fi" "Click to configure the wireless network." \
    --exec omarchy-shell shell toggle omarchy.network
}

announce_network() {
  nm-online -q -s -t 30

  if ! nm-online -q -x -t 30; then
    notify_wifi
    nm-online -q -t 3600 || return
  fi

  notify_update
}

announce_network &
