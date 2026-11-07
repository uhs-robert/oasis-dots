#!/usr/bin/env bash
# Runs spawn-successor.sh and rename-window.sh against a private tmux server (-L, never the owner's default one)
#, then checks the window names.
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
spawn() { (cd "$work" && PATH=$work/bin:$PATH "$skill/spawn-successor.sh" pred-00); }

# Not in tmux
out=$(env -u TMUX -u TMUX_PANE "$skill/rename-window.sh" active sess-00)
check "outside tmux rename exits 0 with a note" test $? -eq 0 -a -n "$out"

# Roles build the name from the session name
run plain "$skill/rename-window.sh" next sess-01 >/dev/null
check "next adds -next" has_name sess-01-next
run plain2 "$skill/rename-window.sh" active sess-02 >/dev/null
check "active uses the bare session name" has_name sess-02
run plain3 "$skill/rename-window.sh" prev sess-03 >/dev/null
check "prev adds -prev" has_name sess-03-prev
run plain4 "$skill/rename-window.sh" "done" sess-04 >/dev/null
check "done adds -done" has_name sess-04-done

# Every role types the bare session name as a /rename into the caller's own pane. The pane runs cat so the typed
# text lands in a file. stty -echo keeps the terminal from echoing it back into the pane.
typed() {
  local file=$work/typed-$1 pane
  pane=$(t new-window -d -P -F '#{pane_id}' -n "typing-$1" "stty -echo; cat >$file")
  TMUX=$(t display-message -p '#{socket_path},#{pid},0') TMUX_PANE=$pane "$skill/rename-window.sh" "$1" "sess-t$1" >/dev/null
  sleep 0.3
  [[ $(cat "$file") == "/rename sess-t$1" ]]
}
for role in next active prev "done"; do
  check "$role types /rename with the bare session name" typed "$role"
done
touch "$work/typed-refused"
pane=$(t new-window -d -P -F '#{pane_id}' -n typing-refused "stty -echo; cat >$work/typed-refused")
TMUX=$(t display-message -p '#{socket_path},#{pid},0') TMUX_PANE=$pane "$skill/rename-window.sh" active 'bad name' >/dev/null 2>&1
sleep 0.3
check "a refused name types nothing" test ! -s "$work/typed-refused"

# Refusals leave the window name alone
run keep1 "$skill/rename-window.sh" bogus sess-05 >/dev/null 2>&1
check "an unknown role is refused" has_name keep1
run keep2 "$skill/rename-window.sh" active 'bad name;x' >/dev/null 2>&1
check "a name with a space and a semicolon is refused" has_name keep2
run keep3 "$skill/rename-window.sh" active -flag >/dev/null 2>&1
check "a name starting with a dash is refused" has_name keep3
run keep4 "$skill/rename-window.sh" active >/dev/null 2>&1
check "a missing name is refused" has_name keep4
run keep5 "$skill/spawn-successor.sh" 'bad name' >/dev/null 2>&1
check "spawn refuses a bad predecessor name" has_name keep5

# Spawn: the successor window is `next`, the caller becomes <predecessor>-prev
before_next=$(t list-windows -F '#{window_name}' | grep -cx next)
run caller1 spawn >/dev/null
check "caller is renamed to <predecessor>-prev" has_name pred-00-prev
check "successor window is named next" test "$(t list-windows -F '#{window_name}' | grep -cx next)" -eq $((before_next + 1))

# The caller's window is renamed, not the active one
main_window=$(t display-message -p -t main "#{window_id}")
pane=$(t new-window -d -P -F '#{pane_id}' -n bg-window "sleep 60")
t select-window -t "$main_window"
TMUX=$(t display-message -p '#{socket_path},#{pid},0') TMUX_PANE=$pane "$skill/rename-window.sh" "done" bg-sess >/dev/null
check "a background caller's own window is the one renamed" has_name bg-sess-done
check "the active window kept its name" test "$(t display-message -p -t "$main_window" "#{window_name}")" != bg-sess-done

# A failed spawn leaves the caller's name alone: a tmux wrapper that refuses new-window
mkdir "$work/failbin"
real_tmux=$(command -v tmux)
# shellcheck disable=SC2016 # $1 is for the wrapper to expand
printf '#!/bin/sh\n[ "$1" = new-window ] && exit 1\nexec %s "$@"\n' "$real_tmux" >"$work/failbin/tmux"
chmod +x "$work/failbin/tmux"
pane=$(t new-window -d -P -F '#{pane_id}' -n fail-caller "sleep 60")
(cd "$work" && PATH=$work/failbin:$PATH TMUX=$(t display-message -p '#{socket_path},#{pid},0') TMUX_PANE=$pane "$skill/spawn-successor.sh" pred-fail >/dev/null 2>&1)
check "a failed spawn does not rename the caller" has_name fail-caller

# Two concurrent spawns: two new `next` windows, each caller renamed to its own -prev
before_next=$(t list-windows -F '#{window_name}' | grep -cx next)
pane_a=$(t new-window -d -P -F '#{pane_id}' -n conc-a "sleep 60")
pane_b=$(t new-window -d -P -F '#{pane_id}' -n conc-b "sleep 60")
tmux_env=$(t display-message -p '#{socket_path},#{pid},0')
(cd "$work" && PATH=$work/bin:$PATH TMUX=$tmux_env TMUX_PANE=$pane_a "$skill/spawn-successor.sh" pred-a >/dev/null) &
(cd "$work" && PATH=$work/bin:$PATH TMUX=$tmux_env TMUX_PANE=$pane_b "$skill/spawn-successor.sh" pred-b >/dev/null) &
wait
check "two concurrent spawns open two next windows" test "$(t list-windows -F '#{window_name}' | grep -cx next)" -eq $((before_next + 2))
check "first concurrent caller is renamed to its own -prev" test "$(t display-message -p -t "$pane_a" '#{window_name}')" = pred-a-prev
check "second concurrent caller is renamed to its own -prev" test "$(t display-message -p -t "$pane_b" '#{window_name}')" = pred-b-prev

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
