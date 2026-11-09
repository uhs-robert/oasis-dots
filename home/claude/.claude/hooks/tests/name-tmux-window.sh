#!/usr/bin/env bash
# Tests for name-tmux-window.sh against a private tmux server (-L, never the owner's default one) and a fake
# sessions dir: start names the window of $TMUX_PANE, end turns automatic-rename back on, both stay silent and exit 0.
set -uo pipefail
hook=$(cd "$(dirname "$0")" && pwd)/../name-tmux-window.sh
pass=0 fail=0
work=$(mktemp -d)
socket=name-window-test-$$
t() { tmux -L "$socket" "$@"; }
trap 't kill-server 2>/dev/null; rm -rf "$work"' EXIT
check() {
  local label=$1
  shift
  if "$@"; then
    echo "ok   $label"
    pass=$((pass + 1))
  else
    echo "FAIL $label"
    fail=$((fail + 1))
  fi
}
t new-session -d -s main "sleep 60" || {
  echo "FAIL could not start the private tmux server"
  exit 1
}
tmux_env=$(t display-message -p '#{socket_path},#{pid},0')
export CLAUDE_SESSIONS_DIR=$work
printf '{"pid":4242,"name":"sess-01"}' >"$work/4242.json"
printf '{"pid":4243}' >"$work/4243.json"
printf '{"pid":4244,"name":"bad name;x"}' >"$work/4244.json"

new_window() { t new-window -d -P -F '#{pane_id}' -n "$1" "sleep 60"; }
wname() { t display-message -p -t "$1" '#{window_name}'; }
auto() { t show-options -w -v -t "$1" automatic-rename 2>/dev/null; }
# hook <pane> <mode> <pid> [stdin]: runs the hook as that pane; prints the hook's output and exit code
hook() {
  printf '%s' "${4:-{\}}" | TMUX=$tmux_env TMUX_PANE=$1 CLAUDE_PID=$3 "$hook" "$2" 2>&1
  echo "rc=$?"
}

pane=$(new_window plain)
out=$(hook "$pane" start 4242)
check "start renames the window to the session name" test "$(wname "$pane")" = sess-01
check "start is silent and exits 0" test "$out" = rc=0

# Resume and /clear run start again
out=$(hook "$pane" start 4242)
check "a second start leaves the name and exits 0" test "$(wname "$pane")-$out" = sess-01-rc=0

# The window of the caller's pane is the one renamed, not the active one
main=$(t display-message -p -t main '#{window_id}')
pane=$(new_window bg)
t select-window -t "$main"
hook "$pane" start 4242 >/dev/null
check "a background pane's own window is renamed" test "$(wname "$pane")" = sess-01
check "the active window keeps its name" test "$(wname "$main")" != sess-01

# Handoff labels survive start
for label in prev "done"; do
  pane=$(new_window "sess-01-$label")
  hook "$pane" start 4242 >/dev/null
  check "start keeps the -$label label" test "$(wname "$pane")" = "sess-01-$label"
done

# Skips: each leaves the window name alone and prints nothing but rc=0
skip() {
  local label=$1 pane=$2 out
  shift 2
  out=$("$@")
  check "$label" test "$(wname "$pane")-$out" = "keep-rc=0"
}
pane=$(new_window keep)
skip "a subagent (agent_id set) is skipped" "$pane" hook "$pane" start 4242 '{"agent_id":"a1"}'
skip "a missing session file is skipped" "$pane" hook "$pane" start 9999
skip "a session file without a name is skipped" "$pane" hook "$pane" start 4243
skip "an invalid name is skipped" "$pane" hook "$pane" start 4244
out=$(
  printf '{}' | env -u TMUX -u TMUX_PANE CLAUDE_PID=4242 "$hook" start 2>&1
  echo "rc=$?"
)
check "outside tmux is silent and exits 0" test "$out" = rc=0
out=$(
  printf '{}' | TMUX=$tmux_env TMUX_PANE=%99999 CLAUDE_PID=4242 "$hook" start 2>&1
  echo "rc=$?"
)
check "a pane that does not exist is silent and exits 0" test "$out" = rc=0
# Unreadable hook input does not stop the rename: the name needs no input field
garbage=$(new_window garbage)
out=$(hook "$garbage" start 4242 'not json')
check "garbage hook input is silent, exits 0 and still names the window" test "$(wname "$garbage")-$out" = sess-01-rc=0
out=$(hook "$pane" bogus 4242)
check "an unknown mode does nothing" test "$(wname "$pane")-$out" = "keep-rc=0"

# End
pane=$(new_window sess-01)
t set-option -w -t "$pane" automatic-rename off
out=$(hook "$pane" end 4242)
check "end turns automatic-rename on" test "$(auto "$pane")" = on
check "end is silent and exits 0" test "$out" = rc=0
for label in prev "done"; do
  pane=$(new_window "sess-01-$label")
  t set-option -w -t "$pane" automatic-rename off
  hook "$pane" end 4242 >/dev/null
  check "end leaves a -$label window alone" test "$(auto "$pane")" = off
done
pane=$(new_window bg-end)
t set-option -w -t "$pane" automatic-rename off
t select-window -t "$main"
hook "$pane" end 4242 >/dev/null
check "end acts on its own pane's window" test "$(auto "$pane")" = on
check "end leaves the active window alone" test "$(auto "$main")" != off
pane2=$(new_window sub)
t set-option -w -t "$pane2" automatic-rename off
hook "$pane2" end 4242 '{"agent_id":"a1"}' >/dev/null
check "end skips a subagent" test "$(auto "$pane2")" = off

# Several Claude panes in one window: the last start wins
printf '{"pid":5001,"name":"first-00"}' >"$work/5001.json"
printf '{"pid":5002,"name":"second-00"}' >"$work/5002.json"
pane=$(new_window shared)
pane_b=$(t split-window -d -P -F '#{pane_id}' -t "$pane" "sleep 60")
hook "$pane" start 5001 >/dev/null
hook "$pane_b" start 5002 >/dev/null
check "with two panes in a window the last start wins" test "$(wname "$pane")" = second-00

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
