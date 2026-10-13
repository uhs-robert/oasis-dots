#!/usr/bin/env bash
# Tests for voxcmd's voice sessions (click mode) and its auto-stop detector. run.sh runs these beside its own, each in a
# sandbox of its own; run alone: home/voxcmd/tests/run-sessions.sh
#
# voxcmd runs for real here, against the sandbox's voxtype, auto-stop and bar, so nothing records, clicks or listens.
# Read by name inside the strings check evals.
# shellcheck disable=SC2034
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
package=$(cd "$here/.." && pwd)
[ -n "${SANDBOX_DIR:-}" ] || exec "$here/sandbox.sh" "$0" "$@"
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$here/lib.sh"

# ---- voice sessions ---------------------------------------------------------------------------------------------------
# A copy of the package whose voxcmd-autostop is the sandbox's stub, with the sandbox's setsid really starting the
# watcher and its voxtype "hearing" the next line of $SANDBOX_VOXTYPE_TURNS ("SILENCE" and an empty queue are no
# speech, "EMPTY" is speech that transcribes to nothing, "HOLD" keeps recording until stopped or cancelled, "FAIL" is a
# record start that fails). Every run ends when no watcher is left, which is what proves the microphone stops
# re-opening.

section "voice sessions"
sess_stubs=$root/sess-stubs
sess_pkg=$root/sess-pkg
mkdir -p "$sess_stubs" "$sess_pkg"
cp -r "$package/.local" "$sess_pkg/.local"
ln -sf "$SANDBOX_DIR/bin/voxcmd-autostop" "$sess_pkg/.local/bin/voxcmd-autostop"
sess_voxcmd=$sess_pkg/.local/bin/voxcmd
# The stub detector's long sleep, under its own name so the tests can end the ones a killed watcher leaves behind.
stub_sleep=$root/stub-sleep
cp "$(command -v sleep)" "$stub_sleep"
trap 'pkill -f "$stub_sleep" 2>/dev/null; rm -rf "$root"' EXIT
sess_turns=$root/turns
# The numbered overlay: answers with the next line of $STUB_PICKS, a choice's index or CANCEL.
export STUB_PICKS=$root/picks
cat >"$sess_stubs/sess-hints" <<STUB
#!/bin/sh
echo "pick no_speech_secs=\${VOXCMD_AUTOSTOP_NO_SPEECH_SECS:-default}" >> "$log"
echo "pick min_speech_secs=\${VOXCMD_AUTOSTOP_MIN_SPEECH_SECS:-default} silence_secs=\${VOXCMD_AUTOSTOP_SILENCE_SECS:-default}" >> "$log"
answer=\$(head -n 1 "\$STUB_PICKS"); sed -i 1d "\$STUB_PICKS"
[ "\$answer" != CANCEL ] || exit 1
echo "\$answer"
STUB
chmod +x "$sess_stubs/sess-hints"
hints_state=$SANDBOX_DIR/clickhints-state popup_state_file=$SANDBOX_DIR/popup-state

# "both" is two targets, which the overlay asks about.
sess_config=$root/config-sess
mkdir -p "$sess_config/integrations.d" "$sess_config/replacements.d"
cat >"$sess_config/integrations.d/sess.sh" <<STUB
name="Sess"
verbs=("begin_it start testing" "stop_it stop testing" "tap tap {target}")
session_miss_actions=(none)
session_exit_phrases="(okay )?stop testing|done testing"
pick_command=$sess_stubs/sess-hints
candidates() {
  case "\$2" in
  missing) echo '[{"id": "zz", "label": "zz"}]' ;;
  both) echo '[{"id": "both left", "label": "both left"}, {"id": "both right", "label": "both right"}]' ;;
  *) jq -n -c --arg t "\$2" '[{id: \$t, label: \$t}]' ;;
  esac
}
pick_box() { echo "0 0 10 10"; }
declare -A no_match_actions=([tap]=none)
declare -A actions=(
  [begin_it]='session_begin test "\$file" "Test mode"'
  [stop_it]='session_end done'
  [tap]='echo "tap \$id" >> "$log"'
  [none]='echo "tap nothing" >> "$log"'
)
session_rewrite() {
  [ "\$1" != noise ] || return 0
  printf 'tap %s' "\$1"
}
STUB

