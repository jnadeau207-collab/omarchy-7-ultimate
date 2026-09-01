
if omarchy-hw-asus-expertbook-b9406; then
  mkdir -p /etc/limine-entry-tool.d
  cat > /etc/limine-entry-tool.d/asus-expertbook-b9406-display.conf <<'EOF'
# ASUS ExpertBook B9406 (Panther Lake / Xe3) display workaround
KERNEL_CMDLINE[default]+=" xe.enable_panel_replay=0"
EOF
fi
