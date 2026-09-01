#!/bin/bash

set -euo pipefail

systemctl --user daemon-reload
systemctl --user enable --now \
  bt-agent.service \
  omarchy-recover-internal-monitor.service \
  omarchy-sleep-lock.service \
  omarchy-migrate-notify.service \
  omarchy-fcitx5.service \
  omarchy-crash-watch.service \
  omarchy-fabric.service \
  omarchy-hyprland-monitor-apply.service
