#!/usr/bin/env bash
# Tests for stale-shells.sh: a shell with a child blocked reading a pipe is reported; a sleeping one is not.
set -u
hook="$(dirname "$0")/../stale-shells.sh"
failures=0

check() {
  local name=$1
  shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}

run_hook() {
  local input=${1:-'{}'}
  STALE_SHELLS_ROOT_PID=$$ STALE_SHELLS_MIN_AGE=0 bash "$hook" <<<"$input" 2>"$err"
}

err=$(mktemp)
trap 'kill $(jobs -p) 2>/dev/null; rm -f "$err"' EXIT

# A sleeping wait loop is a deliberate wait, not a stuck shell.
bash -c ': shell-snapshots; sleep 30; true' &
sleep 0.3
run_hook
check "a sleeping shell is left alone" test $? -eq 0
kill %1 2>/dev/null
wait 2>/dev/null

# A cat on a pipe nobody writes to is stuck.
sleep 30 | bash -c ': shell-snapshots; cat; true' &
sleep 0.3
run_hook
status=$?
check "a shell blocked on a pipe stops the agent" test "$status" -eq 2
check "the report names the blocked command" grep -q "'cat' blocked reading input" "$err"

run_hook '{"stop_hook_active": true}'
check "a second stop is let through" test $? -eq 0

# Shells that are not the session's Bash tool shells are not its business.
kill %1 2>/dev/null
wait 2>/dev/null
sleep 30 | bash -c 'cat; true' &
sleep 0.3
run_hook
check "other shells are ignored" test $? -eq 0

((failures == 0)) && echo "stale-shells tests passed"
exit $((failures > 0))
