#!/usr/bin/env bash
# The wake word listener: its decision logic (wake_test.py, fake scores and stubbed commands) and `voxcmd wake`
# against a stub systemctl, inside the sandbox. The microphone is never opened.
#
#   home/voxcmd/tests/run-wake.sh
set -euo pipefail

tests_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=../../../lib/check/lock.sh
. "$tests_dir/../../../lib/check/lock.sh"
check_lock_gate "voxcmd ${0##*/}" "$0" "$@"
if [ -z "${SANDBOX_DIR:-}" ]; then
  exec "$tests_dir/sandbox.sh" "$0" "$@"
fi
# In the sandbox, so a notify-send the tests miss reaches its stub, never the desktop.
python3 -I "$tests_dir/wake_test.py"

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

# ---- voxcmd _wake-confirm: a trigger's audio, transcribed by a fake `voxtype transcribe` -------------------------------
# It prints what the real `voxtype -q transcribe` does (captured on a recorded take): progress lines on stdout naming
# the file, then a blank line and the transcript ($FAKE_TRANSCRIPT); FAKE_TRANSCRIBE=nospeech, fail or hang act out VAD
# finding nothing, an error and a stuck GPU. Without -q the real one would also log INFO lines, so the stub refuses to
# transcribe without it. `config get` answers voxtype-prompt, which builds the prompt both the daemon and the
# confirmation pass.
transcribe_dir="$SANDBOX_DIR/transcribe-bin"
voxtype_package_bin="$tests_dir/../../voxtype/.local/bin"
mkdir -p "$transcribe_dir"
cat >"$transcribe_dir/voxtype" <<'STUB'
#!/bin/sh
if [ "$1 $2" = "config get" ]; then echo "stub base prompt."; exit 0; fi
[ "$1" = -q ] || exit 64
shift
model="" prompt=""
while :; do
  case "$1" in
  --model) model="$2"; shift 2 ;;
  --initial-prompt) prompt="$2"; shift 2 ;;
  *) break ;;
  esac
done
[ "$1" = transcribe ] || exit 64
printf 'voxtype transcribe %s riff=%s\n' "$2" "$(head -c 4 "$2")" >>"$SANDBOX_DIR/calls.log"
printf 'voxtype prompt: %s\n' "$prompt" >>"$SANDBOX_DIR/calls.log"
printf 'voxtype model: %s\n' "$model" >>"$SANDBOX_DIR/calls.log"
case "${FAKE_TRANSCRIBE:-}" in
fail) echo "Error: no model" >&2; exit 1 ;;
hang) exec sleep 30 ;;
esac
printf 'Loading audio file: "%s"\nAudio format: 16000 Hz, 1 channel(s), Int\nProcessing 63461 samples (3.97s)...\n' "$2"
if [ "${FAKE_TRANSCRIBE:-}" = nospeech ]; then echo "No speech detected, skipping transcription."; exit 0; fi
printf 'VAD: 0.54s speech (13.6%% of audio)\n\n%s\n' "$FAKE_TRANSCRIPT"
STUB
chmod +x "$transcribe_dir/voxtype"
wav="$SANDBOX_DIR/trigger.wav"
python3 -I -c 'import sys, wave
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000); w.writeframes(bytes(64000))' "$wav"
# confirm <transcript> [voxcmd args...]: "<exit> <output>" of `voxcmd _wake-confirm` on the WAV, as stdin like voxcmd-wake
# passes it.
confirm() {
  local transcript="$1" output code=0
  shift
  output=$(PATH="$transcribe_dir:$voxtype_package_bin:$PATH" FAKE_TRANSCRIPT="$transcript" voxcmd _wake-confirm "${@:-/dev/stdin}" <"$wav") || code=$?
  printf '%s %s' "$code" "$output"
}

