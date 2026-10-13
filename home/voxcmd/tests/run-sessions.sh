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
echo "pick-args \$*" >> "$log"
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
  slow)
    # A route that is still working when the test presses Stop.
    touch "$root/routing"
    while [ ! -e "$root/route-release" ]; do sleep 0.02; done
    echo '[{"id": "slow left", "label": "slow left"}, {"id": "slow right", "label": "slow right"}]'
    ;;
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
session_ended() { echo "ended-hook" >> "$log"; }
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

# every_detector_logged <setting> <line>: each session listen's detector logged its <setting> as <line>, and at least one
# did. A turn of speech can end before its listen's detector starts, which then never runs (nor logs), so the run ends
# on a turn of silence: that recording lasts until its detector's verdict, so its line is always there.
every_detector_logged() {
  local lines
  lines=$(grep "^voxcmd-autostop $1" "$log" | sed 's/^voxcmd-autostop //')
  [[ -n $lines ]] && ! grep -qvx "$2" <<<"$lines"
}
sess_run alpha SILENCE
check "session listens allow 10s of silence" "every_detector_logged no_speech_secs= no_speech_secs=10"
check "no session listen asks for the default" "! grep -q 'no_speech_secs=default' '$log'"

sess_env=(VOXCMD_AUTOSTOP_NO_SPEECH_SECS=4)
sess_run alpha SILENCE
check "the session's allowance wins over a user's auto-stop setting" "every_detector_logged no_speech_secs= no_speech_secs=10"
sess_env=(VOXCMD_SESSION_NO_SPEECH_SECS=7)
sess_run alpha SILENCE
check "VOXCMD_SESSION_NO_SPEECH_SECS sets it" "every_detector_logged no_speech_secs= no_speech_secs=7"
sess_env=(VOXCMD_AUTOSTOP_MIN_SPEECH_SECS=0.1 VOXCMD_AUTOSTOP_SILENCE_SECS=0.5)
sess_run alpha SILENCE
check "session listens want 0.4s of speech and a 1.5s pause, whatever auto-stop's settings" "every_detector_logged min_speech_secs= 'min_speech_secs=0.4 silence_secs=1.5'"
sess_env=(VOXCMD_SESSION_MIN_SPEECH_SECS=0.8 VOXCMD_SESSION_SILENCE_SECS=2)
sess_run alpha SILENCE
check "VOXCMD_SESSION_MIN_SPEECH_SECS and VOXCMD_SESSION_SILENCE_SECS set them" "every_detector_logged min_speech_secs= 'min_speech_secs=0.8 silence_secs=2'"
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
# Whisper can echo the wake-word sentence voxtype-daemon puts in its prompt.
sess_run "Voice commands start with Jarvis." alpha "done"
check "an echo of the transcriber's prompt is noise" "session_gone && [[ \$(grep '^tap ' '$log') == 'tap alpha' && \$(record_starts) == 3 ]] && ! grep -q 'no match' '$log'"
sess_env=(VOXCMD_WAKE_WORD=computer)
sess_run "Voice commands start with Computer." alpha "done"
check "and it follows the configured wake word" "session_gone && [[ \$(grep '^tap ' '$log') == 'tap alpha' && \$(record_starts) == 3 ]] && ! grep -q 'no match' '$log'"
sess_env=()
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
# A long speech is cut at max_secs, as type mode chunks it; without the limit it runs on to its pause.
pcm "$root/long-speech.pcm" noise:0.3:-60 voice:9:-18 noise:3:-60
check "max_secs cuts a long speech into chunks" "[[ \$(detect '$root/long-speech.pcm' VOXCMD_AUTOSTOP_MAX_SECS=4) == 0 ]] && grep -q 'recording with speech in it, cutting here' '$detector_trace' && grep -q 'verdict speech then quiet at 4\.' '$detector_trace'"
check "and with none the speech runs to its pause" "[[ \$(detect '$root/long-speech.pcm') == 0 ]] && grep -q 'verdict speech then quiet at 1[0-9]\.' '$detector_trace'"
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

# stop is the one key for any voice activity: the session, a picker waiting for an answer, a recording.
sess_start HOLD
owner_is_listening
sess_voxcmd_env stop
sess_wait
check "stop during a session ends it, cancels its recording and closes the microphone" "session_gone && grep -q '^voxtype record cancel' '$log' && [[ \$(cat '$XDG_RUNTIME_DIR/voxtype/state') == idle && \$(record_starts) == 1 ]] && ended_because 'stopped'"

# Stopped while the turn is already transcribing: the watcher is past the microphone, and must not listen again. The
# watcher is frozen while stop runs, so it is stop that finds the recording and cancels it.
sess_start HOLD
owner_is_listening
stopped_owner=$(jq -r .owner "$XDG_RUNTIME_DIR/voxcmd/session.json")
echo transcribing >"$XDG_RUNTIME_DIR/voxtype/state"
kill -STOP "$stopped_owner"
sess_voxcmd_env stop
kill -CONT "$stopped_owner"
sess_wait
check "stop while a turn transcribes ends the session and opens no further microphone" "session_gone && [[ \$(record_starts) == 1 && \$(taps) == 0 ]] && ended_because 'stopped'"
check "and stop itself cancels the transcribing" "grep -q 'stop: cancelling the transcribing voxtype' '$debug_log' && grep -q '^voxtype record cancel' '$log'"

