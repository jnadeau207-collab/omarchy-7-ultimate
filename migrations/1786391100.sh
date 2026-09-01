echo "Run the WPA handshake in software on Macs with Broadcom Wi-Fi"

dmi_vendor="${OMARCHY_BRCMFMAC_DMI_VENDOR:-/sys/class/dmi/id/sys_vendor}"
conf="${OMARCHY_BRCMFMAC_CONF:-/etc/modprobe.d/brcmfmac.conf}"

sys_vendor="$(cat "$dmi_vendor" 2>/dev/null || true)"

if ! lspci -nn | grep "106b:180[12]" >/dev/null &&
  ! { [[ $sys_vendor == Apple* ]] &&
    lspci -nn | grep -E "14e4:(43ba|43bb|43bc|43a3|43dc|4464|4488|4425|4433)" >/dev/null; }; then
  exit 0
fi

if [[ -f $conf ]] &&
  grep -Eq '^[[:space:]]*options[[:space:]]+brcmfmac[[:space:]].*feature_disable=0x82000' "$conf"; then
  exit 0
fi

sudo mkdir -p "$(dirname "$conf")"

sudo tee -a "$conf" >/dev/null <<'EOF'

# Broadcom's firmware supplicant and authenticator fail the WPA four-way
# handshake on Apple hardware, which surfaces as a rejected password. Disable
# both so wpa_supplicant performs the handshake instead.
options brcmfmac feature_disable=0x82000
EOF

omarchy-state set reboot-required
