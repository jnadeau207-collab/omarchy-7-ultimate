
pci_info=$(lspci -nn)

if (echo "$pci_info" | grep -q "14e4:43a0" || echo "$pci_info" | grep -q "14e4:4331"); then
  echo "BCM4360 / BCM4331 detected"
  omarchy-pkg-add broadcom-wl dkms linux-headers
fi