# Stopped while the turn's action is already routing: it finishes, but the picker it opens does not listen for a reply.
rm -f "$root/routing" "$root/route-release"
echo CANCEL >"$STUB_PICKS"
sess_start slow
while [ ! -e "$root/routing" ]; do sleep 0.02; done
sess_voxcmd_env stop
touch "$root/route-release"
sess_wait
check "stop while a turn routes: the picker it opens does not listen and no microphone opens" "session_gone && grep -q '^pick-args ' '$log' && ! grep -q '^pick-args .*--listen' '$log' && [[ \$(record_starts) == 1 ]] && ended_because 'stopped'"
rm -f "$root/routing" "$root/route-release"

# A recording nobody here watches (Speech to Text, or a command's) is cancelled, so nothing said is typed or routed.
fresh_logs
echo recording >"$XDG_RUNTIME_DIR/voxtype/state"
sess_voxcmd_env stop
check "stop cancels a dictation and says nothing" "grep -q '^voxtype record cancel' '$log' && ! grep -q '^notify-send' '$log'"

# A waiting picker is answered with an empty line, as a cancel.
fresh_logs
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
cp /bin/sleep "$root/voxcmd-hints"
"$root/voxcmd-hints" 60 &
stop_waiter_pid=$!
mkfifo "$root/stop-fifo"
jq -n -c --argjson pid "$stop_waiter_pid" --arg fifo "$root/stop-fifo" \
  '{pid: $pid, fifo: $fifo, label: "Which one?", kind: "hints", expansions: {}, choices: [{id: "a", label: "1. A"}]}' >"$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
timeout 10 head -n1 "$root/stop-fifo" >"$root/stop-answer" &
stop_reader_pid=$!
sess_voxcmd_env stop
wait "$stop_reader_pid"
check "stop cancels a waiting picker with an empty answer" "[[ \$(cat '$root/stop-answer') == '' && \$(wc -l <'$root/stop-answer') == 1 ]] && ! grep -q '^voxtype record' '$log'"
rm -f "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
kill "$stop_waiter_pid" 2>/dev/null
wait "$stop_waiter_pid" 2>/dev/null

# A bar that hangs fails notify-send, which must not keep stop from taking down the session, the picker or the recording.
mkdir -p "$root/failing-bin"
printf '#!/bin/sh\nexit 1\n' >"$root/failing-bin/notify-send"
chmod +x "$root/failing-bin/notify-send"
sess_start HOLD
owner_is_listening
cp /bin/sleep "$root/voxcmd-hints"
"$root/voxcmd-hints" 60 &
stop_waiter_pid=$!
mkfifo "$root/stop-fifo-2"
jq -n -c --argjson pid "$stop_waiter_pid" --arg fifo "$root/stop-fifo-2" \
  '{pid: $pid, fifo: $fifo, label: "Which one?", kind: "hints", expansions: {}, choices: [{id: "a", label: "1. A"}]}' >"$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
timeout 10 head -n1 "$root/stop-fifo-2" >"$root/stop-answer-2" &
stop_reader_pid=$!
sess_env=(PATH="$root/failing-bin:$PATH")
sess_voxcmd_env stop
sess_env=()
wait "$stop_reader_pid"
sess_wait
check "stop with a failing notification still ends the session, runs its ended hook and cancels picker and recording" "session_gone && log_has_soon '^ended-hook' && [[ \$(cat '$root/stop-answer-2') == '' ]] && grep -q '^voxtype record cancel' '$log'"
rm -f "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
kill "$stop_waiter_pid" 2>/dev/null
wait "$stop_waiter_pid" 2>/dev/null

# With nothing open it is silent.
fresh_logs
rm -f "$XDG_RUNTIME_DIR/voxcmd/session.json"
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
check "stop with nothing open exits 0 and does nothing" "env SANDBOX_SETSID_RUN=1 VOXCMD_CONFIG_DIR='$sess_config' '$sess_voxcmd' stop >/dev/null 2>&1 && ! grep -qE '^(voxtype record|notify-send)' '$log'"

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

# ---- modes: rapid, type, and the stack they share ----------------------------------------------------------------------
# rapid.sh, typing.sh and click.sh for real beside the test mode, Media (a routed "stop") and two
# integrations that ask: a yes/no card and a picker of two. The card and the picker are logging stubs.
section "modes"
modes_config=$root/config-modes
mkdir -p "$modes_config/integrations.d" "$modes_config/replacements.d"
cp "$root/config-sess/integrations.d/sess.sh" "$modes_config/integrations.d/"
for integration in rapid typing click media; do
  cp "$package/.config/voxcmd/integrations.d/$integration.sh" "$modes_config/integrations.d/"
