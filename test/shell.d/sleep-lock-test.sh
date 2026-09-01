#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

sleep_lock="$ROOT/bin/omarchy-system-sleep-lock"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

setup_scenario() {
  scenario_dir="$tmpdir/$1"
  mock_bin="$scenario_dir/bin"
  call_log="$scenario_dir/calls"
  state_dir="$scenario_dir/state"
  notify_log="$scenario_dir/notifications"
  journal_log="$scenario_dir/journal"
  mkdir -p "$mock_bin" "$state_dir"
  : >"$notify_log"
  : >"$journal_log"

  mock_logind_window 5000000

  cat >"$mock_bin/omarchy-notification-send" <<SH
#!/bin/bash

printf '%s\n' "\$*" >>"$notify_log"
SH
  chmod +x "$mock_bin/omarchy-notification-send"
}

mock_logind_window() {
  cat >"$mock_bin/busctl" <<SH
#!/bin/bash

printf 't %s\n' $1
SH
  chmod +x "$mock_bin/busctl"
}

mock_clamshell() {
  cat >"$mock_bin/omarchy-hyprland-monitor-clamshell" <<SH
#!/bin/bash

echo clamshell >>"\$CALL_LOG"
sleep ${1:-0}
SH
  chmod +x "$mock_bin/omarchy-hyprland-monitor-clamshell"
}

