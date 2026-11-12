#!/usr/bin/env bash
# Runs the fleet skill's watch.sh against a private tmux server (-L, never the owner's default one), stand-in panes
# and a stand-in `plans`. Checks the stuck rule, the log line for each state, one report per stall, that a check types
# into no pane, the guarded --nudge fallback, no touch outside the fleet session, and the planner's background loop
# from SKILL.md: it sleeps through ok, wakes once on a problem or on all finished, and wakes on a crashed check.
set -uo pipefail
skill=${FLEET_SKILL_DIR:-$(cd "$(dirname "$0")" && pwd)/../../skills/fleet}
guard=$(cd "$(dirname "$0")" && pwd)/../guard-wait-loops.sh
pass=0 fail=0

work=$(mktemp -d)
socket=fleet-watch-test-$$
# TMUX_TMPDIR keeps even a stray bare `tmux` away from the owner's default socket.
export TMUX_TMPDIR=$work
unset TMUX TMUX_PANE
t() { tmux -L "$socket" "$@"; }
cleanup() {
  jobs -p | xargs -r kill 2>/dev/null
  t kill-server 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

mkdir "$work/bin" "$work/plans-data"
# Stand-in `plans ls --owner X --json`: prints the file plans-data/X.json, or an empty list.
cat >"$work/bin/plans" <<'STANDIN'
#!/bin/sh
owner=
while [ $# -gt 0 ]; do
  [ "$1" = --owner ] && owner=$2
  shift
done
[ -e "$PLANS_DATA/FAIL" ] && exit 1
cat "$PLANS_DATA/$owner.json" 2>/dev/null || echo '[]'
STANDIN
# Pane stand-ins. A pane that shows an empty prompt box and appends every line typed into it to $TYPED.
cat >"$work/bin/pane-idle" <<'STANDIN'
#!/bin/sh
printf '❯\302\240\n'
exec claude >>"$TYPED"
STANDIN
cat >"$work/bin/pane-busy" <<'STANDIN'
#!/bin/sh
echo '✶ Working… (5s · ↓ 98 tokens)'
printf '❯ \n'
exec claude >>"$TYPED"
STANDIN
cat >"$work/bin/pane-moving" <<'STANDIN'
#!/bin/sh
printf '❯ \n'
(
  i=0
  while :; do i=$((i + 1)); echo "line $i"; sleep 0.3; done
) &
exec claude >>"$TYPED"
STANDIN
cat >"$work/bin/pane-permission" <<'STANDIN'
#!/bin/sh
printf 'Do you want to proceed?\n❯ 1. Yes\n  2. No\n'
exec claude >>"$TYPED"
STANDIN
cat >"$work/bin/pane-typed" <<'STANDIN'
#!/bin/sh
printf '❯ half typed text\n'
exec claude >>"$TYPED"
STANDIN
cat >"$work/bin/pane-nobox" <<'STANDIN'
#!/bin/sh
echo 'no prompt box here'
exec claude >>"$TYPED"
STANDIN
chmod +x "$work"/bin/*
# Every pane stand-in ends in `exec claude`, a link to cat under that name: watch.sh looks for a claude process
ln -s "$(command -v cat)" "$work/bin/claude"

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

t new-session -d -s base -c "$work" -x 120 -y 30 "sleep 300" || {
  echo "FAIL could not start the private tmux server"
  exit 1
}
git -C "$work" init -q
git -C "$work" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
export PLANS_DATA=$work/plans-data
export PATH=$work/bin:$PATH
tmux_env=$(t display-message -p '#{socket_path},#{pid},0')

# win <session> <name> <pane stand-in>: a window in the session (created with it when new) whose pane runs the stand-in
win() {
  local session=$1 name=$2 prog=$3 cmd
  cmd="TYPED=$work/typed-$session-$name PATH=$PATH $prog"
  if t has-session -t "=$session" 2>/dev/null; then
    t new-window -d -t "=$session:" -n "$name" "$cmd"
  else
    t new-session -d -s "$session" -n "$name" -x 120 -y 30 "$cmd"
  fi
}
typed_lines() { cat "$work/typed-$1-$2" 2>/dev/null | wc -l; }
# doc <owner> <id> <status> [waiting_on] [branch]: the stand-in plan doc, with a plan file last changed an hour ago
doc() {
  local owner=$1 id=$2 status=$3 waiting=${4:-} branch=${5:-none}
  mkdir -p "$work/.plans/p"
  touch -d '1 hour ago' "$work/.plans/p/$id.md"
  jq -n --arg id "$id" --arg s "$status" --arg w "$waiting" --arg b "$branch" --arg p "$work/.plans/p/$id.md" \
    '[{id: $id, project: "p", status: $s, waiting_on: $w, branch: $b, path: $p}]' >"$PLANS_DATA/$owner.json"
}
watch() { (cd "$work" && TMUX=$tmux_env FLEET_STUCK_SECONDS=${stuck:-3} "$skill/watch.sh" "$@"); }
# The planner's loop, the one line of SKILL.md that starts with `sleep`, with the one-second sleeps and the script path
# of the test. Its output is what would wake the planner.
loop_line() { # <fleet> <project> [script]
  grep -m1 '^sleep 1800; while' "$skill/SKILL.md" |
    sed -e "s|sleep 1800|sleep 1|g" -e "s|timeout 900|timeout 2|" -e "s|~/.claude/skills/fleet/watch.sh|${3:-$skill/watch.sh}|" \
      -e "s|<fleet-session>|$1|" -e "s|<project>|$2|"
}
# watch_loop <fleet> <project> [script]: run as `(watch_loop ...) &`, the loop being the background pid
watch_loop() { cd "$work" && TMUX=$tmux_env FLEET_STUCK_SECONDS=${stuck:-3} exec bash -c "$(loop_line "$@")"; }
# fresh_work: counts as new progress for the sessions with a fresh plan doc and a fresh commit
fresh_work() {
  touch "$work/.plans/p/piece-fresh.md"
  # dated ahead: a pass that reaches this window a few seconds after the touch still sees it as recent
  touch -d '30 seconds' "$work/wt/build.out"
  git -C "$work" update-ref refs/heads/piece-branch "$(git -C "$work" -c user.name=t -c user.email=t@t commit-tree 'HEAD^{tree}' -p HEAD -m work)"
}
log_of() { cat "$work/.logs/$1/fleet-watch.md" 2>/dev/null; }

# Fleet f1: one window per state, plus an outside session with a same-named window that must stay untouched
win f1 df-idle pane-idle
win f1 df-busy pane-busy
win f1 df-moving pane-moving
win f1 df-fresh pane-idle
win f1 df-perm pane-permission
win f1 df-typed pane-typed
win f1 df-nobox pane-nobox
win f1 df-exit "exec sh"
win f1 df-exit-clean "exec sh"
# a leftover zsh with a background job and a starship-style prompt mark: not claude, so never typed into
win f1 df-shell-child "sh -c 'sleep 300 & printf \"❯\\302\\240\\n\"; cat >>\"\$TYPED\"; wait'"
win f1 df-wait pane-idle
win f1 df-wt pane-idle
win f1 df-branch pane-idle
win other df-idle pane-idle
sleep 1
for n in idle busy moving fresh perm typed nobox exit branch shell-child; do doc "df-$n" "piece-$n" building; done
doc df-wait piece-wait building "waiting for bundle A to merge"
git -C "$work" branch -q piece-wt
git -C "$work" worktree add -q "$work/wt" piece-wt
doc df-wt piece-wt building "" piece-wt
doc other-owner x review
doc df-exit-clean piece-ec merged
# a fresh plan doc, and a fresh commit on a branch, each count as progress
doc df-branch piece-branch building "" piece-branch
touch -d '1 hour ago' "$work/.plans/p/piece-branch.md"

fresh_work
out1=$(watch f1 p 2>&1)
check "the first check reports no stuck session, whatever the panes show" test -z "$(grep ^STUCK <<<"$out1")"
sleep 4
fresh_work
out2=$(watch f1 p 2>&1)
check "a stuck session is reported as STUCK" grep -q "^STUCK df-idle" <<<"$out2"
fresh_work
out3=$(watch f1 p 2>&1)
sleep 4
fresh_work
out4=$(watch f1 p 2>&1)
check "a stall already reported is not reported again" test -z "$(grep 'STUCK df-idle' <<<"$out3$out4")"
check "a check types into no pane" test "$(cat "$work"/typed-f1-* 2>/dev/null | wc -l)" -eq 0
check "a busy session (spinner) is not stuck" test -z "$(grep df-busy <<<"$out1$out2$out3$out4")"
check "a session whose pane keeps changing is not stuck" test -z "$(grep df-moving <<<"$out1$out2$out3$out4")"
check "a session with a fresh plan doc is not stuck" test -z "$(grep df-fresh <<<"$out1$out2$out3$out4")"
check "a session with a fresh commit on its branch is not stuck" test -z "$(grep df-branch <<<"$out1$out2$out3$out4")"
check "a permission prompt is never typed into" test "$(typed_lines f1 df-perm)" -eq 0
check "a prompt is reported once" test "$(grep -c '^PROMPT df-perm' <<<"$out1$out2$out3$out4")" -eq 1
check "a stuck session with text in its box is reported" grep -q "^STUCK df-typed" <<<"$out2"
check "a session at a shell with unfinished pieces is reported LOST once" test "$(grep -c '^LOST df-exit:' <<<"$out1$out2$out3$out4")" -eq 1
check "a session at a shell with no pieces is reported EXITED once" test "$(grep -c '^EXITED df-exit-clean' <<<"$out1$out2$out3$out4")" -eq 1
check "that shell is reported as lost, not idle" grep -q ' df-shell-child exited ' <<<"$(log_of p)"
check "a session whose piece waits on something is not stuck" test -z "$(grep df-wait <<<"$out1$out2$out3$out4")"
check "a session with fresh files in its branch worktree is not stuck" test -z "$(grep df-wt <<<"$out1$out2$out3$out4")"
check "a same-named window in another tmux session is untouched" test "$(typed_lines other df-idle)" -eq 0

log=$(log_of p)
check "the log has an idle or stuck state line" grep -qE 'df-idle (idle|stuck) pieces=piece-idle' <<<"$log"
check "the log has a stuck line" grep -q ' df-idle stuck ' <<<"$log"
check "the log has a busy line" grep -q ' df-busy busy ' <<<"$log"
check "the log has a busy line for a changing pane" grep -q ' df-moving busy ' <<<"$log"
check "the log has a prompt line" grep -q ' df-perm prompt ' <<<"$log"
check "the log has an exited line" grep -q ' df-exit exited ' <<<"$log"
check "the log has a LOST line" grep -q ' df-exit LOST claude exited' <<<"$log"
check "the log has one STUCK line for the stall" test "$(grep -c ' df-idle STUCK ' <<<"$log")" -eq 1
check "every state line carries the piece and the active count" grep -q ' df-idle .* active=1 ' <<<"$log"

# --nudge, the fallback for a SendMessage held for approval: types only into an idle pane with an empty prompt box
nudge_out=$(watch --nudge f1 p df-idle 2>&1)
sleep 1
check "--nudge prints NUDGED for an idle pane" grep -qx "NUDGED df-idle" <<<"$nudge_out"
check "--nudge types the text, submitted, one line" test "$(typed_lines f1 df-idle)" -eq 1
check "--nudge text reaches the pane" grep -q "Fleet watchdog" "$work/typed-f1-df-idle"
check "--nudge is logged" test "$(grep -c ' df-idle NUDGE sent' <<<"$(log_of p)")" -eq 1
for n in busy perm typed nobox exit shell-child; do
  watch --nudge f1 p "df-$n" >/dev/null 2>&1
  check "--nudge refuses df-$n and types nothing" test "$(typed_lines f1 df-$n)" -eq 0
done
check "--nudge refuses an unknown window" bash -c "cd $work && TMUX=$tmux_env '$skill/watch.sh' --nudge f1 p nosuch >/dev/null 2>&1; test \$? -ne 0"
watch --nudge f1 p df-idle >/dev/null 2>&1
check "--nudge never reaches the same-named window of another session" test "$(typed_lines other df-idle)" -eq 0

# All finished is printed by a check
win f4 df-held pane-idle
sleep 1
doc df-held piece-held building
watch f4 p >/dev/null 2>&1
doc df-held piece-held review "owner: look at it"
out=$(watch f4 p 2>&1)
check "a session whose pieces are all held gives all finished" test "$out" = "all finished"

# A session that never owned a piece is not finished
win f3 df-new pane-idle
sleep 1
out=$(watch f3 p 2>&1)
check "a session that has not claimed yet is not finished" test "$out" = ok

# A fleet session that is gone
out=$(watch nosuchfleet p 2>&1)
check "a missing fleet session prints STOPPED and exits 0" test $? -eq 0 -a "${out%% *}" = STOPPED

# A lost session keeps the fleet from finishing
win f7 df-lost "exec sh"
win f7 df-fine pane-idle
sleep 1
doc df-lost piece-lost building
doc df-fine piece-fine building
out=$(watch f7 s 2>&1)
check "a lost session is reported" grep -q "^LOST df-lost" <<<"$out"
rm "$PLANS_DATA/df-fine.json"
out=$(watch f7 s 2>&1)
check "a lost session keeps the fleet from finishing" test -z "$(grep 'all finished' <<<"$out")"
rm "$PLANS_DATA/df-lost.json"
out=$(watch f7 s 2>&1)
check "the fleet finishes once the lost session owns nothing" test "$out" = "all finished"

# Two fleets on one project: each has its own lock and state
win f8a df-p pane-idle
win f8b df-q pane-idle
sleep 1
doc df-p piece-p building
doc df-q piece-q building
watch f8a z >/dev/null 2>&1
watch f8b z >/dev/null 2>&1
check "the two fleets keep separate state files" test -s "$work/.logs/z/fleet-watch-f8a.state" -a -s "$work/.logs/z/fleet-watch-f8b.state"
sleep 4
out=$(watch f8b z 2>&1)
check "the second fleet reports its own stall" grep -q "^STUCK df-q" <<<"$out"
exec 8>"$work/.logs/z/fleet-watch-f8a.lock"
flock -n 8
out=$(watch f8a z 2>&1)
check "a check that finds the lock held prints ok" test "$out" = ok
exec 8>&-
out=$(watch f8b z 2>&1)
check "a second check does not report a stall twice" test "$out" = ok

# A failed `plans ls` is not an empty list: the fleet does not finish on it
win f9 df-z pane-idle
sleep 1
doc df-z piece-z building
watch f9 y >/dev/null 2>&1
touch "$PLANS_DATA/FAIL"
out=$(watch f9 y 2>&1)
check "a failed plans ls does not finish the fleet" test -z "$(grep 'all finished' <<<"$out")"
check "a failed plans ls is logged" grep -q 'df-z plans ls failed' <<<"$(log_of y)"
rm "$PLANS_DATA/FAIL"

# State survives across runs: a stall is timed over separate runs, and a reported one stays quiet
win f10 df-s pane-idle
sleep 1
doc df-s piece-s building
watch f10 s2 >/dev/null 2>&1
check "the state file exists after one run" test -s "$work/.logs/s2/fleet-watch-f10.state"
sleep 4
out=$(watch f10 s2 2>&1)
check "the stall is found on a later run from the state alone" grep -q "^STUCK df-s" <<<"$out"
out=$(watch f10 s2 2>&1)
check "and is quiet on the run after" test "$out" = ok

# The planner's loop: the form in SKILL.md passes the repo's wait-loop guard
loop_cmd=$(loop_line f p)
check "SKILL.md has the loop line" test -n "$loop_cmd"
guard_out=$(jq -n --arg c "$(grep -m1 '^sleep 1800; while' "$skill/SKILL.md")" '{tool_input: {command: $c}}' | "$guard")
check "the loop is not refused by guard-wait-loops.sh" test -z "$guard_out"

# Loop: sleeps through ok, exits once on a problem with the line, and a handled stall does not wake it again
win l1 df-l pane-idle
sleep 1
doc df-l piece-l building
(watch_loop l1 l >"$work/l1.out" 2>&1) &
loop_pid=$!
sleep 2.5
check "the loop keeps sleeping while every check prints ok" kill -0 "$loop_pid"
check "the loop prints nothing while it sleeps" test ! -s "$work/l1.out"
for _ in $(seq 1 12); do
  kill -0 "$loop_pid" 2>/dev/null || break
  sleep 1
done
check "the loop exits on a problem" test -z "$(ps -o stat= -p "$loop_pid" | grep -v Z)"
wait "$loop_pid"
check "the loop exits 0 on a problem" test $? -eq 0
check "the loop prints the problem line" grep -q '^STUCK df-l' "$work/l1.out"
# The planner handled it and restarts the loop: the same stall must not wake it again
(watch_loop l1 l >"$work/l1b.out" 2>&1) &
loop_pid=$!
sleep 7
check "a restarted loop keeps sleeping on a stall already handled" kill -0 "$loop_pid"
check "and prints nothing" test ! -s "$work/l1b.out"
# It exits on all finished
rm "$PLANS_DATA/df-l.json"
doc df-l piece-l review "owner: look"
for _ in $(seq 1 12); do
  kill -0 "$loop_pid" 2>/dev/null || break
  sleep 1
done
check "the loop exits on all finished" test -z "$(ps -o stat= -p "$loop_pid" | grep -v Z)"
wait "$loop_pid"
check "the loop prints all finished" grep -qx 'all finished' "$work/l1b.out"

# A crashed check exits the loop with a message instead of spinning
printf '#!/bin/sh\necho boom >&2\nexit 3\n' >"$work/bin/crash-watch"
chmod +x "$work/bin/crash-watch"
(watch_loop l1 l "$work/bin/crash-watch" >"$work/crash.out" 2>&1) &
loop_pid=$!
for _ in $(seq 1 6); do
  kill -0 "$loop_pid" 2>/dev/null || break
  sleep 1
done
check "a crashed check exits the loop" test -z "$(ps -o stat= -p "$loop_pid" | grep -v Z)"
wait "$loop_pid"
check "the crash message names the exit status" grep -q 'exit 3' "$work/crash.out"
check "the crash message carries the check's own output" grep -q boom "$work/crash.out"

# A check that hangs ends the loop through timeout, with exit 124, instead of hanging it
printf '#!/bin/sh\nsleep 30\n' >"$work/bin/hang-watch"
chmod +x "$work/bin/hang-watch"
(watch_loop l1 l "$work/bin/hang-watch" >"$work/hang.out" 2>&1) &
loop_pid=$!
for _ in $(seq 1 6); do
  kill -0 "$loop_pid" 2>/dev/null || break
  sleep 1
done
hung=0
if kill -0 "$loop_pid" 2>/dev/null; then
  hung=1
  kill "$loop_pid"
fi
wait "$loop_pid" 2>/dev/null
check "a hung check ends the loop" test "$hung" -eq 0
check "the hang message names exit 124" grep -q 'exit 124' "$work/hang.out"

# A session that exits before its first claim is lost, and the fleet does not finish on the others
win f12 df-nc "exec sh"
win f12 df-ok pane-idle
sleep 1
doc df-ok piece-ok review "owner: look"
out=$(watch f12 nc 2>&1)
check "an exit before the first claim is LOST, never claimed" grep -q "^LOST df-nc: .*first claim" <<<"$out"
check "an exit before the first claim is not EXITED" test -z "$(grep '^EXITED df-nc' <<<"$out")"
out=$(watch f12 nc 2>&1)
check "a session that never claimed keeps the fleet from finishing" test -z "$(grep 'all finished' <<<"$out")"

# A closed window keeps its unfinished pieces in the finish check
win f13 df-g1 pane-idle
win f13 df-g2 pane-idle
sleep 1
doc df-g1 piece-g1 review "owner: look"
doc df-g2 piece-g2 building
watch f13 gw >/dev/null 2>&1
t kill-window -t "=f13:=df-g2"
out=$(watch f13 gw 2>&1)
check "a closed window that owns a building piece is reported GONE" grep -q "^GONE df-g2" <<<"$out"
check "the fleet is not finished while that window is closed" test -z "$(grep 'all finished' <<<"$out")"
out=$(watch f13 gw 2>&1)
check "GONE is reported once and still blocks finishing" test "$out" = ok
doc df-g2 piece-g2 merged
out=$(watch f13 gw 2>&1)
check "the fleet finishes once the closed window's pieces are done" test "$out" = "all finished"

# --nudge refuses a pane that changed since the check reported it stuck
win f11 df-c pane-idle
sleep 1
doc df-c piece-c building
watch f11 nc2 >/dev/null 2>&1
sleep 4
out=$(watch f11 nc2 2>&1)
check "the stall is reported before the pane changes" grep -q "^STUCK df-c" <<<"$out"
# one line typed and submitted: the box is empty again, but the pane is not the one that was reported
t send-keys -t "=f11:=df-c" -l "y"
sleep 0.5
t send-keys -t "=f11:=df-c" Enter
sleep 1
typed_before=$(typed_lines f11 df-c)
out=$(watch --nudge f11 nc2 df-c 2>&1)
check "--nudge refuses a pane that moved since the report" grep -q "NOT NUDGED df-c" <<<"$out"
check "and types nothing" test "$(typed_lines f11 df-c)" -eq "$typed_before"
out=$(watch --nudge f1 p df-fresh 2>&1)
check "--nudge refuses a session no check reported stuck" grep -q "NOT NUDGED df-fresh" <<<"$out"

# Outside a git repository a check creates nothing
nogit=$(mktemp -d)
(cd "$nogit" && TMUX=$tmux_env "$skill/watch.sh" f1 p >/dev/null 2>&1)
check "a check outside a git repository exits 2" test $? -eq 2
check "and leaves no .logs behind" test ! -e "$nogit/.logs"
rm -rf "$nogit"

# Bad arguments
check "no arguments are refused" bash -c "cd $work && '$skill/watch.sh' >/dev/null 2>&1; test \$? -eq 2"
check "a bad fleet name is refused" bash -c "cd $work && '$skill/watch.sh' 'a b' p >/dev/null 2>&1; test \$? -eq 2"
check "--nudge without a name is refused" bash -c "cd $work && '$skill/watch.sh' --nudge f1 p >/dev/null 2>&1; test \$? -eq 2"

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
