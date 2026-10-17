# Shared by run.sh, run-sessions.sh, run-sequences.sh, run-overview.sh and run-monitors.sh, sourced inside the sandbox: check and
# section, waits for events, a private runtime dir under $root, and the summary.
# shellcheck shell=bash
# shellcheck disable=SC2034 # read by the suites that source this
pass=0 fail=0 failed_checks=()
# VOXCMD_TEST_TIMES=1 adds each check's seconds since the previous one, and each section's total as it ends.
times=${VOXCMD_TEST_TIMES:-}
current_section="" section_started=$EPOCHREALTIME check_started=$EPOCHREALTIME
elapsed_since() { awk -v from="$1" -v to="$EPOCHREALTIME" 'BEGIN { printf "%.2fs", to - from }'; }
section() {
  [ -z "$times" ] || [ -z "$current_section" ] || echo "   $current_section took $(elapsed_since "$section_started")"
  current_section=$1 section_started=$EPOCHREALTIME check_started=$EPOCHREALTIME
  [ -z "$1" ] || echo "== $1"
}
check() {
  local took=""
  if eval "$2"; then
    pass=$((pass + 1))
    [ -z "$times" ] || took=" ($(elapsed_since "$check_started"))"
    echo "ok   $1$took"
  else
    fail=$((fail + 1))
    failed_checks+=("$current_section: $1")
    echo "FAIL $1 (in $current_section)"
  fi
  check_started=$EPOCHREALTIME
}

# The tests wait for events (a line logged, a file written, a process gone), never for a stretch of time, so they pass
# the same however loaded the machine is. A wait returns as soon as its event happens; its bound only ends one for an
# event that never comes, so it is far beyond what any load stretches a step to.
test_wait_secs=${VOXCMD_TEST_WAIT_SECS:-120}
# wait_until <command...>: runs the command until it succeeds, failing after test_wait_secs.
wait_until() {
  local deadline=$((SECONDS + test_wait_secs))
  until "$@"; do
    ((SECONDS < deadline)) || return 1
    sleep 0.02
  done
}
# wait_for_line <pattern> <file>: for what a background process logs.
wait_for_line() { wait_until grep -qs -- "$1" "$2"; }
# wait_for_count <pattern> <file> <count>: until the file holds that many matching lines.
wait_for_count() { wait_until line_count_reaches "$@"; }
line_count_reaches() {
  local count
  count=$(grep -cs -- "$1" "$2")
  ((${count:-0} >= $3))
}
wait_for_path() { wait_until test -e "$1"; }
# Running, not a zombie waiting to be reaped.
process_running() { [[ -e /proc/$1 && $(awk '{print $3}' "/proc/$1/stat" 2>/dev/null) != Z ]]; }
process_gone() { ! process_running "$1"; }
# An empty PID, a lookup that found nothing, fails at once rather than waiting out the bound.
wait_until_gone() { [ -n "$1" ] && wait_until process_gone "$1"; }
# logged_processes_gone <sed pattern>: every process whose PID voxcmd's debug log names in the pattern's \1 is gone.
# voxcmd logs each watcher it starts and each ended hook it runs before it exits, so once the logged watchers are gone
# no line naming another is still to come.
logged_processes_gone() {
  local pid
  while read -r pid; do
    process_gone "$pid" || return 1
  done < <(sed -n "s/$1/\\1/p" "$debug_log")
}
# Stubs run as "/bin/sh $SANDBOX_DIR/bin/<name>", so once none is running no stub call is still to be logged: what a
# check that a call was never made waits for.
stub_calls_done() { ! pgrep -f -- "^/bin/sh $SANDBOX_DIR/bin/" >/dev/null; }
watchers_gone() { logged_processes_gone '.* listen: recording started, watcher \([0-9]*\) .*'; }
ended_hooks_gone() { logged_processes_gone '.* session: ended hook \([0-9]*\) runs$'; }

# link_voxcmd_shim <package copy>: the new CLI for a copied package, whose stubbed siblings sit beside its own bash voxcmd.
# A suite then runs <copy>/tests/bin/voxcmd. With VOXCMD_BIN=bash (the default) that is the shim, which execs the copy's
# voxcmd by its real path; with VOXCMD_BIN=rs it is a link to this checkout's Rust build, which sandbox.sh made.
link_voxcmd_shim() {
  local tests_dir
  tests_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  mkdir -p "$1/tests/bin"
  if [ "${VOXCMD_BIN:-bash}" = rs ]; then
    ln -sf "$tests_dir/../target/release/voxcmd" "$1/tests/bin/voxcmd"
  else
    ln -sf "$tests_dir/bin/voxcmd" "$1/tests/bin/voxcmd"
  fi
}

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export XDG_RUNTIME_DIR=$root/run
mkdir -p "$XDG_RUNTIME_DIR"
debug_log=$XDG_RUNTIME_DIR/voxcmd/debug.log
log=$SANDBOX_DIR/calls.log
# voxcmd polls ten times as often, so its waits (and the session tests) take a tenth of the time.
export VOXCMD_TIME_SCALE=0.1

# Ends the suite: the counts, then every failed check again, by section, so the last lines of the output name them.
finish() {
  section ""
  echo
  echo "$pass passed, $fail failed"
  [ "$fail" = 0 ] || printf 'FAILED %s\n' "${failed_checks[@]}"
  [[ $fail == 0 ]]
}