reset_calls
check "the wake word alone is the wake word" "0 wake" "$(confirm "Cortana.")"
check "the stdin path reaches voxtype, and it reads the WAV" 1 "$(calls | grep -c '^voxtype transcribe /dev/stdin riff=RIFF$')"
check "the daemon's prompt is passed to voxtype transcribe" 1 "$(calls | grep -c '^voxtype prompt: stub base prompt. Voice commands start with Cortana.$')"
# The confirmation's model is base.en when its file is in the data dir, and the daemon's model (no --model) when not.
model_data="$SANDBOX_DIR/model-data"
mkdir -p "$model_data/voxtype/models"
: >"$model_data/voxtype/models/ggml-base.en.bin"
: >"$model_data/voxtype/models/ggml-tiny.en.bin"
reset_calls
check "the confirmation transcribes with base.en when its model is downloaded" "0 wake" "$(XDG_DATA_HOME="$model_data" confirm "Cortana.")"
check "and passes it to voxtype" 1 "$(calls | grep -c '^voxtype model: base.en$')"
check "VOXCMD_WAKE_CONFIRM_MODEL names another downloaded model" "0 wake" "$(XDG_DATA_HOME="$model_data" VOXCMD_WAKE_CONFIRM_MODEL=tiny.en confirm "Cortana.")"
check "and passes that one" 1 "$(calls | grep -c '^voxtype model: tiny.en$')"
reset_calls
check "without the model file the daemon's model answers, and the listener still wakes" "0 wake" "$(XDG_DATA_HOME="$SANDBOX_DIR/no-models" confirm "Cortana.")"
check "and no --model is passed" 1 "$(calls | grep -c '^voxtype model: $')"
check "the fallback is logged" 1 "$(
  XDG_DATA_HOME="$SANDBOX_DIR/no-models" VOXCMD_DEBUG=1 confirm "Cortana." >/dev/null
  grep -c 'ggml-base.en.bin is missing' "$XDG_RUNTIME_DIR/voxcmd/debug.log"
)"
check "what follows the wake word is said" "0 wake stop" "$(confirm "Cortana, stop.")"
check "an alias Whisper writes counts" "0 wake" "$(confirm "Kortana")"
check "a leading hey still counts" "0 wake" "$(confirm "Hey Cortana!")"
check "the wake word after other words counts" "0 wake open firefox" "$(confirm "So, Cortana, open Firefox.")"
check "another word is not the wake word" "1 not_wake" "$(confirm "Cortina")"
check "the wake word inside a longer word is not" "1 not_wake" "$(confirm "Cortanas")"
check "ordinary speech is not" "1 not_wake" "$(confirm "I was talking to Donna about it.")"
check "no speech is not" "1 not_wake" "$(FAKE_TRANSCRIBE=nospeech confirm "")"
check "the file name in voxtype's progress is not heard" "1 not_wake" "$(cp "$wav" "$SANDBOX_DIR/cortana.wav" && confirm "hello" "$SANDBOX_DIR/cortana.wav")"
check "a failed transcription is a failure" "2 failed" "$(FAKE_TRANSCRIBE=fail confirm "")"
status=0
PATH="$transcribe_dir:$voxtype_package_bin:$PATH" voxcmd _wake-confirm </dev/null >/dev/null || status=$?
check "no file is a failure" 2 "$status"
started=$(date +%s)
check "a stuck transcription times out as a failure" "2 failed" "$(VOXCMD_WAKE_CONFIRM_TIMEOUT_SECS=1 FAKE_TRANSCRIBE=hang confirm "")"
check "and is not waited out" 1 "$([ $(($(date +%s) - started)) -lt 5 ] && echo 1 || echo 0)"
check "the aliases setting replaces the built-in spellings" "1 not_wake" "$(VOXCMD_WAKE_ALIASES=jarvis confirm "Kortana.")"
check "and adds its own" "0 wake" "$(VOXCMD_WAKE_ALIASES=jarvis confirm "Jarvis.")"
check "while the wake word itself always counts" "0 wake" "$(VOXCMD_WAKE_ALIASES=jarvis confirm "Cortana.")"
check "no setting changes the word" "1 not_wake" "$(VOXCMD_WAKE_WORD=jarvis confirm "Jarvis.")"
failing_awk_dir="$SANDBOX_DIR/failing-awk-bin"
mkdir -p "$failing_awk_dir"
printf '#!/bin/sh\nexit 1\n' >"$failing_awk_dir/awk"
chmod +x "$failing_awk_dir/awk"
check "an error in voxcmd itself is a failure, not a verdict" "2" "$(
  code=0
  PATH="$failing_awk_dir:$transcribe_dir:$voxtype_package_bin:$PATH" FAKE_TRANSCRIPT="Cortana" voxcmd _wake-confirm /dev/stdin <"$wav" >/dev/null || code=$?
  echo "$code"
)"
reset_calls
# Every directory holding one, not just the package's: a stowed voxtype puts it in ~/.local/bin too.
no_prompt_path=$(printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r dir; do [ -x "$dir/voxtype-prompt" ] || printf '%s\n' "$dir"; done | paste -sd:)
check "without voxtype-prompt it still transcribes, without a prompt" "wake" "$(PATH="$transcribe_dir:$no_prompt_path" FAKE_TRANSCRIPT=Cortana voxcmd _wake-confirm /dev/stdin <"$wav")"
check "and passes none" 1 "$(calls | grep -c '^voxtype prompt: $')"
debug_log="$XDG_RUNTIME_DIR/voxcmd/debug.log"
rm -f "$debug_log"
VOXCMD_DEBUG=1 XDG_DATA_HOME="$model_data" confirm "Cortana, my secret plans." >/dev/null
VOXCMD_DEBUG=1 XDG_DATA_HOME="$model_data" confirm "another secret sentence" >/dev/null
check "the debug log has the verdicts" 2 "$(grep -c 'wake confirm: ' "$debug_log")"
check "but never what was heard" 0 "$(grep -c -i 'secret' "$debug_log")"

