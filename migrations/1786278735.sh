echo "Detect dropped SSH connections quickly instead of leaving terminals hung"

conf="/etc/ssh/ssh_config.d/20-omarchy-keepalive.conf"

if [[ ! -f $conf ]]; then
  sudo install -d -m 755 /etc/ssh/ssh_config.d
  sudo tee "$conf" >/dev/null <<'EOF'
# Omarchy: notice dropped connections quickly instead of hanging until TCP
# times out. Settings in ~/.ssh/config take precedence over these defaults.
Host *
  ServerAliveInterval 15
  ServerAliveCountMax 3
  ConnectTimeout 10
EOF
  sudo chmod 644 "$conf"
fi
