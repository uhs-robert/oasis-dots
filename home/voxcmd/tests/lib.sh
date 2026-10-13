# Shared by run.sh and run-sessions.sh, sourced inside the sandbox: check and section, waits for what background
# processes log, a private runtime dir under $root, and the summary.
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

# wait_for_line <pattern> <file> [secs]: for what a background process logs. The bound only matters when the line never
# comes, so it is generous.
wait_for_line() {
  local deadline=$((SECONDS + ${3:-20}))
  until grep -q -- "$1" "$2" 2>/dev/null; do
    ((SECONDS < deadline)) || return 1
    sleep 0.02
  done
}
# Running, not a zombie waiting to be reaped.
process_running() { [[ -e /proc/$1 && $(awk '{print $3}' "/proc/$1/stat" 2>/dev/null) != Z ]]; }

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