sess_voxcmd_env() {
  env SANDBOX_SETSID_RUN=1 SANDBOX_VOXTYPE_TURNS="$sess_turns" SANDBOX_AUTOSTOP_SLEEP="$stub_sleep" \
    VOXCMD_CONFIG_DIR="$sess_config" VOXCMD_APP_SETTLE_SECS=0 VOXCMD_DEBUG=1 SANDBOX_VOXTYPE_SPEAK_SECS=0 \
    "${sess_env[@]}" "$sess_voxcmd" "$@" >/dev/null 2>&1
}
# sess_start <turn>...: types "start testing" with these turns queued. $sess_env adds environment, $sess_overlay is
# what the overlay reports from the start.
sess_env=()
sess_overlay=""
sess_start() {
  printf '%s\n' "$@" >"$sess_turns"
  fresh_logs
  rm -f "$XDG_RUNTIME_DIR/voxcmd/session.json" "$hints_state" "$popup_state_file"
  [ -z "$sess_overlay" ] || echo "$sess_overlay" >"$hints_state"
  mkdir -p "$XDG_RUNTIME_DIR/voxtype" "$XDG_RUNTIME_DIR/voxcmd"
  echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
  # shellcheck disable=SC2086 # the phrase is words
  sess_voxcmd_env ${sess_phrase:-start testing}
}
sess_phrase=""
# The stub call log and voxcmd's debug log, emptied before a run so sess_wait reads only its watchers.
fresh_logs() { mkdir -p "$(dirname "$debug_log")" && : >"$log" && : >"$debug_log"; }
# Waits for every watcher of the run to finish; fails when one is alive after 30s, which would be a microphone that never
# closes. listen logs each watcher's PID as it starts it, before the listen (or the watcher handing over) exits, so a
# watcher still to come always has a live parent or a logged PID.
sess_wait() {
  local deadline=$((SECONDS + 30)) pid running
  while ((SECONDS < deadline)); do
    running=0
    while read -r pid; do process_running "$pid" && running=1 && break; done < <(sed -n 's/.* listen: recording started, watcher \([0-9]*\) .*/\1/p' "$debug_log")
    ((running)) || return 0
    sleep 0.02
  done
  echo "   watchers still running after 30s"
  return 1
}
sess_run() {
  sess_start "$@"
  sess_wait
}
# log_has_soon <pattern> [secs]: the watcher starts in the background, so its log lines can land after listen has
# returned.
log_has_soon() { wait_for_line "$1" "$log" "${2:-20}"; }
taps() { grep -c '^tap ' "$log"; }
record_starts() { grep -c '^voxtype record start' "$log"; }
session_gone() { [[ ! -e $XDG_RUNTIME_DIR/voxcmd/session.json ]]; }
ended_because() { grep -q "^notify-send .*Test mode ended $1" "$log"; }
start_time_of() { sed 's/.*) //' "/proc/$1/stat" | awk '{print $20}'; }
# Waits until the session's owner is a watcher that has seen its recording start, so its traps are set.
owner_is_listening() {
  local deadline=$((SECONDS + 20)) owner
  while ((SECONDS < deadline)); do
    owner=$(jq -r .owner "$XDG_RUNTIME_DIR/voxcmd/session.json" 2>/dev/null)
    if [ -n "$owner" ] && grep -q "voxcmd\[$owner\] watch: voxtype recording\$" "$debug_log"; then
      return 0
    fi
    sleep 0.02
  done
  return 1
}

sess_run alpha beta "done"
check "targets are tapped in turn" "[[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' ]]"
check "it listens once more after each turn, and not after 'done'" "[[ \$(record_starts) == 3 ]]"
check "an exit word clears the session and leaves the microphone idle" "session_gone && [[ \$(cat '$XDG_RUNTIME_DIR/voxtype/state') == idle ]]"
check "session listens allow 10s of silence" "[[ \$(grep -c 'autostop no_speech_secs=10\$' '$log') == 3 ]]"
check "no session listen asks for the default" "! grep -q 'no_speech_secs=default' '$log'"

sess_env=(VOXCMD_AUTOSTOP_NO_SPEECH_SECS=4)
sess_run alpha "done"
check "the session's allowance wins over a user's auto-stop setting" "[[ \$(grep -c 'autostop no_speech_secs=10\$' '$log') == 2 ]]"
sess_env=(VOXCMD_SESSION_NO_SPEECH_SECS=7)
sess_run alpha "done"
check "VOXCMD_SESSION_NO_SPEECH_SECS sets it" "[[ \$(grep -c 'autostop no_speech_secs=7\$' '$log') == 2 ]]"
sess_env=(VOXCMD_AUTOSTOP_MIN_SPEECH_SECS=0.1 VOXCMD_AUTOSTOP_SILENCE_SECS=0.5)
sess_run alpha "done"
check "session listens want 0.4s of speech and a 1.5s pause, whatever auto-stop's settings" "[[ \$(grep -c 'autostop min_speech_secs=0.4 silence_secs=1.5\$' '$log') == 2 ]]"
sess_env=(VOXCMD_SESSION_MIN_SPEECH_SECS=0.8 VOXCMD_SESSION_SILENCE_SECS=2)
sess_run alpha "done"
check "VOXCMD_SESSION_MIN_SPEECH_SECS and VOXCMD_SESSION_SILENCE_SECS set them" "[[ \$(grep -c 'autostop min_speech_secs=0.8 silence_secs=2\$' '$log') == 2 ]]"
sess_env=()

