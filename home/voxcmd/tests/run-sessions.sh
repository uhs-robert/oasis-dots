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
link_voxcmd_shim "$sess_pkg"
# sess_voxcmd is the new CLI, over this copy's bash voxcmd, which is the process name the tests look for.
sess_voxcmd=$sess_pkg/tests/bin/voxcmd
sess_real_voxcmd=$sess_pkg/.local/bin/voxcmd
# A session turn's watcher, as the binary under test names it: the bash `_watch`, or the Rust build's `internal watch`.
if [ "${VOXCMD_BIN:-bash}" = rs ]; then
  sess_rust_voxcmd=$(readlink -f "$sess_voxcmd")
  sess_watcher="$sess_rust_voxcmd internal watch"
  sess_chain_stopper="$sess_rust_voxcmd internal chain-stop"
else
  sess_watcher="$sess_real_voxcmd _watch"
  sess_chain_stopper="$sess_real_voxcmd _chain-stop"
fi
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
# As click mode: a bare exit word is a button label.
session_bare_exits=0
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
session_ended() {
  # A test holds the hook here with \$root/hook-gate, to see it take the session lock once let go.
  if [ -e "$root/hook-gate" ]; then until [ -e "$root/hook-go" ]; do sleep 0.02; done; fi
  session_state >/dev/null || true
  echo "ended-hook" >> "$log"
}
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
sess_queued_turns=0
sess_start() {
  printf '%s\n' "$@" >"$sess_turns"
  sess_queued_turns=$#
  fresh_logs
  rm -f "$XDG_RUNTIME_DIR/voxcmd/session.json" "$hints_state" "$popup_state_file"
  [ -z "$sess_overlay" ] || echo "$sess_overlay" >"$hints_state"
  mkdir -p "$XDG_RUNTIME_DIR/voxtype" "$XDG_RUNTIME_DIR/voxcmd"
  echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
  # shellcheck disable=SC2086 # the phrase is words
  sess_voxcmd_env run ${sess_phrase:-start testing}
}
sess_phrase=""
# The stub call log and voxcmd's debug log, emptied before a run so sess_wait reads only its watchers.
fresh_logs() { mkdir -p "$(dirname "$debug_log")" && : >"$log" && : >"$debug_log"; }
# Waits for every watcher of the run to finish. Fails when test_wait_secs pass without a new watcher while one is alive,
# which would be a microphone that never closes, and when the run has listened 20 times more than it has turns queued,
# which would be one that keeps re-opening. The time bound restarts with each watcher, not once per run: a loaded
# machine can take seconds a turn, so a long run outlasts any fixed total, and the listen count is the ceiling that does
# not depend on load. listen logs each watcher's PID as it starts it, before the listen (or the watcher handing over) exits, so a
# watcher still to come always has a live parent or a logged PID.
sess_wait() {
  local deadline=$((SECONDS + test_wait_secs)) max_listens=$((sess_queued_turns + 20)) pid running watchers seen=0
  while ((SECONDS < deadline)); do
    running=0
    watchers=$(sed -n 's/.* listen: recording started, watcher \([0-9]*\) .*/\1/p' "$debug_log")
    while read -r pid; do [ -n "$pid" ] && process_running "$pid" && running=1 && break; done <<<"$watchers"
    # Read again once they are seen gone: the last one may have logged its successor and exited in between.
    ((running)) || [[ $(sed -n 's/.* listen: recording started, watcher \([0-9]*\) .*/\1/p' "$debug_log") != "$watchers" ]] ||
      return 0
    if (($(wc -l <<<"$watchers") > seen)); then
      seen=$(wc -l <<<"$watchers") deadline=$((SECONDS + test_wait_secs))
    fi
    if ((seen > max_listens)); then
      echo "   the microphone kept re-opening: $seen listens for $sess_queued_turns queued turns"
      return 1
    fi
    sleep 0.02
  done
  echo "   a watcher still running ${test_wait_secs}s after the last one started"
  return 1
}
sess_run() {
  sess_start "$@"
  sess_wait
}
# log_has_soon <pattern>: the watcher starts in the background, so its log lines can land after listen has
# returned.
log_has_soon() { wait_for_line "$1" "$log"; }
taps() { grep -c '^tap ' "$log"; }
record_starts() { grep -c '^voxtype record start' "$log"; }
session_gone() { [[ ! -e $XDG_RUNTIME_DIR/voxcmd/session.json ]]; }
ended_because() { grep -q "^notify-send .*Test mode ended $1" "$log"; }
start_time_of() { sed 's/.*) //' "/proc/$1/stat" | awk '{print $20}'; }
# Waits until the session's owner is a watcher that has seen its recording start, so its traps are set.
owner_is_listening() { wait_until owner_saw_recording; }
owner_saw_recording() {
  local owner
  owner=$(jq -r .owner "$XDG_RUNTIME_DIR/voxcmd/session.json" 2>/dev/null)
  [ -n "$owner" ] && grep -q "voxcmd\[$owner\] watch: voxtype recording\$" "$debug_log"
}
# The session's owner is a session turn's watcher of the binary under test, so a passing run under VOXCMD_BIN=rs is one
# whose turns the Rust build heard, not one it handed to the bash voxcmd.
owner_is_the_binary_under_test() {
  local owner cmdline
  owner=$(jq -r .owner "$XDG_RUNTIME_DIR/voxcmd/session.json" 2>/dev/null)
  cmdline=$(tr '\0' ' ' <"/proc/$owner/cmdline" 2>/dev/null) || return 1
  [[ $cmdline == *"$sess_watcher session_turn "* ]] || return 1
  [ "${VOXCMD_BIN:-bash}" != rs ] || [[ $(readlink -f "/proc/$owner/exe") == "$sess_rust_voxcmd" ]]
}

sess_run alpha beta "done"
check "targets are tapped in turn" "[[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' ]]"
check "it listens once more after each turn, and not after 'done'" "[[ \$(record_starts) == 3 ]]"
check "an exit word clears the session and leaves the microphone idle" "session_gone && [[ \$(cat '$XDG_RUNTIME_DIR/voxtype/state') == idle ]]"

# every_detector_logged <setting> <line>: each session listen's detector logged its <setting> as <line>, and at least one
# did. A turn of speech can end before its listen's detector has started, which then never runs (nor logs), so the run
# ends on a turn of silence: that recording lasts until its detector's verdict, so its line is always there.
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