done
cat >"$modes_config/integrations.d/ask.sh" <<STUB
name="Ask"
confirm=1
verbs=("ask_it ask me" "both_of_them pick {target}")
candidates() {
  case "\$1" in
  both_of_them) echo '[{"id": "one", "label": "number one"}, {"id": "two", "label": "number two"}]' ;;
  esac
}
declare -A actions=([ask_it]='echo "asked" >> "$log"' [both_of_them]='echo "picked \$id" >> "$log"')
STUB
# The card answers yes unless $root/confirm-no exists.
for asking in voxcmd-confirm voxcmd-pick; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\n[ "%s" = voxcmd-confirm ] || echo 0\n' "$asking" "$log" "$asking" >"$sess_pkg/.local/bin/$asking"
  chmod +x "$sess_pkg/.local/bin/$asking"
done
printf '[ ! -e "%s" ]\n' "$root/confirm-no" >>"$sess_pkg/.local/bin/voxcmd-confirm"
sess_config=$modes_config
focused_window='{"address":"0x1","class":"kitty","size":[800,600]}'
session_json=$XDG_RUNTIME_DIR/voxcmd/session.json
mode_is() { [[ $(jq -r '[.kind, (.stack | map(.kind) | join("/"))] | join(" ")' "$session_json" 2>/dev/null) == "$1" ]]; }
toast_has() { grep -q "^notify-send .*$1" "$log"; }
no_clicks() { ! grep -qE '^(wlrctl|grim|tesseract)' "$log"; }
# hold_in <mode> <recordings>: waits until the session is in that mode ("<kind> <stack kinds>") and has started that many
# recordings, the last one a HOLD, whose watcher has seen it.
hold_in() {
  local deadline=$((SECONDS + 20))
  until mode_is "$1" && [[ $(record_starts) == "$2" ]] && owner_is_listening; do
    ((SECONDS < deadline)) || return 1
    sleep 0.02
  done
}

# Rapid mode: every turn is a command.
sess_phrase="rapid mode"
sess_run "tap alpha" "tap beta" "done"
check "rapid mode routes each turn as a command until 'done'" "session_gone && [[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' && \$(record_starts) == 3 ]]"
sess_start HOLD
owner_is_listening
check "rapid mode's session names the mode, its exit hint and an empty stack" "[[ \$(jq -c '[.kind, .label, .exit_hint, .stack]' '$session_json') == '[\"rapid\",\"Rapid mode\",\"say done to stop\",[]]' ]]"
sess_voxcmd_env end-session
sess_wait
for word in "done" "Done." "that's all" "I'm done" "stop rapid mode" "Okay, quit rapid mode." "done with rapid mode" "rapid mode off" "turn off rapid fire mode"; do
  sess_run "tap alpha" "$word" "tap gamma"
  check "'$word' ends rapid mode" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 2 ]]"
done
for word in "jarvis done" "Jarvis, I'm done." "Jarvis, stop rapid mode." "jarvis stop"; do
  sess_run "tap alpha" "$word" "tap gamma"
  check "'$word' ends rapid mode" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 2 ]]"
done
sess_run "stop" "cancel" "done"
check "'stop' is a command (pause) and 'cancel' a discarded one, neither an exit" "session_gone && grep -q '^playerctl pause' '$log' && [[ \$(record_starts) == 3 ]]"
sess_run "jarvis tap alpha" "tap beta" "done"
check "a 'jarvis ...' that is no mode command is routed as a command, and the mode goes on" "session_gone && ! toast_has 'Not a mode command' && [[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' && \$(record_starts) == 3 ]]"
sess_run "jarvis tap" "tap beta" "done"
check "and one that matches nothing is a missed turn with the usual toast" "session_gone && toast_has 'no match' && [[ \$(grep '^tap ' '$log') == 'tap beta' && \$(record_starts) == 3 ]]"
sess_run "tap alpha"
check "rapid mode ends when nothing is said" "session_gone && toast_has 'Rapid mode ended nothing was said'"
sess_env=(VOXCMD_SESSION_MAX_TURNS=3)
sess_run "tap alpha" "tap alpha" "tap alpha" "tap alpha"
check "rapid mode is capped by turns like any session" "session_gone && [[ \$(taps) == 3 ]] && toast_has 'Rapid mode ended it reached 3 turns'"
sess_env=()
sess_env=(VOXCMD_WAKE_WORD=computer VOXCMD_WAKE_ALIASES="komputer|kompooter")
sess_run "jarvis done" "Komputer, done" "tap alpha"
check "the wake word and its spellings are settings, and the old word is then no command" "session_gone && grep -q 'voxcmd: no match' '$log' && [[ \$(taps) == 0 && \$(record_starts) == 2 ]]"
sess_env=()
sess_phrase="jarvis rapid mode"
sess_run "done"
check "the wake word before an entry phrase is stripped" "session_gone && [[ \$(record_starts) == 1 ]]"
sess_phrase="rapid mode"

# A card and a picker asked in a rapid turn listen for the spoken answer.
sess_run "ask me" "pick number" "done"
check "a confirm card in rapid mode listens for yes or no" "grep -q '^voxcmd-confirm .*--listen' '$log' && [[ \$(grep -c '^asked' '$log') == 1 ]]"
check "and so does a picker of several options" "grep -q '^voxcmd-pick --listen' '$log' && grep -q '^picked one' '$log'"