# While it is open, the session file names its kind and a live owner.
sess_start alpha "done"
check "an open session records its kind, label and a live owner" "[[ \$(jq -r '[.kind, .label, (.owner | tostring | test(\"^[0-9]+\$\"))] | join(\",\")' '$XDG_RUNTIME_DIR/voxcmd/session.json') == 'test,Test mode,true' ]]"
sess_wait

for word in "done" "Done." "that's all" "I'm done" "stop testing" "Okay, stop testing." "done testing"; do
  sess_run alpha "$word" gamma
  check "'$word' ends the session and the microphone with it" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 2 ]]"
done
# Button labels: these are what the user wants clicked.
for word in "cancel" "exit" "stop" "never mind" "stop clicking" "stop testing now"; do
  sess_run "$word" "done"
  check "'$word' is a target, not an exit" "[[ \$(grep '^tap ' '$log') == 'tap $word' && \$(record_starts) == 2 ]]"
done

sess_run alpha
check "no speech ends the session instead of stopping silently" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 2 ]] && ended_because 'nothing was said'"
sess_run
check "no speech in the first listen ends it too" "session_gone && [[ \$(taps) == 0 && \$(record_starts) == 1 ]]"

sess_run noise noise noise alpha
check "three unusable turns in a row end it" "session_gone && [[ \$(taps) == 0 && \$(record_starts) == 3 ]] && ended_because 'nothing understood'"
sess_run missing missing missing alpha
check "three targets found nowhere end it" "session_gone && [[ \$(grep -c '^tap nothing' '$log') == 3 && \$(taps) == 3 ]]"
sess_run EMPTY EMPTY EMPTY alpha "done"
check "recordings that transcribe to nothing listen again without counting as unusable" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 5 ]] && ended_because done"
# Whisper's stock guesses at noise, as voxtype writes them.
sess_run "Thank you." "The End" "you" "..." "Thanks for watching!" "[BLANK_AUDIO]" alpha "done"
check "the transcriber's guesses at noise are not turns that missed" "session_gone && [[ \$(grep '^tap ' '$log') == 'tap alpha' && \$(record_starts) == 8 ]] && ended_because done"
check "and are not reported as not understood" "! grep -q 'Not understood' '$log'"
sess_env=(VOXCMD_SESSION_MAX_TURNS=3)
sess_run "Thank you." "The End" "Thank you." "Thank you." alpha
check "the turn cap still ends a session that only hears noise" "session_gone && [[ \$(taps) == 0 && \$(record_starts) == 3 ]] && ended_because 'it reached 3 turns'"
sess_env=()
sess_run noise noise alpha noise noise "done"
check "a usable turn resets the count" "session_gone && [[ \$(grep -c '^tap alpha' '$log') == 1 && \$(record_starts) == 6 ]]"

# The overlay inside a session: a pick is a turn that did something, a cancel (or timeout) one that did nothing.
printf '%s\n' 0 CANCEL CANCEL CANCEL >"$STUB_PICKS"
sess_run both both both both alpha
check "an overlay pick clicks and the session carries on" "[[ \$(grep '^tap ' '$log') == 'tap both left' ]]"
check "three cancelled overlays in a row end it" "session_gone && [[ \$(record_starts) == 4 ]] && ended_because 'nothing understood'"
check "the overlay's own listen keeps auto-stop's usual allowance" "[[ \$(grep -c '^pick no_speech_secs=default\$' '$log') == 4 && \$(grep -c '^pick min_speech_secs=default silence_secs=default\$' '$log') == 4 ]]"
printf '%s\n' CANCEL CANCEL 1 >"$STUB_PICKS"
sess_run both both both noise noise "done"
check "a pick resets the count of cancelled overlays" "[[ \$(grep '^tap ' '$log') == 'tap both right' && \$(record_starts) == 6 ]] && ended_because done"

# Caps that hold even while every turn does something.
sess_env=(VOXCMD_SESSION_MAX_TURNS=3)
sess_run alpha alpha alpha alpha alpha
check "a session ends after VOXCMD_SESSION_MAX_TURNS turns" "session_gone && [[ \$(taps) == 3 && \$(record_starts) == 3 ]] && ended_because 'it reached 3 turns'"
sess_env=(VOXCMD_SESSION_MAX_SECS=0)
sess_run alpha alpha
check "and after VOXCMD_SESSION_MAX_SECS" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 1 ]] && ended_because 'it reached its time limit'"
sess_env=()
check "by default it is 40 turns or 5 minutes" "grep -q 'VOXCMD_SESSION_MAX_SECS:-300}' '$package/.local/bin/voxcmd' && grep -q 'VOXCMD_SESSION_MAX_TURNS:-40}' '$package/.local/bin/voxcmd'"

