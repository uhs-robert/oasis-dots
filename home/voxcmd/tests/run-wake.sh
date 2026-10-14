#!/usr/bin/env bash
# The wake word listener: its decision logic (wake_test.py, fake scores and stubbed commands) and `voxcmd wake`
# against a stub systemctl, inside the sandbox. The microphone is never opened.
#
#   home/voxcmd/tests/run-wake.sh
set -euo pipefail

tests_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=../../../lib/check-lock.sh
. "$tests_dir/../../../lib/check-lock.sh"
check_lock_gate "voxcmd ${0##*/}" "$0" "$@"
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

# ---- voice.env: the saved settings voxcmd and voxtype-daemon read when the environment has none -----------------------
package_dir="$(cd "$tests_dir/.." && pwd)"
share_dir="$package_dir/.local/share/voxcmd"
voice_env="$SANDBOX_DIR/voice.env"
export VOXCMD_VOICE_ENV_FILE="$voice_env"
# shellcheck source=/dev/null
source "$share_dir/voice-env.sh"

value_of() { voice_env_value "$1" 2>/dev/null || echo none; }
chunk_pause_of() {
  # shellcheck disable=SC2034 # read by the integration
  voxcmd_share_dir="$share_dir"
  # shellcheck source=/dev/null disable=SC2154
  (source "$package_dir/.config/voxcmd/integrations.d/typing.sh" && echo "$session_listen_silence_secs")
}

rm -f "$voice_env"
check "no file, no value" none "$(value_of VOXCMD_DUCK_MEDIA_VOLUME)"
check "no file, chunk pause default" 2.5 "$(chunk_pause_of)"

printf 'VOXCMD_DUCK_MEDIA_VOLUME=20\nVOXCMD_TYPE_CHUNK_PAUSE_SECS=3.5\n' >"$voice_env"
check "file value" 20 "$(value_of VOXCMD_DUCK_MEDIA_VOLUME)"
check "chunk pause from the file" 3.5 "$(chunk_pause_of)"
check "environment beats the file" 40 "$(VOXCMD_DUCK_MEDIA_VOLUME=40 value_of VOXCMD_DUCK_MEDIA_VOLUME)"
check "environment beats the file for chunk pause" 4 "$(VOXCMD_TYPE_CHUNK_PAUSE_SECS=4 chunk_pause_of)"

# The file is data: a line that is not KEY=NUMBER is ignored, never run.
# shellcheck disable=SC2016 # the command substitution must reach the file unexpanded
printf 'VOXCMD_DUCK_MEDIA_VOLUME=$(touch %s/ran)\nVOXCMD_TYPE_CHUNK_PAUSE_SECS=fast\nexport VOXCMD_DUCK_MEDIA_VOLUME=9\n' "$SANDBOX_DIR" >"$voice_env"
check "a command substitution is not a value" none "$(value_of VOXCMD_DUCK_MEDIA_VOLUME)"
check "a word is not a value" 2.5 "$(chunk_pause_of)"
check "nothing in the file ran" 0 "$([ -e "$SANDBOX_DIR/ran" ] && echo 1 || echo 0)"

# voxtype-daemon with a voxtype that prints its arguments.
voxtype_dir="$SANDBOX_DIR/voxtype-bin"
mkdir -p "$voxtype_dir"
cat >"$voxtype_dir/voxtype" <<'STUB'
#!/bin/sh
if [ "$1 $2" = "config get" ]; then echo base; exit 0; fi
printf '%s\n' "$*"
STUB
chmod +x "$voxtype_dir/voxtype"
daemon_args() { PATH="$voxtype_dir:$PATH" XDG_DATA_HOME="$package_dir/.local/share" XDG_CONFIG_HOME="$SANDBOX_DIR/no-config" "$tests_dir/../../voxtype/.local/bin/voxtype-daemon"; }

printf 'VOXCMD_DUCK_MEDIA_VOLUME=20\n' >"$voice_env"
check "daemon passes the saved ducking" 1 "$(daemon_args | grep -c '^--duck-media-volume 20 --initial-prompt ')"
check "daemon prefers the environment" 1 "$(VOXCMD_DUCK_MEDIA_VOLUME=0 daemon_args | grep -c '^--duck-media-volume 0 ')"
rm -f "$voice_env"
check "daemon leaves config.toml's ducking alone without a value" 0 "$(daemon_args | grep -c -e '--duck-media-volume')"
printf 'VOXCMD_DUCK_MEDIA_VOLUME=loud\n' >"$voice_env"
check "daemon ignores a bad saved value" 0 "$(daemon_args | grep -c -e '--duck-media-volume')"
unset VOXCMD_VOICE_ENV_FILE

if [ "$failures" -gt 0 ]; then
  printf '%d of %d wake checks failed\n' "$failures" "$total"
  exit 1
fi
printf '%d wake checks passed\n' "$total"
