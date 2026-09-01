if omarchy-hw-surface; then
  product_name="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
  echo "Detected Surface Device"

  if [[ $product_name != "Surface Laptop 3" ]]; then
    echo "Untested Surface Device: $product_name, additional modules may be required for your device."
  fi

  echo "Attempting to autodetect required pinctrl module"
  pinctrl_module=$(lsmod | grep pinctrl_ | cut -f 1 -d" " || true)
  if [[ -z $pinctrl_module ]]; then
    echo "Failed to autodetect pinctrl module."
  else
    echo "Detected pinctrl module: $pinctrl_module"
    mkdir -p /etc/mkinitcpio.conf.d
    echo "MODULES=(${pinctrl_module} surface_aggregator surface_aggregator_registry surface_aggregator_hub surface_hid_core surface_hid surface_kbd intel_lpss_pci 8250_dw)" > \
      /etc/mkinitcpio.conf.d/surface_device_modules.conf
  fi
fi
