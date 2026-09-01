echo "Remove the tmux alert hooks and its bar indicator"

tmux_config="$HOME/.config/tmux/tmux.conf"

if [[ -f $tmux_config ]]; then
  tmp=$(mktemp)

  if awk '
    function flush(count,   i) { for (i = 0; i < count; i++) print "" }

    function keep(line) {
      if (dropped) { if (printed && blanks) print "" }
      else flush(blanks)

      blanks = 0
      dropped = 0
      printed = 1
      print line
    }

    /^[[:space:]]*# Alerts$/ && header == "" { header = $0; next }

    /^[[:space:]]*set-hook -g alert-(bell|activity|silence) .*omarchy\.indicators refresh/ ||
    /^[[:space:]]*set-hook -g (after-select-window|client-session-changed|client-focus-(in|out))(\[[0-9]+\])? .*(omarchy-tmux-alert track|omarchy\.indicators refresh)/ {
      header = ""
      dropped = 1
      next
    }

    /^[[:space:]]*$/ {
      if (header != "") { keep(header); header = "" }
      blanks++
      next
    }

    {
      if (header != "") { keep(header); header = "" }
      keep($0)
    }

    END {
      if (header != "") keep(header)
      if (!dropped) flush(blanks)
    }
  ' "$tmux_config" >"$tmp"; then
    if ! cmp -s "$tmp" "$tmux_config"; then
      cat "$tmp" >"$tmux_config"
      omarchy-restart-tmux
    fi
  else
    echo "Could not rewrite $tmux_config; remove the tmux alert hooks by hand."
  fi

  rm -f "$tmp"
fi

if tmux has-session 2>/dev/null; then
  while read -r hook; do
    [[ -n $hook ]] || continue
    tmux set-hook -gu "$hook" 2>/dev/null || true
  done < <(tmux show-hooks -g 2>/dev/null |
    awk '$0 ~ /omarchy-tmux-alert|omarchy\.indicators refresh/ { print $1 }')

  while read -r window; do
    [[ -n $window ]] || continue
    tmux set-option -wqu -t "$window" @omarchy_unfocused_activity 2>/dev/null || true
  done < <(tmux list-windows -a -F '#{window_id}' 2>/dev/null)
fi

config_file="$HOME/.config/omarchy/shell.json"

if [[ -s $config_file ]] && grep -q 'TmuxAlert' "$config_file"; then
  tmp=$(mktemp)

  if jq '
    def entry_id:
      if type == "string" then . elif type == "object" then (.id // "") else "" end;

    def without_tmux_alert: map(select(entry_id != "TmuxAlert"));

    def stripped($key):
      if (.[$key] | type) == "array" then .[$key] |= without_tmux_alert else . end;

    def picked:
      if (.items | type) == "array" and (.items | length) > 0 then .items
      elif (.indicators | type) == "array" and (.indicators | length) > 0 then .indicators
      else null end;

    def cleaned:
      if type == "object" and .id == "omarchy.indicators" then stripped("items") | stripped("indicators") else . end;

    def emptied:
      type == "object" and .id == "omarchy.indicators" and
      picked != null and (cleaned | picked) == null;

    walk(if type == "array" then map(select(emptied | not)) | map(cleaned) else . end)
  ' "$config_file" >"$tmp"; then
    cat "$tmp" >"$config_file"
  else
    echo "Could not rewrite $config_file; remove the TmuxAlert indicator by hand."
  fi

  rm -f "$tmp"
fi
