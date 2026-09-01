echo "Give the pre-suspend lock a window it can actually finish in"

sudo systemctl reload systemd-logind >/dev/null 2>&1 || true

dropin=/etc/systemd/logind.conf.d/20-inhibit-delay.conf
expected_s=$(sed -n 's/^InhibitDelayMaxSec=//p' "$dropin" 2>/dev/null || true)
effective_us=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
  org.freedesktop.login1.Manager InhibitDelayMaxUSec 2>/dev/null | awk '{print $2}' || true)

if [[ -z $expected_s || $effective_us != $((expected_s * 1000000)) ]]; then
  omarchy-state set reboot-required
fi