# Without auto-stop nothing would end an idle session.
export SANDBOX_AUTOSTOP_OFF="auto-stop is turned off (enabled = false)"
sess_run alpha
check "no session opens while auto-stop is off" "session_gone && [[ \$(record_starts) == 0 ]] && grep -q '^notify-send .*--transient voxcmd: Test mode needs auto-stop auto-stop is turned off' '$log'"
unset SANDBOX_AUTOSTOP_OFF
# The interpreter itself, not `command -v python3`: a pyenv shim is a bash script, which the bare PATH below cannot run.
python3_binary=$(python3 -c 'import sys; print(sys.executable)')
autostop_check() { env -i PATH="$1" VOXCMD_CONFIG_DIR="$root/autostop-config" "${@:2}" "$python3_binary" "$package/.local/bin/voxcmd-autostop" --check; }
mkdir -p "$root/autostop-config" "$root/pw-bin" "$root/no-pw-bin"
printf '#!/bin/sh\n' >"$root/pw-bin/pw-record"
chmod +x "$root/pw-bin/pw-record"
check "autostop --check passes when it can listen" "autostop_check '$root/pw-bin' >/dev/null"
check "and fails when turned off" "[[ \$(autostop_check '$root/pw-bin' VOXCMD_AUTOSTOP=false) == *'turned off'* ]] && ! autostop_check '$root/pw-bin' VOXCMD_AUTOSTOP=false >/dev/null"
check "or when pw-record is missing" "[[ \$(autostop_check '$root/no-pw-bin') == *'pw-record is not installed'* ]]"
echo "bogus = 1" >"$root/autostop-config/autostop.conf"
check "or when its config is wrong" "[[ \$(autostop_check '$root/pw-bin') == *'unknown setting: bogus'* ]]"

