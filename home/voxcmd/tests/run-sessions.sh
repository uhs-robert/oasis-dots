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
# shellcheck source-path=SCRIPTDIR source=../../../lib/check/lock.sh
. "$here/../../../lib/check/lock.sh"
check_lock_gate "voxcmd ${0##*/}" "$0" "$@"
[ -n "${SANDBOX_DIR:-}" ] || exec "$here/sandbox.sh" "$0" "$@"
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$here/lib.sh"
# shellcheck source-path=SCRIPTDIR source=session-harness.sh
source "$here/session-harness.sh"

# ---- voice sessions ---------------------------------------------------------------------------------------------------
section "voice sessions"
sess_run alpha beta "done"
check "targets are tapped in turn" "[[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' ]]"
check "it listens once more after each turn, and not after 'done'" "[[ \$(record_starts) == 3 ]]"
check "an exit word clears the session and leaves the microphone idle" "session_gone && [[ \$(cat '$XDG_RUNTIME_DIR/voxtype/state') == idle ]]"

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
sess_start HOLD
owner_is_listening
check "the session's turns are heard by the binary under test" "owner_is_the_binary_under_test"
sess_voxcmd_env session end
sess_wait

for word in "done" "Done." "that's all" "I'm done" "stop testing" "Okay, stop testing." "done testing"; do
  sess_run alpha "$word" gamma
  check "'$word' ends the session and the microphone with it" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 2 ]]"
done
# Button labels: these are what the user wants clicked.
for word in "cancel" "exit" "stop" "quit" "never mind" "stop clicking" "stop testing now"; do
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
sess_run "Voice commands start with Cortana." alpha "done"
check "an echo of the transcriber's prompt is noise" "session_gone && [[ \$(grep '^tap ' '$log') == 'tap alpha' && \$(record_starts) == 3 ]] && ! grep -q 'no match' '$log'"
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
check "by default it is 40 turns or 5 minutes" "grep -q 'setting(\"VOXCMD_SESSION_MAX_SECS\", 300)' '$package/src/session/turn.rs' && grep -q 'setting(\"VOXCMD_SESSION_MAX_TURNS\", 40)' '$package/src/session/turn.rs'"

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
# A long speech is cut at max_secs, as type mode's recording is before voxtype's own limit, with a verdict of its own;
# without the limit it runs on to its pause.
pcm "$root/long-speech.pcm" noise:0.3:-60 voice:9:-18 noise:3:-60
check "max_secs cuts a long speech with the length-limit verdict" "[[ \$(detect '$root/long-speech.pcm' VOXCMD_AUTOSTOP_MAX_SECS=4) == 5 ]] && grep -q 'recording with speech in it, cutting here' '$detector_trace' && grep -q 'verdict length limit at 4\.' '$detector_trace'"
check "and with none the speech runs to its pause" "[[ \$(detect '$root/long-speech.pcm') == 0 ]] && grep -q 'verdict speech then quiet at 1[0-9]\.' '$detector_trace'"
pcm "$root/quiet-room.pcm" noise:6:-60
threshold_out=$root/threshold-out
pcm "$root/fan-room.pcm" noise:0.3:-75 noise:7.7:-42
rm -f "$threshold_out"
detect "$root/fan-room.pcm" VOXCMD_AUTOSTOP_THRESHOLD_FILE="$threshold_out" >/dev/null
check "the published threshold follows a room that was quieter at the start, not the floor it began at" "awk '{ exit !(\$1 > -40) }' '$threshold_out'"
pcm "$root/talk-in-quiet.pcm" noise:3:-55 voice:4:-18 noise:3:-55
rm -f "$threshold_out"
detect "$root/talk-in-quiet.pcm" VOXCMD_AUTOSTOP_THRESHOLD_FILE="$threshold_out" >/dev/null
check "and speech does not raise it" "awk '{ exit !(\$1 < -40) }' '$threshold_out'"
check "a quiet room is no speech" "[[ \$(detect '$root/quiet-room.pcm') == 3 ]]"
check "for a reply too" "[[ \$(detect '$root/quiet-room.pcm' \"\${reply_detector[@]}\") == 3 && \$(detect '$root/fan-after-quiet-start.pcm' \"\${reply_detector[@]}\") == 3 ]]"
check "without the debug log there is no trace" "env -u VOXCMD_DEBUG XDG_RUNTIME_DIR='$root/no-trace' python3 '$package/.local/bin/voxcmd-autostop' --pcm '$root/quiet-room.pcm'; [[ ! -e '$root/no-trace/voxcmd/debug.log' ]]"

