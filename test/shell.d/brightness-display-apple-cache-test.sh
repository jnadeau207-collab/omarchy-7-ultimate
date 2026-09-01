#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
tmp_cache="/tmp/omarchy-brightness-display-apple.device"
created_tmp_cache=0

cleanup() {
  rm -rf "$TMPDIR"
  if (( created_tmp_cache )); then
    rm -f "$tmp_cache"
  fi
}
trap cleanup EXIT

stub_dir="$TMPDIR/stubs"
mkdir -p "$stub_dir"

asd_log="$TMPDIR/asdcontrol.log"

cat >"$stub_dir/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
chmod +x "$stub_dir/sudo"

cat >"$stub_dir/asdcontrol" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >>"$asd_log"
# --detect reports nothing, so detection never yields a device.
if [[ \$1 == "--detect" ]]; then
  exit 0
fi
# A brightness read (a lone device arg) returns a plausible value; a set
# (<device> -- <step>) just succeeds.
if [[ \$# -eq 1 ]]; then
  printf '%s: BRIGHTNESS=30000\n' "\$1"
fi
exit 0
STUB
chmod +x "$stub_dir/asdcontrol"

cat >"$stub_dir/omarchy-osd" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$stub_dir/omarchy-osd"

run_wrapper() {
  local xdg="$1"
  shift
  : >"$asd_log"
  if [[ -n $xdg ]]; then
    XDG_RUNTIME_DIR="$xdg" PATH="$stub_dir:$ROOT/bin:$PATH" \
      omarchy-brightness-display-apple "$@" 2>&1 || true
  else
    env -u XDG_RUNTIME_DIR PATH="$stub_dir:$ROOT/bin:$PATH" \
      omarchy-brightness-display-apple "$@" 2>&1 || true
  fi
}

xdg_dir="$TMPDIR/xdg"
mkdir -p "$xdg_dir"
cache_file="$xdg_dir/omarchy-brightness-display-apple.device"

regular_file="$TMPDIR/not-a-device"
: >"$regular_file"

poisons=("/dev/null" "$regular_file" "/tmp/omarchy-evil")

if [[ ! -e /dev/hiddev999 ]]; then
  poisons+=("/dev/hiddev999")
fi

for poison in "${poisons[@]}"; do
  printf '%s\n' "$poison" >"$cache_file"
  output=$(run_wrapper "$xdg_dir" "+5%")
  if grep -qF -- "$poison -- +5%" "$asd_log"; then
    fail "wrapper handed a non-hiddev cache value to asdcontrol: $poison" "$output"
  fi
done
pass "wrapper rejects a cached path that is not a hiddev character device"

real_hiddev=""
for candidate in /dev/usb/hiddev* /dev/hiddev*; do
  if [[ -c $candidate ]]; then
    real_hiddev="$candidate"
    break
  fi
done
if [[ -n $real_hiddev ]]; then
  printf '%s\n' "$real_hiddev" >"$cache_file"
  run_wrapper "$xdg_dir" "+5%" >/dev/null
  grep -qF -- "$real_hiddev -- +5%" "$asd_log" ||
    fail "wrapper did not trust a valid cached hiddev node: $real_hiddev"
  pass "wrapper trusts a cached hiddev character device without re-detecting"
else
  pass "no /dev/hiddev* character device present; skipping the valid-cache case"
fi

if mkfifo "$tmp_cache" 2>/dev/null; then
  created_tmp_cache=1
  status=0
  env -u XDG_RUNTIME_DIR PATH="$stub_dir:$ROOT/bin:$PATH" \
    timeout 5 omarchy-brightness-display-apple "+5%" >/dev/null 2>&1 || status=$?
  rm -f "$tmp_cache"
  created_tmp_cache=0
  (( status != 124 )) ||
    fail "wrapper consulted the world-writable /tmp cache with no XDG_RUNTIME_DIR" \
      "it blocked reading the FIFO decoy at $tmp_cache"
  pass "wrapper ignores the /tmp cache path when XDG_RUNTIME_DIR is unset"
else
  pass "$tmp_cache already present or not safely creatable; skipping the /tmp-fallback case"
fi