# ---- voice.env: the saved settings voxcmd and voxtype-daemon read when the environment has none -----------------------
package_dir="$(cd "$tests_dir/.." && pwd)"
share_dir="$package_dir/.local/share/voxcmd"
voice_env="$SANDBOX_DIR/voice.env"
export VOXCMD_VOICE_ENV_FILE="$voice_env"
# shellcheck source=/dev/null
source "$share_dir/voice-env.sh"

value_of() { voice_env_value "$1" 2>/dev/null || echo none; }

rm -f "$voice_env"
check "no file, no value" none "$(value_of VOXCMD_DUCK_MEDIA_VOLUME)"

printf 'VOXCMD_DUCK_MEDIA_VOLUME=20\n' >"$voice_env"
check "file value" 20 "$(value_of VOXCMD_DUCK_MEDIA_VOLUME)"
check "environment beats the file" 40 "$(VOXCMD_DUCK_MEDIA_VOLUME=40 value_of VOXCMD_DUCK_MEDIA_VOLUME)"

# The file is data: a line that is not KEY=NUMBER is ignored, never run.
# shellcheck disable=SC2016 # the command substitution must reach the file unexpanded
printf 'VOXCMD_DUCK_MEDIA_VOLUME=$(touch %s/ran)\nexport VOXCMD_DUCK_MEDIA_VOLUME=9\n' "$SANDBOX_DIR" >"$voice_env"
check "a command substitution is not a value" none "$(value_of VOXCMD_DUCK_MEDIA_VOLUME)"
check "nothing in the file ran" 0 "$([ -e "$SANDBOX_DIR/ran" ] && echo 1 || echo 0)"

# A number outside Settings' limits falls back to the default, as a bad word does.
printf 'VOXCMD_DUCK_MEDIA_VOLUME=150\n' >"$voice_env"
check "ducking above 100 is not a value" none "$(value_of VOXCMD_DUCK_MEDIA_VOLUME)"
printf 'VOXCMD_DUCK_MEDIA_VOLUME=30.5\n' >"$voice_env"
check "fractional ducking is not a value" none "$(value_of VOXCMD_DUCK_MEDIA_VOLUME)"

printf 'VOXCMD_WAKE_PAUSE_FOR_MEDIA=1\nVOXCMD_WAKE_PAUSE_FOR_MIC=0\n' >"$voice_env"
check "a flag of 1 is read" 1 "$(value_of VOXCMD_WAKE_PAUSE_FOR_MEDIA)"
check "a flag of 0 is read" 0 "$(value_of VOXCMD_WAKE_PAUSE_FOR_MIC)"
printf 'VOXCMD_WAKE_PAUSE_FOR_MEDIA=2\nVOXCMD_WAKE_PAUSE_FOR_MIC=0.5\n' >"$voice_env"
check "a flag of 2 is ignored" none "$(value_of VOXCMD_WAKE_PAUSE_FOR_MEDIA)"
check "a fractional flag is ignored" none "$(value_of VOXCMD_WAKE_PAUSE_FOR_MIC)"
printf 'VOXCMD_WAKE_PAUSE_FOR_MEDIA=01\nVOXCMD_WAKE_PAUSE_FOR_MIC=1.0\n' >"$voice_env"
check "a flag of 01 is ignored" none "$(value_of VOXCMD_WAKE_PAUSE_FOR_MEDIA)"
check "a flag of 1.0 is ignored" none "$(value_of VOXCMD_WAKE_PAUSE_FOR_MIC)"
printf 'VOXCMD_WAKE_SENSITIVITY=relaxed\n' >"$voice_env"
check "a level name is read" relaxed "$(value_of VOXCMD_WAKE_SENSITIVITY)"
printf 'VOXCMD_WAKE_SENSITIVITY=loud\n' >"$voice_env"
check "a word that is no level is ignored" none "$(value_of VOXCMD_WAKE_SENSITIVITY)"
printf 'VOXCMD_WAKE_SENSITIVITY=0.7\n' >"$voice_env"
check "a number is no level" none "$(value_of VOXCMD_WAKE_SENSITIVITY)"
rm -f "$voice_env"

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
check "daemon passes the same prompt the confirmation got" 1 "$(daemon_args | grep -c -e '--initial-prompt base Voice commands start with Cortana.')"
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
