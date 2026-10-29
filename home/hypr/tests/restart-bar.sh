#!/usr/bin/env bash
# Tests scripts/restart-bar.sh against a fake bar that takes a second to exit on SIGTERM, the race that left no bar
# after SUPER+Q b: the old kill-then-`qs -n` line must fail here and the script must succeed. pgrep, the kill command
# and qs are stubs that only see the fake bar's own pid, so the owner's live bar is never signalled. notify-send is a
# stub too, or the survives-SIGKILL case would pop a real "Bar restart failed" on the owner's desktop.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
script=$here/../.config/hypr/scripts/restart-bar.sh
work=$(mktemp -d)
trap 'kill -9 $(cat "$work"/all_pids 2>/dev/null) 2>/dev/null; rm -rf "$work"' EXIT
failures=0
cd "$work" || exit 1

# shellcheck disable=SC2329 # called through check
not() { ! "$@"; }

check() {
  if ! "$@"; then
    failures=$((failures + 1))
    echo "FAIL $*" >&2
  fi
}

mkdir bin
# alive PID: running, not a zombie. Where no init reaps orphans (CI containers) a killed fake bar stays a zombie owned by
# PID 1, and kill -0 would call it alive forever.
cat >bin/alive <<'STUB'
#!/usr/bin/env bash
stat=$(cat "/proc/$1/stat" 2>/dev/null) || exit 1
state=${stat##*) }
[[ ${state%% *} != Z ]]
STUB
# pid: the live fake bar. started: one line per bar the fake qs launched.
cat >bin/qs <<'STUB'
#!/usr/bin/env bash
# Like `qs -n`: exit at once while another instance is alive.
if [[ -s $STUB_DIR/pid ]] && alive "$(cat "$STUB_DIR/pid")"; then
  exit 0
fi
echo started >>"$STUB_DIR/started"
# STUB_BAR=stubborn ignores SIGTERM; otherwise SIGTERM is answered after a second.
if [[ ${STUB_BAR:-slow} == stubborn || ${STUB_BAR:-slow} == immortal ]]; then
  handler=':'
else
  handler='sleep 1; exit 0'
fi
bash -c "trap '$handler' TERM; while :; do sleep 0.1; done" &
echo $! >"$STUB_DIR/pid"
echo $! >>"$STUB_DIR/all_pids"
STUB
cat >bin/pgrep <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$STUB_DIR/pgrep_args"
[[ -s $STUB_DIR/pid ]] && alive "$(cat "$STUB_DIR/pid")"
STUB
cat >bin/pkill <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$STUB_DIR/pkill_args"
signal=TERM
[[ $1 == -KILL ]] && signal=KILL
# STUB_BAR=immortal survives SIGKILL, as a process stuck in D-state does.
[[ $signal == KILL && ${STUB_BAR:-slow} == immortal ]] && exit 0
[[ -s $STUB_DIR/pid ]] && kill -"$signal" "$(cat "$STUB_DIR/pid")" 2>/dev/null
exit 0
STUB
cat >bin/notify-send <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$STUB_DIR/notified"
STUB
chmod +x bin/*
export STUB_DIR=$work PATH=$work/bin:$PATH

start_bar() {
  rm -f "$work/started" "$work/pid"
  qs -n
}
# Waits up to 10 s for a pid to be gone.
wait_dead() {
  local ticks=100
  while ((ticks-- > 0)); do
    alive "$1" || return 0
    sleep 0.1
  done
  return 1
}
bars_started() { wc -l <"$work/started" 2>/dev/null || echo 0; }

# A zombie counts as dead: the parent execs without reaping its exited child.
bash -c 'sleep 0 & echo $! >zombie_pid; exec sleep 30' &
echo $! >>all_pids
sleep 0.3
zombie=$(cat zombie_pid)
check not alive "$zombie"
check test -d /proc/"$zombie"
check alive $$

# The old line: qs -n sees the dying bar, exits, and the bar then dies for good.
start_bar
old_pid=$(cat pid)
bash -c "pkill -f '^qs -n'; qs -n"
wait_dead "$old_pid"
check test "$(bars_started)" -eq 1
check not alive "$old_pid"

# The script: waits for the old bar, then starts a new one.
start_bar
old_pid=$(cat pid)
check bash "$script"
check test "$(bars_started)" -eq 2
check test "$(cat pid)" != "$old_pid"
check alive "$(cat pid)"

# No bar running: it still starts one.
old_pid=$(cat pid)
kill "$old_pid"
wait_dead "$old_pid"
rm -f started pid
check bash "$script"
check test "$(bars_started)" -eq 1
check alive "$(cat pid)"

# A bar that ignores SIGTERM is killed after the grace period.
export STUB_BAR=stubborn
start_bar
old_pid=$(cat pid)
check env RESTART_BAR_GRACE=1 bash "$script"
check test "$(cat pid)" != "$old_pid"
check test "$(bars_started)" -eq 2

# shellcheck source=/dev/null
source "$here/../.config/hypr/scripts/bar-pattern.sh"
# shellcheck disable=SC2154 # bar_pattern comes from bar-pattern.sh
pattern=$bar_pattern
# The signals go to the owner's bars only: both commands get -u $UID and the pattern, and no other match.
: >pgrep_args
unset STUB_BAR
: >pkill_args
start_bar
check bash "$script"
check grep -qxF -- "-u $UID -f $pattern" pkill_args
check grep -qxF -- "-u $UID -f $pattern" pgrep_args
check test "$(grep -cvxF -- "-u $UID -f $pattern" pgrep_args)" -eq 0
check test "$(grep -cvxF -- "-u $UID -f $pattern" pkill_args)" -eq 0

# A fractional grace is not valid arithmetic: warn and fall back instead of crashing.
start_bar
check env RESTART_BAR_GRACE=0.5 bash "$script" 2>err
check grep -q "RESTART_BAR_GRACE='0.5'" err
check test "$(bars_started)" -eq 2
check test "$(cat pid)" != "$old_pid"

# A leading zero is still decimal: 08 must not die in octal arithmetic after the old bar was signalled.
start_bar
check env RESTART_BAR_GRACE=08 bash "$script" 2>err
check test ! -s err
check test "$(bars_started)" -eq 2

# A bar that survives SIGKILL: report it, exit non-zero and do not start another.
export STUB_BAR=immortal
start_bar
env RESTART_BAR_GRACE=1 bash "$script" 2>err
check test $? -ne 0
check grep -q "survived SIGKILL" err
check grep -q "Bar restart failed" notified
check test "$(bars_started)" -eq 1
check grep -qxF -- "-KILL -u $UID -f $pattern" pkill_args

# The pattern the script passes matches a bar launched with a path, and not a shadow bar or a look-alike.
used=$(sed -n 's/^-u [0-9]* -f //p' pkill_args | head -n1)
for line in "qs -n" "/usr/bin/qs -n" "/usr/bin/qs -n -p /x" "qs -n -p /x" "quickshell" "/usr/bin/quickshell"; do
  check grep -Eq -- "$used" <<<"$line"
done
for line in "qs-shadow -n" "/usr/bin/qs-shadow -n" "qs -p /x" "quickshell -p /x" "bash restart-bar.sh qs -n" "qsx -n"; do
  # shellcheck disable=SC2016 # expanded by the inner shell
  check bash -c '! grep -Eq -- "$0" <<<"$1"' "$used" "$line"
done

exit $((failures > 0))
