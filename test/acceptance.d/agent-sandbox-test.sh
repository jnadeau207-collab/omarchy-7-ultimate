#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

command -v bwrap >/dev/null 2>&1 || fail "managed agent sandbox requires bubblewrap" "bubblewrap is missing; managed execution must fail closed"
command -v python3 >/dev/null 2>&1 || fail "managed agent sandbox has its runtime" "python3 is missing"

sandbox_root=$(mktemp -d)
trap 'rm -rf -- "$sandbox_root"' EXIT

mkdir -p "$sandbox_root/workspace" "$sandbox_root/artifacts" "$sandbox_root/host-home/.ssh" "$sandbox_root/host-home/.config/google-chrome" "$sandbox_root/host-home/.local/share/keyrings" "$sandbox_root/runtime/omarchy"
printf '%s\n' "workspace-visible" >"$sandbox_root/workspace/visible.txt"
printf '%s\n' "home-secret" >"$sandbox_root/host-home/secret.txt"
printf '%s\n' "ssh-secret" >"$sandbox_root/host-home/.ssh/id_ed25519"
printf '%s\n' "browser-secret" >"$sandbox_root/host-home/.config/google-chrome/Login Data"
printf '%s\n' "keyring-secret" >"$sandbox_root/host-home/.local/share/keyrings/login.keyring"
printf '%s\n' "not-a-real-socket" >"$sandbox_root/runtime/omarchy/fabric.sock"
readlink /proc/self/ns/net >"$sandbox_root/workspace/host-netns.txt"

bwrap_args=(
  --die-with-parent
  --new-session
  --unshare-all
  --clearenv
  --ro-bind /usr /usr
)

for runtime_tree in /lib /lib64; do
  if [[ -L $runtime_tree ]]; then
    bwrap_args+=(--symlink "$(readlink "$runtime_tree")" "$runtime_tree")
  elif [[ -d $runtime_tree ]]; then
    bwrap_args+=(--ro-bind "$runtime_tree" "$runtime_tree")
  fi
done

bwrap_args+=(
  --proc /proc
  --dev /dev
  --tmpfs /tmp
  --tmpfs /home
  --dir /run
  --dir /workspace
  --dir /artifacts
  --ro-bind "$sandbox_root/workspace" /workspace/task
  --bind "$sandbox_root/artifacts" /artifacts/task
  --setenv HOME /nonexistent
  --setenv PATH /usr/bin
  /usr/bin/python3
  -
)

if ! sandbox_output=$(
  HOME="$sandbox_root/host-home" \
    XDG_RUNTIME_DIR="$sandbox_root/runtime" \
    WAYLAND_DISPLAY=wayland-test \
    DBUS_SESSION_BUS_ADDRESS=unix:path="$sandbox_root/runtime/bus" \
    SSH_AUTH_SOCK="$sandbox_root/runtime/ssh-agent.sock" \
    timeout 20 bwrap "${bwrap_args[@]}" 2>&1 <<'PY'
import os
import pathlib
import socket


def require(condition, message):
    if not condition:
        raise SystemExit(message)


require(pathlib.Path("/workspace/task/visible.txt").read_text().strip() == "workspace-visible", "scoped workspace bind is missing")
pathlib.Path("/artifacts/task/result.txt").write_text("artifact-written\n")
require(not pathlib.Path("/home/secret.txt").exists(), "general home leaked into sandbox")
require(not pathlib.Path("/nonexistent/secret.txt").exists(), "host HOME leaked into sandbox")
require(not pathlib.Path("/run/omarchy/fabric.sock").exists(), "main Fabric socket leaked into sandbox")
require(not pathlib.Path("/run/user").exists(), "session runtime directory leaked into sandbox")
for name in ("WAYLAND_DISPLAY", "DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "SSH_AUTH_SOCK", "GNOME_KEYRING_CONTROL"):
    require(name not in os.environ, f"{name} leaked into sandbox")
host_netns = pathlib.Path("/workspace/task/host-netns.txt").read_text().strip()
current_netns = os.readlink("/proc/self/ns/net")
require(current_netns != host_netns, "sandbox is sharing the host network namespace")
probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
probe.settimeout(0.5)
require(probe.connect_ex(("1.1.1.1", 53)) != 0, "sandbox unexpectedly reached the network")
print("sandbox-boundaries-ok")
PY
); then
  fail "managed agent sandbox denies ambient desktop authority" "$sandbox_output"
fi

[[ $sandbox_output == *sandbox-boundaries-ok* ]] || fail "managed agent sandbox proves its isolation" "$sandbox_output"
[[ $(<"$sandbox_root/artifacts/result.txt") == "artifact-written" ]] || fail "managed agent sandbox writes only its scoped artifact bind"

pass "managed agent sandbox requires real bubblewrap and denies home, desktop IPC, secrets, main Fabric, and network"
pass "managed agent sandbox exposes only the explicit workspace and artifact scopes"
