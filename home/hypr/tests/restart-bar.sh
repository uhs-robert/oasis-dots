#!/usr/bin/env bash
# Tests scripts/restart-bar.sh against a fake bar that takes a second to exit on SIGTERM, the race that left no bar
# after SUPER+Q b: the old kill-then-`qs -n` line must fail here and the script must succeed. pgrep, the kill command
# and qs are stubs that only see the fake bar's own pid, so the owner's live bar is never signalled.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
script=$here/../.config/hypr/scripts/restart-bar.sh
work=$(mktemp -d)
trap 'kill $(cat "$work"/pid 2>/dev/null) 2>/dev/null; rm -rf "$work"' EXIT
failures=0
cd "$work" || exit 1

check() {
  if ! "$@"; then
    failures=$((failures + 1))
    echo "FAIL $*" >&2
  fi
}

mkdir bin
# pid: the live fake bar. started: one line per bar the fake qs launched.
cat >bin/qs <<'STUB'
#!/usr/bin/env bash
# Like `qs -n`: exit at once while another instance is alive.
if [[ -s $STUB_DIR/pid ]] && kill -0 "$(cat "$STUB_DIR/pid")" 2>/dev/null; then
  exit 0
fi
echo started >>"$STUB_DIR/started"
# STUB_BAR=stubborn ignores SIGTERM; otherwise SIGTERM is answered after a second.
if [[ ${STUB_BAR:-slow} == stubborn ]]; then
  handler=':'
else
  handler='sleep 1; exit 0'
fi
bash -c "trap '$handler' TERM; while :; do sleep 0.1; done" &
echo $! >"$STUB_DIR/pid"
STUB
cat >bin/pgrep <<'STUB'
#!/usr/bin/env bash
[[ -s $STUB_DIR/pid ]] && kill -0 "$(cat "$STUB_DIR/pid")" 2>/dev/null
STUB
cat >bin/pkill <<'STUB'
#!/usr/bin/env bash
signal=TERM
[[ $1 == -KILL ]] && signal=KILL
[[ -s $STUB_DIR/pid ]] && kill -"$signal" "$(cat "$STUB_DIR/pid")" 2>/dev/null
exit 0
STUB
chmod +x bin/*
export STUB_DIR=$work PATH=$work/bin:$PATH

start_bar() {
  rm -f "$work/started" "$work/pid"
  qs -n
}
bars_started() { wc -l <"$work/started" 2>/dev/null || echo 0; }

# The old line: qs -n sees the dying bar, exits, and the bar then dies for good.
start_bar
old_pid=$(cat pid)
bash -c "pkill -f '^qs -n'; qs -n"
sleep 1.5
check test "$(bars_started)" -eq 1
check test ! -d /proc/"$old_pid"

# The script: waits for the old bar, then starts a new one.
start_bar
old_pid=$(cat pid)
check bash "$script"
check test "$(bars_started)" -eq 2
check test "$(cat pid)" != "$old_pid"
check kill -0 "$(cat pid)"

# No bar running: it still starts one.
kill "$(cat pid)"
sleep 1.2
rm -f started pid
check bash "$script"
check test "$(bars_started)" -eq 1
check kill -0 "$(cat pid)"

# A bar that ignores SIGTERM is killed after the grace period.
export STUB_BAR=stubborn
start_bar
old_pid=$(cat pid)
check env RESTART_BAR_GRACE=1 bash "$script"
check test "$(cat pid)" != "$old_pid"
check test "$(bars_started)" -eq 2

exit $((failures > 0))