# With nothing open it is silent.
fresh_logs
rm -f "$XDG_RUNTIME_DIR/voxcmd/session.json"
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
check "stop with nothing open exits 0 and does nothing" "env SANDBOX_SETSID_RUN=1 VOXCMD_CONFIG_DIR='$sess_config' '$sess_voxcmd' stop >/dev/null 2>&1 && ! grep -qE '^(voxtype record|notify-send)' '$log'"

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
echo open >"$hints_state"
check "a screen that never settles is waited on for a bounded time" "[[ \$(settle_ms VOXCMD_APP_SETTLE_SECS=0 VOXCMD_UI_SETTLE_MAX_SECS=0.3) -ge 300 ]] && { timeout '$test_wait_secs' env VOXCMD_APP_SETTLE_SECS=0 VOXCMD_UI_SETTLE_MAX_SECS=0.1 '$sess_voxcmd' internal settle; [[ \$? == 1 ]]; }"
rm -f "$hints_state"
check "no bar to ask counts as settled" "env XDG_CONFIG_HOME='$root/no-bar' VOXCMD_APP_SETTLE_SECS=0 '$sess_voxcmd' internal settle"

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

# The watcher dying mid-session takes the session with it. Killed only once it is listening: a watcher killed while it
# starts dies before its trap is set, and one handing over to a successor that is starting leaves the session to it.
sess_start HOLD
owner_is_listening
pkill -TERM -f "$sess_watcher"
sess_wait
check "a killed listener ends the session" "session_gone"
# SIGKILL runs no trap, so the file stays, but the owner check reads it as no session.
sess_start HOLD
owner_is_listening
pkill -KILL -f "$sess_watcher"
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
check "a pending picker's reply wins over the open session" "grep -qE 'setsid .*(_watch|internal watch) reply' '$log' && ! grep -qE 'setsid .*(_watch|internal watch) session_turn' '$log'"
rm -f "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
: >"$log"
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
"$sess_voxcmd" listen >/dev/null 2>&1
log_has_soon 'setsid '
check "with nothing pending, a live session's listen goes to the session" "grep -qE 'setsid .*(_watch|internal watch) session_turn' '$log'"
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

# ---- modes: rapid, type, and the stack they share ----------------------------------------------------------------------
# rapid.sh, typing.sh and click.sh for real beside the test mode, Media (a routed "stop"), Keys (whose "send it" and
# "press enter" type mode's endings must win over) and two
# integrations that ask: a yes/no card and a picker of two. The card and the picker are logging stubs.
section "modes"
modes_config=$root/config-modes
mkdir -p "$modes_config/integrations.d" "$modes_config/replacements.d"
cp "$root/config-sess/integrations.d/sess.sh" "$modes_config/integrations.d/"
for integration in rapid typing click media keys; do
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
hold_in() { wait_until holding_in "$@"; }
holding_in() { mode_is "$1" && [[ $(record_starts) == "$2" ]] && owner_saw_recording; }

# Rapid mode: every turn is a command.
sess_phrase="rapid mode"
sess_run "tap alpha" "tap beta" "cortana done"
check "rapid mode routes each turn as a command until 'cortana done'" "session_gone && [[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' && \$(record_starts) == 3 ]]"
sess_start HOLD
owner_is_listening
check "rapid mode's session names the mode, its exit hint and an empty stack" "[[ \$(jq -c '[.kind, .label, .exit_hint, .stack]' '$session_json') == '[\"rapid\",\"Rapid mode\",\"say cortana done to stop\",[]]' ]]"
check "and its turns are heard by the binary under test" "owner_is_the_binary_under_test"
sess_voxcmd_env session end
sess_wait
# Bare, a mode-naming exit is a missed turn like "done": the verbs stay for outside a session, but only "cortana ..."
# leaves.
for word in "done" "Done." "that's all" "I'm done" "done with rapid mode" "stop rapid mode" "Okay, quit rapid mode." "rapid mode off" "turn off rapid fire mode"; do
  sess_run "tap alpha" "$word" "tap gamma" "cortana done"
  check "bare '$word' does not end rapid mode" "session_gone && [[ \$(taps) == 2 && \$(record_starts) == 4 ]]"
done
sess_run "tap alpha and then stop rapid mode" "tap gamma" "cortana done"
check "a trailing 'and then stop rapid mode' step does not end rapid mode either" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 3 ]]"
for word in "cortana done" "Cortana, I'm done." "Cortana, stop rapid mode." "cortana stop" "cortana that's all" "cortana done with rapid mode"; do
  sess_run "tap alpha" "$word" "tap gamma"
  check "'$word' ends rapid mode" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 2 ]]"
done
# Bare exit words are not exits in rapid mode: "exit", "cancel" and "quit" match nothing, and "stop" is Media's, as
# outside a session.
for word in "exit" "cancel" "quit"; do
  sess_run "tap alpha" "$word" "tap gamma" "cortana done"
  check "bare '$word' leaves rapid mode open, pausing nothing" "session_gone && ! grep -q '^playerctl' '$log' && [[ \$(taps) == 2 && \$(record_starts) == 4 ]]"
done
for word in "stop" "Stop."; do
  sess_run "tap alpha" "$word" "tap gamma" "cortana done"
  check "bare '$word' pauses the music and leaves rapid mode open" "session_gone && grep -q '^playerctl' '$log' && [[ \$(taps) == 2 && \$(record_starts) == 4 ]]"
done
sess_run "tap alpha and then exit" "tap gamma" "cortana done"
check "a sequence ending in a bare exit does not end rapid mode" "session_gone && [[ \$(taps) == 2 && \$(record_starts) == 3 ]]"
sess_run "cortana tap alpha" "tap beta" "cortana done"
check "a 'cortana ...' that is no mode command is routed as a command, and the mode goes on" "session_gone && ! toast_has 'Not a mode command' && [[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' && \$(record_starts) == 3 ]]"
sess_run "cortana tap" "tap beta" "cortana done"
check "and one that matches nothing is a missed turn with the usual toast" "session_gone && toast_has 'no match' && [[ \$(grep '^tap ' '$log') == 'tap beta' && \$(record_starts) == 3 ]]"
sess_run "tap alpha"
check "rapid mode ends when nothing is said" "session_gone && toast_has 'Rapid mode ended nothing was said'"
sess_env=(VOXCMD_SESSION_MAX_TURNS=3)
sess_run "tap alpha" "tap alpha" "tap alpha" "tap alpha"
check "rapid mode is capped by turns like any session" "session_gone && [[ \$(taps) == 3 ]] && toast_has 'Rapid mode ended it reached 3 turns'"
sess_env=()
sess_env=(VOXCMD_WAKE_ALIASES="komputer|kompooter")
sess_run "kortana done" "Komputer, done" "tap alpha"
check "the wake word's spellings are a setting, and the built-in ones are then no command" "session_gone && grep -q 'voxcmd: no match' '$log' && [[ \$(taps) == 0 && \$(record_starts) == 2 ]]"
sess_env=()
sess_phrase="cortana rapid mode"
sess_run "cortana done"
check "the wake word before an entry phrase is stripped" "session_gone && [[ \$(record_starts) == 1 ]]"
sess_phrase="rapid mode"

