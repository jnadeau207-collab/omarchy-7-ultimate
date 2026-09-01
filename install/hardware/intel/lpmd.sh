
if omarchy-hw-intel && omarchy-battery-present; then
  cpu_model=$(grep -m1 "^model\s*:" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | tr -d ' ')
  if [[ "$cpu_model" =~ ^(151|154|170|172|183|186|189|191|204)$ ]]; then
    omarchy-pkg-add intel-lpmd
    sudo systemctl enable intel_lpmd.service
  fi
fi