# Type mode's pause checks, handed to a stand-in voxcmd that keeps each clip and its arguments, numbered in the order
# they ran. Its first run waits for $pause_gate when the test sets PAUSE_GATE, and each run ends the recording in the
# voxtype state file PAUSE_CANCELS names, as a check hearing "cortana cancel" does. Fed through a pipe, so a test can
# wait on what the detector did before it sends more.
pause_runs=$root/pause-runs pause_gate=$root/pause-gate pause_voxcmd=$root/pause-voxcmd
cat >"$pause_voxcmd" <<'STUB'
#!/bin/sh
run=$(($(find "$PAUSE_RUNS" -name '*.args' | wc -l) + 1))
[ "$run" = 1 ] || [ -e "$PAUSE_RUNS/$((run - 1)).done" ] || : >"$PAUSE_RUNS/overlapped"
cat >"$PAUSE_RUNS/$run.wav"
printf '%s|%s|%s\n' "$*" "${VOXCMD_AUTOSTOP_PAUSE_CHECK_RECORDING-}" "${VOXCMD_AUTOSTOP_THRESHOLD_FILE-}" >"$PAUSE_RUNS/$run.args"
if [ "$run" = 1 ] && [ -n "${PAUSE_GATE-}" ]; then until [ -e "$PAUSE_GATE" ]; do sleep 0.02; done; fi
[ -z "${PAUSE_CANCELS-}" ] || echo idle >"$PAUSE_CANCELS"
: >"$PAUSE_RUNS/$run.done"
STUB
chmod +x "$pause_voxcmd"
type_detector=(VOXCMD_AUTOSTOP_MIN_SPEECH_SECS=0.4 VOXCMD_AUTOSTOP_SILENCE_SECS=10 VOXCMD_AUTOSTOP_NO_SPEECH_SECS=10
  VOXCMD_AUTOSTOP_PAUSE_CHECK_RECORDING=f1:1:1 "VOXCMD_AUTOSTOP_PAUSE_CHECK_VOXCMD=$pause_voxcmd"
  "VOXCMD_AUTOSTOP_THRESHOLD_FILE=$root/pause-threshold" "PAUSE_RUNS=$pause_runs")