# A phrase of steps joined by "and then" is one turn, and each step may ask.
sess_run "tap alpha and then tap beta" "done"
check "a sequence in rapid mode runs its steps in order, as one turn" "session_gone && [[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' && \$(record_starts) == 2 ]]"
sess_env=(VOXCMD_SESSION_MAX_TURNS=2)
sess_run "tap alpha and then tap beta" "tap gamma" "tap delta"
check "and counts once against the turn cap" "session_gone && [[ \$(taps) == 3 ]] && toast_has 'Rapid mode ended it reached 2 turns'"
sess_env=()
sess_run "tap alpha and then tap" "tap beta and then tap" "tap gamma and then tap" "tap delta" "done"
check "a sequence in which a step ran is not a missed turn, though a later step matched nothing" "session_gone && [[ \$(taps) == 4 ]] && ! toast_has 'nothing understood'"
sess_run "tap and then tap" "tap and then tap" "tap and then tap" "tap delta"
check "one in which no step ran is a missed turn" "session_gone && [[ \$(taps) == 0 ]] && toast_has 'nothing understood 3 times'"
sess_run "tap alpha and then ask me" "done"
check "a card asked in a later step listens for yes or no when it was spoken" "grep -q '^voxcmd-confirm .*--listen' '$log' && [[ \$(taps) == 1 && \$(grep -c '^asked' '$log') == 1 ]]"
: >"$root/confirm-no"
sess_run "ask me" "ask me" "ask me" "tap delta"
check "a declined confirm card is a missed turn, not one that ran" "session_gone && [[ \$(taps) == 0 && \$(grep -c '^asked' '$log') == 0 ]] && toast_has 'nothing understood 3 times'"
sess_run "tap alpha and then ask me and then tap beta" "done"
check "a declined card in a sequence stops the rest with one toast" "[[ \$(taps) == 1 && \$(grep -c 'Stopped at step 2 of 3' '$log') == 1 ]] && toast_has 'Stopped at step 2 of 3: not confirmed' && grep -q '^1 more step not run' '$log'"
rm -f "$root/confirm-no"

# Modes nest: the one opened inside returns to the one it was opened from.
sess_run "start testing" "alpha and then beta" "done"
check "a mode that rewrites its turns rewrites each step of a sequence" "session_gone && [[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' ]]"
sess_run "start testing" "alpha and then done" "tap beta" "done"
check "a last step that is the mode's exit phrase runs the steps before it, then leaves the mode" "session_gone && [[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' && \$(record_starts) == 4 ]]"
sess_run "tap alpha and then done" "tap beta"
check "and in rapid mode it ends the mode" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 1 ]]"
sess_run "start testing" "alpha" "done" "tap beta" "done"
check "a mode opened in rapid mode returns to it: test mode's targets, then rapid mode's commands" "session_gone && [[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' && \$(record_starts) == 5 ]]"
check "and runs its ended hook once" "log_has_soon '^ended-hook' && [[ \$(grep -c '^ended-hook' '$log') == 1 ]]"
sess_start "start testing" HOLD
hold_in 'test rapid' 2
check "the session file names the mode on top and the one underneath" "mode_is 'test rapid' && [[ \$(jq -r '[.exit_hint, .stack[0].label] | join(\"|\")' '$session_json') == 'say done to stop (back to Rapid mode)|Rapid mode' ]]"
sess_voxcmd_env end-session
sess_wait
check "ending the session ends every mode in it, running each one's hook" "session_gone && log_has_soon '^ended-hook' && toast_has 'Rapid mode ended ended by request'"
sess_start "rapid mode" HOLD
hold_in 'rapid ' 2
check "saying the mode that is open again changes nothing" "mode_is 'rapid '"
sess_voxcmd_env end-session
sess_wait
sess_start "tap alpha" HOLD
hold_in 'rapid ' 2
sess_voxcmd_env rapid
check "a key or terminal command during a session does not open another mode" "mode_is 'rapid ' && toast_has 'A voice session is already open'"
sess_voxcmd_env end-session
sess_wait

# Click mode over rapid mode: switch phrases are never clicked, and a mode already underneath is returned to.
sess_run "click mode" "rapid mode" "done"
check "'rapid mode' in click mode goes back to rapid mode, clicking nothing" "session_gone && no_clicks && [[ \$(record_starts) == 3 ]]"
sess_start "click mode" "type mode" HOLD
hold_in 'type rapid/click' 3
check "'type mode' in click mode opens type mode over it, clicking nothing" "mode_is 'type rapid/click' && no_clicks"
sess_voxcmd_env end-session
sess_wait
sess_start "click mode" "done" HOLD
hold_in 'rapid ' 3
check "click mode's own 'done' returns to rapid mode" "mode_is 'rapid '"
sess_voxcmd_env end-session
sess_wait
sess_run "click mode" "stop rapid mode" "tap alpha"
check "'stop rapid mode' in click mode leaves both" "session_gone && no_clicks && [[ \$(taps) == 0 && \$(record_starts) == 2 ]]"
sess_phrase="click mode"
sess_run "jarvis tap alpha" "done"
check "a 'jarvis ...' that is no mode command is routed as a command in click mode too" "session_gone && ! toast_has 'Not a mode command' && [[ \$(grep '^tap ' '$log') == 'tap alpha' ]] && no_clicks"
sess_start "rapid mode" HOLD
hold_in 'rapid click' 2
check "'rapid mode' in click mode opens rapid mode over it, clicking nothing" "mode_is 'rapid click' && no_clicks"
sess_voxcmd_env end-session
sess_wait
sess_phrase="rapid mode"

