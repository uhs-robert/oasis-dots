#!/usr/bin/env bash
# The wake word listener: its decision logic (wake_test.py, fake scores and stubbed commands) and `voxcmd wake`
# against a stub systemctl, inside the sandbox. The microphone is never opened.
#
#   home/voxcmd/tests/run-wake.sh
set -euo pipefail

tests_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ -z "${SANDBOX_DIR:-}" ]; then
  python3 -I "$tests_dir/wake_test.py"
  exec "$tests_dir/sandbox.sh" "$0" "$@"
fi

# A systemctl that keeps the unit's state in a file: start sets it, stop clears it.
systemctl_dir="$SANDBOX_DIR/wake-bin"
mkdir -p "$systemctl_dir"
cat >"$systemctl_dir/systemctl" <<'STUB'
#!/bin/sh
printf 'systemctl %s\n' "$*" >>"$SANDBOX_DIR/calls.log"
state_file="$SANDBOX_DIR/wake-unit-state"
case "$*" in
"--user start --no-block voxcmd-wake.service") echo active >"$state_file" ;;
"--user stop voxcmd-wake.service")
  [ ! -e "$SANDBOX_DIR/wake-stop-fails" ] || exit 1
  rm -f "$state_file"
  ;;
"--user is-active voxcmd-wake.service")
  if [ -e "$state_file" ]; then cat "$state_file"; else echo inactive; exit 3; fi
  ;;
esac
STUB
chmod +x "$systemctl_dir/systemctl"
PATH="$systemctl_dir:$PATH"

failures=0
total=0
check() {
  local description="$1" expected="$2" actual="$3"
  total=$((total + 1))
  if [ "$actual" != "$expected" ]; then
    printf '%s: expected "%s", got "%s"\n' "$description" "$expected" "$actual"
    failures=$((failures + 1))
  fi
}
calls() { cat "$SANDBOX_DIR/calls.log"; }
reset_calls() { : >"$SANDBOX_DIR/calls.log"; }

status=0
voxcmd wake status >/dev/null || status=$?
check "off at first" 1 "$status"

reset_calls
voxcmd wake on
check "on starts the unit without blocking" 1 "$(calls | grep -c '^systemctl --user start --no-block voxcmd-wake.service$')"
check "on shows a toast" 1 "$(calls | grep -c '^notify-send .*Wake word on')"
check "status after on" on "$(voxcmd wake status)"

reset_calls
voxcmd wake on
check "on twice does not start again" 0 "$(calls | grep -c ' start ')"

reset_calls
voxcmd wake toggle
check "toggle from on stops the unit" 1 "$(calls | grep -c '^systemctl --user stop voxcmd-wake.service$')"
check "off shows a toast" 1 "$(calls | grep -c '^notify-send .*Wake word off')"
status=0
voxcmd wake status >/dev/null || status=$?
check "status after toggle off" 1 "$status"

reset_calls
voxcmd wake toggle
check "toggle from off starts the unit" 1 "$(calls | grep -c '^systemctl --user start --no-block voxcmd-wake.service$')"

reset_calls
voxcmd wake off
check "off stops the unit" 1 "$(calls | grep -c '^systemctl --user stop voxcmd-wake.service$')"
status=0
voxcmd wake status >/dev/null || status=$?
check "status after off" 1 "$status"

voxcmd wake on
touch "$SANDBOX_DIR/wake-stop-fails"
reset_calls
status=0
voxcmd wake off || status=$?
check "a failed stop fails" 1 "$status"
check "and never claims the microphone was released" 0 "$(calls | grep -c '^notify-send .*Microphone released')"
check "but says it may still be in use" 1 "$(calls | grep -c '^notify-send .*may still be in use')"
rm -f "$SANDBOX_DIR/wake-stop-fails"
voxcmd wake off

status=0
voxcmd wake sideways 2>/dev/null || status=$?
check "an unknown argument is a usage error" 2 "$status"

if [ "$failures" -gt 0 ]; then
  printf '%d of %d wake checks failed\n' "$failures" "$total"
  exit 1
fi
printf '%d wake checks passed\n' "$total"