# pause_detect <feeder> [VAR=value...]: runs the detector on what the feeder (a command line) writes, with type mode's
# settings and the arguments in pause_detect_args, leaving its exit code in $pause_verdict once it has exited.
pause_detect() {
  rm -rf "$pause_runs" "$pause_gate"
  mkdir -p "$pause_runs"
  : >"$detector_trace"
  pause_verdict=0
  eval "$1" | env XDG_RUNTIME_DIR="$root/detector-run" VOXCMD_CONFIG_DIR="$root/detector-config" "${type_detector[@]}" "${@:2}" \
    python3 "$package/.local/bin/voxcmd-autostop" --pcm - "${pause_detect_args[@]}" 2>/dev/null || pause_verdict=$?
}
pause_detect_args=()
pause_runs_made() { find "$pause_runs" -name '*.args' | wc -l; }
# clip_is <run> <secs>: the clip that run was handed is a 16 kHz mono 16-bit WAV of that length.
clip_is() {
  python3 -c 'import sys, wave
with wave.open(sys.argv[1]) as clip:
    sys.exit(not (clip.getframerate(), clip.getnchannels(), clip.getsampwidth(), clip.getnframes()) == (16000, 1, 2, int(float(sys.argv[2]) * 16000)))' "$pause_runs/$1.wav" "$2"
}
# clip_peak <run>: the loudest sample of that run's clip.
clip_peak() {
  python3 -c 'import array, sys, wave
with wave.open(sys.argv[1]) as clip:
    print(max(abs(sample) for sample in array.array("h", clip.readframes(clip.getnframes()))))' "$pause_runs/$1.wav"
}
pcm "$root/pause-first.pcm" noise:2:-55 voice:1:-18 noise:0.7:-55
pcm "$root/pause-quieter.pcm" noise:0.1:-55 voice:1:-24 noise:0.7:-55
pcm "$root/pause-louder.pcm" noise:0.1:-55 voice:1:-12 noise:0.7:-55
pcm "$root/pause-quiet-tail.pcm" noise:0.5:-55
pcm "$root/pause-long-quiet.pcm" noise:2:-55 voice:1:-18 noise:4:-55
pause_detect "cat '$root/pause-first.pcm'; wait_for_path '$pause_runs/1.done'; cat '$root/pause-quieter.pcm'; wait_for_path '$pause_runs/2.done'; cat '$root/pause-quiet-tail.pcm'"
check "each pause after speech hands its last 3 s to voxcmd's confirmation, as a 16 kHz mono WAV" "[[ \$(pause_runs_made) == 2 ]] && clip_is 1 3 && clip_is 2 3 && grep -q 'pause check at 3\.6' '$detector_trace'"
check "naming the recording, as a pause, without the recording's settings in its environment" "[[ \$(cat '$pause_runs/1.args') == '_wake-confirm /dev/stdin f1:1:1 pause||' ]]"
check "and the verdict is still the detector's own: none yet" "[[ \$pause_verdict == 4 ]]"
pause_detect "cat '$root/pause-long-quiet.pcm'; wait_for_path '$pause_runs/1.done'; cat '$root/pause-quiet-tail.pcm'"
check "one long pause is one check" "[[ \$(pause_runs_made) == 1 ]]"
pause_detect "cat '$root/quiet-room.pcm'"
check "quiet alone is no check" "[[ \$(pause_runs_made) == 0 ]]"
pause_detect "cat '$root/pause-first.pcm' '$root/pause-quiet-tail.pcm'" VOXCMD_AUTOSTOP_PAUSE_CHECK_RECORDING=
check "and with no recording named, no pause is checked" "[[ \$(pause_runs_made) == 0 ]]"
# Three pauses while the first check runs: the second check gets the third pause's clip, the louder voice.
pause_detect "cat '$root/pause-first.pcm'; wait_for_path '$pause_runs/1.args'; cat '$root/pause-quieter.pcm' '$root/pause-louder.pcm';
  wait_for_count 'waits for the check running' '$detector_trace' 2; : >'$pause_gate'; wait_for_path '$pause_runs/1.done';
  cat '$root/pause-quiet-tail.pcm'; wait_for_path '$pause_runs/2.done'" "PAUSE_GATE=$pause_gate"
check "pauses during a check keep only the newest clip, run once the check is over" "[[ \$(pause_runs_made) == 2 && ! -e '$pause_runs/overlapped' ]] && ((\$(clip_peak 2) > 10000 && \$(clip_peak 1) < 10000))"
# The detector exits (the recording ended) while its check still runs.
pause_detect "cat '$root/pause-first.pcm'; wait_for_path '$pause_runs/1.args'" "PAUSE_GATE=$pause_gate"
check "a check still running when the detector exits is left to finish" "[[ ! -e '$pause_runs/1.done' ]] && : >'$pause_gate' && wait_for_path '$pause_runs/1.done'"
pcm "$root/word-then-quiet.pcm" noise:2:-55 voice:1:-18 noise:2:-55
type_verdict() { grep 'verdict ' "$detector_trace" | sed 's/.*verdict/verdict/'; }
pause_detect "cat '$root/word-then-quiet.pcm'" VOXCMD_AUTOSTOP_SILENCE_SECS=1.5
with_checks="$pause_verdict $(type_verdict)"
pause_detect "cat '$root/word-then-quiet.pcm'" VOXCMD_AUTOSTOP_SILENCE_SECS=1.5 VOXCMD_AUTOSTOP_PAUSE_CHECK_RECORDING=
check "checks change neither the verdict nor when it comes" "[[ \$pause_verdict == 0 && '$with_checks' == \"\$pause_verdict \$(type_verdict)\" ]]"
# The pause verdict comes while the pause's check still transcribes, which then hears "cortana cancel".
pause_state=$root/pause-state
pause_detect_args=(--state-file "$pause_state")
echo recording >"$pause_state"
pause_detect "cat '$root/word-then-quiet.pcm'; wait_for_path '$pause_runs/1.args'; wait_for_count 'stop waits for the pause checks' '$detector_trace' 1;
  : >'$pause_gate'" VOXCMD_AUTOSTOP_SILENCE_SECS=1.5 "PAUSE_GATE=$pause_gate" "PAUSE_CANCELS=$pause_state"