# A card and a picker asked in a rapid turn listen for the spoken answer.
sess_run "ask me" "pick number" "cortana done"
check "a confirm card in rapid mode listens for yes or no" "grep -q '^voxcmd-confirm .*--listen' '$log' && [[ \$(grep -c '^asked' '$log') == 1 ]]"
check "and so does a picker of several options" "grep -q '^voxcmd-pick --listen' '$log' && grep -q '^picked one' '$log'"

# A phrase of steps joined by "and then" is one turn, and each step may ask.
sess_run "tap alpha and then tap beta" "cortana done"
check "a sequence in rapid mode runs its steps in order, as one turn" "session_gone && [[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' && \$(record_starts) == 2 ]]"
sess_env=(VOXCMD_SESSION_MAX_TURNS=2)
sess_run "tap alpha and then tap beta" "tap gamma" "tap delta"
check "and counts once against the turn cap" "session_gone && [[ \$(taps) == 3 ]] && toast_has 'Rapid mode ended it reached 2 turns'"
sess_env=()
sess_run "tap alpha and then tap" "tap beta and then tap" "tap gamma and then tap" "tap delta" "cortana done"
check "a sequence in which a step ran is not a missed turn, though a later step matched nothing" "session_gone && [[ \$(taps) == 4 ]] && ! toast_has 'nothing understood'"
sess_run "tap and then tap" "tap and then tap" "tap and then tap" "tap delta"
check "one in which no step ran is a missed turn" "session_gone && [[ \$(taps) == 0 ]] && toast_has 'nothing understood 3 times'"
sess_run "tap alpha and then ask me" "cortana done"
check "a card asked in a later step listens for yes or no when it was spoken" "grep -q '^voxcmd-confirm .*--listen' '$log' && [[ \$(taps) == 1 && \$(grep -c '^asked' '$log') == 1 ]]"
: >"$root/confirm-no"
sess_run "ask me" "ask me" "ask me" "tap delta"
check "a declined confirm card is a missed turn, not one that ran" "session_gone && [[ \$(taps) == 0 && \$(grep -c '^asked' '$log') == 0 ]] && toast_has 'nothing understood 3 times'"
sess_run "tap alpha and then ask me and then tap beta" "cortana done"
check "a declined card in a sequence stops the rest with one toast" "[[ \$(taps) == 1 && \$(grep -c 'Stopped at step 2 of 3' '$log') == 1 ]] && toast_has 'Stopped at step 2 of 3: not confirmed' && grep -q '^1 more step not run' '$log'"
rm -f "$root/confirm-no"

# Modes nest: the one opened inside returns to the one it was opened from.
sess_run "start testing" "alpha and then beta" "done"
check "a mode that rewrites its turns rewrites each step of a sequence" "session_gone && [[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' ]]"
sess_run "start testing" "alpha and then done" "tap beta" "cortana done"
check "a last step that is the mode's exit phrase runs the steps before it, then leaves the mode" "session_gone && [[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' && \$(record_starts) == 4 ]]"
sess_run "tap alpha and then done" "tap beta" "cortana done"
check "and in rapid mode it does not: the steps run up to the bare 'done', which matches nothing" "session_gone && toast_has 'stopped at step 2 of 2' && [[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' && \$(record_starts) == 3 ]]"
sess_run "start testing" "alpha" "done" "tap beta" "cortana done"
check "a mode opened in rapid mode returns to it: test mode's targets, then rapid mode's commands" "session_gone && [[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' && \$(record_starts) == 5 ]]"
check "and runs its ended hook once" "log_has_soon '^ended-hook' && [[ \$(grep -c '^ended-hook' '$log') == 1 ]]"
sess_start "start testing" HOLD
hold_in 'test rapid' 2
check "the session file names the mode on top and the one underneath" "mode_is 'test rapid' && [[ \$(jq -r '[.exit_hint, .stack[0].label] | join(\"|\")' '$session_json') == 'say done to stop (back to Rapid mode)|Rapid mode' ]]"
sess_voxcmd_env session end
sess_wait
check "ending the session ends every mode in it, running each one's hook" "session_gone && log_has_soon '^ended-hook' && toast_has 'Rapid mode ended ended by request'"
sess_start "rapid mode" HOLD
hold_in 'rapid ' 2
check "saying the mode that is open again changes nothing" "mode_is 'rapid '"
sess_voxcmd_env session end
sess_wait
sess_start "tap alpha" HOLD
hold_in 'rapid ' 2
sess_voxcmd_env session rapid
check "a key or terminal command during a session does not open another mode" "mode_is 'rapid ' && toast_has 'A voice session is already open'"
sess_voxcmd_env session end
sess_wait

# Click mode over rapid mode: switch phrases are never clicked, and a mode already underneath is returned to.
sess_run "click mode" "cortana rapid mode" "cortana done"
check "'cortana rapid mode' in click mode goes back to rapid mode, clicking nothing" "session_gone && no_clicks && [[ \$(record_starts) == 3 ]]"
sess_start "click mode" "cortana type mode" HOLD
hold_in 'type rapid/click' 3
check "'cortana type mode' in click mode opens type mode over it, clicking nothing" "mode_is 'type rapid/click' && no_clicks"
sess_voxcmd_env session end
sess_wait
sess_start "click mode" "cortana done" HOLD
hold_in 'rapid ' 3
check "'cortana done' in click mode returns to rapid mode" "mode_is 'rapid '"
sess_voxcmd_env session end
sess_wait
sess_run "click mode" "cortana stop rapid mode" "tap alpha"
check "'cortana stop rapid mode' in click mode leaves both" "session_gone && no_clicks && [[ \$(taps) == 0 && \$(record_starts) == 2 ]]"
sess_phrase="click mode"
sess_run "cortana tap alpha" "cortana done"
check "a 'cortana ...' that is no mode command is routed as a command in click mode too" "session_gone && ! toast_has 'Not a mode command' && [[ \$(grep '^tap ' '$log') == 'tap alpha' ]] && no_clicks"
# "start typing" is a click target in click mode, a search box may carry that label; only the wake word switches.
sess_run "start typing" "cortana done"
check "plain 'start typing' in click mode stays a click turn, not a switch to type mode" "session_gone && ! toast_has 'Type mode' && [[ \$(record_starts) == 2 ]]"
# No bare word leaves click mode: every exit word is a button label, and only "cortana ..." ends it.
# The sandbox has no focused window, so a clicked word fails with that toast, which proves it was routed as a click.
for word in "done" "I'm done" "that's all" "exit" "stop clicking" "done clicking" "rapid mode" "type mode"; do
  sess_run "$word" "cortana done"
  check "bare '$word' in click mode is clicked, not an exit" "session_gone && toast_has 'no focused window' && [[ \$(record_starts) == 2 ]]"
