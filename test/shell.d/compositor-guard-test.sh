#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

runtime_dir="$test_dir/run"
stub_bin="$test_dir/bin"
mkdir -p "$runtime_dir" "$stub_bin"

socket_bound=1
if command -v python3 >/dev/null; then
  python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' \
    "$runtime_dir/wayland-1" 2>/dev/null || socket_bound=0
else
  socket_bound=0
fi

attempts_log="$test_dir/hyprctl-attempts"

stub_hyprctl() {
  : >"$attempts_log"
  cat >"$stub_bin/hyprctl" <<STUB
#!/bin/bash
echo asked >>"$attempts_log"
exit $1
STUB
  chmod +x "$stub_bin/hyprctl"
}

stub_flaky_hyprctl() {
  : >"$attempts_log"
  cat >"$stub_bin/hyprctl" <<STUB
#!/bin/bash
echo asked >>"$attempts_log"
(( \$(grep -c asked "$attempts_log") > 1 ))
STUB
  chmod +x "$stub_bin/hyprctl"
}

attempts() {
  grep -c asked "$attempts_log" || true
}

run_guard() {
  env "$@" PATH="$stub_bin:$PATH" bash -c '
    source "$1/base-test.sh"
    ulimit -c unlimited 2>/dev/null || true
    require_compositor "sample runtime test"
    printf "launched with core limit %s\n" "$(ulimit -c)"
  ' bash "$SHELL_TEST_DIR" 2>&1 || printf 'guard exited %s\n' "$?"
}

skipped="ok - no Wayland compositor; skipping sample runtime test"

output=$(run_guard -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$runtime_dir")
[[ $output == "$skipped" ]] || fail "guard skips without a display" "$output"
pass "guard skips without a display"

output=$(run_guard WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$test_dir/blocked")
[[ $output == "$skipped" ]] || fail "guard skips when the socket is unreachable" "$output"
pass "guard skips when the socket is unreachable"

if (( ! socket_bound )); then
  pass "cannot bind a Unix socket here; skipping the cases that need one"
  exit 0
fi

stub_hyprctl 1
output=$(run_guard WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$runtime_dir" HYPRLAND_INSTANCE_SIGNATURE=test)
[[ $output == "$skipped" ]] || fail "guard skips when the compositor stopped answering" "$output"
pass "guard skips when the compositor stopped answering"

[[ $(attempts) == 3 ]] || fail "guard retries a silent compositor before giving up" "asked $(attempts) times"
pass "guard retries a silent compositor before giving up"

stub_flaky_hyprctl
output=$(run_guard WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$runtime_dir" HYPRLAND_INSTANCE_SIGNATURE=test)
[[ $output == "launched with core limit 0" ]] || fail "guard rides out a missed query" "$output"
pass "guard rides out a missed query"

stub_hyprctl 1
output=$(run_guard -u HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$runtime_dir")
[[ $output == "launched with core limit 0" ]] || fail "guard runs when hyprctl cannot be asked" "$output"
pass "guard runs when hyprctl cannot be asked"

[[ $(attempts) == 0 ]] || fail "guard leaves hyprctl alone without a signature" "asked $(attempts) times"
pass "guard leaves hyprctl alone without a signature"

stub_hyprctl 0
output=$(run_guard WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$runtime_dir" HYPRLAND_INSTANCE_SIGNATURE=test)
[[ $output == "launched with core limit 0" ]] || fail "guard runs with core dumps disabled" "$output"
pass "guard runs with core dumps disabled"
