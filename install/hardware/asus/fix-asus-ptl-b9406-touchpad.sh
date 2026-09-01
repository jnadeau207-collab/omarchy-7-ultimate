
if omarchy-hw-asus-expertbook-b9406; then
  mkdir -p /etc/libinput
  cat > /etc/libinput/asus-expertbook-b9406.quirks <<'EOF'
[ASUS ExpertBook B9406 Touchpad]
MatchBus=i2c
MatchUdevType=touchpad
MatchVendor=0x093A
MatchProduct=0x4F05
MatchDMIModalias=dmi:*svnASUS*:pn*B9406*
AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE;
EOF
fi