done
# "click mode off" starts with "click", so it used to reach the stop_clicking verb as a click phrase; the rewrite drops it
# now, a missed turn like the other bare exits.
sess_run "click mode off" "cortana done"
check "'click mode off' does not end click mode: the rewrite rejects it" "session_gone && no_clicks && [[ \$(taps) == 0 && \$(record_starts) == 2 ]]"
for word in "cortana done" "cortana stop clicking" "cortana done clicking" "cortana exit click mode"; do
  sess_run "$word" "tap alpha"
  check "'$word' leaves click mode" "session_gone && no_clicks && [[ \$(taps) == 0 && \$(record_starts) == 1 ]]"
done
sess_start HOLD
hold_in 'click ' 1
check "click mode's hint names the wake word" "[[ \$(jq -r .exit_hint '$session_json') == 'say cortana done to stop' ]]"
sess_voxcmd_env session end
sess_wait
sess_start "cortana start typing" HOLD
hold_in 'type click' 2
check "'cortana start typing' in click mode switches to type mode, clicking nothing" "mode_is 'type click' && no_clicks"
sess_voxcmd_env session end
sess_wait
sess_start "cortana rapid mode" HOLD
hold_in 'rapid click' 2
check "'cortana rapid mode' in click mode opens rapid mode over it, clicking nothing" "mode_is 'rapid click' && no_clicks"
sess_voxcmd_env session end
sess_wait
sess_phrase="rapid mode"
sess_start "click mode" HOLD
hold_in 'click rapid' 2
check "click mode over rapid mode says cortana done, and the mode underneath" "[[ \$(jq -r .exit_hint '$session_json') == 'say cortana done to stop (back to Rapid mode)' ]]"
sess_voxcmd_env session end
sess_wait
# The mode-entering verbs are commands, so rapid mode runs them bare.
sess_start "type mode" HOLD
hold_in 'type rapid' 2
check "'type mode' in rapid mode still opens type mode bare" "mode_is 'type rapid'"
sess_voxcmd_env session end
sess_wait

# Silence leaves one mode at a time.
sess_phrase="rapid mode"
sess_run "click mode" SILENCE "tap beta" "cortana done"
check "silence in click mode returns to rapid mode, which goes on" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 4 ]] && toast_has 'Click mode ended nothing was said'"

# Caps end every mode and run every popped hook.
sess_env=(VOXCMD_SESSION_MAX_TURNS=3)
sess_run "start testing" "alpha" "alpha" "alpha"
check "a cap ends rapid mode and the mode over it" "session_gone && log_has_soon '^ended-hook' && [[ \$(taps) == 2 ]] && toast_has 'Rapid mode ended it reached 3 turns'"
sess_env=()

# Type mode: one recording, typed once it ends. "UNTIL_STOP <speech>" records until stopped and only then writes the
# speech, as voxtype does with a long dictation; wake_heard plays voxcmd-wake's confirmation of a trigger heard during it.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
sess_phrase="type mode"
wtype_is() { [[ $(grep '^wtype ' "$log") == "$(printf '%s\n' "$@")" ]]; }
# wake_heard <transcript> [recording]: what the confirmation's Whisper heard in a clip cut during that recording (by
# default the one now under way, as voxcmd-wake names it). It runs in the foreground, as the listener's confirmation
# does, so whatever it ends has been ended once it returns.
wake_heard() { SANDBOX_TRANSCRIBE_TEXT="$1" sess_voxcmd_env internal wake-confirm /dev/stdin "${2:-$(recording_now)}" </dev/null; }
# Read under the session lock: a listen holds it from the recording's start until its watcher is the owner, and
# hold_in alone can pass before that, on the watcher before it, which saw a recording of its own.
recording_now() {
  (
    flock 9
    jq -r '"\(.frame_id):\(.owner):\(.owner_start)"' "$session_json"
  ) 9>"$XDG_RUNTIME_DIR/voxcmd/session.lock"
}
voxtype_now() { cat "$XDG_RUNTIME_DIR/voxtype/state"; }
# A mode's ended hook runs in the background and may outlive its watcher.
hooks_done() { wait_until ended_hooks_gone; }

sess_start "UNTIL_STOP Hello world. Cortana, stop."
owner_is_listening
check "type mode's session file names it, its hint, and that it is one recording the wake listener hears through" "[[ \$(jq -c '[.kind, .label, .exit_hint, .one_recording, .wake_listens, .stack]' '$session_json') == '[\"type\",\"Type mode\",\"say cortana stop, or cortana cancel\",true,true,[]]' ]]"
check "its one recording ends after 10 s of quiet or of no speech, and at 295 s" "log_has_soon 'no_speech_secs=10\$' && log_has_soon 'autostop min_speech_secs=0.4 silence_secs=10\$' && log_has_soon 'autostop max_secs=295\$'"
check "once its watcher owns the session, the hand-over is over" "! jq -e '.owner_handover' '$session_json' >/dev/null"
check "its one recording is watched by the binary under test" "owner_is_the_binary_under_test"
check "with the wake listener off, its start says to press the voice key" "log_has_soon '^notify-send .*voxcmd: Type mode Press the voice key to type it'"
wake_heard "Cortana, stop."
sess_wait
check "cortana stop ends the recording and types it once, without the ending" "session_gone && wtype_is 'wtype -- Hello world.' && [[ \$(record_starts) == 1 ]] && grep -q '^voxtype record stop' '$log' && toast_has 'Type mode ended done'"

for ending in "Cortana stop typing." "Cortana, stop recording." "cortana done" "Cortana, stop dictation."; do
  sess_start "UNTIL_STOP Some text. $ending"
  owner_is_listening
  wake_heard "$ending"
  sess_wait
  check "'$ending' types the dictation too" "session_gone && wtype_is 'wtype -- Some text.'"
done
sess_start "UNTIL_STOP I asked Cortana about it. Cortana, stop."
owner_is_listening
wake_heard "asked Cortana about it. Cortana, stop."
sess_wait
check "the ending follows the clip's last wake word, and only the one at the end is cut" "session_gone && wtype_is 'wtype -- I asked Cortana about it.'"

for ending in "Cortana, send it." "Cortana press enter" "Cortana, send." "Cortana send message" "Cortana, send the message."; do
  sess_start "UNTIL_STOP Ship it. $ending"
  owner_is_listening
  wake_heard "$ending"
  sess_wait
  # Keys has the same phrases outside type mode; here they are only the mode's ending, never routed.
  check "'$ending' types the dictation, then presses Return" "session_gone && wtype_is 'wtype -- Ship it.' 'wtype -k Return' && ! grep -q 'Keys' '$log'"
