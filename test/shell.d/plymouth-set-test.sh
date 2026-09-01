#!/bin/bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

test_tmp=$(mktemp -d)
[[ -n $test_tmp && -d $test_tmp ]] ||
  fail "the test creates its own scratch directory before touching anything"
secret="$test_tmp/secret"
trap 'chmod 0600 "$secret" 2>/dev/null || true; rm -rf -- "$test_tmp"' EXIT

plymouth_theme_assets=(
  bullet.png
  entry.png
  lock.png
  logo.png
  omarchy.plymouth
  omarchy.script
  preview-unlock.png
  progress_bar.png
  progress_box.png
)
plymouth_default_assets=("${plymouth_theme_assets[@]}" logos/oma.png)
sddm_theme_assets=(Main.qml bullet.png entry-failed.png entry.png lock-failed.png lock.png logo.png)
sddm_default_assets=("${sddm_theme_assets[@]}" metadata.desktop theme.conf)

packaged_plymouth_assets=$(find "$ROOT/default/plymouth" -type f -printf '%P\n' | LC_ALL=C sort)
allowlisted_plymouth_assets=$(printf '%s\n' "${plymouth_default_assets[@]}" | LC_ALL=C sort)
[[ $packaged_plymouth_assets == "$allowlisted_plymouth_assets" ]] ||
  fail "Plymouth refresh allowlist differs from the packaged asset set" "$packaged_plymouth_assets"
pass "Plymouth refresh allowlist covers every packaged asset"

packaged_sddm_assets=$(find "$ROOT/default/sddm/omarchy" -type f -printf '%P\n' | LC_ALL=C sort)
allowlisted_sddm_assets=$(printf '%s\n' "${sddm_default_assets[@]}" | LC_ALL=C sort)
[[ $packaged_sddm_assets == "$allowlisted_sddm_assets" ]] ||
  fail "SDDM refresh allowlist differs from the packaged asset set" "$packaged_sddm_assets"
pass "SDDM refresh allowlist covers every packaged asset"

printf 'not yours\n' >"$secret"
ln -s "$secret" "$test_tmp/logo-link.png"

output=$(OMARCHY_PATH="$ROOT" /bin/bash "$ROOT/bin/omarchy-plymouth-set" '#1d2021' '#ebdbb2' "$test_tmp/logo-link.png" 2>&1)
status=$?

(( status != 0 )) || fail "omarchy-plymouth-set refuses a symlinked logo"
[[ $output == *"symlink"* ]] || fail "omarchy-plymouth-set says why it refused the logo" "$output"

pass "a themed logo cannot republish a file it merely points at"

if unshare --user --map-root-user true 2>/dev/null; then
  output=$(unshare --user --map-root-user env OMARCHY_PATH="$ROOT" /bin/bash "$ROOT/bin/omarchy-plymouth-set" '#1d2021' '#ebdbb2' "$secret" 2>&1)
  status=$?
  (( status != 0 )) || fail "omarchy-plymouth-set refuses to run as root"
  [[ $output == *"as your user"* && $output == *"not under sudo"* ]] ||
    fail "the root refusal explains how to invoke the publisher safely" "$output"
else
  grep -A2 -Eq '^if \(\( EUID == 0 \)\); then$' "$ROOT/bin/omarchy-plymouth-set" ||
    fail "omarchy-plymouth-set retains its root-invocation guard"
fi
pass "the logo descriptor can only be opened by an unprivileged caller"

require_command node