# Silence leaves one mode at a time.
sess_phrase="rapid mode"
sess_run "click mode" SILENCE "tap beta" "done"
check "silence in click mode returns to rapid mode, which goes on" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 4 ]] && toast_has 'Click mode ended nothing was said'"

# Caps end every mode and run every popped hook.
sess_env=(VOXCMD_SESSION_MAX_TURNS=3)
sess_run "start testing" "alpha" "alpha" "alpha"
check "a cap ends rapid mode and the mode over it" "session_gone && log_has_soon '^ended-hook' && [[ \$(taps) == 2 ]] && toast_has 'Rapid mode ended it reached 3 turns'"
sess_env=()

# Type mode.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
sess_phrase="type mode"
wtype_is() { [[ $(grep '^wtype ' "$log") == "$(printf '%s\n' "$@")" ]]; }
# A mode's ended hook runs in the background, in a copy of the watcher that may outlive it: waits until no voxcmd is left.
hooks_done() {
  local deadline=$((SECONDS + 20))
  while pgrep -f -- "$sess_voxcmd( |\$)" >/dev/null; do
    ((SECONDS < deadline)) || return 1
    sleep 0.02
  done
}
other_window='{"address":"0x2","class":"foot","size":[800,600]}'
type_flushed() { log_has_soon "^wtype -- [.!?]\$"; }
sess_run "Hello world." "This is a test." "jarvis stop typing"
type_flushed
check "type mode types each chunk, holding back its closing mark until the next says whether the sentence ends" "session_gone && wtype_is 'wtype -- Hello world' 'wtype -- . This is a test' 'wtype -- .' && [[ \$(record_starts) == 3 ]]"
sess_start HOLD
owner_is_listening
check "type mode's session file names it and its hint" "[[ \$(jq -c '[.kind, .label, .exit_hint, .stack]' '$session_json') == '[\"type\",\"Type mode\",\"say jarvis stop typing\",[]]' ]]"
# The listen's detector logs its settings once it starts, which under load can come after the owner is listening.
check "type mode listens for a chunk: a 2.5s pause ends it, 25s cuts it, 30s of silence is a quiet listen" "log_has_soon 'no_speech_secs=30\$' && log_has_soon 'autostop min_speech_secs=0.4 silence_secs=2.5\$' && log_has_soon 'autostop max_secs=25\$'"
sess_voxcmd_env end-session
sess_wait
sess_run "Alpha and then beta." "jarvis stop typing"
type_flushed
check "type mode types a chunk holding 'and then' whole, never split into steps" "wtype_is 'wtype -- Alpha and then beta' 'wtype -- .' && ! toast_has 'stopped at step'"
sess_run "Hello world." "and more text" "jarvis stop typing"
type_flushed
check "a chunk that continues the sentence drops the held mark and types a space" "wtype_is 'wtype -- Hello world' 'wtype --  and more text'"
sess_run "Hello there," "The next part" "I think so" "London is big" "jarvis stop typing"
hooks_done
check "without a held mark a chunk's capital is lowercased when it is a common word, and kept for a name or I" "wtype_is 'wtype -- Hello there,' 'wtype --  the next part' 'wtype --  I think so' 'wtype --  London is big'"
sess_run $'Tab\there' $'Esc\e[31m' "-x marks the spot" "jarvis stop typing"
hooks_done
check "control characters become spaces and a leading dash is typed" "wtype_is 'wtype -- Tab here' 'wtype --  Esc [31m' 'wtype --  -x marks the spot'"
sess_run "done" "stop typing" "click mode" "I'm done" "Jarvis, stop typing."
hooks_done
check "without the wake word 'done', 'stop typing' and 'click mode' are text" "session_gone && wtype_is 'wtype -- done' 'wtype --  stop typing' 'wtype --  click mode' 'wtype --  I'\\''m done' && [[ \$(record_starts) == 5 ]]"
sess_run "Please send the plan. Jarvis, stop typing."
type_flushed
check "a command at the end of a chunk types the chunk, then runs" "session_gone && wtype_is 'wtype -- Please send the plan' 'wtype -- .'"
sess_run "I asked Jarvis what time it is." "jarvis stop typing"
hooks_done
check "the wake word in the middle of a sentence is just text" "wtype_is 'wtype -- I asked Jarvis what time it is' 'wtype -- .'"
sess_run "Jarvis, what is the weather" "Hello." "jarvis stop typing"
hooks_done
check "an unknown command from the wake word is told so without its text, and typed nowhere" "toast_has 'Not a mode command\$' && ! grep -q weather '$log' && wtype_is 'wtype -- Hello' 'wtype -- .'"
sess_run "Hello world." "Next bit here." "jarvis scratch that" "jarvis scratch that" "jarvis stop typing"
hooks_done
check "scratch that deletes the last chunk with one BackSpace per character and restores the held mark" "session_gone && [[ \$(grep '^wtype -k' '$log' | head -n1 | grep -o BackSpace | wc -l) == 15 ]] && [[ \$(grep -c '^wtype -k' '$log') == 1 ]] && toast_has 'Nothing to scratch' && grep -q '^wtype -- \.\$' '$log'"
sess_run "Hello world." "jarvis new line" "Second line." "jarvis new paragraph" "Third." "jarvis stop typing"
hooks_done
check "new line and new paragraph press Return once and twice, after closing the held mark" "wtype_is 'wtype -- Hello world' 'wtype -- .' 'wtype -k Return' 'wtype -- Second line' 'wtype -- .' 'wtype -k Return -k Return' 'wtype -- Third' 'wtype -- .'"
sess_run SILENCE SILENCE "Hello" "jarvis stop typing"
hooks_done
check "silence never leaves type mode" "session_gone && [[ \$(record_starts) == 4 ]] && wtype_is 'wtype -- Hello' && ! toast_has 'ended nothing was said'"
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" VOXCMD_TYPE_IDLE_SECS=1)
sess_run SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE
check "the idle bound ends type mode" "session_gone && toast_has 'Type mode ended nothing was said for 1 s' && [[ \$(record_starts) -lt 16 ]]"
sess_run "Held mark." SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE SILENCE
hooks_done
check "an end the owner did not ask for types nothing, not even the held mark" "session_gone && wtype_is 'wtype -- Held mark'"
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" VOXCMD_TYPE_MAX_SECS=1)
sess_run word word word word word word word word word word word word word word word word word word word word word word word word
check "the hard cap ends type mode while it is being used" "session_gone && toast_has 'Type mode ended it reached its time limit (1 s)'"