done

for ending in "Cortana, cancel." "Cortana never mind" "Cortana, nevermind."; do
  sess_start "UNTIL_STOP Secret words. $ending"
  owner_is_listening
  wake_heard "$ending"
  sess_wait
  check "'$ending' cancels the recording and types nothing" "session_gone && ! grep -q '^wtype' '$log' && grep -q '^voxtype record cancel' '$log' && toast_has 'Type mode ended cancelled, nothing typed'"
done

# An ending followed by "and then" records the chain and keeps recording until the pause (the stub detector hears it
# once $SANDBOX_DIR/chain-pause exists), then handles the dictation and routes the words after it from the transcript.
chain_pause() { touch "$SANDBOX_DIR/chain-pause"; }
chain_is_waiting() { [[ $(voxtype_now) == recording ]] && ! grep -qE '^voxtype record (stop|cancel)' "$log" && [[ $(jq -r '.ending.chain' "$session_json") == true ]]; }
rm -f "$SANDBOX_DIR/chain-pause"
sess_start "UNTIL_STOP Typed. Cortana stop typing then tap tap beta and then tap tap alpha."
owner_is_listening
wake_heard "Cortana stop typing then tap tap beta"
chain_pause
sess_wait
check "a bare 'then' right after the ending is a separator in the final transcript too, and the router splits the rest" "session_gone && wtype_is 'wtype -- Typed.' && [[ \$(grep '^tap ' '$log' | tr '\\n' ' ') == 'tap tap beta tap tap alpha ' ]]"
rm -f "$SANDBOX_DIR/chain-pause"

sess_start "UNTIL_STOP Ship it. Cortana send it and then tap tap beta."
owner_is_listening
wake_heard "Cortana send it and then"
check "an ending and 'and then' keep recording and record the chain" "chain_is_waiting && [[ \$(jq -c .ending '$session_json') == '{\"action\":\"send\",\"by\":\"voice\",\"chain\":true}' ]]"
check "its stopper is detached through setsid by the binary under test" "wait_until grep -qF 'setsid owner= $sess_chain_stopper ' '$log'"
chain_pause
sess_wait
check "the pause stops it: the dictation is sent without the ending, then the chain runs" "session_gone && wtype_is 'wtype -- Ship it.' 'wtype -k Return' && [[ \$(taps) == 1 ]] && grep -q '^tap tap beta' '$log'"
rm -f "$SANDBOX_DIR/chain-pause"

sess_start "UNTIL_STOP Some text. Cortana, stop typing, then tap tap beta."
owner_is_listening
wake_heard "Cortana stop typing then tap tap beta"
check "'stop typing, then ...' is a chain too" "chain_is_waiting"
chain_pause
sess_wait
check "and types the dictation, then runs the commands" "session_gone && wtype_is 'wtype -- Some text.' && [[ \$(taps) == 1 ]]"
rm -f "$SANDBOX_DIR/chain-pause"

sess_start "UNTIL_STOP Secret words. Cortana cancel and then tap tap beta."
owner_is_listening
wake_heard "Cortana cancel and then tap"
chain_pause
sess_wait
check "cancel with a chain drops the dictation, stopping the recording instead of cancelling it, and still runs the chain" "session_gone && ! grep -q '^wtype' '$log' && ! grep -q '^voxtype record cancel' '$log' && grep -q '^voxtype record stop' '$log' && [[ \$(taps) == 1 ]] && toast_has 'Type mode ended cancelled, nothing typed'"
rm -f "$SANDBOX_DIR/chain-pause"

sess_start "UNTIL_STOP Go. Cortana stop and then tap tap a and then tap tap b and then tap tap c and then tap tap d and then tap tap e."
owner_is_listening
wake_heard "Cortana stop and then tap tap a"
chain_pause
sess_wait
check "a chain of 5 steps runs them all, in order" "session_gone && wtype_is 'wtype -- Go.' && [[ \$(taps) == 5 ]] && [[ \$(grep '^tap ' '$log' | tr '\\n' ' ') == 'tap tap a tap tap b tap tap c tap tap d tap tap e ' ]]"
rm -f "$SANDBOX_DIR/chain-pause"
sess_start "UNTIL_STOP Go. Cortana stop and then tap tap a and then tap tap b and then tap tap c and then tap tap d and then tap tap e and then tap tap f."
owner_is_listening
wake_heard "Cortana stop and then tap tap a"
chain_pause
sess_wait
check "a sixth step runs nothing of the chain, as in any phrase, but the dictation is typed" "session_gone && wtype_is 'wtype -- Go.' && [[ \$(taps) == 0 ]] && toast_has 'Nothing ran: a phrase can have at most 5 steps'"
rm -f "$SANDBOX_DIR/chain-pause"

check "the chain's detector wants no speech of its own: speech may be over before it starts" "grep -q 'min_speech_secs=0 silence_secs=1.5\$' '$log'"

# A detector that errors (exit 1) leaves the recording running for the voice key.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" SANDBOX_CHAIN_DETECTOR_EXIT=1)
sess_start "UNTIL_STOP Kept. Cortana stop and then tap tap beta."
owner_is_listening
wake_heard "Cortana stop and then tap"
log_has_soon '^voxcmd-autostop max_secs=10'
check "a detector error does not stop the recording" "chain_is_waiting && wait_for_line 'chain.s detector gave verdict 1' '$debug_log'"
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
sess_voxcmd_env listen
sess_wait

# Stop Voice landing while the dictation is being typed ends the session; the chain must not run after it.
stop_block=$root/wtype-block
rm -f "$stop_block".entered "$stop_block".release
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" SANDBOX_WTYPE_BLOCK="$stop_block")
sess_start "UNTIL_STOP Typed. Cortana stop and then tap tap beta."
owner_is_listening
wake_heard "Cortana stop and then tap"
chain_pause
wait_until test -e "$stop_block.entered"
sess_voxcmd_env stop
touch "$stop_block.release"
sess_wait
check "Stop Voice while the dictation is typed ends the session and runs no chain" "session_gone && [[ \$(taps) == 0 ]]"
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
rm -f "$SANDBOX_DIR/chain-pause"