# The detector itself, on synthetic audio: pcm <file> <kind>:<secs>:<dBFS>..., where noise is a steady hiss (a fan)
# and voice is a syllable-paced tone over the last noise. Nothing here is recorded.
pcm() {
  python3 - "$@" <<'PY'
import math, random, struct, sys
rate, rng, samples, room_db = 16000, random.Random(7), [], -90.0
for segment in sys.argv[2:]:
    kind, secs, db = segment.split(":")
    count, amplitude = int(float(secs) * rate), 32768 * 10 ** (float(db) / 20)
    if kind == "noise":
        room_db = float(db)
        samples += [rng.gauss(0, amplitude) for _ in range(count)]
    else:
        room_amplitude = 32768 * 10 ** (room_db / 20)
        samples += [rng.gauss(0, room_amplitude) + amplitude * math.sqrt(2) * abs(math.sin(math.pi * 4 * i / rate))
                    * math.sin(2 * math.pi * 180 * i / rate) for i in range(count)]
with open(sys.argv[1], "wb") as out:
    out.write(b"".join(struct.pack("<h", max(-32768, min(32767, int(sample)))) for sample in samples))
PY
}
# detect <file> [VAR=value...]: runs the detector on it with voxcmd's debug log on, printing its exit code; the trace
# is left in $detector_trace.
detector_trace=$root/detector-run/voxcmd/debug.log
mkdir -p "$root/detector-config" "$(dirname "$detector_trace")"
detect() {
  local status=0
  : >"$detector_trace"
  env XDG_RUNTIME_DIR="$root/detector-run" VOXCMD_CONFIG_DIR="$root/detector-config" "${@:2}" \
    python3 "$package/.local/bin/voxcmd-autostop" --pcm "$1" 2>/dev/null || status=$?
  echo "$status"
}
session_detector=(VOXCMD_AUTOSTOP_MIN_SPEECH_SECS=0.4 VOXCMD_AUTOSTOP_SILENCE_SECS=1.5 VOXCMD_AUTOSTOP_NO_SPEECH_SECS=5)
section "auto-stop detector"
# A microphone's first fraction of a second, quieter than the fan the rest of the recording hears.
pcm "$root/fan-after-quiet-start.pcm" noise:0.3:-75 noise:7.7:-42
check "a steady fan after a quiet start is not speech then a pause" "[[ \$(detect '$root/fan-after-quiet-start.pcm') == 3 ]]"
check "the trace says why the fan was set aside" "grep -q '1.80s of speech is 0.00s against the room now' '$detector_trace' && grep -q 'verdict no speech' '$detector_trace'"
check "and in a session" "[[ \$(detect '$root/fan-after-quiet-start.pcm' \"\${session_detector[@]}\") == 3 ]]"
pcm "$root/word-over-fan.pcm" noise:0.3:-75 noise:2.7:-42 voice:0.9:-18 noise:4:-42
check "a word over the same fan still stops it" "[[ \$(detect '$root/word-over-fan.pcm') == 0 ]]"
check "the trace has the room, the threshold, each speech run and the verdict" "grep -q 'calibrated: room -7[0-9.]* dBFS, threshold -45.0 dBFS' '$detector_trace' && grep -q 'speech run [0-9.]*s +[0-9.]*s: mean -[0-9.]* peak -[0-9.]* threshold -[0-9.]* dBFS' '$detector_trace' && grep -q 'verdict speech then quiet at [0-9.]*s: room -4[0-9.]*, threshold -3[0-9.]* dBFS, speech [0-9.]*s' '$detector_trace'"
check "a session stops on it too" "[[ \$(detect '$root/word-over-fan.pcm' \"\${session_detector[@]}\") == 0 ]]"
# Two knocks on the desk: enough for a command, not for a session turn.
pcm "$root/knocks.pcm" noise:1:-55 voice:0.15:-25 noise:0.35:-55 voice:0.15:-25 noise:5:-55
check "two knocks then quiet stop a command" "[[ \$(detect '$root/knocks.pcm') == 0 ]] && grep -q 'verdict speech then quiet at [12]\.' '$detector_trace'"
check "a session does not stop on them, only takes them as a short word at its no-speech deadline" "[[ \$(detect '$root/knocks.pcm' \"\${session_detector[@]}\") == 0 ]] && grep -q 'a short word, stopping' '$detector_trace' && grep -q 'verdict speech then quiet at 5\.' '$detector_trace'"
# A spoken "cancel" heard as 0.15s of speech: short of a command's min_speech_secs, but still an answer.
reply_detector=(VOXCMD_AUTOSTOP_MIN_SPEECH_SECS=0.1)
pcm "$root/short-word.pcm" noise:2:-48 voice:0.15:-28 noise:6:-48
check "a short word is transcribed at the no-speech deadline, not cancelled" "[[ \$(detect '$root/short-word.pcm') == 0 ]] && grep -q 'a short word, stopping' '$detector_trace' && grep -q 'verdict speech then quiet at 6\.' '$detector_trace'"
check "a reply's lower minimum stops on the pause after it" "[[ \$(detect '$root/short-word.pcm' \"\${reply_detector[@]}\") == 0 ]] && grep -q 'verdict speech then quiet at 3\.' '$detector_trace'"
pcm "$root/word-at-deadline.pcm" noise:5.8:-48 voice:0.5:-28 noise:3:-48
check "speech under way at the deadline still waits for its pause" "[[ \$(detect '$root/word-at-deadline.pcm') == 0 ]] && grep -q 'verdict speech then quiet at 7\.' '$detector_trace'"
pcm "$root/quiet-room.pcm" noise:6:-60
check "a quiet room is no speech" "[[ \$(detect '$root/quiet-room.pcm') == 3 ]]"
check "for a reply too" "[[ \$(detect '$root/quiet-room.pcm' \"\${reply_detector[@]}\") == 3 && \$(detect '$root/fan-after-quiet-start.pcm' \"\${reply_detector[@]}\") == 3 ]]"
check "without the debug log there is no trace" "env -u VOXCMD_DEBUG XDG_RUNTIME_DIR='$root/no-trace' python3 '$package/.local/bin/voxcmd-autostop' --pcm '$root/quiet-room.pcm'; [[ ! -e '$root/no-trace/voxcmd/debug.log' ]]"

section "voice sessions: endings and settling"
# A start that fails ends the session rather than leaving it open with no microphone.
sess_run alpha FAIL
check "a failed record start ends the session" "session_gone && [[ \$(taps) == 1 ]] && ended_because 'the microphone could not be opened'"
sess_run FAIL
check "so does one for the first turn" "session_gone && [[ \$(taps) == 0 ]] && ended_because 'the microphone could not be opened'"

# The voice key pressed while a turn is still settling: that listen takes the session over, and the turn's own watcher
# leaves it alone instead of ending it and discarding the user's recording. The overlay stays "open" so the first
# watcher is held in its settle wait until the takeover is done.
sess_overlay=open
sess_env=(VOXCMD_UI_SETTLE_MAX_SECS=30)
sess_start alpha beta
log_has_soon '^qs-ipc call clickhints state'
sess_voxcmd_env listen
log_has_soon '^tap beta'
echo closed >"$hints_state"
sess_wait
check "a voice key pressed during a turn takes the session over" "[[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' ]]"
check "the turn's watcher does not listen again or cancel the new recording" "[[ \$(record_starts) == 3 ]] && ! grep -q 'microphone could not be opened' '$log' && ended_because 'nothing was said'"
sess_overlay=""
sess_env=()

