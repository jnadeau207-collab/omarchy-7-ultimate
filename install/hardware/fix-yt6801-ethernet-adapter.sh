if lspci | grep -i "YT6801\|Motorcomm.*Ethernet"; then
  omarchy-pkg-add linux-headers yt6801-dkms
fi
