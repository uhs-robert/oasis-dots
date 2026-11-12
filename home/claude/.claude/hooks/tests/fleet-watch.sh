#!/usr/bin/env bash
# Runs the fleet skill's watch.sh against a private tmux server (-L, never the owner's default one), stand-in panes
# and a stand-in `plans`. Checks the stuck rule, the log line for each state and each nudge, one nudge per stall,
# no nudge to a busy session, no touch outside the fleet session and a clean stop.
set -uo pipefail
skill=$(cd "$(dirname "$0")" && pwd)/../../skills/fleet
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
cat "$PLANS_DATA/$owner.json" 2>/dev/null || echo '[]'
STANDIN
# Pane stand-ins. Each ends in `exec` of a program that is not a shell, because watch.sh reads a shell as an exit from
# claude. A pane that shows an empty prompt box and appends every line typed into it to $TYPED.
cat >"$work/bin/pane-idle" <<'STANDIN'
#!/bin/sh
printf '❯\302\240\n'
exec cat >>"$TYPED"
STANDIN
cat >"$work/bin/pane-busy" <<'STANDIN'
#!/bin/sh
echo '✶ Working… (5s · ↓ 98 tokens)'
printf '❯ \n'
exec cat >>"$TYPED"
STANDIN
cat >"$work/bin/pane-moving" <<'STANDIN'
#!/bin/sh
printf '❯ \n'
(
  i=0
  while :; do i=$((i + 1)); echo "line $i"; sleep 0.3; done
) &
exec sleep 300
STANDIN
cat >"$work/bin/pane-permission" <<'STANDIN'
#!/bin/sh
printf 'Do you want to proceed?\n❯ 1. Yes\n  2. No\n'
exec cat >>"$TYPED"
STANDIN
cat >"$work/bin/pane-typed" <<'STANDIN'
#!/bin/sh
printf '❯ half typed text\n'
exec cat >>"$TYPED"
STANDIN
cat >"$work/bin/pane-nobox" <<'STANDIN'
#!/bin/sh
echo 'no prompt box here'
exec cat >>"$TYPED"
STANDIN
chmod +x "$work"/bin/*

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
watch() { (cd "$work" && TMUX=$tmux_env FLEET_STUCK_SECONDS=${stuck:-3} FLEET_INTERVAL_SECONDS=1 "$skill/watch.sh" "$@"); }
# watch_bg: run as `(watch_bg ...) &`; the exec makes the script itself the background pid, so a signal reaches it
watch_bg() { cd "$work" && TMUX=$tmux_env FLEET_STUCK_SECONDS=${stuck:-3} FLEET_INTERVAL_SECONDS=1 exec "$skill/watch.sh" "$@"; }
# fresh_work: counts as new progress for the sessions with a fresh plan doc and a fresh commit
fresh_work() {
  touch "$work/.plans/p/piece-fresh.md"
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
win f1 df-shell-child "sh -c 'sleep 300; true'"
win f1 df-branch pane-idle
win other df-idle pane-idle
sleep 1
for n in idle busy moving fresh perm typed nobox exit branch; do doc "df-$n" "piece-$n" building; done
doc other-owner x review
# a fresh plan doc, and a fresh commit on a branch, each count as progress
doc df-branch piece-branch building "" piece-branch
touch -d '1 hour ago' "$work/.plans/p/piece-branch.md"

fresh_work
out1=$(watch --once f1 p 2>&1)
check "the first pass nudges nobody, whatever the pane shows" test "$(typed_lines f1 df-idle)" -eq 0
sleep 4
fresh_work
out2=$(watch --once f1 p 2>&1)
sleep 2
check "a stuck session gets one nudge line on stdout" grep -qx "NUDGED df-idle" <<<"$out2"
check "the nudge text reaches the stuck pane" grep -q "Fleet watchdog" "$work/typed-f1-df-idle"
check "the nudge is submitted, one line typed" test "$(typed_lines f1 df-idle)" -eq 1
fresh_work
out3=$(watch --once f1 p 2>&1)
sleep 4
fresh_work
out4=$(watch --once f1 p 2>&1)
check "the same stall is not nudged again" test "$(typed_lines f1 df-idle)" -eq 1
check "no NUDGED line for a stall already nudged" test -z "$(grep NUDGED <<<"$out3$out4")"
check "a busy session (spinner) is not nudged" test "$(typed_lines f1 df-busy)" -eq 0
check "a session whose pane keeps changing is not nudged" test "$(typed_lines f1 df-moving)" -eq 0
check "a session with a fresh plan doc is not nudged" test "$(typed_lines f1 df-fresh)" -eq 0
check "a session with a fresh commit on its branch is not nudged" test "$(typed_lines f1 df-branch)" -eq 0
check "a permission prompt is never typed into" test "$(typed_lines f1 df-perm)" -eq 0
check "a prompt is reported once" test "$(grep -c '^PROMPT df-perm' <<<"$out1$out2$out3$out4")" -eq 1
check "text left in the prompt box is not nudged over" test "$(typed_lines f1 df-typed)" -eq 0
check "a stuck session with text in its box is reported as STALL" grep -qx "STALL df-typed" <<<"$out2"
check "a pane with no prompt box is not nudged" test "$(typed_lines f1 df-nobox)" -eq 0
check "a session at a shell is reported EXITED once" test "$(grep -c '^EXITED df-exit' <<<"$out1$out2$out3$out4")" -eq 1
check "a shell with a child process (claude under sh -c) is not an exit" test "$(grep -c ' df-shell-child exited' <<<"$(log_of p)")" -eq 0
check "a same-named window in another tmux session is untouched" test "$(typed_lines other df-idle)" -eq 0

log=$(log_of p)
check "the log has an idle or stuck state line" grep -qE 'df-idle (idle|stuck) pieces=piece-idle' <<<"$log"
check "the log has a stuck line" grep -q ' df-idle stuck ' <<<"$log"
check "the log has a busy line" grep -q ' df-busy busy ' <<<"$log"
check "the log has a busy line for a changing pane" grep -q ' df-moving busy ' <<<"$log"
check "the log has a prompt line" grep -q ' df-perm prompt ' <<<"$log"
check "the log has an exited line" grep -q ' df-exit exited ' <<<"$log"
check "the log has one NUDGE line for the stall" test "$(grep -c ' df-idle NUDGE sent' <<<"$log")" -eq 1
check "the log has a STALL line for the unnudgeable session" grep -q ' df-typed STALL not nudged' <<<"$log"
check "every state line carries the piece and the active count" grep -q ' df-idle .* active=1 ' <<<"$log"

# Fleet f2: stop when every session is finished (loop mode)
win f2 df-gone "exec sh"
win f2 df-done pane-idle
sleep 1
doc df-done piece-done building
(watch_bg f2 p >"$work/f2.out" 2>&1) &
watcher=$!
sleep 2
check "a fleet with a session that still owns a building piece keeps being watched" kill -0 "$watcher"
rm "$PLANS_DATA/df-done.json"
for _ in 1 2 3 4 5 6 7 8; do
  kill -0 "$watcher" 2>/dev/null || break
  sleep 1
done
check "the watcher stops by itself when all sessions finished" test -z "$(ps -o stat= -p "$watcher" | grep -v Z)"
wait "$watcher"
check "the watcher exits 0 when all finished" test $? -eq 0
check "FINISHED is printed" grep -qx FINISHED "$work/f2.out"
check "the log says all sessions finished" grep -q 'all fleet sessions finished' <<<"$(log_of p)"

# A session that never owned a piece is not finished
win f3 df-new pane-idle
sleep 1
out=$(watch --once f3 p 2>&1)
check "a session that has not claimed yet is not finished" test -z "$out"

# A held piece (review, waiting on the owner) counts as finished
win f4 df-held pane-idle
sleep 1
doc df-held piece-held building
watch --once f4 p >/dev/null 2>&1
doc df-held piece-held review "owner: look at it"
out=$(watch --once f4 p 2>&1)
check "a session whose pieces are all held is finished" grep -qx FINISHED <<<"$out"

# A signal: the loop stops clean, prints STOPPED, logs it and leaves no child or lock
win f5 df-live pane-busy
sleep 1
doc df-live piece-live building
(watch_bg f5 q >"$work/f5.out" 2>&1) &
watcher=$!
sleep 2
kill -TERM "$watcher"
wait "$watcher"
check "a signal stops the watcher with exit 0" test $? -eq 0
check "a signal prints STOPPED" grep -qx STOPPED "$work/f5.out"
check "a signal is logged" grep -q 'stopped by signal' <<<"$(log_of q)"
check "the lock is released after a signal" watch --once f5 q
check "the fleet window is left alone by the signal" test "$(typed_lines f5 df-live)" -eq 0

# A fleet session that is gone ends the watch
out=$(watch --once nosuchfleet p 2>&1)
check "a missing fleet session stops the watch with STOPPED" test $? -eq 0 -a "$out" = STOPPED

# Two watchers on one fleet: one runs, one nudge
win f6 df-two pane-idle
sleep 1
doc df-two piece-two building
watch --once f6 r >/dev/null 2>&1
sleep 4
(watch --once f6 r >"$work/w1.out" 2>&1) &
(watch --once f6 r >"$work/w2.out" 2>&1) &
wait
sleep 2
check "two watchers at once nudge once" test "$(typed_lines f6 df-two)" -eq 1

# Bad arguments
check "no arguments are refused" bash -c "cd $work && '$skill/watch.sh' >/dev/null 2>&1; test \$? -eq 2"
check "a bad fleet name is refused" bash -c "cd $work && '$skill/watch.sh' 'a b' p >/dev/null 2>&1; test \$? -eq 2"

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
