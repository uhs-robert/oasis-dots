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
if [[ ${1:-} == list ]]; then
  if [[ -s $STUB_DIR/pid ]] && alive "$(cat "$STUB_DIR/pid")"; then
    echo "[{\"pid\": $(cat "$STUB_DIR/pid")}]"
  else
    # The real qs prints this notice, not JSON, when no instance runs.
    printf 'No running instances for "%s"\nUse --all to list all instances.\n' "$HOME/.config/quickshell/shell.qml"
  fi
  exit 0
fi
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
cat >bin/kill <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$STUB_DIR/kill_args"
signal=TERM
[[ $1 == -KILL ]] && signal=KILL
[[ $signal == KILL && ${STUB_BAR:-slow} == immortal ]] && exit 0
[[ -s $STUB_DIR/pid ]] && command kill -"$signal" "$(cat "$STUB_DIR/pid")" 2>/dev/null
exit 0
STUB
cat >bin/notify-send <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$STUB_DIR/notified"
STUB
# Like Hyprland's exec_cmd: launches the bar detached from the caller. STUB_HYPR=fail errors out, STUB_HYPR=noop launches
# nothing (a bar that never comes up).
cat >bin/hyprctl <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$STUB_DIR/hyprctl_args"
[[ ${STUB_HYPR:-} == fail ]] && exit 1
[[ ${STUB_HYPR:-} == noop ]] || qs -n </dev/null >/dev/null 2>&1
exit 0
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

# The script: waits for the old bar, then starts a new one, and stays quiet while no bar runs in between.
start_bar
old_pid=$(cat pid)
check bash "$script" 2>err
check test ! -s err
check test "$(bars_started)" -eq 2
check test "$(cat pid)" != "$old_pid"
check alive "$(cat pid)"

# No bar running: it still starts one.
old_pid=$(cat pid)
kill "$old_pid"
wait_dead "$old_pid"
rm -f started pid
check bash "$script" 2>err
check test ! -s err
check test "$(bars_started)" -eq 1
check alive "$(cat pid)"

# A bar that ignores SIGTERM is killed after the grace period.
export STUB_BAR=stubborn
start_bar
old_pid=$(cat pid)
check env RESTART_BAR_GRACE=1 bash "$script"
check test "$(cat pid)" != "$old_pid"
check test "$(bars_started)" -eq 2

# The signals go to the pids `qs list` reports.
unset STUB_BAR
: >kill_args
start_bar
old_pid=$(cat pid)
check bash "$script"
check grep -qxF -- "$old_pid" kill_args

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
check grep -qxF -- "-KILL $(cat pid)" kill_args

unset STUB_BAR
# Stop mode: the bar is gone and none is started.
start_bar
old_pid=$(cat pid)
check bash "$script" stop
check not alive "$old_pid"
check test "$(bars_started)" -eq 1

# Stop mode with a bar that ignores SIGTERM: SIGKILL after the grace, still no new bar.
export STUB_BAR=stubborn
start_bar
old_pid=$(cat pid)
check env RESTART_BAR_GRACE=1 bash "$script" stop
check not alive "$old_pid"
check test "$(bars_started)" -eq 1

# Stop mode with a bar that survives SIGKILL: critical notification, exit 1.
export STUB_BAR=immortal
start_bar
env RESTART_BAR_GRACE=1 bash "$script" stop 2>err
check test $? -ne 0
check grep -q "survived SIGKILL" err
check grep -q "critical Bar restart failed" notified
check test "$(bars_started)" -eq 1
unset STUB_BAR

# Stop mode with no bar running succeeds.
rm -f started pid
check bash "$script" stop
check test ! -e started

# Start mode: launches through Hyprland's exec_cmd and succeeds once the bar is up.
rm -f started pid hyprctl_args
check bash "$script" start
check grep -qF "hl.dsp.exec_cmd('qs -n')" hyprctl_args
check test "$(bars_started)" -eq 1
check alive "$(cat pid)"

# Stop, then start, leaves a fresh bar (the ship-batch sequence).
old_pid=$(cat pid)
check bash "$script" stop
check bash "$script" start
check test "$(cat pid)" != "$old_pid"
check test "$(bars_started)" -eq 2

# Start mode fails, with a critical notification, when no bar comes up.
bash "$script" stop
rm -f started pid notified
STUB_HYPR=noop bash "$script" start 2>err
check test $? -ne 0
check grep -q "did not come back" err
check grep -q "critical Bar start failed" notified

# Start mode fails when hyprctl cannot dispatch.
rm -f started pid notified
STUB_HYPR=fail bash "$script" start 2>err
check test $? -ne 0
check grep -q "hyprctl could not relaunch" err
check grep -q "critical Bar start failed" notified
check test ! -e started

# An unknown mode is a usage error and touches nothing.
start_bar
old_pid=$(cat pid)
bash "$script" bogus 2>err
check test $? -eq 2
check grep -q usage err
check alive "$old_pid"

exit $((failures > 0))
