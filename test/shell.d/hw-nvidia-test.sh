#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

write_pci_devices() {
  rm -rf "$tmp_dir/devices"
  mkdir -p "$tmp_dir/devices"

  local index=0
  local spec
  for spec in "$@"; do
    local slot
    slot=$(printf '0000:%02x:00.0' "$index")
    mkdir -p "$tmp_dir/devices/$slot"
    printf '%s\n' "${spec%%:*}" >"$tmp_dir/devices/$slot/vendor"
    printf '%s\n' "$(cut -d: -f2 <<<"$spec")" >"$tmp_dir/devices/$slot/device"
    printf '%s\n' "${spec##*:}" >"$tmp_dir/devices/$slot/class"
    index=$((index + 1))
  done
}

hw_nvidia() {
  OMARCHY_PCI_DEVICES_PATH="$tmp_dir/devices" "$ROOT/bin/omarchy-hw-$1"
}

assert_detects() {
  local description="$1" nvidia="$2" gsp="$3" without_gsp="$4"

  local command
  for command in nvidia gsp without-gsp; do
    local expected
    case $command in
      nvidia) expected=$nvidia ;;
      gsp) expected=$gsp ;;
      without-gsp) expected=$without_gsp ;;
    esac

    local detector=nvidia
    [[ $command == "nvidia" ]] || detector="nvidia-$command"

    local actual=no
    hw_nvidia "$detector" && actual=yes

    [[ $actual == "$expected" ]] ||
      fail "$description" "omarchy-hw-$detector: expected $expected, got $actual"
  done

  pass "$description"
}

write_pci_devices 0x1002:0x15e7:0x030000
assert_detects "a machine without an NVIDIA GPU detects nothing" no no no

write_pci_devices 0x1002:0x15e7:0x030000 0x10de:0x2560:0x030200
assert_detects "a hybrid Ampere laptop detects a GSP GPU" yes yes no

write_pci_devices 0x10de:0x1f91:0x030000
assert_detects "Turing is the oldest generation with GSP firmware" yes yes no

write_pci_devices 0x10de:0x1d81:0x030000
assert_detects "Volta is the newest generation without GSP firmware" yes no yes

write_pci_devices 0x10de:0x1b80:0x030000
assert_detects "Pascal detects a GPU without GSP firmware" yes no yes

write_pci_devices 0x10de:0x1340:0x030000
assert_detects "Maxwell detects a GPU without GSP firmware" yes no yes

write_pci_devices 0x10de:0x1004:0x030000
assert_detects "Kepler is too old for either driver" yes no no

write_pci_devices 0x10de:0x06cd:0x030000
assert_detects "Fermi is too old for either driver" yes no no

write_pci_devices 0x10de:0x2c02:0x030000
assert_detects "Blackwell detects a GSP GPU" yes yes no

write_pci_devices 0x10de:0x228e:0x040300
assert_detects "a non-display NVIDIA function is not a GPU" no no no

write_pci_devices
assert_detects "a machine with no PCI devices detects nothing" no no no
