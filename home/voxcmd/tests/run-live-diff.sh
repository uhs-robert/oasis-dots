#!/usr/bin/env bash
# Runs every phrase of phrases.tsv live, once under the bash voxcmd and once under the Rust one, inside the sandbox
# (every stub logs instead of acting), and reports each phrase whose exit code, stub calls or confirm lines differ.
# Run by hand: it is the differential check of what actions do (voxcmd-port 2.3), not part of lib/check.
#
#   home/voxcmd/tests/run-live-diff.sh
#   VOXCMD_DIFF_ONLY='volume|close' home/voxcmd/tests/run-live-diff.sh   only the phrases matching the regex
#
# Both binaries ask through the same stubs (voxcmd-pick answers the first choice, voxcmd-confirm says yes), found
# beside a copy of the bash voxcmd. Left out of the comparison: how often a sequence polled the bar. `date +%s` is the
# same moment for every phrase, so a timer's calendar time compares as written. Skipped: "what can i say" (Voice Help
# is 2.6 in Rust) and "stop" (the bash voxcmd's `run stop` is its Stop Voice command, not the phrase).
set -euo pipefail

tests_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC2034 # read by phrase-fixtures.sh
fixtures_dir="$tests_dir/fixtures"
# shellcheck source-path=SCRIPTDIR source=../../../lib/check/lock.sh
. "$tests_dir/../../../lib/check/lock.sh"
check_lock_gate "voxcmd ${0##*/}" "$0" "$@"

if [ -z "${SANDBOX_DIR:-}" ]; then
  cargo build --release --quiet --manifest-path "$tests_dir/../Cargo.toml" >&2
  # shellcheck source-path=SCRIPTDIR source=phrase-fixtures.sh
  . "$tests_dir/phrase-fixtures.sh"
  exec "$tests_dir/sandbox.sh" "$0" "$@"
fi

package_dir=$(dirname "$tests_dir")
calls_log=$SANDBOX_DIR/calls.log
debug_log=$XDG_RUNTIME_DIR/voxcmd/debug.log
rs_bin="$package_dir/target/release/voxcmd"

# A copy of the package whose voxcmd-pick and voxcmd-confirm are the sandbox's stubs.
copy=$SANDBOX_DIR/package
mkdir -p "$copy"
cp -r "$package_dir/.local" "$copy/.local"
for helper in voxcmd-pick voxcmd-confirm; do
  ln -sf "$SANDBOX_DIR/bin/.stub" "$copy/.local/bin/$helper"
done
mkdir -p "$copy/tests/bin"
ln -sf "$tests_dir/bin/voxcmd" "$copy/tests/bin/voxcmd"
bash_bin="$copy/.local/bin/voxcmd"
bash_cli="$copy/tests/bin/voxcmd"
# The paths each binary passes the no-match toast's waiter for itself, all read as one.
exe_paths=$(printf '%s\n' "$bash_bin" "$rs_bin" "$(readlink -f "$bash_bin")" "$(readlink -f "$rs_bin")" | sort -u |
  sed 's/[][\.*^$#]/\\&/g' | paste -sd'|')

# A clock stopped at the start for the timer integration's `date +%s`; any other use of date passes through.
clock_dir=$SANDBOX_DIR/clock
mkdir -p "$clock_dir"
printf '#!/bin/sh\n[ "$*" = +%%s ] && exec echo %s\nexec %s "$@"\n' "$(date +%s)" "$(command -v date)" >"$clock_dir/date"
chmod +x "$clock_dir/date"
export VOXCMD_LEGACY_BIN="$bash_bin"
"$tests_dir/firefox-profile" "$HOME/.config/mozilla/firefox"

# The monitor slot query runs as a hook once per phrase in Rust (hooks run each query once) and once per use in bash.
uniq_monitor_slots() {
  awk '!($0 ~ /^hyprctl eval local W = require/ && $0 == previous) { print } { previous = $0 }'
}

# Until the stubs stop logging: the no-match toast's waiter is detached, and the bash voxcmd backgrounds it, so its call
# can land after voxcmd has exited.
wait_for_stubs() {
  local size=-1 polls=0
  while [ "$polls" -lt 40 ]; do
    if [ "$(stat -c %s "$calls_log")" = "$size" ] && ! pgrep -f "^/bin/sh $SANDBOX_DIR/bin/" >/dev/null; then
      return
    fi
    size=$(stat -c %s "$calls_log")
    polls=$((polls + 1))
    sleep 0.05
  done
}

# What a binary did for a phrase: its exit code, then the stub calls and the confirm lines, normalized.
act() {
  : >"$calls_log"
  rm -rf "$XDG_RUNTIME_DIR/voxcmd" "$SANDBOX_DIR/popup-state" "$SANDBOX_DIR/clickhints-state" "$XDG_STATE_HOME/voxcmd"
  mkdir -p "$XDG_RUNTIME_DIR/voxcmd"
  : >"$debug_log"
  local status=0
  PATH="$clock_dir:$PATH" "$1" run "$2" >/dev/null 2>&1 || status=$?
  wait_for_stubs
  echo "exit $status"
  sed -E \
    -e '/^qs-ipc call (clickhints|popup) state$/d' \
    -e "s#($exe_paths)#<voxcmd>#g" \
    -e 's#(launcher-sessions|voxcmd-hints|voxcmd-click)\.[A-Za-z0-9]{6}#\1.<random>#g' \
    -e 's#voxcmd-timer-[0-9]+#voxcmd-timer-<ms>#' \
    -e 's#"pid":[0-9]+#"pid":<pid>#' \
    -e 's#(session_turn [0-9]+:[a-z]+:)[0-9]+-[0-9]+#\1<id>#' \
    "$calls_log" | uniq_monitor_slots
  sed -nE 's/^[0-9:.]+ voxcmd\[[0-9]+\] (confirm .*)$/\1/p' "$debug_log"
}

differing=0 total=0
only=${VOXCMD_DIFF_ONLY:-}
while IFS=$'\t' read -r phrase expected _; do
  [ -n "$phrase" ] && [ "$phrase" != phrase ] || continue
  [ "$phrase" != "what can i say" ] && [ "$phrase" != stop ] || continue
  [ -z "$only" ] || [[ "$phrase" =~ $only ]] || continue
  total=$((total + 1))
  from_bash=$(act "$bash_cli" "$phrase")
  from_rs=$(act "$rs_bin" "$phrase")
  [ "$from_bash" != "$from_rs" ] || continue
  differing=$((differing + 1))
  printf '== %s (expected %s)\n' "$phrase" "$expected"
  diff -u --label bash --label rs <(echo "$from_bash") <(echo "$from_rs") | tail -n +3 || true
done <"$tests_dir/phrases.tsv"
printf '%s of %s phrases acted differently\n' "$differing" "$total"
[ "$differing" = 0 ]
