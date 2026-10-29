#!/usr/bin/env bash
# Tests scripts/restart-bar.sh against a fake bar that takes a second to exit on SIGTERM, the race that left no bar
# after SUPER+Q b: the old kill-then-`qs -n` line must fail here and the script must succeed. `qs` is a stub whose `list`
# reports only the fake bar's own pid, so the owner's live bar is never signalled. notify-send is a stub too, or the
# survives-SIGKILL case would pop a real "Bar restart failed" on the owner's desktop.
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
# pid: the live fake bar. started: one line per bar the fake qs launched. `qs list` reports the default config's bar; with --all it adds
# the decoy test/shadow bar whose pid is in decoy_pid. STUB_BAR=immortal keeps listing a bar that was killed, as a process
# stuck in D-state would.
cat >bin/qs <<'STUB'
#!/usr/bin/env bash
if [[ $1 == list ]]; then
  # STUB_BAR=broken: qs list itself fails. Without --any-display a shell off the owner's display sees no bar.
  [[ ${STUB_BAR:-slow} == broken ]] && { echo "qs: boom" >&2; exit 1; }
  [[ " $* " == *" --any-display "* ]] || { echo "No running instances"; exit 0; }
  pids=()
  if [[ -s $STUB_DIR/pid ]] && { alive "$(cat "$STUB_DIR/pid")" || [[ ${STUB_BAR:-slow} == immortal ]]; }; then
    pids+=("$(cat "$STUB_DIR/pid")")
  fi
  [[ " $* " == *" --all "* && -s $STUB_DIR/decoy_pid ]] && pids+=("$(cat "$STUB_DIR/decoy_pid")")
  ((${#pids[@]})) || { echo "No running instances for \"owner\""; exit 0; }
  printf '%s\n' "${pids[@]}" | jq -R 'select(. != "") | {pid: tonumber}' | jq -s .
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
# STUB_BAR=crashed leaves only a crash reporter (a bare `quickshell` that is no listed instance).
if [[ ${STUB_BAR:-slow} == crashed ]]; then
  bash -c "exec -a quickshell sleep 30" &
  echo $! >>"$STUB_DIR/all_pids"
  exit 0
fi
bash -c "trap '$handler' TERM; while :; do sleep 0.1; done" &
echo $! >"$STUB_DIR/pid"
echo $! >>"$STUB_DIR/all_pids"
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
bash -c 'kill "$1"; qs -n' _ "$old_pid"
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

# A decoy test or shadow bar is not in the default `qs list` and must survive the restart.
bash -c 'exec -a quickshell sleep 60' &
decoy=$!
echo "$decoy" >decoy_pid
echo "$decoy" >>all_pids
unset STUB_BAR
start_bar
old_pid=$(cat pid)
check test "$(bash "$script" --pids)" = "$old_pid"
check bash "$script"
check test "$(cat pid)" != "$old_pid"
check alive "$decoy"
check test "$(bash "$script" --pids)" = "$(cat pid)"

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

# A failing `qs list` is an error, not "no bar": nothing is killed or started.
export STUB_BAR=slow
start_bar
started_before=$(bars_started)
STUB_BAR=broken bash "$script" 2>err
check test $? -ne 0
check grep -q "could not list the bar" err
check test "$(bars_started)" -eq "$started_before"
check alive "$(cat pid)"
STUB_BAR=broken bash "$script" --pids 2>/dev/null
check test $? -ne 0

# A crash reporter (a bare `quickshell` that is no listed instance) is not a bar.
export STUB_BAR=crashed
start_bar
check test -z "$(bash "$script" --pids)"

exit $((failures > 0))