check "a pause verdict waits for the check still running, and gives way when it ends the recording" "[[ \$pause_verdict == 4 && -e '$pause_runs/1.done' ]]"
echo recording >"$pause_state"
pause_detect "cat '$root/word-then-quiet.pcm'; wait_for_count 'stop waits for the pause checks' '$detector_trace' 1; : >'$pause_gate'" \
  VOXCMD_AUTOSTOP_SILENCE_SECS=1.5 "PAUSE_GATE=$pause_gate"
check "and stops it once a check that heard no ending is over" "[[ \$pause_verdict == 0 && -e '$pause_runs/1.done' ]]"
pause_detect "cat '$root/word-then-quiet.pcm'" VOXCMD_AUTOSTOP_SILENCE_SECS=1.5 VOXCMD_AUTOSTOP_PAUSE_CHECK_WAIT_SECS=0.5 \
  "PAUSE_GATE=$pause_gate"
check "a hung check holds the pause verdict back only pause_check_wait_secs" "[[ \$pause_verdict == 0 && ! -e '$pause_runs/1.done' ]] && grep -q 'still running after 0.5s, stopping anyway' '$detector_trace'"
: >"$pause_gate"
wait_for_path "$pause_runs/1.done"
pause_detect_args=()

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
sess_voxcmd_env session end
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
wait_for_path "$root/routing"
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
timeout "$test_wait_secs" head -n1 "$root/stop-fifo" >"$root/stop-answer" &
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
timeout "$test_wait_secs" head -n1 "$root/stop-fifo-2" >"$root/stop-answer-2" &
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

# Settling: the next listen waits for the overlay and popups. The stub bar reports what the files hold. A wait is told
# from none by how often the bar is asked, and only the lower bounds are times, which load can only stretch.
settle_ms() {
  local started
  started=$(date +%s%N)
  timeout "$test_wait_secs" env "$@" "$sess_voxcmd" internal settle >/dev/null 2>&1
  echo $((($(date +%s%N) - started) / 1000000))
}
bar_asks() { grep -c '^qs-ipc call clickhints state' "$log"; }
# settle_waits_out <state file> <state>: with the overlay or popup in that state, `internal settle` has asked the bar twice and
# is still waiting, then settles once it closes.
settle_waits_out() {
  local settle_pid
  echo "$2" >"$1"
  : >"$log"
  env VOXCMD_APP_SETTLE_SECS=0 VOXCMD_UI_SETTLE_MAX_SECS="$test_wait_secs" "$sess_voxcmd" internal settle >/dev/null 2>&1 &
  settle_pid=$!
  wait_until asked_twice_or_gone "$settle_pid"
  process_running "$settle_pid" || return 1
  echo closed >"$1"
  wait "$settle_pid"
}
asked_twice_or_gone() { (($(bar_asks) >= 2)) || process_gone "$1"; }
rm -f "$hints_state" "$popup_state_file"
: >"$log"
check "a settled screen waits only the app's moment" "[[ \$(settle_ms VOXCMD_APP_SETTLE_SECS=0.1 VOXCMD_UI_SETTLE_MAX_SECS=20) -ge 100 && \$(bar_asks) == 1 ]]"
check "an open overlay is waited out" "settle_waits_out '$hints_state' open"
for popup_state in "opening weather" "open weather" "closing weather"; do
  check "a popup that is '$popup_state' is waited out" "settle_waits_out '$popup_state_file' '$popup_state'"