run_sleep_lock() {
  local args=()
  [[ -n ${1:-} ]] && args=("$1")

  start_us=${EPOCHREALTIME//[!0-9]/}
  set +e
  CALL_LOG="$call_log" STATE_DIR="$state_dir" PATH="$mock_bin:$PATH" \
    "$sleep_lock" "${args[@]}" 2>"$journal_log"
  exit_status=$?
  set -e
  elapsed_us=$((10#${EPOCHREALTIME//[!0-9]/} - 10#$start_us))

  mapfile -t calls <"$call_log"
}

setup_scenario responsive
cat >"$mock_bin/omarchy-shell" <<'SH'
#!/bin/bash

printf 'shell %s\n' "$*" >>"$CALL_LOG"
if [[ $* == "lock lock" ]]; then
  printf 'ok\n'
elif [[ $* == "lock status" ]]; then
  printf '{"secure":true}\n'
fi
SH
chmod +x "$mock_bin/omarchy-shell"
mock_clamshell 2

run_sleep_lock 4000

(( exit_status == 0 )) ||
  fail "sleep lock succeeds once the session reports secure" "exit: $exit_status"
pass "sleep lock succeeds once the session reports secure"

[[ ${calls[0]} == "shell lock lock" ]] ||
  fail "sleep lock requests the session lock first" "first call: ${calls[0]}"
pass "sleep lock requests the session lock first"

[[ ${calls[1]} == "clamshell" && ${calls[2]} == "shell lock status" ]] ||
  fail "sleep lock checks security after clamshell reconciliation"
pass "sleep lock checks security after clamshell reconciliation"

(( elapsed_us < 1500000 )) ||
  fail "sleep lock bounds a stalled clamshell sync" "elapsed: ${elapsed_us}us"
pass "sleep lock bounds a stalled clamshell sync"

setup_scenario never_secure
cat >"$mock_bin/omarchy-shell" <<'SH'
#!/bin/bash

printf 'shell %s\n' "$*" >>"$CALL_LOG"
if [[ $* == "lock lock" ]]; then
  printf 'ok\n'
elif [[ $* == "lock status" ]]; then
  printf '{"secure":false}\n'
fi
SH
chmod +x "$mock_bin/omarchy-shell"
mock_clamshell

run_sleep_lock 1500

(( exit_status != 0 )) ||
  fail "sleep lock reports failure when the session never secures"
pass "sleep lock reports failure when the session never secures"

(( elapsed_us <= 1700000 )) ||
  fail "sleep lock gives up within its budget" "elapsed: ${elapsed_us}us"
pass "sleep lock gives up within its budget"

polls=0
for call in "${calls[@]}"; do
  [[ $call == "shell lock status" ]] && (( ++polls ))
done
(( polls > 1 )) ||
  fail "sleep lock keeps polling until the deadline" "polls: $polls"
pass "sleep lock keeps polling until the deadline"

setup_scenario retry_lock
cat >"$mock_bin/omarchy-shell" <<'SH'
#!/bin/bash

printf 'shell %s\n' "$*" >>"$CALL_LOG"

if [[ $* == "lock lock" ]]; then
  if [[ -f $STATE_DIR/requested ]]; then
    touch "$STATE_DIR/locked"
    printf 'ok\n'
    exit 0
  fi
  touch "$STATE_DIR/requested"
  exit 1
fi

if [[ $* == "lock status" ]]; then
  if [[ -f $STATE_DIR/locked ]]; then
    printf '{"secure":true}\n'
  else
    printf '{"secure":false}\n'
  fi
fi
SH
chmod +x "$mock_bin/omarchy-shell"
mock_clamshell

run_sleep_lock 4000

(( exit_status == 0 )) ||
  fail "sleep lock retries a failed lock request" "exit: $exit_status"
pass "sleep lock retries a failed lock request"

requests=0
for call in "${calls[@]}"; do
  [[ $call == "shell lock lock" ]] && (( ++requests ))
done
(( requests == 2 )) ||
  fail "sleep lock stops requesting once the lock lands" "requests: $requests"
pass "sleep lock stops requesting once the lock lands"

setup_scenario pending_lock
cat >"$mock_bin/omarchy-shell" <<'SH'
#!/bin/bash

printf 'shell %s\n' "$*" >>"$CALL_LOG"

if [[ $* == "lock lock" ]]; then
  exit 1
fi

if [[ $* == "lock status" ]]; then
  if [[ -f $STATE_DIR/pending_seen ]]; then
    printf '{"secure":true}\n'
  else
    touch "$STATE_DIR/pending_seen"
    printf '{"secure":false,"requested":true,"pending":true,"sessionLocked":false}\n'
  fi
fi
SH
chmod +x "$mock_bin/omarchy-shell"
mock_clamshell

run_sleep_lock 4000

(( exit_status == 0 )) ||
  fail "sleep lock succeeds after observing a pending lock" "exit: $exit_status"
pass "sleep lock succeeds after observing a pending lock"

requests=0
for call in "${calls[@]}"; do
  [[ $call == "shell lock lock" ]] && (( ++requests ))
done
(( requests == 1 )) ||
  fail "sleep lock does not retry an observed pending lock" "requests: $requests"
pass "sleep lock does not retry an observed pending lock"

setup_scenario missing_pam
cat >"$mock_bin/omarchy-shell" <<'SH'
#!/bin/bash

printf 'shell %s\n' "$*" >>"$CALL_LOG"
if [[ $* == "lock lock" ]]; then
  printf 'missing-pam\n'
fi
exit 0
SH
chmod +x "$mock_bin/omarchy-shell"
mock_clamshell

run_sleep_lock 4000

(( exit_status != 0 )) ||
  fail "sleep lock fails fast when the shell cannot lock at all"
(( elapsed_us < 500000 )) ||
  fail "sleep lock fails fast when the shell cannot lock at all" "elapsed: ${elapsed_us}us"
pass "sleep lock fails fast when the shell cannot lock at all"

[[ ${calls[*]} != *"lock status"* ]] ||
  fail "sleep lock stops polling a shell that refused to lock" "calls: ${calls[*]}"
pass "sleep lock stops polling a shell that refused to lock"

grep -qF "did not lock before suspend" "$notify_log" ||
  fail "sleep lock warns that the session was left unlocked" \
    "notifications: $(< "$notify_log")"
pass "sleep lock warns that the session was left unlocked"

grep -qF "suspending without a secure lock" "$journal_log" ||
  fail "sleep lock records the unlocked suspend in the journal" \
    "journal: $(< "$journal_log")"
pass "sleep lock records the unlocked suspend in the journal"

never_secures() {
  cat >"$mock_bin/omarchy-shell" <<'SH'
#!/bin/bash

printf 'shell %s\n' "$*" >>"$CALL_LOG"
if [[ $* == "lock lock" ]]; then
  printf 'ok\n'
elif [[ $* == "lock status" ]]; then
  printf '{"secure":false,"requested":true,"pending":true,"sessionLocked":false}\n'
fi
SH
  chmod +x "$mock_bin/omarchy-shell"
  mock_clamshell
}

setup_scenario derived_short_window
mock_logind_window 2000000
never_secures

run_sleep_lock

(( elapsed_us <= 1300000 )) ||
  fail "sleep lock derives its budget from logind's window" "elapsed: ${elapsed_us}us"
pass "sleep lock derives its budget from logind's window"

setup_scenario unreadable_window
cat >"$mock_bin/busctl" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin/busctl"
never_secures

run_sleep_lock

(( elapsed_us > 1300000 && elapsed_us <= 4300000 )) ||
  fail "sleep lock falls back to a conservative budget" "elapsed: ${elapsed_us}us"
pass "sleep lock falls back to a conservative budget when logind cannot be read"

setup_scenario capped_window
mock_logind_window 600000000
never_secures

run_sleep_lock

(( exit_status != 0 )) ||
  fail "sleep lock caps the budget a huge logind window would allow"
(( elapsed_us <= 12500000 )) ||
  fail "sleep lock caps the budget a huge logind window would allow" \
    "elapsed: ${elapsed_us}us"
pass "sleep lock caps the budget a huge logind window would allow"

inhibit_delay=$(sed -n 's/^InhibitDelayMaxSec=//p' "$ROOT/etc/systemd/logind.conf.d/20-inhibit-delay.conf")
budget_cap_ms=$(sed -n 's/^budget_cap_ms=//p' "$sleep_lock")

[[ -n $inhibit_delay && -n $budget_cap_ms ]] ||
  fail "sleep lock cap and logind window are both declared" \
    "window: ${inhibit_delay:-unset} cap: ${budget_cap_ms:-unset}"
(( budget_cap_ms < inhibit_delay * 1000 )) ||
  fail "sleep lock cap leaves logind room to act" \
    "cap: ${budget_cap_ms}ms window: ${inhibit_delay}s"
pass "sleep lock cap stays inside the shipped logind inhibitor window"
