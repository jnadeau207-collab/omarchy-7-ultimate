if ! grep -qE '^PATH[[:space:]]' /etc/security/pam_env.conf; then
  cat >>/etc/security/pam_env.conf <<'EOF'

# Omarchy: give SSH commands and other non-shell logins the user-level tool paths
PATH DEFAULT=/usr/local/sbin:/usr/local/bin:/usr/bin:@{HOME}/.local/share/mise/shims:@{HOME}/.local/bin
EOF
fi
