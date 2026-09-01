
if omarchy-hw-match "XPS" && omarchy-hw-intel-ptl; then
  echo "Detected Dell XPS Panther Lake, installing PTL kernel..."

  omarchy-pkg-add linux-ptl linux-ptl-headers
  pacman -Rdd --noconfirm linux linux-headers || true

  if pacman -Qq linux &>/dev/null; then
    echo "WARNING: stock linux kernel still installed alongside linux-ptl:"
    pacman -Qi linux | grep -i "required by"
  fi

  mkdir -p /etc/limine-entry-tool.d
  rm -f /etc/limine-entry-tool.d/dell-xps-panther-lake.conf
  cat > /etc/limine-entry-tool.d/zz-dell-xps-panther-lake.conf <<'EOF'
# Only show Panther Lake kernel in boot menu on Dell XPS Panther Lake
BOOT_ORDER="linux-ptl*, *fallback, Snapshots"
EOF
fi