# The chain's detector starts mid-speech, so it takes the threshold the recording's own detector wrote.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" SANDBOX_ROOM_THRESHOLD_DB=-45.0)
sess_start "UNTIL_STOP Typed. Cortana stop and then tap tap beta."
owner_is_listening
wait_until compgen -G "$XDG_RUNTIME_DIR/voxcmd/threshold.*" >/dev/null
wake_heard "Cortana stop and then tap"
chain_pause
sess_wait
check "the chain's detector, and only it, gets the room threshold the recording's own detector measured" "[[ \$(grep -c '^voxcmd-autostop threshold_db=' '$log') == 1 ]] && grep -q '^voxcmd-autostop threshold_db=-45.0' '$log' && [[ \$(taps) == 1 ]]"
check "and the threshold file is gone with the watcher" "! compgen -G '$XDG_RUNTIME_DIR/voxcmd/threshold.*'"
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
rm -f "$SANDBOX_DIR/chain-pause"

sess_start "UNTIL_STOP Typed. Cortana stop."
owner_is_listening
wake_heard "Cortana stop."
sess_wait
check "a plain ending stops at once, with no chain" "session_gone && wtype_is 'wtype -- Typed.' && ! grep -q '_chain-stop' '$log'"
check "and detaches no chain stopper, under either binary's spelling" "! grep -qE '(_chain-stop|internal chain-stop)' '$log'"

sess_start "UNTIL_STOP First part and then tap tap beta. Cortana stop."
owner_is_listening
wake_heard "Cortana stop."
sess_wait
check "'and then' in the dictation, before the wake word and ending, stays text" "session_gone && wtype_is 'wtype -- First part and then tap tap beta.' && [[ \$(taps) == 0 ]]"

sess_start "UNTIL_STOP Note it. Cortana stop. And then tap tap beta."
owner_is_listening
wake_heard "Cortana stop."
sess_wait
check "so is an 'and then' after a plain ending the clip heard as the whole phrase" "session_gone && [[ \$(taps) == 0 ]]"

sess_start "UNTIL_STOP Hello. Cortana new paragraph and then more."
owner_is_listening
wake_heard "Cortana new paragraph and then more"
check "a wake word and 'and then' after words that are no ending leave the recording running" "[[ \$(voxtype_now) == recording ]] && ! grep -qE '^voxtype record (stop|cancel)' '$log' && ! jq -e .ending '$session_json' >/dev/null"
sess_voxcmd_env listen
sess_wait

sess_start "UNTIL_STOP Hello. Cortana new paragraph. More."
owner_is_listening
wake_heard "Cortana, new paragraph."
check "any other words after the wake word leave the recording running" "[[ \$(voxtype_now) == recording ]] && ! grep -qE '^voxtype record (stop|cancel)' '$log'"
wake_heard "Cortana, what time is it"
check "so does the wake word alone, or a question" "[[ \$(voxtype_now) == recording ]] && ! grep -qE '^voxtype record (stop|cancel)' '$log'"
sess_voxcmd_env listen
sess_wait
check "the voice key ends it and types all of it" "session_gone && wtype_is 'wtype -- Hello. Cortana new paragraph. More.' && toast_has 'Type mode ended done'"

sess_start "UNTIL_STOP Kept words."
owner_is_listening
(
  flock 9
  jq -c '.ending = {action: "type", by: "cap"}' "$session_json" >"$session_json.new" && mv "$session_json.new" "$session_json"
) 9>"$XDG_RUNTIME_DIR/voxcmd/session.lock"
wake_heard "Cortana cancel"
check "an ending recorded first wins: a later cancel does nothing" "[[ \$(voxtype_now) == recording ]] && ! grep -q '^voxtype record cancel' '$log'"
SANDBOX_VOXTYPE_TURNS="$sess_turns" voxtype record stop
sess_wait
check "and the recording is typed as that ending says" "session_gone && wtype_is 'wtype -- Kept words.' && toast_has 'Type mode ended it reached its recording limit (295 s)'"

# A confirmation that outlasted its recording: its clip was cut during an earlier type mode, or an earlier recording of
# this one (another watcher), and must not end the recording now under way.
sess_start "UNTIL_STOP Earlier words."
owner_is_listening
earlier_recording=$(recording_now)
sess_voxcmd_env listen
sess_wait
sess_start "UNTIL_STOP Newer words."
owner_is_listening
wake_heard "Cortana, stop." "$earlier_recording"
check "a stop heard in an earlier type mode's recording leaves the new one running" "[[ \$(voxtype_now) == recording ]] && ! grep -qE '^voxtype record (stop|cancel)' '$log' && grep -q 'heard in an earlier recording' '$debug_log'"
wake_heard "Cortana cancel" "$(jq -r '"\(.frame_id):1:1"' "$session_json")"
check "so does a cancel heard in an earlier recording of the same type mode" "[[ \$(voxtype_now) == recording ]] && ! grep -qE '^voxtype record (stop|cancel)' '$log' && ! jq -e .ending '$session_json' >/dev/null"
SANDBOX_TRANSCRIBE_TEXT="Cortana, stop." sess_voxcmd_env internal wake-confirm /dev/stdin </dev/null
check "and a confirmation that names no recording ends none" "[[ \$(voxtype_now) == recording ]] && ! grep -qE '^voxtype record (stop|cancel)' '$log'"
wake_heard "Cortana, stop."
sess_wait
check "while its own stop still ends it" "session_gone && wtype_is 'wtype -- Newer words.'"

sess_run "CAP A long talk."
check "at the length limit it types what was said, ends the mode with a toast, and records nothing more" "session_gone && wtype_is 'wtype -- A long talk.' && [[ \$(record_starts) == 1 ]] && toast_has 'Type mode ended it reached its recording limit (295 s)'"
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" VOXCMD_TYPE_MAX_SECS=60)
sess_run "CAP A long talk."
check "the limit toast names the limit that was set" "session_gone && wtype_is 'wtype -- A long talk.' && toast_has 'Type mode ended it reached its recording limit (1 min)'"
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
sess_run "IDLE Words, then quiet."
check "10 s of quiet after speech type what was said, as a stop would" "session_gone && wtype_is 'wtype -- Words, then quiet.' && toast_has 'Type mode ended typed after 10 s of quiet'"
sess_run SILENCE
check "10 s with no speech end the mode, typing nothing" "session_gone && ! grep -q '^wtype' '$log' && [[ \$(record_starts) == 1 ]] && toast_has 'Type mode ended nothing was said for 10 s'"
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" VOXCMD_TYPE_IDLE_SECS=30 VOXCMD_TYPE_MAX_SECS=60)
sess_run SILENCE
check "VOXCMD_TYPE_IDLE_SECS and VOXCMD_TYPE_MAX_SECS set the bounds" "every_detector_logged no_speech_secs= no_speech_secs=30 && grep -q 'silence_secs=30\$' '$log' && grep -q 'max_secs=60\$' '$log'"
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")

