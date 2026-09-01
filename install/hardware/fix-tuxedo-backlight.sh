if cat /sys/class/dmi/id/sys_vendor 2>/dev/null | grep -qi "TUXEDO\|Slimbook"; then
  omarchy-pkg-add linux-headers tuxedo-drivers-nocompatcheck-dkms

  mkdir -p /etc/modprobe.d
  echo "blacklist clevo_xsm_wmi" > /etc/modprobe.d/blacklist-clevo-xsm-wmi.conf

  for f in /lib/modules/*/extra/clevo-xsm-wmi.ko; do
    if [[ -f $f ]]; then
      rm "$f"
    fi
  done
fi
