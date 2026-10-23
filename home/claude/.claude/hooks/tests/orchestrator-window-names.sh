#!/usr/bin/env bash
# Runs spawn-successor.sh and rename-window.sh against a private tmux server (-L, never the owner's default one)
# and a throwaway state dir, then checks the window names and numbers.
set -uo pipefail
skill=$(cd "$(dirname "$0")" && pwd)/../../skills/orchestrator-handoff
pass=0 fail=0

work=$(mktemp -d)
socket=orch-names-test-$$
t() { tmux -L "$socket" "$@"; }
cleanup() {
  t kill-server 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

# The windows start `claude` through the server's PATH; a stand-in keeps them alive and harmless.
mkdir "$work/bin"
printf '#!/bin/sh\nsleep 60\n' >"$work/bin/claude"
chmod +x "$work/bin/claude"
export XDG_STATE_HOME=$work/state

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
has_name() { t list-windows -F '#{window_name}' | grep -qx "$1"; }

# run <window name> <script> [args]: runs a script as the pane of a new window with that name
run() {
  local name=$1 pane
  shift
  pane=$(t new-window -d -P -F '#{pane_id}' -n "$name" "sleep 60")
  TMUX=$(t display-message -p '#{socket_path},#{pid},0') TMUX_PANE=$pane "$@"
}

PATH=$work/bin:$PATH t new-session -d -s main -c "$work" "sleep 60" || {
  echo "FAIL could not start the private tmux server"
  exit 1
}
git -C "$work" init -q
# spawn-successor.sh opens the successor in the main checkout, found through git
spawn() { (cd "$work" && PATH=$work/bin:$PATH "$skill/spawn-successor.sh" pred); }

# Not in tmux
out=$(env -u TMUX -u TMUX_PANE "$skill/rename-window.sh" active)
check "outside tmux rename exits 0 with a note" test $? -eq 0 -a -n "$out"

# Cold start: an unnumbered window gets a number on active
run plain "$skill/rename-window.sh" active >/dev/null
check "unnumbered window becomes orch-1 on active" has_name orch-1

# Spawn from an unnumbered window: caller gets k, successor gets the next number
run plain2 spawn >/dev/null
check "caller without a number is renamed to a numbered -prev" has_name orch-2-prev
check "successor window is orch-3-next" has_name orch-3-next

# Spawn from a numbered window keeps its number
run orch-7 spawn >/dev/null
check "numbered caller keeps its number as -prev" has_name orch-7-prev
check "successor number continues the global counter" has_name orch-4-next

# Roles keep the number
run orch-9-next "$skill/rename-window.sh" active >/dev/null
check "active drops the -next suffix" has_name orch-9
run orch-9-prev "$skill/rename-window.sh" "done" >/dev/null
check "done renames -prev to -done" has_name orch-9-done
run orch-5 "$skill/rename-window.sh" prev >/dev/null
check "prev adds the suffix" has_name orch-5-prev

# prev and done need a number
run plain3 "$skill/rename-window.sh" "done" >/dev/null 2>&1
check "done without a number fails and leaves the name" has_name plain3
run plain4 "$skill/rename-window.sh" bogus >/dev/null 2>&1
check "an unknown role is refused" has_name plain4

# The caller's window is renamed, not the active one
main_window=$(t display-message -p -t main "#{window_id}")
pane=$(t new-window -d -P -F '#{pane_id}' -n orch-20 "sleep 60")
t select-window -t "$main_window"
TMUX=$(t display-message -p '#{socket_path},#{pid},0') TMUX_PANE=$pane "$skill/rename-window.sh" "done" >/dev/null
check "a background caller's own window is the one renamed" has_name orch-20-done
check "the active window kept its name" test "$(t display-message -p -t "$main_window" "#{window_name}")" != orch-20-done

# A failed spawn leaves the caller's name alone: a tmux wrapper that refuses new-window
mkdir "$work/failbin"
real_tmux=$(command -v tmux)
# shellcheck disable=SC2016 # $1 is for the wrapper to expand
printf '#!/bin/sh\n[ "$1" = new-window ] && exit 1\nexec %s "$@"\n' "$real_tmux" >"$work/failbin/tmux"
chmod +x "$work/failbin/tmux"
pane=$(t new-window -d -P -F '#{pane_id}' -n orch-30 "sleep 60")
(cd "$work" && PATH=$work/failbin:$PATH TMUX=$(t display-message -p '#{socket_path},#{pid},0') TMUX_PANE=$pane "$skill/spawn-successor.sh" pred >/dev/null 2>&1)
check "a failed spawn does not rename the caller" has_name orch-30

# Two concurrent spawns get distinct -next numbers, and the launch prompt carries its number
before_nexts=$(t list-windows -F '#{window_name}' | grep -c -- '-next$')
pane_a=$(t new-window -d -P -F '#{pane_id}' -n orch-31 "sleep 60")
pane_b=$(t new-window -d -P -F '#{pane_id}' -n orch-32 "sleep 60")
tmux_env=$(t display-message -p '#{socket_path},#{pid},0')
(cd "$work" && PATH=$work/bin:$PATH TMUX=$tmux_env TMUX_PANE=$pane_a "$skill/spawn-successor.sh" pred >/dev/null) &
(cd "$work" && PATH=$work/bin:$PATH TMUX=$tmux_env TMUX_PANE=$pane_b "$skill/spawn-successor.sh" pred >/dev/null) &
wait
nexts=$(t list-windows -F '#{window_name}' | grep -- '-next$')
check "two concurrent spawns open two -next windows" test "$(grep -c . <<<"$nexts")" -eq $((before_nexts + 2))
check "the concurrent -next numbers are distinct" test "$(grep -- '-next$' <<<"$nexts" | sort -u | wc -l)" -eq $((before_nexts + 2))
# the launch prompt is the pane's command; every -next window's must carry its own name
prompts_match() {
  local name
  while read -r name; do
    t list-panes -a -F '#{window_name} #{pane_start_command}' | grep "^$name " | grep -q "is.*${name}" || return 1
  done <<<"$nexts"
}
check "each launch prompt carries its window's number" prompts_match

# Concurrent allocation hands out distinct numbers
rm -rf "$XDG_STATE_HOME"
# shellcheck source=/dev/null
source "$skill/window-names.sh"
for i in $(seq 1 20); do next_window_number >"$work/n$i" & done
wait
check "20 concurrent allocations are all distinct" test "$(cat "$work"/n* | sort -u | wc -l)" -eq 20
check "the counter ends at the number allocated" test "$(cat "$XDG_STATE_HOME/claude/orchestrator-window-counter")" -eq 20

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