# What is typed.
for heard in "Thank you." "Cortana, stop." "Cortana cancel"; do
  sess_start "UNTIL_STOP $heard"
  owner_is_listening
  sess_voxcmd_env listen
  sess_wait
  check "'$heard' alone types nothing" "session_gone && ! grep -q '^wtype' '$log'"
done
sess_start $'UNTIL_STOP Tab\there -x'
owner_is_listening
sess_voxcmd_env listen
sess_wait
check "control characters become spaces and a dash is typed as text" "wtype_is 'wtype -- Tab here -x'"
sess_start "UNTIL_STOP exit, stop, cancel and quit"
owner_is_listening
sess_voxcmd_env listen
sess_wait
check "bare exit words are dictated text in type mode" "wtype_is 'wtype -- exit, stop, cancel and quit'"
sess_start "UNTIL_STOP done, stop typing and click mode"
owner_is_listening
sess_voxcmd_env listen
sess_wait
check "without the wake word 'done', 'stop typing' and 'click mode' are text" "wtype_is 'wtype -- done, stop typing and click mode'"

# Inside rapid mode.
sess_phrase="rapid mode"
sess_start "type mode" "UNTIL_STOP Back again. Cortana stop." "tap beta" "cortana done"
hold_in 'type rapid' 2
check "type mode's hint says where it returns to" "[[ \$(jq -r .exit_hint '$session_json') == 'say cortana stop, or cortana cancel (back to Rapid mode)' ]]"
wake_heard "Cortana stop."
sess_wait
check "cortana stop leaves only type mode, back to rapid mode" "session_gone && wtype_is 'wtype -- Back again.' && [[ \$(taps) == 1 && \$(record_starts) == 4 ]]"
sess_start "type mode" "UNTIL_STOP All done. Cortana, stop listening." "tap beta"
hold_in 'type rapid' 2
wake_heard "Cortana, stop listening."
sess_wait
check "cortana stop listening types it and ends the whole session" "session_gone && wtype_is 'wtype -- All done.' && [[ \$(taps) == 0 && \$(record_starts) == 2 ]] && toast_has 'Rapid mode ended stopped'"
sess_start HOLD
owner_is_listening
wake_heard "Cortana, stop."
check "a mode that is not listened through is never ended by the wake listener" "[[ \$(voxtype_now) == recording ]] && ! grep -qE '^voxtype record (stop|cancel)' '$log'"
sess_voxcmd_env session end
sess_wait
sess_start "type mode" "UNTIL_STOP Stopped words." "tap beta"
hold_in 'type rapid' 2
sess_voxcmd_env stop
sess_wait
check "Stop Voice types the dictation, then ends the session" "session_gone && wtype_is 'wtype -- Stopped words.' && [[ \$(taps) == 0 && \$(record_starts) == 2 ]] && toast_has 'Rapid mode ended stopped' && ! grep -q '^voxtype record cancel' '$log'"

# The time spent in type mode is not counted against the session's: the session is aged past its cap while the
# recording runs, without the test waiting it out.
session_cap_secs=600
# age_session <secs>: as if that long had passed, every time the session recorded moves that far into the past. Under
# the session lock, so no turn rewrites the file meanwhile.
age_session() {
  (
    flock 9
    jq -c --argjson secs "$1" '
      def aged: with_entries(if .key == "started" or .key == "mode_started" then .value -= $secs else . end);
      aged | if .stack then .stack |= map(aged) else . end' "$session_json" >"$session_json.aged" &&
      mv "$session_json.aged" "$session_json"
  ) 9>"$XDG_RUNTIME_DIR/voxcmd/session.lock"
}
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" "VOXCMD_SESSION_MAX_SECS=$session_cap_secs")
sess_start "type mode" "UNTIL_STOP Long dictation." "tap beta" "done"
hold_in 'type rapid' 2
age_session $((session_cap_secs + 1))
sess_voxcmd_env listen
sess_wait
check "the time spent in type mode is not counted against the session's time" "session_gone && wtype_is 'wtype -- Long dictation.' && [[ \$(taps) == 1 ]] && ! toast_has 'time limit'"
sess_phrase="type mode"

# Stopped while the recording is already transcribing: it is typed, then the session ends.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
sess_start HOLD
owner_is_listening
echo transcribing >"$XDG_RUNTIME_DIR/voxtype/state"
sess_voxcmd_env stop
check "Stop Voice while type mode transcribes leaves the transcription alone" "! grep -qE '^voxtype record (stop|cancel)' '$log'"
printf 'Late words.' >"$XDG_RUNTIME_DIR/voxcmd/transcript.txt"
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
sess_wait
check "and the transcript is typed before the session ends" "session_gone && wtype_is 'wtype -- Late words.' && toast_has 'Type mode ended stopped'"
# Stopped once voxtype is idle again but before the watcher has read the transcript: the watcher is frozen meanwhile, so
# Stop Voice finds only the session to tell it the recording is still to be handled.
sess_start "UNTIL_STOP Finished words."
owner_is_listening
stopped_owner=$(jq -r .owner "$session_json")
kill -STOP "$stopped_owner"
SANDBOX_VOXTYPE_TURNS="$sess_turns" voxtype record stop
sess_voxcmd_env stop
check "Stop Voice after the recording ended but before its watcher read it keeps the session for the watcher" "[[ -e '$session_json' && \$(jq -r .ending.by '$session_json') == key ]] && ! grep -q '^voxtype record cancel' '$log'"
kill -CONT "$stopped_owner"
sess_wait
check "and the finished dictation is typed, then the session ends" "session_gone && wtype_is 'wtype -- Finished words.' && toast_has 'Type mode ended stopped'"
# A voice key pressed in the same window (twice, or just after auto-stop) must not take the transcript or the session.
sess_start "UNTIL_STOP Kept dictation."
owner_is_listening
stopped_owner=$(jq -r .owner "$session_json")
kill -STOP "$stopped_owner"
SANDBOX_VOXTYPE_TURNS="$sess_turns" voxtype record stop
sess_voxcmd_env listen
check "a voice key while the watcher has not read its transcript starts no recording" "[[ \$(record_starts) == 1 && -s '$XDG_RUNTIME_DIR/voxcmd/transcript.txt' && \$(jq -r .owner '$session_json') == '$stopped_owner' ]] && toast_has 'voxcmd: Type mode Still typing what was said'"
kill -CONT "$stopped_owner"
sess_wait
check "and the dictation is typed" "session_gone && wtype_is 'wtype -- Kept dictation.' && [[ \$(record_starts) == 1 ]]"