# Ending the session while its recording is open cancels that recording.
sess_start HOLD
owner_is_listening
sess_voxcmd_env end-session
sess_wait
check "end-session while recording cancels it and closes the microphone" "session_gone && grep -q '^voxtype record cancel' '$log' && [[ \$(cat '$XDG_RUNTIME_DIR/voxtype/state') == idle && \$(record_starts) == 1 ]] && ended_because 'ended by request'"

# Settling: the next listen waits for the overlay and popups. The stub bar reports what the files hold. Bounds are
# loose, since a loaded machine stretches every sleep; they only tell a short wait from the long one.
settle_ms() {
  local started
  started=$(date +%s%N)
  env "$@" "$sess_voxcmd" _settle >/dev/null 2>&1
  echo $((($(date +%s%N) - started) / 1000000))
}
rm -f "$hints_state" "$popup_state_file"
check "a settled screen waits only the app's moment" "[[ \$(settle_ms VOXCMD_APP_SETTLE_SECS=0.1 VOXCMD_UI_SETTLE_MAX_SECS=20) -ge 100 && \$(settle_ms VOXCMD_APP_SETTLE_SECS=0.1 VOXCMD_UI_SETTLE_MAX_SECS=20) -lt 10000 ]]"
echo open >"$hints_state"
(sleep 0.2 && echo closed >"$hints_state") &
check "an open overlay is waited out" "[[ \$(settle_ms VOXCMD_APP_SETTLE_SECS=0) -ge 150 ]]"
wait
for popup_state in "opening weather" "open weather" "closing weather"; do
  echo "$popup_state" >"$popup_state_file"
  (sleep 0.2 && echo closed >"$popup_state_file") &
  check "a popup that is '$popup_state' is waited out" "[[ \$(settle_ms VOXCMD_APP_SETTLE_SECS=0) -ge 150 ]]"
  wait
done
echo open >"$hints_state"
check "a screen that never settles is waited on for a bounded time" "[[ \$(settle_ms VOXCMD_APP_SETTLE_SECS=0 VOXCMD_UI_SETTLE_MAX_SECS=0.3) -ge 300 && \$(settle_ms VOXCMD_APP_SETTLE_SECS=0 VOXCMD_UI_SETTLE_MAX_SECS=0.3) -lt 10000 ]] && ! env VOXCMD_APP_SETTLE_SECS=0 VOXCMD_UI_SETTLE_MAX_SECS=0.1 '$sess_voxcmd' _settle"
rm -f "$hints_state"
check "no bar to ask counts as settled" "env XDG_CONFIG_HOME='$root/no-bar' VOXCMD_APP_SETTLE_SECS=0 '$sess_voxcmd' _settle"

# In a session the bar is asked after the turn's action and before the microphone opens again.
sess_run alpha "done"
check "the screen is checked between a turn's action and the next listen" "[[ \$(awk '/^tap alpha/{a=NR} /qs-ipc call clickhints state/{if (a && !q) q=NR} /voxtype record start/{n++; if (n==2) r=NR} END{print (a && a < q && q < r) ? \"ok\" : \"no\"}' '$log') == ok ]]"

# A stale session: its owner is gone, so the next listen routes normally and clears it.
stale_listen() {
  printf '%s\n' "tap hello" >"$sess_turns"
  fresh_logs
  echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
  jq -n -c --argjson owner "$1" --arg owner_start "$2" \
    '{kind: "test", integration: "x", label: "Test mode", started: 0, owner: $owner, owner_start: $owner_start, unclear: 0, turns: 0}' \
    >"$XDG_RUNTIME_DIR/voxcmd/session.json"
  sess_voxcmd_env listen
  sess_wait
}
stale_listen 999999 1
check "a stale session is dropped and the command routes normally" "session_gone && [[ \$(grep '^tap ' '$log') == 'tap hello' && \$(record_starts) == 1 ]]"
check "a normal listen keeps the default silence allowance" "grep -q 'no_speech_secs=default' '$log' && grep -q 'min_speech_secs=default silence_secs=default' '$log'"
# A live process under the owner's PID is not the owner unless it started when the owner did.
"$stub_sleep" 60 &
reused_pid=$!
stale_listen "$reused_pid" 1
check "a reused owner PID does not keep the session" "session_gone && [[ \$(grep '^tap ' '$log') == 'tap hello' ]]"
kill "$reused_pid" 2>/dev/null
wait "$reused_pid" 2>/dev/null
# Outside a session the same words are a command like any other.
rm -f "$XDG_RUNTIME_DIR/voxcmd/session.json"
printf '%s\n' "thank you" >"$sess_turns"
: >"$XDG_RUNTIME_DIR/voxcmd/debug.log"
sess_voxcmd_env listen
sess_wait
check "outside a session a stock noise transcript is routed" "grep -q 'transcript \"thank you\" goes to route' '$XDG_RUNTIME_DIR/voxcmd/debug.log' && ! grep -q 'guess at noise' '$XDG_RUNTIME_DIR/voxcmd/debug.log'"
rm -f "$XDG_RUNTIME_DIR/voxcmd/debug.log"