unlock_action=$(node -e '
  const fs = require("fs")
  const path = require("path")
  const menu = require(path.join(process.env.ROOT, "shell/plugins/menu/MenuModel.js"))
  const items = menu.parseMenuJsonc(fs.readFileSync(path.join(process.env.ROOT, "default/omarchy/omarchy-menu.jsonc"), "utf8"))
  process.stdout.write(items.find(item => item.id === "style.unlock").action)
')

[[ -n $unlock_action ]] || fail "the shipped menu still carries a style.unlock action"

stub_dir="$test_tmp/stubs"
mkdir -p "$stub_dir"

canary="$test_tmp/canary"
set_args="$test_tmp/set-args"
reset_marker="$test_tmp/reset-ran"

cat >"$stub_dir/omarchy-test-canary" <<STUB
#!/bin/bash
printf 'ran\n' >"$canary"
STUB

cat >"$stub_dir/omarchy-plymouth-switcher" <<'STUB'
#!/bin/bash
printf '%s\n' "$OMARCHY_TEST_UNLOCK_NAME"
STUB

ln -s "$ROOT/bin/omarchy-launch-floating-terminal-with-presentation" "$stub_dir/omarchy-launch-floating-terminal-with-presentation"

cat >"$stub_dir/omarchy-restart-gum" <<'STUB'
#!/bin/bash
:
STUB

cat >"$stub_dir/setsid" <<'STUB'
#!/bin/bash
while (( $# >= 3 )); do
  if [[ $1 == "bash" && $2 == "-c" ]]; then
    exec bash -c "$3"
  fi
  shift
done
exit 97
STUB

cat >"$stub_dir/omarchy-plymouth-set-by-theme" <<'STUB'
#!/bin/bash
printf '%s\n' "$#" "$@" >"$OMARCHY_TEST_SET_ARGS"
STUB

cat >"$stub_dir/omarchy-plymouth-reset" <<'STUB'
#!/bin/bash
printf 'ran\n' >"$OMARCHY_TEST_RESET_MARKER"
STUB

for command in omarchy-show-logo omarchy-show-done; do
  printf '#!/bin/bash\nexit 0\n' >"$stub_dir/$command"
done

chmod +x "$stub_dir"/*

run_unlock_action() {
  rm -f "$canary" "$set_args" "$reset_marker"

  PATH="$stub_dir:$PATH" \
    OMARCHY_TEST_UNLOCK_NAME="$1" \
    OMARCHY_TEST_SET_ARGS="$set_args" \
    OMARCHY_TEST_RESET_MARKER="$reset_marker" \
    bash -c "$unlock_action" >/dev/null 2>&1
}

for name in "a';omarchy-test-canary;'b" 'a$(omarchy-test-canary)b' 'a`omarchy-test-canary`b' 'a b' '-a'; do
  run_unlock_action "$name"

  [[ ! -e $canary ]] || fail "a theme name reaches the unlock screen as data, not as shell" "ran for: $name"
  [[ $(cat "$set_args" 2>/dev/null) == $'1\n'"$name" ]] ||
    fail "the unlock screen gets the theme name whole" "$name: $(cat "$set_args" 2>/dev/null)"
done

pass "a theme name cannot carry a command into the unlock screen"

run_unlock_action "tokyo-night"
[[ $(cat "$set_args" 2>/dev/null) == $'1\ntokyo-night' ]] ||
  fail "an ordinary theme name still reaches omarchy-plymouth-set-by-theme" "$(cat "$set_args" 2>/dev/null)"

run_unlock_action "default"
[[ -e $reset_marker ]] || fail "picking default still resets the unlock screen"
[[ ! -e $set_args ]] || fail "picking default does not look up a theme named default" "$(cat "$set_args")"

pass "the unlock picker still applies a theme and still resets on default"

fake_bin="$test_tmp/bin"
root_tools="$test_tmp/root-tools"
stages="$test_tmp/stages"
mkdir -p "$fake_bin" "$root_tools" "$stages"

cat >"$fake_bin/sudo" <<'SH'
#!/bin/bash
set -u

for argument in "$@"; do
  if [[ $argument == *"$TEST_STAGES"* ]]; then
    printf '%s\n' "$argument" >>"$TEST_LEAK_LOG"
  fi
done

case "$1" in
/bin/bash)
  [[ ${2:-} == -c && $# == 9 ]] || exit 90
  code=$3
  shell_name=$4
  shift 4
  printf 'root transaction\n' >>"$TEST_SUDO_LOG"

  code=${code/PATH=\/usr\/bin:\/bin/PATH=$TEST_ROOT_TOOLS:\/usr\/bin:\/bin}
  code=${code/omarchy_conf=\/etc\/omarchy.conf/omarchy_conf=$TEST_OMARCHY_CONF}
  code=${code/theme_dir=\/usr\/share\/plymouth\/themes\/omarchy/theme_dir=$TEST_FAKE_ROOT\/usr\/share\/plymouth\/themes\/omarchy}
  code=${code/sddm_dir=\/usr\/share\/sddm\/themes\/omarchy/sddm_dir=$TEST_FAKE_ROOT\/usr\/share\/sddm\/themes\/omarchy}

  [[ $code == *"PATH=$TEST_ROOT_TOOLS:/usr/bin:/bin"* ]] || exit 94
  [[ $code == *"omarchy_conf=$TEST_OMARCHY_CONF"* ]] || exit 94
  [[ $code == *"theme_dir=$TEST_FAKE_ROOT/usr/share/plymouth/themes/omarchy"* ]] || exit 94
  [[ $code == *"sddm_dir=$TEST_FAKE_ROOT/usr/share/sddm/themes/omarchy"* ]] || exit 94

  PATH="$TEST_ROOT_TOOLS:/usr/bin:/bin" \
    /bin/bash -c "$code" "$shell_name" "$@"
  ;;
plymouth-set-default-theme | limine-mkinitcpio | mkinitcpio)
  printf 'command %s\n' "$*" >>"$TEST_SUDO_LOG"
  exit 0
  ;;
*)
  echo "unexpected sudo command: $*" >&2
  exit 92
  ;;
esac
SH

cat >"$root_tools/stat" <<'SH'
#!/bin/bash
last=${!#}
if [[ ${1:-} == -c && ${2:-} == %u ]]; then
  if [[ (-n ${TEST_UNTRUSTED_SOURCE:-} && $last == "$TEST_UNTRUSTED_SOURCE"*) ||
        (-n ${TEST_UNTRUSTED_CONFIGURATION:-} && $last == "$TEST_UNTRUSTED_CONFIGURATION"*) ]]; then
    printf '1000\n'
    exit 0
  fi
  printf '0\n'
  exit 0
fi
if [[ ${1:-} == -c && ${2:-} == %a && $last == /tmp ]]; then
  printf '755\n'
  exit 0
fi
exec /usr/bin/stat "$@"
SH

cat >"$root_tools/chown" <<'SH'
#!/bin/bash
last=${!#}
[[ $last == "$TEST_FAKE_ROOT"* || $last == /tmp/omarchy-plymouth.* ]] || exit 93
exit 0
SH

cat >"$root_tools/install" <<'SH'
#!/bin/bash
mode=
while (( $# )); do
  case "$1" in
  -o | -g)
    shift 2
    ;;
  -m)
    mode=$2
    shift 2
    ;;
  --)
    shift
    break
    ;;
  *)
    exit 96
    ;;
  esac
done

(( $# == 2 )) || exit 96
[[ $mode == "0600" || $mode == "0644" ]] || exit 96
destination=$2
[[ $destination == "$TEST_FAKE_ROOT"* || $destination == /tmp/omarchy-plymouth.* ]] || exit 93
exec /usr/bin/install -m "$mode" -- "$1" "$destination"
SH

cat >"$root_tools/magick" <<'SH'
#!/bin/bash
source=$1
destination=${@: -1}
[[ $source == "$destination" ]] || /usr/bin/cp -- "$source" "$destination"
SH

cat >"$fake_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 1
SH

chmod +x "$fake_bin"/* "$root_tools"/*

printf 'caller-selected logo\n' >"$test_tmp/logo.png"

setup_run() {
  run_dir=$(mktemp -d "$test_tmp/run.XXXXXXXX")
  fake_root="$run_dir/root"
  sudo_log="$run_dir/sudo.log"
  leak_log="$run_dir/leaked-stage-path.log"
  omarchy_conf="$run_dir/omarchy.conf"
  theme="$fake_root/usr/share/plymouth/themes/omarchy"
  sddm="$fake_root/usr/share/sddm/themes/omarchy"

  mkdir -p "$theme/logos" "$sddm"
  chmod 0755 \
    "$fake_root/usr" \
    "$fake_root/usr/share" \
    "$fake_root/usr/share/plymouth" \
    "$fake_root/usr/share/plymouth/themes" \
    "$theme" \
    "$theme/logos" \
    "$fake_root/usr/share/sddm" \
    "$fake_root/usr/share/sddm/themes" \
    "$sddm"

  local asset destination
  for asset in "${plymouth_default_assets[@]}"; do
    destination="$theme/$asset"
    printf 'old plymouth %s\n' "$asset" >"$destination"
    chmod 0600 "$destination"
  done
  for asset in "${sddm_default_assets[@]}"; do
    destination="$sddm/$asset"
    printf 'old sddm %s\n' "$asset" >"$destination"
    chmod 0600 "$destination"
  done

  plymouth_victim="$run_dir/plymouth-victim"
  sddm_victim="$run_dir/sddm-victim"
  legacy_victim="$run_dir/legacy-victim"
  printf 'PLYMOUTH VICTIM\n' >"$plymouth_victim"
  printf 'SDDM VICTIM\n' >"$sddm_victim"
  printf 'LEGACY VICTIM\n' >"$legacy_victim"
  chmod 0600 "$plymouth_victim" "$sddm_victim" "$legacy_victim"

  rm -f "$theme/omarchy.script" "$sddm/Main.qml"
  ln -s "$plymouth_victim" "$theme/omarchy.script"
  ln -s "$sddm_victim" "$sddm/Main.qml"
  ln -s "$legacy_victim" "$sddm/logo.svg"
}

setup_fresh_run() {
  local asset destination

  setup_run
  for asset in "${plymouth_default_assets[@]}"; do
    destination="$theme/$asset"
    rm -f -- "$destination"
    /usr/bin/install -m 0644 -- "$ROOT/default/plymouth/$asset" "$destination"
  done
  for asset in "${sddm_default_assets[@]}"; do
    destination="$sddm/$asset"
    rm -f -- "$destination"
    /usr/bin/install -m 0644 -- "$ROOT/default/sddm/omarchy/$asset" "$destination"
  done
  rm -f -- "$sddm/logo.svg"
}

run_in_fake_root() {
  local requested_umask="$1"
  shift
  (
    umask "$requested_umask"
    PATH="$fake_bin:$ROOT/bin:$PATH" \
      TMPDIR="$stages" \
      OMARCHY_PATH="$ROOT" \
      TEST_FAKE_ROOT="$fake_root" \
      TEST_STAGES="$stages" \
      TEST_ROOT_TOOLS="$root_tools" \
      TEST_OMARCHY_CONF="$omarchy_conf" \
      TEST_SUDO_LOG="$sudo_log" \
      TEST_LEAK_LOG="$leak_log" \
      "$@"
  )
}

run_set_colors() {
  local requested_umask="$1" background="$2" text="$3"
  shift 3
  run_in_fake_root "$requested_umask" "$@" \
    /bin/bash "$ROOT/bin/omarchy-plymouth-set" "$background" "$text" "$test_tmp/logo.png"
}

run_set() {
  local requested_umask="$1"
  shift
  run_set_colors "$requested_umask" '#1d2021' '#ebdbb2' "$@"
}

run_refresh_plymouth() {
  run_in_fake_root 022 "$@" /bin/bash "$ROOT/bin/omarchy-refresh-plymouth"
}

run_refresh_sddm() {
  run_in_fake_root 022 "$@" /bin/bash "$ROOT/bin/omarchy-refresh-sddm"
}

run_reset() {
  run_in_fake_root 022 "$@" /bin/bash "$ROOT/bin/omarchy-plymouth-reset"
}

assert_no_temporary_files() {
  local directory="$1" leftovers
  leftovers=$(find "$directory" -name '.*.omarchy-new.*' -print)
  [[ -z $leftovers ]] || fail "failed publication cleans up its root-side temporary file" "$leftovers"
}

assert_packaged_assets() {
  local context=$1 source_dir=$2 destination_dir=$3
  shift 3

  local asset destination
  for asset in "$@"; do
    destination="$destination_dir/$asset"
    cmp -s "$source_dir/$asset" "$destination" || fail "$context publishes the packaged $asset bytes"
    [[ -f $destination && ! -L $destination && $(stat -c %a "$destination") == 644 ]] ||
      fail "$context publishes $asset as a regular mode-0644 file"
  done
}

for requested_umask in 022 027 077; do
  setup_fresh_run
  output=$(run_set "$requested_umask" env 2>&1)
  status=$?
  (( status == 0 )) || fail "Plymouth publisher succeeds under umask $requested_umask" "$output"

  for asset in "${plymouth_theme_assets[@]}"; do
    destination="$theme/$asset"
    [[ -f $destination && ! -L $destination ]] || fail "Plymouth $asset is a regular file under umask $requested_umask"
    [[ $(stat -c %a "$destination") == 644 ]] || fail "Plymouth $asset is mode 0644 under umask $requested_umask"
    [[ -s $destination ]] || fail "Plymouth $asset is nonempty under umask $requested_umask"
  done
  for asset in "${sddm_theme_assets[@]}"; do
    destination="$sddm/$asset"
    [[ -f $destination && ! -L $destination ]] || fail "SDDM $asset is a regular file under umask $requested_umask"
    [[ $(stat -c %a "$destination") == 644 ]] || fail "SDDM $asset is mode 0644 under umask $requested_umask"
    [[ -s $destination ]] || fail "SDDM $asset is nonempty under umask $requested_umask"
  done

  cmp -s "$test_tmp/logo.png" "$theme/logo.png" || fail "Plymouth receives the selected logo under umask $requested_umask"
  cmp -s "$test_tmp/logo.png" "$sddm/logo.png" || fail "SDDM receives the selected logo under umask $requested_umask"
  grep -Fq '#1d2021' "$sddm/Main.qml" || fail "SDDM Main.qml receives the selected background under umask $requested_umask"
  grep -Fq 'Window.SetBackgroundTopColor(0.114, 0.125, 0.129);' "$theme/omarchy.script" || fail "Plymouth script receives the selected background under umask $requested_umask"

  cmp -s "$ROOT/default/plymouth/logos/oma.png" "$theme/logos/oma.png" || fail "theme set leaves the packaged nested logo unchanged"
  cmp -s "$ROOT/default/sddm/omarchy/metadata.desktop" "$sddm/metadata.desktop" || fail "theme set leaves packaged SDDM metadata unchanged"
  cmp -s "$ROOT/default/sddm/omarchy/theme.conf" "$sddm/theme.conf" || fail "theme set leaves packaged SDDM configuration unchanged"
  [[ ! -s $leak_log ]] || fail "no privileged command receives a user-writable staged pathname" "$(cat "$leak_log")"
  [[ $(stat -c %a "$theme") == 755 && $(stat -c %a "$sddm") == 755 && $(stat -c %a "$theme/logos") == 755 ]] || fail "publication preserves destination directory modes under umask $requested_umask"
  grep -Fq 'command plymouth-set-default-theme omarchy' "$sudo_log" || fail "theme set activates the published Plymouth theme"
  grep -Fq 'command mkinitcpio -P' "$sudo_log" || fail "theme set rebuilds the initramfs"
  assert_no_temporary_files "$fake_root"
done

pass "a fresh installation receives complete mode-0644 Plymouth and SDDM theme files across restrictive umasks"

setup_run
output=$(run_set 022 env 2>&1)
status=$?

(( status == 0 )) || fail "theme set repairs migrated Plymouth and SDDM destinations" "$output"
[[ -f $theme/omarchy.script && ! -L $theme/omarchy.script ]] || fail "theme set replaces a migrated Plymouth destination symlink"
[[ -f $sddm/Main.qml && ! -L $sddm/Main.qml ]] || fail "theme set replaces a migrated SDDM destination symlink"
[[ $(cat "$plymouth_victim") == 'PLYMOUTH VICTIM' && $(stat -c %a "$plymouth_victim") == 600 ]] || fail "theme set never changes a Plymouth symlink victim"
[[ $(cat "$sddm_victim") == 'SDDM VICTIM' && $(stat -c %a "$sddm_victim") == 600 ]] || fail "theme set never changes an SDDM symlink victim"
[[ $(cat "$legacy_victim") == 'LEGACY VICTIM' && $(stat -c %a "$legacy_victim") == 600 ]] || fail "theme set never changes the legacy logo victim"
[[ ! -e $sddm/logo.svg && ! -L $sddm/logo.svg ]] || fail "theme set removes the legacy SDDM logo"
assert_no_temporary_files "$fake_root"

pass "theme set repairs migrated destinations without following existing symlinks"

setup_run
output=$(run_set_colors 022 '#ffffff' '#000000' env 2>&1)
status=$?
(( status == 0 )) || fail "White theme publishes through the safe asset pipeline" "$output"
grep -Fq 'color: "#ffffff"' "$sddm/Main.qml" || fail "White theme preserves its SDDM background color"
if grep -Fq '__OMARCHY_SDDM_' "$sddm/Main.qml"; then
  fail "SDDM color substitution left an intermediate token behind"
fi
pass "White theme keeps a white SDDM background instead of becoming black-on-black"

setup_run
preopen_hook="$run_dir/preopen-hook"
preopen_marker="$run_dir/preopen-marker"
printf 'ROOT ONLY\n' >"$secret"
chmod 000 "$secret"
cat >"$preopen_hook" <<'SH'
if [[ $0 == */bin/omarchy-plymouth-set ]]; then
  set -T
  trap '
    if [[ $BASH_COMMAND == exec* && $BASH_COMMAND == *logo_fd* &&
          ! -e $TEST_PREOPEN_MARKER ]]; then
      mv -T -- "$logo_path" "$logo_path.before-preopen-swap"
      ln -s -- "$TEST_SECRET" "$logo_path"
      printf "swapped\n" >"$TEST_PREOPEN_MARKER"
    fi
  ' DEBUG
fi
SH

output=$(TEST_PREOPEN_MARKER="$preopen_marker" TEST_SECRET="$secret" BASH_ENV="$preopen_hook" run_set 077 env 2>&1)
status=$?
chmod 0600 "$secret"
rm -f "$test_tmp/logo.png"
mv "$test_tmp/logo.png.before-preopen-swap" "$test_tmp/logo.png"

(( status != 0 )) || fail "an unreadable pre-open source swap aborts publication"
[[ -s $preopen_marker ]] || fail "the pre-open source swap ran deterministically" "$output"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' && $(stat -c %a "$theme/bullet.png") == 600 ]] || fail "pre-open failure leaves the live destination unchanged"
[[ $(cat "$plymouth_victim") == 'PLYMOUTH VICTIM' ]] || fail "pre-open failure leaves destination-link victims unchanged"
if [[ -e $sudo_log ]] && grep -Fq 'root transaction' "$sudo_log"; then
  fail "sudo started despite the caller-side open failure"
fi
assert_no_temporary_files "$fake_root"

pass "an unreadable source swap before open fails without publication"

setup_run
nonregular_hook="$run_dir/nonregular-hook"
nonregular_marker="$run_dir/nonregular-marker"
cat >"$nonregular_hook" <<'SH'
if [[ $0 == */bin/omarchy-plymouth-set ]]; then
  set -T
  trap '
    if [[ $BASH_COMMAND == exec* && $BASH_COMMAND == *logo_fd* &&
          ! -e $TEST_NONREGULAR_MARKER ]]; then
      mv -T -- "$logo_path" "$logo_path.before-nonregular-swap"
      mkdir -- "$logo_path"
      printf "swapped\n" >"$TEST_NONREGULAR_MARKER"
    fi
  ' DEBUG
fi
SH

output=$(TEST_NONREGULAR_MARKER="$nonregular_marker" BASH_ENV="$nonregular_hook" run_set 077 env 2>&1)
status=$?
rmdir "$test_tmp/logo.png"
mv "$test_tmp/logo.png.before-nonregular-swap" "$test_tmp/logo.png"

(( status != 0 )) || fail "a non-regular opened logo descriptor aborts publication"
[[ -s $nonregular_marker ]] || fail "the non-regular pre-open source swap ran deterministically" "$output"
[[ $output == *"no longer a regular file"* ]] || fail "the descriptor check says why it refused the opened directory" "$output"
if [[ -e $sudo_log ]] && grep -Fq 'root transaction' "$sudo_log"; then
  fail "sudo started despite the non-regular opened logo descriptor"
fi
[[ $(cat "$theme/logo.png") == 'old plymouth logo.png' ]] || fail "a non-regular opened logo leaves the live logo unchanged"
assert_no_temporary_files "$fake_root"

pass "the caller refuses an opened descriptor that is not a regular file"

setup_run
attacker_stage="$stages/tmp.attacker"
mkdir -p "$attacker_stage/plymouth"
printf 'MALICIOUS BOOT SCRIPT\n' >"$attacker_stage/plymouth/omarchy.script"
ln -s "$secret" "$attacker_stage/plymouth/logo.png"

output=$(run_set 022 env 2>&1)
status=$?

(( status == 0 )) || fail "a planted caller-owned stage cannot disrupt publication" "$output"
! grep -Rqs 'MALICIOUS BOOT SCRIPT' "$fake_root" || fail "caller-owned staged content reached the boot theme"
[[ -f $theme/omarchy.script && ! -L $theme/omarchy.script ]] || fail "the trusted Plymouth script replaces the planted destination symlink"
grep -Fq 'Window.SetBackgroundTopColor(0.114, 0.125, 0.129);' "$theme/omarchy.script" || fail "the installed script was derived from the trusted packaged source"
unexpected_stages=$(find "$stages" -mindepth 1 -maxdepth 1 ! -name tmp.attacker -print)
[[ -z $unexpected_stages ]] || fail "the caller created an authoritative staging directory" "$unexpected_stages"
assert_no_temporary_files "$fake_root"

pass "caller-owned content cannot enter the root-owned boot-image stage"

setup_run
output=$(run_set 022 env TEST_UNTRUSTED_SOURCE="$ROOT/default/plymouth" 2>&1)
status=$?

(( status != 0 )) || fail "a user-owned packaged source tree is rejected"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "an untrusted packaged source leaves the live theme unchanged"
[[ -L $theme/omarchy.script && $(cat "$plymouth_victim") == 'PLYMOUTH VICTIM' ]] || fail "an untrusted source cannot replace executable Plymouth content"
[[ $output == *"refusing to publish"* ]] || fail "a rejected packaged source says why it refused" "$output"
assert_no_temporary_files "$fake_root"

pass "root rejects packaged assets that a desktop process could rewrite"

setup_run
symlink_source_root=$(mktemp -d "$test_tmp/symlink-source.XXXXXXXX")
symlink_source_root=$(realpath -e -- "$symlink_source_root")
mkdir -p "$symlink_source_root/default"
cp -a "$ROOT/default/plymouth" "$ROOT/default/sddm" "$symlink_source_root/default/"
rm -f "$symlink_source_root/default/plymouth/bullet.png"
ln -s "$secret" "$symlink_source_root/default/plymouth/bullet.png"
printf 'export OMARCHY_PATH="%s"\n' "$symlink_source_root" >"$omarchy_conf"
chmod 0644 "$omarchy_conf"
output=$(run_set 022 env OMARCHY_PATH="$symlink_source_root" TEST_UNTRUSTED_SOURCE="$symlink_source_root" 2>&1)
status=$?

(( status != 0 )) || fail "a symlinked packaged asset is rejected" "$output"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "a packaged source symlink leaves the live theme unchanged"
[[ $output == *"refusing to publish"* ]] || fail "a rejected packaged source symlink says why it refused" "$output"
assert_no_temporary_files "$fake_root"

pass "root never follows a packaged asset symlink"

setup_run
output=$(run_set 022 env TEST_UNTRUSTED_SOURCE="$ROOT" 2>&1)
status=$?

(( status != 0 )) || fail "a user-owned OMARCHY_PATH is rejected"
[[ $output == *"user-owned"* ]] || fail "the refusal names the untrusted source tree" "$output"
[[ $output == *"omarchy dev link"* ]] || fail "the refusal names how to authorize a development checkout" "$output"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "a user-owned OMARCHY_PATH leaves the live theme unchanged"
assert_no_temporary_files "$fake_root"

setup_run
printf 'export OMARCHY_PATH="/some/other/checkout"\n' >"$omarchy_conf"
chmod 0644 "$omarchy_conf"
output=$(run_set 022 env TEST_UNTRUSTED_SOURCE="$ROOT" 2>&1)
status=$?

(( status != 0 )) || fail "a stale dev-link authorization is rejected"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "a stale dev-link authorization leaves the live theme unchanged"
[[ $output == *"$omarchy_conf"* ]] || fail "a stale dev-link refusal names the authorization it rejected" "$output"
[[ $output != *"directory / "* ]] || fail "a stale dev-link refusal does not blame the root directory" "$output"
assert_no_temporary_files "$fake_root"

setup_run
printf 'export OMARCHY_PATH="%s"\n' "$ROOT" >"$omarchy_conf"
chmod 0666 "$omarchy_conf"
output=$(run_set 022 env TEST_UNTRUSTED_SOURCE="$ROOT" 2>&1)
status=$?

(( status != 0 )) || fail "a writable dev-link authorization is rejected"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "a writable dev-link authorization leaves the live theme unchanged"
assert_no_temporary_files "$fake_root"

setup_run
authorization_target="$run_dir/authorization-target"
printf 'export OMARCHY_PATH="%s"\n' "$ROOT" >"$authorization_target"
chmod 0644 "$authorization_target"
ln -s "$authorization_target" "$omarchy_conf"
output=$(run_set 022 env TEST_UNTRUSTED_SOURCE="$ROOT" 2>&1)
status=$?

(( status != 0 )) || fail "a symlinked dev-link authorization is rejected"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "a symlinked dev-link authorization leaves the live theme unchanged"
assert_no_temporary_files "$fake_root"

setup_run
printf 'export OMARCHY_PATH="%s"\n' "$ROOT" >"$omarchy_conf"
chmod 0644 "$omarchy_conf"
output=$(run_set 022 env TEST_UNTRUSTED_SOURCE="$ROOT" TEST_UNTRUSTED_CONFIGURATION="$omarchy_conf" 2>&1)
status=$?

(( status != 0 )) || fail "a user-owned dev-link authorization is rejected"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "a user-owned dev-link authorization leaves the live theme unchanged"
assert_no_temporary_files "$fake_root"

setup_run
printf 'export OMARCHY_PATH="%s"\n' "$ROOT" >"$omarchy_conf"
chmod 0644 "$omarchy_conf"
output=$(run_set 022 env TEST_UNTRUSTED_SOURCE="$ROOT" 2>&1)
status=$?

(( status == 0 )) || fail "the root-authorized development checkout can publish Plymouth assets" "$output"
cmp -s "$ROOT/default/plymouth/bullet.png" "$theme/bullet.png" || fail "the authorized development checkout supplies the packaged assets"

pass "only a regular root-owned authorization may name the exact development checkout"

setup_run
mv "$theme" "$theme.real"
ln -s "$theme.real" "$theme"
output=$(run_set 022 env 2>&1)
status=$?
(( status != 0 )) || fail "a symlinked destination parent is rejected"
[[ $(cat "$theme.real/bullet.png") == 'old plymouth bullet.png' ]] || fail "a symlinked parent leaves its target unchanged"
[[ $output == *"refusing to publish"* ]] || fail "a rejected symlinked parent says why it refused" "$output"
assert_no_temporary_files "$fake_root"

setup_run
chmod 0777 "$theme"
output=$(run_set 022 env 2>&1)
status=$?
(( status != 0 )) || fail "a writable destination parent is rejected"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "a writable parent leaves its live destination unchanged"
[[ $output == *"refusing to publish"* ]] || fail "a rejected writable parent says why it refused" "$output"
assert_no_temporary_files "$fake_root"

pass "publication rejects symlinked and non-root-writable destination parents"

setup_run
chmod 0777 "$fake_root/usr/share/plymouth"
output=$(run_set 022 env 2>&1)
status=$?
chmod 0755 "$fake_root/usr/share/plymouth"

(( status != 0 )) || fail "a writable destination ancestor is rejected" "$output"
[[ $(stat -c %a "$theme") == 755 ]] || fail "only the ancestor, not the destination, was untrustworthy"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "a writable ancestor leaves the live destination unchanged"
[[ $output == *"refusing to publish"* ]] || fail "a rejected ancestor says why it refused" "$output"
assert_no_temporary_files "$fake_root"

pass "publication walks the whole parent chain, not only the immediate parent"

setup_run
output=$(run_set 022 env TEST_UNTRUSTED_SOURCE="$theme" 2>&1)
status=$?

(( status != 0 )) || fail "a user-owned destination directory is rejected" "$output"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "a user-owned destination directory keeps its live file"
[[ $output == *"refusing to publish"* ]] || fail "a rejected destination directory says why it refused" "$output"
assert_no_temporary_files "$fake_root"

pass "publication refuses a destination directory root does not own"

setup_run
output=$(run_set 022 env TEST_UNTRUSTED_SOURCE="$ROOT/default/plymouth/bullet.png" 2>&1)
status=$?

(( status != 0 )) || fail "a single user-owned packaged asset is rejected" "$output"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "one untrusted asset leaves the live theme unchanged"
[[ $output == *"refusing to publish"* ]] || fail "a rejected packaged asset says why it refused" "$output"
assert_no_temporary_files "$fake_root"

pass "root checks every packaged asset, not only its directory"

setup_run
writable_directory_root=$(mktemp -d "$test_tmp/writable-directory-source.XXXXXXXX")
writable_directory_root=$(realpath -e -- "$writable_directory_root")
mkdir -p "$writable_directory_root/default"
cp -a "$ROOT/default/plymouth" "$ROOT/default/sddm" "$writable_directory_root/default/"
chmod 0777 "$writable_directory_root/default/plymouth"
output=$(run_set 022 env OMARCHY_PATH="$writable_directory_root" 2>&1)
status=$?

(( status != 0 )) || fail "a writable packaged source directory is rejected" "$output"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "a writable packaged directory leaves the live theme unchanged"
[[ $output == *"refusing to publish"* ]] || fail "a rejected packaged directory says why it refused" "$output"
assert_no_temporary_files "$fake_root"

pass "root validates the packaged source parent chain before copying"

setup_run
writable_root=$(mktemp -d "$test_tmp/writable-source.XXXXXXXX")
writable_root=$(realpath -e -- "$writable_root")
mkdir -p "$writable_root/default"
cp -a "$ROOT/default/plymouth" "$ROOT/default/sddm" "$writable_root/default/"
chmod 0666 "$writable_root/default/plymouth/bullet.png"
output=$(run_set 022 env OMARCHY_PATH="$writable_root" 2>&1)
status=$?

(( status != 0 )) || fail "a world-writable packaged asset is rejected" "$output"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "a writable packaged asset leaves the live theme unchanged"
[[ $output == *"refusing to publish"* ]] || fail "a rejected writable asset says why it refused" "$output"
assert_no_temporary_files "$fake_root"

pass "root refuses a packaged asset its own mode leaves rewritable"

setup_run
cp -- "$test_tmp/logo.png" "$test_tmp/logo.png.keep"
: >"$test_tmp/logo.png"
output=$(run_set 022 env 2>&1)
status=$?
mv -f -- "$test_tmp/logo.png.keep" "$test_tmp/logo.png"

(( status != 0 )) || fail "an empty logo is rejected" "$output"
[[ $(cat "$theme/logo.png") == 'old plymouth logo.png' ]] || fail "an empty logo leaves the live logo unchanged"
assert_no_temporary_files "$fake_root"

pass "an empty logo cannot be published"

setup_run
cp -- "$test_tmp/logo.png" "$test_tmp/logo.png.keep"
truncate -s "$((64 * 1024 * 1024 + 1))" "$test_tmp/logo.png"
output=$(run_set 022 env 2>&1)
status=$?
mv -f -- "$test_tmp/logo.png.keep" "$test_tmp/logo.png"

(( status != 0 )) || fail "an oversized logo is rejected" "$output"
[[ $(cat "$theme/logo.png") == 'old plymouth logo.png' ]] || fail "an oversized logo leaves the live logo unchanged"
assert_no_temporary_files "$fake_root"

pass "a logo larger than the publication bound cannot be published"

setup_run
output=$(run_refresh_plymouth 2>&1)
status=$?
(( status == 0 )) || fail "Plymouth refresh succeeds through the safe publisher" "$output"

assert_packaged_assets "Plymouth refresh" "$ROOT/default/plymouth" "$theme" "${plymouth_default_assets[@]}"
[[ -L $sddm/Main.qml && $(cat "$sddm_victim") == 'SDDM VICTIM' ]] || fail "Plymouth refresh leaves SDDM unchanged"
! grep -Fq 'transaction /usr/share/sddm/' "$sudo_log" || fail "Plymouth refresh does not publish SDDM assets"
[[ ! -s $leak_log ]] || fail "refresh never gives root a user-writable source pathname" "$(cat "$leak_log")"
grep -Fq 'command plymouth-set-default-theme omarchy' "$sudo_log" || fail "Plymouth refresh activates the restored theme"
grep -Fq 'command mkinitcpio -P' "$sudo_log" || fail "Plymouth refresh rebuilds the initramfs"

pass "refresh safely publishes its complete fixed asset set, including logos/oma.png"

setup_run
output=$(run_refresh_sddm 2>&1)
status=$?
(( status == 0 )) || fail "SDDM refresh succeeds through the safe publisher" "$output"

assert_packaged_assets "SDDM refresh" "$ROOT/default/sddm/omarchy" "$sddm" "${sddm_default_assets[@]}"
[[ -L $theme/omarchy.script && $(cat "$plymouth_victim") == 'PLYMOUTH VICTIM' ]] || fail "SDDM refresh leaves Plymouth unchanged"
[[ $(cat "$sddm_victim") == 'SDDM VICTIM' && $(stat -c %a "$sddm_victim") == 600 ]] || fail "SDDM refresh never changes a destination symlink victim"
[[ $(cat "$legacy_victim") == 'LEGACY VICTIM' && $(stat -c %a "$legacy_victim") == 600 ]] || fail "SDDM refresh never changes the legacy logo victim"
[[ ! -e $sddm/logo.svg && ! -L $sddm/logo.svg ]] || fail "SDDM refresh removes the legacy logo.svg"
! grep -Fq 'command plymouth-set-default-theme' "$sudo_log" || fail "SDDM refresh does not activate Plymouth"
! grep -Fq 'command mkinitcpio' "$sudo_log" || fail "SDDM refresh does not rebuild the initramfs"
[[ ! -s $leak_log ]] || fail "SDDM refresh never gives root a user-writable source pathname" "$(cat "$leak_log")"

pass "SDDM refresh safely restores its complete packaged asset set without rebuilding Plymouth"

setup_fresh_run
output=$(run_reset 2>&1)
status=$?
(( status == 0 )) || fail "reset succeeds on a fresh installation" "$output"

assert_packaged_assets "fresh reset Plymouth" "$ROOT/default/plymouth" "$theme" "${plymouth_default_assets[@]}"
assert_packaged_assets "fresh reset SDDM" "$ROOT/default/sddm/omarchy" "$sddm" "${sddm_default_assets[@]}"
grep -Fq 'command plymouth-set-default-theme omarchy' "$sudo_log" || fail "fresh reset activates the packaged Plymouth theme"
grep -Fq 'command mkinitcpio -P' "$sudo_log" || fail "fresh reset rebuilds the initramfs"
assert_no_temporary_files "$fake_root"

pass "reset is safe and idempotent on a fresh package installation"

setup_run
output=$(run_reset 2>&1)
status=$?
(( status == 0 )) || fail "combined Plymouth and SDDM reset succeeds" "$output"

assert_packaged_assets "migrated reset Plymouth" "$ROOT/default/plymouth" "$theme" "${plymouth_default_assets[@]}"
assert_packaged_assets "migrated reset SDDM" "$ROOT/default/sddm/omarchy" "$sddm" "${sddm_default_assets[@]}"
[[ $(cat "$plymouth_victim") == 'PLYMOUTH VICTIM' && $(stat -c %a "$plymouth_victim") == 600 ]] || fail "reset never changes a Plymouth destination symlink victim"
[[ $(cat "$sddm_victim") == 'SDDM VICTIM' && $(stat -c %a "$sddm_victim") == 600 ]] || fail "reset never changes an SDDM destination symlink victim"
[[ $(cat "$legacy_victim") == 'LEGACY VICTIM' && $(stat -c %a "$legacy_victim") == 600 ]] || fail "reset never changes the legacy logo victim"
[[ ! -e $sddm/logo.svg && ! -L $sddm/logo.svg ]] || fail "reset removes the legacy logo.svg"
grep -Fq 'command plymouth-set-default-theme omarchy' "$sudo_log" || fail "reset activates the restored Plymouth theme"
grep -Fq 'command mkinitcpio -P' "$sudo_log" || fail "reset rebuilds the initramfs"
[[ ! -s $leak_log ]] || fail "reset never gives root a user-writable source pathname" "$(cat "$leak_log")"

pass "reset safely repairs a migrated Plymouth and SDDM installation"

setup_run
for asset in "${plymouth_default_assets[@]}"; do
  rm -f -- "$theme/$asset"
done
for asset in "${sddm_default_assets[@]}"; do
  rm -f -- "$sddm/$asset"
done
rm -f -- "$sddm/logo.svg"
output=$(run_reset 2>&1)
status=$?
(( status == 0 )) || fail "reset repairs missing Plymouth and SDDM destinations" "$output"
assert_packaged_assets "missing-file reset Plymouth" "$ROOT/default/plymouth" "$theme" "${plymouth_default_assets[@]}"
assert_packaged_assets "missing-file reset SDDM" "$ROOT/default/sddm/omarchy" "$sddm" "${sddm_default_assets[@]}"

pass "reset recreates missing files in package-owned destination trees"

setup_run
chmod 0777 "$sddm"
output=$(run_reset 2>&1)
status=$?

(( status != 0 )) || fail "reset rejects an unsafe SDDM destination" "$output"
assert_packaged_assets "Plymouth before SDDM refusal" "$ROOT/default/plymouth" "$theme" "${plymouth_default_assets[@]}"
[[ $(cat "$plymouth_victim") == 'PLYMOUTH VICTIM' ]] || fail "the successful Plymouth refresh never changes its old symlink victim"
[[ -L $sddm/Main.qml && $(cat "$sddm_victim") == 'SDDM VICTIM' ]] || fail "a rejected reset leaves SDDM unchanged"
[[ $output == *"refusing to publish"* ]] || fail "an unsafe reset destination says why it refused" "$output"
assert_no_temporary_files "$fake_root"

pass "an SDDM refusal cannot make either refresh follow an unsafe destination"

setup_run
output=$(run_reset env TEST_UNTRUSTED_SOURCE="$ROOT" 2>&1)
status=$?

(( status != 0 )) || fail "reset rejects an untrusted packaged source" "$output"
[[ $(cat "$theme/bullet.png") == 'old plymouth bullet.png' ]] || fail "an untrusted reset source leaves Plymouth unchanged"
[[ -L $sddm/Main.qml && $(cat "$sddm_victim") == 'SDDM VICTIM' ]] || fail "an untrusted reset source leaves SDDM unchanged"
[[ $output == *"refusing to publish"* ]] || fail "an untrusted reset source says why it refused" "$output"
[[ $(grep -c '^root transaction$' "$sudo_log") == 1 ]] || fail "reset stops before SDDM when Plymouth refuses"
assert_no_temporary_files "$fake_root"

pass "a reset refusal cannot fall through to an unhardened SDDM copy"
