
if omarchy-hw-intel; then
  cpu_model=$(grep -m1 "^model\s*:" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | tr -d ' ')
  cpu_model=${cpu_model:-0}
  if ((cpu_model >= 42)) && omarchy-battery-present; then
    omarchy-pkg-add thermald
    sudo systemctl enable thermald.service
  fi
fi
