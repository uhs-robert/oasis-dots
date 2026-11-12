#!/usr/bin/env bash
# Runs the fleet skill's launch.sh against a private tmux server (-L, never the owner's default one) with a stand-in
# `claude`, then checks the windows, the environment, the refusals and that a failure leaves nothing behind.
set -uo pipefail
skill=$(cd "$(dirname "$0")" && pwd)/../../skills/fleet
pass=0 fail=0

work=$(mktemp -d)
socket=fleet-launch-test-$$
# TMUX_TMPDIR keeps even a stray bare `tmux` away from the owner's default socket.
export TMUX_TMPDIR=$work
unset TMUX TMUX_PANE
t() { tmux -L "$socket" "$@"; }
cleanup() {
  t kill-server 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

# The windows start `claude` through the server's PATH. The stand-in prints what it was given, then stays alive.
mkdir "$work/bin"
cat >"$work/bin/claude" <<'STANDIN'
#!/bin/sh
echo "standin budget=$CLAUDE_CONTEXT_BUDGET name=$2 mode=$4 args=$#"
echo "$5" | sed -n 1,2p
sleep 120
STANDIN
chmod +x "$work/bin/claude"
mkdir "$work/silentbin"
printf '#!/bin/sh\nsleep 120\n' >"$work/silentbin/claude"
chmod +x "$work/silentbin/claude"

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
sessions() { t list-sessions -F '#{session_name}' 2>/dev/null | sort | tr '\n' ' '; }
windows_of() { t list-windows -t "=$1" -F '#{window_name}' 2>/dev/null | sort | tr '\n' ' '; }
pane_of() { t capture-pane -p -t "=$1:=$2"; }

PATH=$work/bin:$PATH t new-session -d -s base -c "$work" "sleep 120" || {
  echo "FAIL could not start the private tmux server"
  exit 1
}
git -C "$work" init -q
# shellcheck disable=SC2016 # the dollar sign is literal test text
printf '/orchestrator auto. You are df-a, line one.\nsecond line with "quotes" and $dollar\n' >"$work/prompt-a.txt"
printf '/orchestrator auto. You are df-b, line one.\n' >"$work/prompt-b.txt"
printf '/orchestrator auto. You are df-c, line one.\n' >"$work/prompt-c.txt"
launch() { (cd "$work" && TMUX=$(t display-message -p '#{socket_path},#{pid},0') PATH=$work/bin:$PATH FLEET_CONFIRM_SECONDS=10 "$skill/launch.sh" "$@"); }

# A good launch: one window per bundle, no spare window, the budget and flags reach claude, the prompt is one argument
out=$(launch fleet1 424242 df-a="$work/prompt-a.txt" df-b="$work/prompt-b.txt" 2>&1)
check "a good launch exits 0" test $? -eq 0
check "the fleet session exists" grep -qw fleet1 <<<"$(sessions)"
check "windows are the bundle names and nothing else" test "$(windows_of fleet1)" = "df-a df-b "
check "the first window carries the budget, the name and auto mode" grep -q "standin budget=424242 name=df-a mode=auto args=5" <<<"$(pane_of fleet1 df-a)"
check "the second window carries its own name" grep -q "name=df-b " <<<"$(pane_of fleet1 df-b)"
# shellcheck disable=SC2016 # the dollar sign is literal test text
check "the prompt arrives as one argument, quotes and dollar intact" grep -qF 'second line with "quotes" and $dollar' <<<"$(pane_of fleet1 df-a)"
check "the output says how to switch to the fleet" grep -qx "tmux switch-client -t fleet1" <<<"$out"
check "the output confirms each window" test "$(grep -c '^started ' <<<"$out")" -eq 2
check "the window starts in the repo root" test "$(t display-message -p -t '=fleet1:=df-a' '#{pane_current_path}')" = "$(realpath "$work")"

# Refusals leave the server as it was
before=$(sessions)
refused() { # <label> <args...>: exit 2 and no new session
  local label=$1
  shift
  launch "$@" >/dev/null 2>&1
  local rc=$?
  check "$label" test "$rc" -eq 2 -a "$(sessions)" = "$before"
}
refused "an existing session name is refused" fleet1 1000 df-c="$work/prompt-c.txt"
refused "an existing window name in another session is refused" fleet2 1000 df-a="$work/prompt-c.txt"
refused "a name given twice is refused" fleet2 1000 df-c="$work/prompt-c.txt" df-c="$work/prompt-c.txt"
refused "a non-numeric budget is refused" fleet2 lots df-c="$work/prompt-c.txt"
refused "a zero budget is refused" fleet2 0 df-c="$work/prompt-c.txt"
refused "a missing prompt file is refused" fleet2 1000 df-c="$work/none.txt"
refused "a relative prompt path is refused" fleet2 1000 df-c=prompt-c.txt
refused "a prompt path with a newline is refused" fleet2 1000 "df-c=$work/pro
mpt.txt"
refused "an uppercase name is refused (not a plans session name)" fleet2 1000 "DF-c=$work/prompt-c.txt"
refused "a name without a hyphen is refused (not a plans session name)" fleet2 1000 "dfc=$work/prompt-c.txt"
refused "a name ending in a hyphen is refused (not a plans session name)" fleet2 1000 "df-c-=$work/prompt-c.txt"
refused "a window name with a dot is refused" fleet2 1000 "df.c=$work/prompt-c.txt"
refused "a window name with a space is refused" fleet2 1000 "df c=$work/prompt-c.txt"
refused "a name starting with a dash is refused" fleet2 1000 "-x=$work/prompt-c.txt"
refused "a fleet session name with a colon is refused" "fl:eet" 1000 df-c="$work/prompt-c.txt"
refused "a window named like the fleet is refused" fleet2 1000 fleet2="$work/prompt-c.txt"
refused "too few arguments are refused" fleet2 1000
refused "a pair without = is refused" fleet2 1000 df-c

# A prompt path with a space and a single quote is accepted and read intact
mkdir "$work/dir with 'quote' and space"
printf '/orchestrator auto. You are df-q, line one.\n' >"$work/dir with 'quote' and space/prompt q.txt"
out=$(launch fleet7 1000 "df-q=$work/dir with 'quote' and space/prompt q.txt" 2>&1)
check "a prompt path with a space and a quote launches" test $? -eq 0
check "the prompt of such a path reaches claude" grep -q "You are df-q, line one" <<<"$(pane_of fleet7 df-q)"
t kill-session -t =fleet7
before=$(sessions)

# A reused fleet name does not inherit the old watcher's state, unless that watcher still holds its lock
mkdir -p "$work/.logs/p"
echo stale >"$work/.logs/p/fleet-watch-fleet8.state"
echo keep >"$work/.logs/p/fleet-watch-fleet9.state"
flock "$work/.logs/p/fleet-watch-fleet9.lock" sleep 20 &
holder=$!
sleep 0.5
launch fleet8 1000 df-r="$work/prompt-c.txt" >/dev/null 2>&1
launch fleet9 1000 df-t="$work/prompt-c.txt" >/dev/null 2>&1
check "a new fleet removes the stale state of its name" test ! -e "$work/.logs/p/fleet-watch-fleet8.state"
check "a state file whose watcher holds the lock stays" test -e "$work/.logs/p/fleet-watch-fleet9.state"
kill "$holder"
t kill-session -t =fleet8
t kill-session -t =fleet9
before=$(sessions)

# A tmux that fails on new-window part way: the new session is killed again and the first fleet is untouched
mkdir "$work/failbin"
real_tmux=$(command -v tmux)
# shellcheck disable=SC2016 # $1 is for the wrapper to expand
printf '#!/bin/sh\n[ "$1" = new-window ] && exit 1\nexec %s "$@"\n' "$real_tmux" >"$work/failbin/tmux"
chmod +x "$work/failbin/tmux"
(cd "$work" && TMUX=$(t display-message -p '#{socket_path},#{pid},0') PATH=$work/failbin:$work/bin:$PATH "$skill/launch.sh" fleet3 1000 df-c="$work/prompt-c.txt" df-d="$work/prompt-c.txt" >/dev/null 2>&1)
check "a failed new-window exits 3" test $? -eq 3
check "a failed new-window leaves no session behind" test "$(sessions)" = "$before"

# A tmux that fails on new-session: nothing is created
# shellcheck disable=SC2016
printf '#!/bin/sh\n[ "$1" = new-session ] && exit 1\nexec %s "$@"\n' "$real_tmux" >"$work/failbin/tmux"
(cd "$work" && TMUX=$(t display-message -p '#{socket_path},#{pid},0') PATH=$work/failbin:$work/bin:$PATH "$skill/launch.sh" fleet4 1000 df-c="$work/prompt-c.txt" >/dev/null 2>&1)
check "a failed new-session exits 3 and leaves nothing" test $? -eq 3 -a "$(sessions)" = "$before"

# new-session fails because another process made the session in the gap after the check: that session stays
# shellcheck disable=SC2016
printf '#!/bin/sh\nif [ "$1" = new-session ]; then %s new-session -d -s racefleet "sleep 120"; exit 1; fi\nexec %s "$@"\n' "$real_tmux" "$real_tmux" >"$work/failbin/tmux"
(cd "$work" && TMUX=$(t display-message -p '#{socket_path},#{pid},0') PATH=$work/failbin:$work/bin:$PATH "$skill/launch.sh" racefleet 1000 df-c="$work/prompt-c.txt" >/dev/null 2>&1)
check "a failed new-session exits 3" test $? -eq 3
check "a failed new-session does not kill a session another process made" grep -qw racefleet <<<"$(sessions)"
t kill-session -t =racefleet
before=$(sessions)

# The same names launch again once the first fleet is gone
t kill-session -t =fleet1
launch fleet5 1000 df-a="$work/prompt-a.txt" >/dev/null 2>&1
check "a name is free again after its fleet is killed" test $? -eq 0

# A claude that never shows its prompt: reported with exit 4, and the fleet keeps running
out=$(cd "$work" && TMUX=$(t display-message -p '#{socket_path},#{pid},0') PATH=$work/silentbin:$PATH FLEET_CONFIRM_SECONDS=1 "$skill/launch.sh" fleet6 1000 df-s="$work/prompt-b.txt" 2>&1)
check "an unconfirmed start exits 4" test $? -eq 4
check "an unconfirmed start names the window" grep -q "UNCONFIRMED df-s" <<<"$out"
check "an unconfirmed fleet is left running" grep -qw fleet6 <<<"$(sessions)"

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
