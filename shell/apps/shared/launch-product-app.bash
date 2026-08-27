# Shared single-instance launcher for the two standalone product applications.
# This file is sourced by bin/omarchy-launch-settings and
# bin/omarchy-launch-agent-center; it is not a user-facing command.

product_app_usage() {
  local application="$1"
  local command_name scheme default_route

  if [[ $application == "settings" ]]; then
    command_name="omarchy-launch-settings"
    scheme="omarchy-settings"
    default_route="settings.overview"
  else
    command_name="omarchy-launch-agent-center"
    scheme="omarchy-agent"
    default_route="agent.overview"
  fi

  cat <<USAGE
Usage: $command_name [route|$scheme://link] [options]

Open or route the existing standalone application instance. The default route
is $default_route. Route IDs and arguments are validated against the shipped v1
catalog before a process is started or an IPC message is sent.

Options:
  --route ID            Open a registered route ID
  --args-json OBJECT    Typed non-secret arguments for a route ID
  --screen NAME         Request a connected output by exact name
  --anchor X,Y,W,H      Record the invoking surface anchor rectangle
  --seat ID             Record the invoking input seat
  --focus-return ID     Record the non-secret focus restoration target
  --source SOURCE       cli, desktop, shell, notification, or automation
  -h, --help            Show this help
USAGE
}

product_app_focus() {
  local app_id="$1"
  local clients address active attempt

  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    if clients=$(hyprctl clients -j 2>/dev/null); then
      address=$(jq -r --arg app "$app_id" '
        [.[] | select(.class == $app or .initialClass == $app)]
        | sort_by(.focusHistoryID // 999999)
        | (.[0].address // empty)
      ' <<<"$clients")
      if [[ -n $address ]]; then
        if OMARCHY_SHELL_IPC_TIMEOUT=0.5s "$OMARCHY_PATH/bin/omarchy-shell" window focus "$address" >/dev/null 2>&1; then
          for (( attempt = 0; attempt < 10; attempt++ )); do
            active=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty' 2>/dev/null)
            if [[ ${active,,} == ${address,,} ]]; then
              return 0
            fi
            sleep 0.02
          done
        fi

        # Recovery path for callers racing a shell restart. Hyprland can return
        # success for a stale Lua address handle, so verify the active address
        # instead of trusting the dispatcher exit status.
        hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })" >/dev/null 2>&1
        for (( attempt = 0; attempt < 10; attempt++ )); do
          active=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty' 2>/dev/null)
          if [[ ${active,,} == ${address,,} ]]; then
            return 0
          fi
          sleep 0.02
        done

        return 1
      fi
    fi
  fi

  return 0
}

product_app_activate() {
  local entrypoint="$1"
  local ipc_target="$2"
  local envelope="$3"
  local output

  if output=$(timeout --kill-after=1s "${OMARCHY_PRODUCT_IPC_TIMEOUT:-1s}" \
    qs ipc -n -p "$entrypoint" call -- "$ipc_target" activate "$envelope" 2>/dev/null); then
    if [[ $output == "ok" ]]; then
      return 0
    elif [[ $output == rejected:* ]]; then
      printf '%s\n' "Launch rejected by the application: ${output#rejected:}" >&2
      return 1
    else
      return 2
    fi
  else
    return 2
  fi
}

launch_product_app() {
  local application="$1"
  shift

  if (( $# > 0 )) && [[ $1 == "-h" || $1 == "--help" ]]; then
    product_app_usage "$application"
    return 0
  fi

  local entrypoint ipc_target app_id unit_name normalizer envelope activation_status start_failed=false
  normalizer="$OMARCHY_PATH/shell/apps/shared/normalize_launch.py"

  # IPC instance selection is display-scoped. Direct launches inherit the
  # session display, while support work over SSH/TTY does not; recover only the
  # owner-scoped Wayland socket name, just as bin/omarchy-shell does.
  if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
    local socket
    if socket=$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$UID}"/wayland-[0-9]* 2>/dev/null | grep -v '\.lock$' | head -n1); then
      export WAYLAND_DISPLAY=${socket##*/}
    else
      socket=""
    fi
  fi

  if [[ $application == "settings" ]]; then
    entrypoint="$OMARCHY_PATH/shell/ultimate-settings.qml"
    ipc_target="omarchy.settings"
    app_id="org.omarchy.Settings"
    unit_name="omarchy-ultimate-settings"
  elif [[ $application == "agent-center" ]]; then
    entrypoint="$OMARCHY_PATH/shell/ultimate-agent-center.qml"
    ipc_target="omarchy.agent-center"
    app_id="org.omarchy.AgentCenter"
    unit_name="omarchy-ultimate-agent-center"
  else
    printf 'Unknown standalone application: %s\n' "$application" >&2
    return 2
  fi

  if [[ ! -f $entrypoint || ! -f $normalizer ]]; then
    printf 'Standalone application files are incomplete for %s.\n' "$app_id" >&2
    return 1
  fi

  if envelope=$(python "$normalizer" "$application" "$@"); then
    :
  else
    return $?
  fi

  if product_app_activate "$entrypoint" "$ipc_target" "$envelope"; then
    product_app_focus "$app_id"
    return 0
  else
    activation_status=$?
    if (( activation_status == 1 )); then
      return 1
    fi
  fi

  if systemd-run --user --quiet --collect --unit="$unit_name" \
    --property=Type=exec --property=Restart=no \
    --setenv=QS_DISABLE_FILE_WATCHER=1 --setenv=QS_NO_RELOAD_POPUP=1 \
    quickshell -n -p "$entrypoint"; then
    start_failed=false
  else
    start_failed=true
  fi

  local attempt
  for (( attempt = 0; attempt < 100; attempt++ )); do
    if product_app_activate "$entrypoint" "$ipc_target" "$envelope"; then
      product_app_focus "$app_id"
      return 0
    else
      activation_status=$?
      if (( activation_status == 1 )); then
        return 1
      fi
    fi
    sleep 0.05
  done

  if [[ $start_failed == true ]]; then
    printf '%s is not responding, and its systemd user service could not be started.\n' "$app_id" >&2
  else
    printf '%s started but did not accept its validated route before the deadline.\n' "$app_id" >&2
  fi
  return 1
}
