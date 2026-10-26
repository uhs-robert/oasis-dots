# The voice-session harness that run-sessions.sh and run-modes.sh share, sourced inside the sandbox after lib.sh: a copy
# of the package whose auto-stop is the sandbox's stub, the "Sess" integration, and the helpers that start a session on
# scripted turns and wait for it to end. Each script sources it into a sandbox of its own, so they share no state.
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # read by the suites that source this; set by them and lib.sh

# A copy of the package whose voxcmd-autostop is the sandbox's stub, with the sandbox's setsid really starting the
# watcher and its voxtype "hearing" the next line of $SANDBOX_VOXTYPE_TURNS ("SILENCE" and an empty queue are no
# speech, "EMPTY" is speech that transcribes to nothing, "HOLD" keeps recording until stopped or cancelled, "FAIL" is a
# record start that fails). Every run ends when no watcher is left, which is what proves the microphone stops
# re-opening.

sess_stubs=$root/sess-stubs
sess_pkg=$root/sess-pkg
mkdir -p "$sess_stubs" "$sess_pkg"
cp -r "$package/.local" "$sess_pkg/.local"
ln -sf "$SANDBOX_DIR/bin/voxcmd-autostop" "$sess_pkg/.local/bin/voxcmd-autostop"
link_voxcmd_build "$sess_pkg"
# sess_voxcmd is the build under test, linked into the copy; its session turns' watchers are the process name the tests
# look for.
sess_voxcmd=$sess_pkg/tests/bin/voxcmd
sess_rust_voxcmd=$(readlink -f "$sess_voxcmd")
sess_watcher="$sess_rust_voxcmd internal watch"
# The voxcmd a type-mode recording's detector has check its pauses: the binary that listened.
sess_pause_voxcmd=$sess_rust_voxcmd
sess_chain_stopper="$sess_rust_voxcmd internal chain-stop"
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
# The Test integration's picker is the built-in hints overlay, which asks through ask-stub: this stub is its answer.
ln -sf "$sess_stubs/sess-hints" "$sess_pkg/.local/bin/voxcmd-hints"
hints_state=$SANDBOX_DIR/clickhints-state popup_state_file=$SANDBOX_DIR/popup-state

# The "Test" integration (kind "test"). "both" is two targets, which the overlay asks about: their ids carry a box, as
# click's do.
sess_config=$root/config-sess
mkdir -p "$sess_config/integrations" "$sess_config/replacements.d"
cat >"$sess_config/integrations/test.toml" <<'STUB'
name = "Sess"
picker = "hints"
verbs = [
  { action = "begin_it", match = 'start testing' },
  { action = "stop_it", match = 'stop testing' },
  { action = "tap", match = 'tap {target}' },
  { action = "calc", match = 'calculate {target}' },
]

[actions]
begin_it = { enter_mode = true, mode_switch = true }
stop_it = { leave_mode = "done", mode_switch = true }
# The candidates hook of "slow" waits for the test's release, far past the hook default.
tap = { run = 'test_tap', candidates = 'test_candidates', no_match = 'none', timeout_secs = 60 }
calc = { run = 'echo "calc $VOXCMD_RAW_TRANSCRIPT" >> "$TEST_LOG"', candidates = 'test_candidates' }
none = { run = 'echo "tap nothing" >> "$TEST_LOG"', miss = true }

[mode]
label = "Test mode"
exit_phrases = '(okay )?stop testing|done testing'
# As click mode: a bare exit word is a button label.
bare_exits = false
rewrite_hook = 'test_rewrite "$VOXCMD_PHRASE"'
ended = 'test_ended'
STUB
cat >"$sess_config/integrations/test.sh" <<STUB
# shellcheck shell=bash
TEST_LOG="$log"
export TEST_LOG
test_candidates() {
  case "\$VOXCMD_ARG_TARGET" in
  missing) printf 'zz\tzz\n' ;;
  both) printf '1,1,left,0,0,10,10\tboth left\n2,2,left,0,0,10,10\tboth right\n' ;;
  slow)
    # A route that is still working when the test presses Stop.
    touch "$root/routing"
    while [ ! -e "$root/route-release" ]; do sleep 0.02; done
    printf '1,1,left,0,0,10,10\tslow left\n2,2,left,0,0,10,10\tslow right\n'
    ;;
  *) printf '%s\t%s\n' "\$VOXCMD_ARG_TARGET" "\$VOXCMD_ARG_TARGET" ;;
  esac
}
test_tap() { echo "tap \$VOXCMD_LABEL" >> "$log"; }
test_ended() {
  echo "ended-hook" >> "$log"
}
test_rewrite() {
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
# signal_watchers <signal>: signals this sandbox's watchers only. Every sandbox's watcher has the same command line, so a
# plain pkill -f would reach the watchers of scripts running beside this one; their environment carries this sandbox's
# SANDBOX_DIR.
signal_watchers() {
  local pid
  for pid in $(pgrep -f -- "$sess_watcher"); do
    grep -qzxF "SANDBOX_DIR=$SANDBOX_DIR" "/proc/$pid/environ" 2>/dev/null && kill "-$1" "$pid" 2>/dev/null
  done
  return 0
}
start_time_of() { sed 's/.*) //' "/proc/$1/stat" | awk '{print $20}'; }
# Waits until the session's owner is a watcher that has seen its recording start, so its traps are set.
owner_is_listening() { wait_until owner_saw_recording; }
owner_saw_recording() {
  local owner
  owner=$(jq -r .owner "$XDG_RUNTIME_DIR/voxcmd/session.json" 2>/dev/null)
  [ -n "$owner" ] && grep -q "voxcmd\[$owner\] watch: voxtype recording\$" "$debug_log"
}
# The session's owner is a session turn's watcher of the binary under test, which these checks prove ran.
owner_is_the_binary_under_test() {
  local owner cmdline
  owner=$(jq -r .owner "$XDG_RUNTIME_DIR/voxcmd/session.json" 2>/dev/null)
  cmdline=$(tr '\0' ' ' <"/proc/$owner/cmdline" 2>/dev/null) || return 1
  [[ $cmdline == *"$sess_watcher session_turn "* ]] || return 1
  [[ $(readlink -f "/proc/$owner/exe") == "$sess_rust_voxcmd" ]]
}

# every_detector_logged <setting> <line>: each session listen's detector logged its <setting> as <line>, and at least one
# did. A turn of speech can end before its listen's detector has started, which then never runs (nor logs), so the run
# ends on a turn of silence: that recording lasts until its detector's verdict, so its line is always there.
every_detector_logged() {
  local lines
  lines=$(grep "^voxcmd-autostop $1" "$log" | sed 's/^voxcmd-autostop //')
  [[ -n $lines ]] && ! grep -qvx "$2" <<<"$lines"
}