done
rm -f "$hints_state"

# In a session the bar is asked after the turn's action and before the microphone opens again.
sess_run alpha "done"
check "the screen is checked between a turn's action and the next listen" "[[ \$(awk '/^tap alpha/{a=NR} /qs-ipc call clickhints state/{if (a && !q) q=NR} /voxtype record start/{n++; if (n==2) r=NR} END{print (a && a < q && q < r) ? \"ok\" : \"no\"}' '$log') == ok ]]"

# The settings the detector of one listen logs. The listen hears silence: a turn of speech can end before its detector
# starts, which then never logs.
detector_settings_of() {
  printf '%s\n' SILENCE >"$sess_turns"
  fresh_logs
  echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
  sess_voxcmd_env listen
  sess_wait
  grep '^voxcmd-autostop ' "$log" | sed 's/^voxcmd-autostop //' | paste -sd' '
}
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
check "a normal listen keeps the default silence allowance" "[[ \$(detector_settings_of) == 'no_speech_secs=default min_speech_secs=default silence_secs=default' ]]"
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

# SIGKILL runs no trap, so the file stays, but the owner check reads it as no session. Killed only once it is listening:
# a watcher killed while it starts dies before it could set a trap anyway.
sess_start HOLD
owner_is_listening
signal_watchers KILL
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
check "a pending picker's reply wins over the open session" "grep -qE 'setsid .*internal watch reply' '$log' && ! grep -qE 'setsid .*internal watch session_turn' '$log'"
rm -f "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
: >"$log"
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
"$sess_voxcmd" listen >/dev/null 2>&1
log_has_soon 'setsid '
check "with nothing pending, a live session's listen goes to the session" "grep -qE 'setsid .*internal watch session_turn' '$log'"
# The detector each listen starts: a reply's lower speech minimum, the session's settings, nothing for a command.
sess_env=(VOXCMD_AUTOSTOP_MIN_SPEECH_SECS=0.5)
jq -n -c --argjson owner "$owner_pid" --arg owner_start "$(start_time_of "$owner_pid")" \
  '{kind: "test", integration: "x", label: "Test mode", started: 0, owner: $owner, owner_start: $owner_start, unclear: 0, turns: 0}' \
  >"$XDG_RUNTIME_DIR/voxcmd/session.json"
check "a session turn's listen keeps the session's settings" "[[ \$(detector_settings_of) == 'no_speech_secs=10 min_speech_secs=0.4 silence_secs=1.5' ]]"
# The watcher takes the detector's settings from the listen that started it. With the session lock held elsewhere, one
# that read the session again would wait for it and its detector would not start.
detector_starts_without_session_lock() {
  local holder watcher status=1
  printf '%s\n' SILENCE >"$sess_turns"
  fresh_logs
  echo recording >"$XDG_RUNTIME_DIR/voxtype/state"
  rm -f "$root/holder-ready" "$root/holder-release"
  (flock 9 && : >"$root/holder-ready" && wait_for_path "$root/holder-release") 9>"$XDG_RUNTIME_DIR/voxcmd/session.lock" &
  holder=$!
  wait_for_path "$root/holder-ready"
  env SANDBOX_VOXTYPE_TURNS="$sess_turns" SANDBOX_AUTOSTOP_SLEEP="$stub_sleep" VOXCMD_CONFIG_DIR="$sess_config" \
    VOXCMD_DEBUG=1 "$sess_voxcmd" internal watch session_turn - 0 VOXCMD_AUTOSTOP_NO_SPEECH_SECS=7 >/dev/null 2>&1 &
  watcher=$!
  # Logged while the lock is still held here: a watcher that waited for it would log only after the release.
  log_has_soon 'no_speech_secs=7$' && status=0
  : >"$root/holder-release"
  kill "$watcher" 2>/dev/null
  wait "$holder" "$watcher" 2>/dev/null
  pkill -f "$stub_sleep" 2>/dev/null
  echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
  return $status
}
check "a session listen's detector starts without the session lock, from the listen's settings" "detector_starts_without_session_lock"
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

finish