# Type mode inside rapid mode returns to it, and its chunks are not turns or time of the session's.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
sess_phrase="rapid mode"
sess_run "type mode" "Hello there" "jarvis stop typing" "tap beta" "done"
check "type mode opened in rapid mode returns to it" "session_gone && wtype_is 'wtype -- Hello there' && [[ \$(taps) == 1 && \$(record_starts) == 5 ]]"
sess_start "type mode" HOLD
hold_in 'type rapid' 2
check "and its hint says where it returns to" "mode_is 'type rapid' && [[ \$(jq -r .exit_hint '$session_json') == 'say jarvis stop typing (back to Rapid mode)' ]]"
sess_voxcmd_env end-session
sess_wait
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" VOXCMD_SESSION_MAX_TURNS=2)
sess_run "type mode" one two three four five six "jarvis stop typing" "tap beta" "tap gamma"
check "typed chunks are not turns of the session's cap" "session_gone && [[ \$(grep -c '^wtype -- ' '$log') == 6 && \$(taps) == 1 ]] && toast_has 'Rapid mode ended it reached 2 turns'"
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" VOXCMD_SESSION_MAX_SECS=3 SANDBOX_VOXTYPE_SPEAK_SECS=0.4)
sess_run "type mode" one two three four five six seven eight nine ten "jarvis stop typing" "tap beta" "done"
check "and the time spent in type mode is not counted against the session's time" "session_gone && [[ \$(taps) == 1 ]] && ! toast_has 'time limit'"

# Time spent in type mode is credited when click mode opens over it, not when it is popped, so the new mode's cap does
# not count the typing. The ~8 s of typing is well over the 6 s cap, and the turns after the push stay well under it
# even on a loaded machine.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" VOXCMD_SESSION_MAX_SECS=6 SANDBOX_VOXTYPE_SPEAK_SECS=0.4)
sess_run "type mode" one two three four five six seven eight nine ten one two three four five six seven eight nine ten "jarvis click mode" "done" "jarvis stop typing" "tap beta" "done"
check "a mode opened over type mode does not count the time spent typing against its cap" "session_gone && [[ \$(taps) == 1 ]] && ! toast_has 'time limit'"

# A detour through another mode keeps the held mark and the spacing, but not what "scratch that" would delete: a click
# may have moved the cursor.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
sess_phrase="type mode"
sess_run "Hello world." "jarvis click mode" "done" "jarvis scratch that" "Next part" "jarvis stop typing"
check "after a detour scratch that types nothing and the held mark is typed with the next chunk" "session_gone && wtype_is 'wtype -- Hello world' 'wtype -- . Next part' && toast_has 'Nothing to scratch'"

# Time away from type mode does not restart its hard cap.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" VOXCMD_TYPE_MAX_SECS=4 SANDBOX_VOXTYPE_SPEAK_SECS=0.4)
sess_run one two three four "jarvis click mode" "done" five six seven eight "jarvis click mode" "done" nine ten eleven twelve "jarvis stop typing"
check "repeated detours still reach the type-mode time limit" "session_gone && toast_has 'Type mode ended it reached its time limit (4 s)'"
sess_phrase="rapid mode"

