#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-brcmfmac-supplicant.sh"
fix_t2="$ROOT/install/hardware/apple/fix-t2.sh"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1786391100.sh"

grep -q 'apple/fix-brcmfmac-supplicant.sh' "$all" ||
  fail "the brcmfmac quirk runs during hardware setup"

! grep -q 'brcmfmac' "$fix_t2" ||
  fail "only one leaf owns /etc/modprobe.d/brcmfmac.conf"
pass "the brcmfmac quirk has a single owner and runs during setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
conf="$test_tmp/etc/modprobe.d/brcmfmac.conf"
mkdir -p "$stub_bin" "$test_tmp/dmi"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

# Chatty like real lspci: keep writing well past the pipe buffer after the
# match, so a grep -q consumer would kill this stub with SIGPIPE and pipefail
# would read that as "no such hardware" (#6608).
if (( ${T2_HARDWARE:-0} == 1 )); then
  echo '01:00.0 Bridge [0680]: Apple Inc. T2 Security Chip [106b:1801]'
fi
if [[ -n ${WIFI_ID:-} ]]; then
  echo "03:00.0 Network controller [0280]: Broadcom Inc. Wireless [14e4:$WIFI_ID]"
fi
for _ in {1..4096}; do
  echo '02:00.0 Host bridge [0600]: Filler Device [ffff:0000]'
done
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

run_leaf() {
  local vendor="$1" wifi_id="${2:-}" t2="${3:-0}"
  rm -rf "$test_tmp/etc"
  mkdir -p "$test_tmp/etc"
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"

  local script="$test_tmp/leaf.sh"
  sed -e "s|/sys/class/dmi/id/sys_vendor|$test_tmp/dmi/sys_vendor|g" \
      -e "s|/etc/modprobe.d|$test_tmp/etc/modprobe.d|g" \
      "$leaf" >"$script"

  WIFI_ID="$wifi_id" T2_HARDWARE="$t2" PATH="$stub_bin:$PATH" \
    bash -eE -o pipefail -c 'source "$1"' bash "$script" </dev/null
}

run_leaf "Apple Inc." 4488 1 >/dev/null
grep -q 'feature_disable=0x82000' "$conf" 2>/dev/null ||
  fail "a T2 Mac still gets the quirk" "$(ls -R "$test_tmp/etc" 2>&1)"
pass "a T2 Mac still gets the quirk"

for wifi_id in 43ba 43bb 43bc 43a3 43dc 4464 4425 4433; do
  run_leaf "Apple Inc." "$wifi_id" 0 >/dev/null
  [[ -f $conf ]] || fail "a Mac without a T2 gets the quirk" "14e4:$wifi_id"
done
pass "every brcmfmac part on a Mac without a T2 gets the quirk"

run_leaf "Apple Computer, Inc." 43ba 0 >/dev/null
[[ -f $conf ]] || fail "the older Apple vendor string is recognized"
pass "the older Apple vendor string is recognized"

run_leaf "Apple Inc." 43a0 0 >/dev/null
[[ ! -f $conf ]] || fail "a Mac whose Wi-Fi brcmfmac does not drive is left alone"
pass "a Mac whose Wi-Fi brcmfmac does not drive is left alone"

run_leaf "LENOVO" 43ba 0 >/dev/null
[[ ! -f $conf ]] || fail "non-Apple hardware is left alone"
pass "non-Apple hardware is left alone"

run_leaf "Apple Inc." "" 0 >/dev/null
[[ ! -f $conf ]] || fail "a Mac with no wireless device is left alone"
pass "a Mac with no wireless device is left alone"

run_migration() {
  local vendor="$1" wifi_id="${2:-}" t2="${3:-0}"
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"
  : >"$calls"

  WIFI_ID="$wifi_id" T2_HARDWARE="$t2" PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_BRCMFMAC_DMI_VENDOR="$test_tmp/dmi/sys_vendor" \
    OMARCHY_BRCMFMAC_CONF="$conf" \
    bash -euo pipefail "$migration" >/dev/null
}

rm -rf "$test_tmp/etc"
run_migration "Apple Inc." 4488 1
grep -q '^options brcmfmac feature_disable=0x82000$' "$conf" 2>/dev/null ||
  fail "the migration fixes a T2 install that never got the quirk" "$(ls -R "$test_tmp/etc" 2>&1)"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration asks for the reboot that applies it" "$(cat "$calls")"
pass "the migration fixes a T2 install that never got the quirk"

run_migration "Apple Inc." 4488 1
(( $(grep -c '^options brcmfmac feature_disable=0x82000$' "$conf") == 1 )) ||
  fail "the migration is idempotent" "$(cat "$conf")"
[[ ! -s $calls ]] || fail "a repaired install is left untouched" "$(cat "$calls")"
pass "the migration is idempotent"

rm -rf "$test_tmp/etc"
run_migration "Apple Inc." 43ba 0
grep -q '^options brcmfmac feature_disable=0x82000$' "$conf" 2>/dev/null ||
  fail "the migration fixes an install on a Mac without a T2" "$(ls -R "$test_tmp/etc" 2>&1)"
pass "the migration fixes an install on a Mac without a T2"

printf '%s' 'options brcmfmac roamoff=1' >"$conf"
run_migration "Apple Inc." 43ba 0
grep -qx 'options brcmfmac roamoff=1' "$conf" ||
  fail "the migration keeps other options in the config" "$(cat "$conf")"
grep -qx 'options brcmfmac feature_disable=0x82000' "$conf" ||
  fail "the migration appends the quirk to an existing config" "$(cat "$conf")"
pass "the migration appends to a config that holds other options"

printf '#options brcmfmac feature_disable=0x82000\n' >"$conf"
run_migration "Apple Inc." 43ba 0
grep -qx 'options brcmfmac feature_disable=0x82000' "$conf" ||
  fail "a commented-out option does not count as applied" "$(cat "$conf")"
pass "a commented-out option does not count as applied"

rm -rf "$test_tmp/etc"
run_migration "Apple Inc." 43a0 0
[[ ! -e $conf ]] || fail "the migration skips a Mac brcmfmac does not drive" "$(cat "$conf")"
[[ ! -s $calls ]] || fail "the migration escalates nothing on unaffected Macs" "$(cat "$calls")"
pass "the migration skips hardware brcmfmac does not drive"
