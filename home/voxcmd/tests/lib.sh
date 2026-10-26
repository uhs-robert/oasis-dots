# Shared by run.sh, run-sessions.sh, run-modes.sh, run-sequences.sh, run-overview.sh and run-monitors.sh, sourced inside the sandbox: check and
# section, waits for events, a private runtime dir under $root, and the summary.
# shellcheck shell=bash
# shellcheck disable=SC2034 # read by the suites that source this
pass=0 fail=0 failed_checks=()
# VOXCMD_TEST_TIMES=1 adds each check's seconds since the previous one, and each section's total as it ends.
times=${VOXCMD_TEST_TIMES:-}
current_section="" section_started=$EPOCHREALTIME check_started=$EPOCHREALTIME
# VOXCMD_ONLY_SECTIONS="name|name" runs only the checks of the sections so named (a section's other code still runs, which
# is cheap next to the sections that wait on voice), so the checks a port item can pass are run alone.
only_sections=${VOXCMD_ONLY_SECTIONS:-} skipping_section=0
elapsed_since() { awk -v from="$1" -v to="$EPOCHREALTIME" 'BEGIN { printf "%.2fs", to - from }'; }
section() {
  [ -z "$times" ] || [ -z "$current_section" ] || echo "   $current_section took $(elapsed_since "$section_started")"
  current_section=$1 section_started=$EPOCHREALTIME check_started=$EPOCHREALTIME
  skipping_section=0
  [ -z "$only_sections" ] || [ -z "$1" ] || [[ "|$only_sections|" == *"|$1|"* ]] || skipping_section=1
  [ -z "$1" ] || [ "$skipping_section" = 1 ] || echo "== $1"
}
check() {
  [ "$skipping_section" = 0 ] || return 0
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
  [ "$skipping_section" = 0 ] || return 1
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
  local pid logged
  logged=$(sed -n "s/$1/\\1/p" "$debug_log")
  while read -r pid; do
    [ -z "$pid" ] || process_gone "$pid" || return 1
  done <<<"$logged"
  # Read again once they are seen gone: the last one may have logged another and exited in between.
  [[ $(sed -n "s/$1/\\1/p" "$debug_log") == "$logged" ]]
}
# sandbox_process_running <path>...: a process started as one of these paths (a link and the binary it resolves to) whose
# environment names this sandbox is running. Every sandbox runs the same release binary, so its path alone would also
# match the suites running beside this one.
sandbox_process_running() {
  local path pid
  for path; do
    for pid in $(pgrep -f -- "$path( |\$)"); do
      process_running "$pid" && grep -qzxF "SANDBOX_DIR=$SANDBOX_DIR" "/proc/$pid/environ" 2>/dev/null && return 0
    done
  done
  return 1
}
# Stubs run as "/bin/sh $SANDBOX_DIR/bin/<name>", so once none is running no stub call is still to be logged: what a
# check that a call was never made waits for.
stub_calls_done() { ! pgrep -f -- "^/bin/sh $SANDBOX_DIR/bin/" >/dev/null; }
watchers_gone() { logged_processes_gone '.* listen: recording started, watcher \([0-9]*\) .*'; }
ended_hooks_gone() { logged_processes_gone '.* session: ended hook \([0-9]*\) runs$'; }

# copy_shipped_integrations <config dir> [stem...]: the shipped integrations (integrations/<stem>.toml and its <stem>.sh
# hook library) of $package into <config dir>/integrations, all of them without a stem.
copy_shipped_integrations() {
  local dest=$1/integrations stem file
  # shellcheck disable=SC2154 # the suites set $package
  local source_dir=$package/.config/voxcmd/integrations
  shift
  mkdir -p "$dest"
  if [ "$#" -eq 0 ]; then
    find "$source_dir" -maxdepth 1 -type f ! -name '.*' -exec cp -t "$dest/" {} +
    return
  fi
  for stem in "$@"; do
    for file in "$source_dir/$stem".{toml,sh}; do
      [ ! -f "$file" ] || cp "$file" "$dest/"
    done
  done
}

# link_voxcmd_build <package copy>: this checkout's Rust build for a copied package, whose stubbed auto-stop and ask
# helpers sit in its .local/bin. A suite then runs <copy>/tests/bin/voxcmd. The copy has no voxcmd of its own;
# VOXCMD_LEGACY_BIN only names where the binary looks for its neighbours (share dir, auto-stop), and VOXCMD_ASK_CMD routes
# every question through tests/bin/ask-stub to the copy's voxcmd-<kind> stubs.
link_voxcmd_build() {
  local tests_dir
  tests_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  mkdir -p "$1/tests/bin"
  ln -sf "$tests_dir/../target/release/voxcmd" "$1/tests/bin/voxcmd"
  export VOXCMD_LEGACY_BIN=$1/.local/bin/voxcmd VOXCMD_ASK_CMD=$tests_dir/bin/ask-stub
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