# A chunk handled while type mode is left (here: popped to the mode under it) is not typed.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" SANDBOX_CLICKHINTS_STATE_BLOCK="$root/state-block")
rm -f "$root/state-block.entered" "$root/state-block.release"
sess_start "type mode" "Stale chunk" HOLD
until [[ -e $root/state-block.entered ]]; do sleep 0.02; done
jq -c '.stack[-1] + {owner, owner_start, turns, started, last_heard, stack: .stack[:-1]}' "$session_json" >"$session_json.new"
mv "$session_json.new" "$session_json"
: >"$root/state-block.release"
hold_in 'rapid ' 3
sess_voxcmd_env end-session
sess_wait
check "a chunk whose type mode was popped while it was handled is not typed" "! grep -q '^wtype' '$log' && grep -q 'type: not typed' '$debug_log'"

# State a killed listener left behind belongs to no mode of a new session.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
sess_phrase="type mode"
mkdir -p "$XDG_RUNTIME_DIR/voxcmd"
echo '{"frame":"1:1","held":".","prev_held":"-","last_len":9,"typed":true}' >"$XDG_RUNTIME_DIR/voxcmd/type-state"
sess_run "jarvis scratch that" "jarvis stop typing"
check "a new type mode ignores the held mark and length of an earlier one" "session_gone && toast_has 'Nothing to scratch' && ! grep -q '^wtype' '$log'"

# Refusals: nothing is typed, and the toast has no text.
sess_env=()
sess_phrase="type mode"
sess_run "Secret words" "jarvis stop typing"
check "without a focused window nothing is typed" "session_gone && toast_has 'voxcmd: not typed no window has focus' && ! grep -q '^wtype' '$log' && ! grep -rq 'Secret' '$log' '$debug_log'"
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" SANDBOX_VOXTYPE_SPEAK_SECS=1)
cp /bin/sleep "$root/voxcmd-hints"
"$root/voxcmd-hints" 60 &
waiter_pid=$!
mkfifo "$root/modes-fifo"
sess_start "Secret words" HOLD
owner_is_listening
jq -n -c --argjson pid "$waiter_pid" --arg fifo "$root/modes-fifo" \
  '{pid: $pid, fifo: $fifo, label: "Which one?", kind: "hints", expansions: {}, choices: [{id: "a", label: "1. A"}]}' >"$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
log_has_soon 'voxcmd: not typed'
rm -f "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
sess_voxcmd_env end-session
sess_wait
check "with a picker or card waiting nothing is typed either" "toast_has 'voxcmd: not typed a voxcmd picker or card is open' && ! grep -q '^wtype' '$log'"
kill "$waiter_pid" 2>/dev/null
wait "$waiter_pid" 2>/dev/null

# Dictation stays out of the logs and the session file.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
sess_run "Hello private words." "jarvis stop typing"
hooks_done
check "type mode logs lengths, never the text" "! grep -q 'private' '$debug_log' && grep -q 'a transcript of 20 characters goes to session_turn' '$debug_log' && grep -q 'typed a chunk of 19 characters' '$debug_log'"
check "and the last chunk is not left on disk" "[[ ! -e '$XDG_RUNTIME_DIR/voxcmd/transcript.txt' ]]"

# Dictation never goes to a picker that is waiting when type mode listens.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
cp /bin/sleep "$root/voxcmd-hints"
"$root/voxcmd-hints" 60 &
waiter_pid=$!
rm -f "$root/modes-fifo"
mkfifo "$root/modes-fifo"
jq -n -c --argjson pid "$waiter_pid" --arg fifo "$root/modes-fifo" \
  '{pid: $pid, fifo: $fifo, label: "Which one?", kind: "hints", expansions: {}, choices: [{id: "a", label: "1. A"}]}' >"$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
sess_run "Secret words" "jarvis stop typing"
hooks_done
rm -f "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
check "a pending picker does not take dictation: it stays with type mode, which refuses it" "session_gone && toast_has 'voxcmd: not typed a voxcmd picker or card is open' && ! grep -q 'goes to reply' '$debug_log' && grep -q 'a transcript of 12 characters goes to session_turn' '$debug_log' && ! grep -q '^wtype' '$log'"
check "and no dictated text is logged" "! grep -rq 'Secret' '$log' '$debug_log'"
kill "$waiter_pid" 2>/dev/null
wait "$waiter_pid" 2>/dev/null

# A mode re-created at the same depth is not the one a chunk was heard in.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" SANDBOX_CLICKHINTS_STATE_BLOCK="$root/frame-block")
rm -f "$root/frame-block.entered" "$root/frame-block.release"
sess_start "Stale chunk" HOLD
until [[ -e $root/frame-block.entered ]]; do sleep 0.02; done
jq -c '.frame_id = "recreated"' "$session_json" >"$session_json.new"
mv "$session_json.new" "$session_json"
: >"$root/frame-block.release"
hold_in 'type ' 2
sess_voxcmd_env end-session
sess_wait
hooks_done
check "a chunk heard in a type mode that was re-created at the same depth is not typed" "! grep -q '^wtype' '$log' && grep -q 'type: not typed' '$debug_log'"

