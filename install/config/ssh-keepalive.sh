if [[ ! -f /etc/ssh/ssh_config.d/20-omarchy-keepalive.conf ]]; then
  install -d -m 755 /etc/ssh/ssh_config.d
  cat >/etc/ssh/ssh_config.d/20-omarchy-keepalive.conf <<'EOF'
# Omarchy: notice dropped connections quickly instead of hanging until TCP
# times out. Settings in ~/.ssh/config take precedence over these defaults.
Host *
  ServerAliveInterval 15
  ServerAliveCountMax 3
  ConnectTimeout 10
EOF
  chmod 644 /etc/ssh/ssh_config.d/20-omarchy-keepalive.conf
fi
