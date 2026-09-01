echo "Unmask wpa_supplicant so NetworkManager can bring wifi back"

state=$(systemctl is-enabled wpa_supplicant.service 2>/dev/null || true)
[[ $state == masked* ]] || exit 0

sudo systemctl unmask wpa_supplicant.service

state=$(systemctl is-enabled wpa_supplicant.service 2>/dev/null || true)
if [[ $state == "masked-runtime" ]]; then
  sudo systemctl unmask --runtime wpa_supplicant.service
fi

if [[ ${OMARCHY_UPGRADE_TO_QUATTRO_LIVE:-0} != "1" ]] &&
  systemctl is-active --quiet NetworkManager.service 2>/dev/null &&
  [[ $(LC_ALL=C nmcli -t -f TYPE,STATE device 2>/dev/null || true) == *"wifi:unavailable"* ]]; then
  sudo systemctl restart NetworkManager.service || true
fi