# Focus that moved to another window since the last chunk: nothing is deleted, held or spaced into it.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" SANDBOX_ACTIVEWINDOW_AFTER_WTYPE_JSON="$other_window")
sess_run "Hello world." "jarvis scratch that" "jarvis stop typing"
hooks_done
check "scratch that after the focus moved deletes nothing" "session_gone && toast_has 'Nothing to scratch' && ! grep -q '^wtype -k' '$log'"
check "and the mode's end does not type the held mark into the other window" "wtype_is 'wtype -- Hello world'"
sess_run "Hello." "World again." "jarvis stop typing"
hooks_done
check "a chunk in another window drops the held mark and starts without a space" "wtype_is 'wtype -- Hello' 'wtype -- World again' 'wtype -- .'"

# The ended hook runs after the mode is left, in the background.
sess_phrase="rapid mode"
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" SANDBOX_ACTIVEWINDOW_BLOCK_AFTER_WTYPE="$root/hook-block")
rm -f "$root/hook-block.entered" "$root/hook-block.release"
sess_start "type mode" "Hello." "jarvis stop typing" HOLD
until [[ -e $root/hook-block.entered ]]; do sleep 0.02; done
hold_in 'rapid ' 4
sess_voxcmd_env stop
sess_wait
: >"$root/hook-block.release"
hooks_done
check "Stop after leaving type mode keeps the held mark from being typed" "session_gone && wtype_is 'wtype -- Hello'"

rm -f "$root/hook-block.entered" "$root/hook-block.release"
sess_start "type mode" "Hello." "jarvis stop typing" HOLD
until [[ -e $root/hook-block.entered ]]; do sleep 0.02; done
hold_in 'rapid ' 4
flock_file=$XDG_RUNTIME_DIR/voxcmd/session.lock
rm -f "$root/lock-held" "$root/lock-release"
flock "$flock_file" sh -c ": >'$root/lock-held'; until [ -e '$root/lock-release' ]; do sleep 0.02; done" &
lock_holder=$!
until [[ -e $root/lock-held ]]; do sleep 0.02; done
: >"$root/hook-block.release"
# A negative: the hook, not holding the lock, must wait for the one held here. No event says that it has not typed.
sleep 0.3
check "the ended hook takes the session lock instead of assuming the caller's" "! grep -q '^wtype -- \.\$' '$log'"
: >"$root/lock-release"
wait "$lock_holder"
type_flushed
sess_voxcmd_env end-session
sess_wait
hooks_done

rm -f "$root/hook-block.entered" "$root/hook-block.release"
sess_start "type mode" "Hello." "jarvis stop typing" "type mode" "World." HOLD
until [[ -e $root/hook-block.entered ]]; do sleep 0.02; done
hold_in 'type rapid' 6
: >"$root/hook-block.release"
hooks_done
check "an ended hook leaves the state of a type mode opened since" "[[ \$(jq -r .frame '$XDG_RUNTIME_DIR/voxcmd/type-state') == \$(jq -r .frame_id '$session_json') ]]"
sess_voxcmd_env end-session
sess_wait
hooks_done
sess_phrase="type mode"

# A turn heard in a mode that changed, or after the session went, is never acted on.
sess_env=(SANDBOX_VOXTYPE_SPEAK_SECS=0.8)
sess_phrase="rapid mode"
sess_start "start testing" "tap alpha" "done"
wait_for_line 'voxtype record start' "$log"
until [[ $(record_starts) == 2 ]]; do sleep 0.02; done
sess_voxcmd_env "stop testing"
sess_wait
check "a transcript heard before the mode changed is told so and never run" "session_gone && ! grep -q '^tap alpha' '$log' && toast_has 'The mode changed, say it again'"
sess_start "tap alpha" "done"
until [[ $(record_starts) == 1 ]]; do sleep 0.02; done
rm -f "$session_json"
sess_wait
check "a turn whose session is gone is routed when it was heard in rapid mode" "grep -q '^tap alpha' '$log'"
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" SANDBOX_VOXTYPE_SPEAK_SECS=0.8)
sess_phrase="type mode"
sess_start "tap alpha" "done"
until [[ $(record_starts) == 1 ]]; do sleep 0.02; done
rm -f "$session_json"
sess_wait
check "and discarded when it was heard in type mode" "! grep -q '^tap alpha' '$log' && ! grep -q '^wtype' '$log'"

# Stop Voice while a type-mode turn is transcribing types nothing.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
sess_start HOLD
owner_is_listening
stopped_owner=$(jq -r .owner "$session_json")
echo transcribing >"$XDG_RUNTIME_DIR/voxtype/state"
kill -STOP "$stopped_owner"
sess_voxcmd_env stop
kill -CONT "$stopped_owner"
sess_wait
check "Stop Voice during a type-mode turn types nothing and ends the session" "session_gone && ! grep -q '^wtype' '$log' && toast_has 'Type mode ended stopped'"
sess_env=()
sess_phrase=""
sess_config=$root/config-sess

finish