# The watcher dying mid-session takes the session with it. Killed only once it is listening: a watcher killed while it
# starts dies before its trap is set, and one handing over to a successor that is starting leaves the session to it.
sess_start HOLD
owner_is_listening
pkill -TERM -f "$sess_voxcmd _watch"
sess_wait
check "a killed listener ends the session" "session_gone"
# SIGKILL runs no trap, so the file stays, but the owner check reads it as no session.
sess_start HOLD
owner_is_listening
pkill -KILL -f "$sess_voxcmd _watch"
sess_wait
check "a SIGKILLed listener leaves its file behind" "! session_gone"
printf '%s\n' "tap hello" >"$sess_turns"
fresh_logs
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
sess_voxcmd_env listen
sess_wait
check "and the next listen finds no session and routes normally" "session_gone && [[ \$(grep '^tap ' '$log') == 'tap hello' ]]"
pkill -f "$stub_sleep"

# A recording that belongs to a reply keeps its priority over the session.
mkdir -p "$root/owner"
cp /bin/sleep "$root/owner/voxcmd"
"$root/owner/voxcmd" 60 &
owner_pid=$!
cp /bin/sleep "$root/voxcmd-hints"
"$root/voxcmd-hints" 60 &
waiter_pid=$!
mkfifo "$root/pending-fifo"
jq -n -c --argjson pid "$waiter_pid" --arg fifo "$root/pending-fifo" \
  '{pid: $pid, fifo: $fifo, label: "Which one?", kind: "hints", expansions: {}, choices: [{id: "a", label: "1. A"}]}' >"$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
jq -n -c --argjson owner "$owner_pid" --arg owner_start "$(start_time_of "$owner_pid")" \
  '{kind: "test", integration: "x", label: "Test mode", started: 0, owner: $owner, owner_start: $owner_start, unclear: 0, turns: 0}' \
  >"$XDG_RUNTIME_DIR/voxcmd/session.json"
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
: >"$log"
"$sess_voxcmd" listen >/dev/null 2>&1
log_has_soon 'setsid '
check "a pending picker's reply wins over the open session" "grep -q 'setsid .*_watch reply' '$log' && ! grep -q 'setsid .*_watch session_turn' '$log'"
rm -f "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
: >"$log"
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
"$sess_voxcmd" listen >/dev/null 2>&1
log_has_soon 'setsid '
check "with nothing pending, a live session's listen goes to the session" "grep -q 'setsid .*_watch session_turn' '$log'"
# The detector each listen starts: a reply's lower speech minimum, the session's settings, nothing for a command.
sess_env=(VOXCMD_AUTOSTOP_MIN_SPEECH_SECS=0.5)
detector_settings_of() {
  printf '%s\n' SILENCE >"$sess_turns"
  fresh_logs
  echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
  sess_voxcmd_env listen
  sess_wait
  grep '^voxcmd-autostop ' "$log" | sed 's/^voxcmd-autostop //' | paste -sd' '
}
jq -n -c --argjson owner "$owner_pid" --arg owner_start "$(start_time_of "$owner_pid")" \
  '{kind: "test", integration: "x", label: "Test mode", started: 0, owner: $owner, owner_start: $owner_start, unclear: 0, turns: 0}' \
  >"$XDG_RUNTIME_DIR/voxcmd/session.json"
check "a session turn's listen keeps the session's settings" "[[ \$(detector_settings_of) == 'no_speech_secs=10 min_speech_secs=0.4 silence_secs=1.5' ]]"
rm -f "$XDG_RUNTIME_DIR/voxcmd/session.json"
check "a command's listen keeps auto-stop's own" "[[ \$(detector_settings_of) == 'no_speech_secs=default min_speech_secs=0.5 silence_secs=default' ]]"
jq -n -c --argjson pid "$waiter_pid" --arg fifo "$root/pending-fifo" \
  '{pid: $pid, fifo: $fifo, label: "Which one?", kind: "hints", expansions: {}, choices: [{id: "a", label: "1. A"}]}' >"$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
