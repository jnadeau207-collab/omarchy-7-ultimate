echo "Give SSH commands the user-level tool paths via the PAM environment"

grep -qE '^PATH[[:space:]]' /etc/security/pam_env.conf && exit 0

sudo tee -a /etc/security/pam_env.conf >/dev/null <<'EOF'

# Omarchy: give SSH commands and other non-shell logins the user-level tool paths
PATH DEFAULT=/usr/local/sbin:/usr/local/bin:/usr/bin:@{HOME}/.local/share/mise/shims:@{HOME}/.local/bin
EOF