# Type mode re-created at the same depth while the recording was handled: nothing is typed into the new one.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window" SANDBOX_CLICKHINTS_STATE_BLOCK="$root/frame-block")
rm -f "$root/frame-block.entered" "$root/frame-block.release"
sess_start "UNTIL_STOP Stale words."
owner_is_listening
sess_voxcmd_env listen
wait_for_path "$root/frame-block.entered"
jq -c '.frame_id = "recreated"' "$session_json" >"$session_json.new"
mv "$session_json.new" "$session_json"
: >"$root/frame-block.release"
sess_wait
check "a recording whose type mode was re-created while it was handled is not typed" "! grep -q '^wtype' '$log' && grep -q 'type: not typed' '$debug_log'"

# Refusals: nothing is typed, and the toast has no text.
sess_env=()
sess_start "UNTIL_STOP Secret words."
owner_is_listening
sess_voxcmd_env listen
sess_wait
check "without a focused window nothing is typed" "session_gone && toast_has 'voxcmd: not typed no window has focus' && ! grep -q '^wtype' '$log' && ! grep -rq 'Secret' '$log' '$debug_log'"
sess_env=(SANDBOX_HYPRCTL_UNREACHABLE=1)
sess_start "UNTIL_STOP Secret words."
owner_is_listening
sess_voxcmd_env listen
sess_wait
check "an unreachable Hyprland is named, not read as no focus" "session_gone && toast_has 'voxcmd: not typed Hyprland cannot be reached' && ! grep -q '^wtype' '$log'"
# Dictation never goes to a picker that is waiting when type mode listens.
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
cp /bin/sleep "$root/voxcmd-hints"
"$root/voxcmd-hints" 60 &
waiter_pid=$!
rm -f "$root/modes-fifo"
mkfifo "$root/modes-fifo"
jq -n -c --argjson pid "$waiter_pid" --arg fifo "$root/modes-fifo" \
  '{pid: $pid, fifo: $fifo, label: "Which one?", kind: "hints", expansions: {}, choices: [{id: "a", label: "1. A"}]}' >"$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
sess_start "UNTIL_STOP Secret words."
owner_is_listening
sess_voxcmd_env listen
sess_wait
rm -f "$XDG_RUNTIME_DIR/voxcmd/pending-pick.json"
check "a pending picker does not take dictation: it stays with type mode, which refuses it" "session_gone && toast_has 'voxcmd: not typed a voxcmd picker or card is open' && ! grep -q 'goes to reply' '$debug_log' && grep -q 'a transcript of 13 characters goes to session_turn' '$debug_log' && ! grep -q '^wtype' '$log'"
kill "$waiter_pid" 2>/dev/null
wait "$waiter_pid" 2>/dev/null

# Dictation stays out of the logs and the session file.
sess_start "UNTIL_STOP Hello private words. Cortana, stop."
owner_is_listening
wake_heard "private words. Cortana, stop."
check "the ending is recorded without the words" "[[ \$(jq -c .ending '$session_json' 2>/dev/null) == '{\"action\":\"type\",\"by\":\"voice\"}' ]] || session_gone"
sess_wait
check "type mode logs lengths, never the text" "! grep -q 'private' '$debug_log' && grep -q 'a transcript of 35 characters goes to session_turn' '$debug_log' && grep -q 'typed 20 characters' '$debug_log' && ! grep -v '^wtype ' '$log' | grep -q private"
check "and the transcript is not left on disk" "[[ ! -e '$XDG_RUNTIME_DIR/voxcmd/transcript.txt' ]]"

# The ended hook runs in the background, taking the session lock rather than assuming the caller's.
sess_phrase="rapid mode"
sess_env=()
hook_waits_for_lock() {
  local pid
  [[ -n $1 ]] || return 1
  for pid in $(pgrep -x flock); do
    descends_from "$pid" "$1" && return 0
  done
  return 1
}
descends_from() {
  local pid=$1
  until [[ $pid == "$2" ]]; do
    pid=$(sed 's/.*) //' "/proc/$pid/stat" 2>/dev/null | awk '{print $2}')
    [[ -n $pid && $pid != 0 && $pid != 1 ]] || return 1
  done
}
rm -f "$root/hook-go"
: >"$root/hook-gate"
sess_start "start testing" "done" HOLD
hold_in 'rapid ' 3
flock_file=$XDG_RUNTIME_DIR/voxcmd/session.lock
rm -f "$root/lock-held" "$root/lock-release"
flock "$flock_file" sh -c ": >'$root/lock-held'; until [ -e '$root/lock-release' ]; do sleep 0.02; done" &
lock_holder=$!
wait_for_path "$root/lock-held"
: >"$root/hook-go"
# A negative: the hook, not holding the lock, must wait for the one held here. Once a flock started by the hook waits on
# it, the hook has reached the lock without going on.
hook_pid=$(sed -n 's/.* session: ended hook \([0-9]*\) runs$/\1/p' "$debug_log" | tail -n 1)
wait_until hook_waits_for_lock "$hook_pid"
check "the ended hook takes the session lock instead of assuming the caller's" "! grep -q '^ended-hook' '$log'"
: >"$root/lock-release"
wait "$lock_holder"
log_has_soon '^ended-hook'
rm -f "$root/hook-gate" "$root/hook-go"
sess_voxcmd_env session end
sess_wait
hooks_done
sess_phrase="type mode"

# A turn heard in a mode that changed, or after the session went, is never acted on. Each turn is spoken only once the
# test has changed what it was heard in.
voxtype_release=$SANDBOX_DIR/voxtype-release
# Waits until the run has started this many recordings.
record_starts_reach() { wait_until record_starts_are "$1"; }
record_starts_are() { [[ $(record_starts) == "$1" ]]; }
sess_env=()
sess_phrase="rapid mode"
rm -f "$voxtype_release"
sess_start "start testing" "GATED tap alpha" "done"
record_starts_reach 2
sess_voxcmd_env run "stop testing"
: >"$voxtype_release"
sess_wait
check "a transcript heard before the mode changed is told so and never run" "session_gone && ! grep -q '^tap alpha' '$log' && toast_has 'The mode changed, say it again'"
rm -f "$voxtype_release"
sess_start "GATED tap alpha" "done"
record_starts_reach 1
rm -f "$session_json"
: >"$voxtype_release"
sess_wait
check "a turn whose session is gone is routed when it was heard in rapid mode" "grep -q '^tap alpha' '$log'"
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
sess_phrase="type mode"
rm -f "$voxtype_release"
sess_start "GATED tap alpha" "done"
record_starts_reach 1
rm -f "$session_json"
: >"$voxtype_release"
sess_wait
check "and discarded when it was heard in type mode" "! grep -q '^tap alpha' '$log' && ! grep -q '^wtype' '$log'"
rm -f "$voxtype_release"

sess_env=()
sess_phrase=""
sess_config=$root/config-sess

finish
