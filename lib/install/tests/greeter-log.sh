#!/usr/bin/env bash
# Tests that the installer creates the greeter log and that qs-greeter writes there, or falls back to the runtime dir, with stubs and no sudo.
set -u
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT

source "$repo_dir/lib/common/output.sh"
source "$repo_dir/lib/install/greeter.sh"

failures=0
check() {
  if ! "$@"; then
    printf 'FAIL %s: %s\n' "$case_name" "$*" >&2
    failures=$((failures + 1))
  fi
}

case_name='install commands create the log owned by greeter, group-readable by the installer'
cmds=$(greeter_install_cmds /stage /repo)
check grep -Fq "sudo touch '$GREETER_LOG'" <<<"$cmds"
check grep -Eq "chown greeter:.*'$GREETER_LOG'" <<<"$cmds"
check grep -Fq "chmod 640 '$GREETER_LOG'" <<<"$cmds"

# The wrapper ends in the tuigreet fallback once the stubbed qs exits, so kitty, hyprctl and sleep are stubbed too.
stubs=$scratch/stubs
mkdir -p "$stubs" "$scratch/config"
touch "$scratch/config/shell.qml"
printf '#!/bin/sh\necho qs-output\nexit 1\n' >"$stubs/qs"
printf '#!/bin/sh\nexit 0\n' >"$stubs/kitty"
cp "$stubs/kitty" "$stubs/hyprctl"
cp "$stubs/kitty" "$stubs/sleep"
chmod +x "$stubs"/*

run_wrapper() {
  PATH="$stubs:$PATH" XDG_RUNTIME_DIR="$scratch/run" QS_GREETER_CONFIG="$scratch/config" QS_GREETER_LOG="$1" \
    bash "$repo_dir/system/usr/local/bin/qs-greeter" >/dev/null 2>&1
}

case_name='writes to the pre-created log, keeping its mode and replacing the last run'
log=$scratch/qs-greeter.log
echo old-run >"$log"
chmod 640 "$log"
run_wrapper "$log"
check test "$(cat "$log")" = qs-output
check test "$(stat -c %a "$log")" = 640
check test ! -e "$scratch/run/qs-greeter/qs.log"

case_name='falls back to the runtime dir when the log is missing'
run_wrapper "$scratch/absent.log"
check test "$(cat "$scratch/run/qs-greeter/qs.log")" = qs-output
check test ! -e "$scratch/absent.log"

case_name='falls back when the log is not writable'
unwritable=$scratch/unwritable.log
echo keep >"$unwritable"
chmod 440 "$unwritable"
rm -f "$scratch/run/qs-greeter/qs.log"
if [ "$(id -u)" -ne 0 ]; then
  run_wrapper "$unwritable"
  check test "$(cat "$scratch/run/qs-greeter/qs.log")" = qs-output
  check test "$(cat "$unwritable")" = keep
fi

[ "$failures" -eq 0 ] || exit 1
echo 'greeter-log: ok'
