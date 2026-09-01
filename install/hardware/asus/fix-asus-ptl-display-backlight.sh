
if omarchy-hw-asus-expertbook-b9406 || omarchy-hw-asus-zenbook-ux5406aa; then
  sudo mkdir -p /etc/limine-entry-tool.d
  sudo tee /etc/limine-entry-tool.d/asus-ptl-display-backlight.conf >/dev/null <<'EOF'
# ASUS Panther Lake display backlight fix
KERNEL_CMDLINE[default]+=" xe.enable_dpcd_backlight=1"
EOF
fi
