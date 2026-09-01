
if lspci -nn | grep -qE '\[8086:(e440|272b)\]'; then
  mkdir -p /etc/modprobe.d
  cat > /etc/modprobe.d/iwlwifi-disable-eht.conf <<'EOF'
# Temporary fix Dell XPS 14/16 on Panther lake
# Disable WiFi 7 (EHT) on Intel BE200/BE211 — broken RX rate adaptation
# Remove this file when fixes land in the iwlwifi EHT data path
options iwlwifi disable_11be=Y
EOF
fi
