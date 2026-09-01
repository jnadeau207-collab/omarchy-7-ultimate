echo "Repair the pre-suspend lock monitor's graphical session environment"

user_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
sleep_lock_unit="$user_config_home/systemd/user/omarchy-sleep-lock.service"
sleep_lock_dropin_dir="$user_config_home/systemd/user/omarchy-sleep-lock.service.d"
sleep_lock_dropin="$sleep_lock_dropin_dir/90-omarchy-session-environment.conf"

if [[ -f $sleep_lock_unit ]]; then
  mkdir -p "$sleep_lock_dropin_dir"
  printf '%s\n' \
    '[Unit]' \
    'After=dbus.socket wayland-session-waitenv.service' \
    'Requires=dbus.socket' \
    'PartOf=graphical-session.target' \
    'ConditionEnvironment=OMARCHY_PATH' \
    'ConditionEnvironment=WAYLAND_DISPLAY' >"$sleep_lock_dropin"
fi

user_manager_socket="${XDG_RUNTIME_DIR:-/run/user/$UID}/systemd/private"
if ! error=$(systemctl --user show-environment 2>&1); then
  if [[ -S $user_manager_socket ]]; then
    echo "Could not reach the running user service manager: $error"
    echo "The pre-suspend lock repair will be retried by omarchy-migrate."
    exit 1
  fi
  exit 0
fi

if ! error=$(systemctl --user daemon-reload 2>&1); then
  echo "Could not reload the user service manager: $error"
  echo "The pre-suspend lock repair will be retried by omarchy-migrate."
  exit 1
fi

if ! graphical_state=$(systemctl --user show --property=ActiveState --value graphical-session.target 2>&1); then
  echo "Could not inspect graphical-session.target: $graphical_state"
  echo "The pre-suspend lock repair will be retried by omarchy-migrate."
  exit 1
fi

if [[ $graphical_state == "active" ]]; then
  if ! error=$(systemctl --user reset-failed omarchy-sleep-lock.service 2>&1); then
    echo "Could not reset omarchy-sleep-lock.service: $error"
    echo "The pre-suspend lock repair will be retried by omarchy-migrate."
    exit 1
  elif ! error=$(systemctl --user restart omarchy-sleep-lock.service 2>&1); then
    echo "Could not restart omarchy-sleep-lock.service: $error"
    echo "The pre-suspend lock repair will be retried by omarchy-migrate."
    exit 1
  elif ! sleep_lock_state=$(systemctl --user show --property=ActiveState --value omarchy-sleep-lock.service 2>&1); then
    echo "Could not inspect omarchy-sleep-lock.service: $sleep_lock_state"
    echo "The pre-suspend lock repair will be retried by omarchy-migrate."
    exit 1
  elif [[ $sleep_lock_state != "active" ]]; then
    echo "omarchy-sleep-lock.service did not stay active after restart."
    echo "The pre-suspend lock repair will be retried by omarchy-migrate."
    exit 1
  fi
else
  if ! error=$(systemctl --user stop omarchy-sleep-lock.service 2>&1); then
    echo "Could not stop stale omarchy-sleep-lock.service: $error"
    echo "The pre-suspend lock repair will be retried by omarchy-migrate."
    exit 1
  elif ! error=$(systemctl --user reset-failed omarchy-sleep-lock.service 2>&1); then
    echo "Could not reset omarchy-sleep-lock.service: $error"
    echo "The pre-suspend lock repair will be retried by omarchy-migrate."
    exit 1
  fi
fi