check "a reply's listen wants only 0.1s of speech, with auto-stop's own pause and deadline" "[[ \$(detector_settings_of) == 'no_speech_secs=default min_speech_secs=0.1 silence_secs=default' ]]"
sess_env=(VOXCMD_REPLY_MIN_SPEECH_SECS=0.2)
check "VOXCMD_REPLY_MIN_SPEECH_SECS sets it" "[[ \$(detector_settings_of) == 'no_speech_secs=default min_speech_secs=0.2 silence_secs=default' ]]"
sess_env=()
rm -f "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
kill "$owner_pid" "$waiter_pid" 2>/dev/null
wait "$owner_pid" "$waiter_pid" 2>/dev/null
rm -f "$XDG_RUNTIME_DIR/voxcmd/session.json" "$XDG_RUNTIME_DIR/voxtype/state"

# ---- link hints: "show links" listens for the number, then follows it or takes the hints down -----------------------
# firefox.sh for real, with a firefox-tab that logs what it is asked to type (and fails while $links_fail exists).
section "link hints"
cat >"$sess_pkg/.local/share/voxcmd/firefox-tab" <<STUB
#!/bin/sh
echo "firefox-tab \$*" >> "$log"
[ ! -e "$root/links-fail" ]
STUB
chmod +x "$sess_pkg/.local/share/voxcmd/firefox-tab"
links_config=$root/config-links
mkdir -p "$links_config/integrations.d" "$links_config/replacements.d"
cp "$package/.config/voxcmd/integrations.d/firefox.sh" "$links_config/integrations.d/"
sess_config=$links_config
sess_phrase="show links"
tab_calls() { grep '^firefox-tab ' "$log" | sed 's/^firefox-tab //' | paste -sd,; }
# The hints come down on their own, in the background after the session ends.
dismissed_soon() { log_has_soon '^firefox-tab dismiss-hints$'; }
rm -f "$root/links-fail" "$XDG_RUNTIME_DIR/voxcmd/links-shown"

sess_run 3
check "'show links' shows the hints, listens, and a bare number follows that link" "[[ \$(tab_calls) == 'hints,hints 3' ]]"
check "the follow ends the session and the microphone, with the hints left to Firefox" "session_gone && [[ \$(record_starts) == 1 ]]"
sleep 0.5
check "and Escape is not typed after a followed link" "! grep -q dismiss-hints '$log'"
check "the listen is a reply's: 0.1s of speech and auto-stop's own deadline" "[[ \$(grep '^voxcmd-autostop ' '$log' | sed 's/^voxcmd-autostop //' | paste -sd' ') == 'no_speech_secs=default min_speech_secs=0.1 silence_secs=default' ]]"
sess_run "Follow link 3."
check "'follow link 3' works too" "[[ \$(tab_calls) == 'hints,hints 3' ]]"
sess_run "three"
check "a number word is a number" "[[ \$(tab_calls) == 'hints,hints 3' ]]"
sess_run "Twenty one."
check "so is a longer one" "[[ \$(tab_calls) == 'hints,hints 21' ]]"
sess_run "open link number 7"
check "and 'open link number 7'" "[[ \$(tab_calls) == 'hints,hints 7' ]]"

sess_run
check "nothing said: the session ends, and the hints are taken down" "session_gone && [[ \$(record_starts) == 1 ]] && grep -q '^notify-send .*Link hints ended nothing was said' '$log'"
dismissed_soon
check "with one Escape, after the hints were typed" "[[ \$(tab_calls) == 'hints,dismiss-hints' ]]"
sess_run banana "the weather" "ten past"
check "words that are no number follow nothing and, three times, end it" "session_gone && [[ \$(record_starts) == 3 ]] && ! grep -q '^firefox-tab hints [a-z0-9]' '$log'"
dismissed_soon
check "and take the hints down" "[[ \$(tab_calls) == 'hints,dismiss-hints' ]]"
sess_run banana 5
check "an unclear turn is no reason to give up: the next one follows" "[[ \$(tab_calls) == 'hints,hints 5' ]]"
sess_run cancel
dismissed_soon
check "'cancel' takes the hints down and follows nothing" "session_gone && [[ \$(tab_calls) == 'hints,dismiss-hints' && \$(record_starts) == 1 ]]"
sess_run "never mind"
dismissed_soon
check "'never mind' does too" "[[ \$(tab_calls) == 'hints,dismiss-hints' ]]"
sess_run "done"
dismissed_soon
check "and so does the session's own 'done'" "[[ \$(tab_calls) == 'hints,dismiss-hints' ]]"

: >"$root/links-fail"
sess_run 3
check "hints that could not be shown open no listen" "session_gone && [[ \$(tab_calls) == hints && \$(record_starts) == 0 ]]"
rm -f "$root/links-fail"
sess_phrase="follow link 4"
sess_run
check "'follow link 4' alone opens no session" "session_gone && [[ \$(tab_calls) == 'hints 4' && \$(record_starts) == 0 ]]"
sess_phrase=""
sess_config=$root/config-sess

finish
