#!/usr/bin/env bash
# Tests for voxcmd's modes (rapid, type and the stack they share), split from run-sessions.sh so the two run side by
# side. run.sh runs these beside its own, each in a sandbox of its own; run alone: home/voxcmd/tests/run-modes.sh
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

# ---- modes: rapid, type, and the stack they share ----------------------------------------------------------------------
# rapid, typing and click for real beside the test mode, Media (a routed "stop"), Keys (whose "send it" and
# "press enter" type mode's endings must win over) and two
# integrations that ask: a yes/no card and a picker of two. The card and the picker are logging stubs.
section "modes"
modes_config=$root/config-modes
mkdir -p "$modes_config/integrations" "$modes_config/replacements.d"
cp "$root/config-sess/integrations/test."{toml,sh} "$modes_config/integrations/"
for integration in rapid typing click media keys; do
  copy_shipped_integrations "$modes_config" "$integration"
done
cat >"$modes_config/integrations/ask.toml" <<'STUB'
name = "Ask"
confirm = true
verbs = [
  { action = "ask_it", match = 'ask me' },
  { action = "both_of_them", match = 'pick {target}' },
]

[actions]
ask_it = 'echo "asked" >> "$ASK_LOG"'
both_of_them = { run = 'echo "picked $VOXCMD_ID" >> "$ASK_LOG"', candidates = 'ask_candidates' }
STUB
cat >"$modes_config/integrations/ask.sh" <<STUB
# shellcheck shell=bash
ASK_LOG="$log"
export ASK_LOG
ask_candidates() { printf 'one\tnumber one\ntwo\tnumber two\n'; }
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
# A session's kind is the stem of the mode's TOML file.
type_kind=typing
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
for word in "done" "Done." "that's all" "I'm done" "done with rapid mode"; do
  sess_run "tap alpha" "$word" "tap gamma" "cortana done"
  check "bare '$word' does not end rapid mode, and says how to leave" "session_gone && toast_has 'say cortana done to leave' && [[ \$(taps) == 2 && \$(record_starts) == 4 ]]"
done
# The mode-naming forms stay rejected by the rewrite, with the generic toast and no hint.
for word in "stop rapid mode" "Okay, quit rapid mode." "rapid mode off" "turn off rapid fire mode"; do
  sess_run "tap alpha" "$word" "tap gamma" "cortana done"
  check "bare '$word' does not end rapid mode, and gives no leave hint" "session_gone && toast_has 'Not understood' && ! toast_has 'say cortana done to leave' && [[ \$(taps) == 2 && \$(record_starts) == 4 ]]"
done
sess_run "tap alpha and then stop rapid mode" "tap gamma" "cortana done"
check "a trailing 'and then stop rapid mode' step does not end rapid mode either" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 3 ]]"
for word in "cortana done" "Cortana, I'm done." "Cortana, stop rapid mode." "cortana stop" "cortana that's all" "cortana done with rapid mode" "cortana exit" "Cortana, quit."; do
  sess_run "tap alpha" "$word" "tap gamma"
  check "'$word' ends rapid mode" "session_gone && [[ \$(taps) == 1 && \$(record_starts) == 2 ]]"
done
# Bare exit words are not exits in rapid mode: "exit", "quit" and "stop" give the leave hint, and "cancel" matches nothing.
for word in "exit" "quit"; do
  sess_run "tap alpha" "$word" "tap gamma" "cortana done"
  check "bare '$word' leaves rapid mode open, pausing nothing, with the leave hint" "session_gone && ! grep -q '^playerctl' '$log' && toast_has 'say cortana done to leave' && [[ \$(taps) == 2 && \$(record_starts) == 4 ]]"
done
sess_run "tap alpha" "cancel" "tap gamma" "cortana done"
check "bare 'cancel' leaves rapid mode open, pausing nothing, with no leave hint" "session_gone && ! grep -q '^playerctl' '$log' && ! toast_has 'say cortana done to leave' && [[ \$(taps) == 2 && \$(record_starts) == 4 ]]"
# Owner request: a bare "stop" pausing the music was surprising, so it is a missed turn with the hint, like "done".
for word in "stop" "Stop."; do
  sess_run "tap alpha" "$word" "tap gamma" "cortana done"
  check "bare '$word' pauses nothing, leaves rapid mode open and says how to leave" "session_gone && ! grep -q '^playerctl' '$log' && toast_has 'say cortana done to leave' && [[ \$(taps) == 2 && \$(record_starts) == 4 ]]"
done
for word in "Stop. Stop. Stop." "stop stop" "Done. Done."; do
  sess_run "tap alpha" "$word" "tap gamma" "cortana done"
  check "repeated '$word' pauses nothing, leaves rapid mode open and says how to leave" "session_gone && ! grep -q '^playerctl' '$log' && toast_has 'say cortana done to leave' && [[ \$(taps) == 2 && \$(record_starts) == 4 ]]"
done
for word in "stop the music" "pause"; do
  sess_run "tap alpha" "$word" "tap gamma" "cortana done"
  check "'$word' still pauses the music in rapid mode" "session_gone && grep -q '^playerctl' '$log' && [[ \$(taps) == 2 && \$(record_starts) == 4 ]]"
done
sess_run "tap alpha and then exit" "tap gamma" "cortana done"
check "a sequence ending in a bare exit does not end rapid mode, and says how to leave" "session_gone && toast_has 'say cortana done to leave' && [[ \$(taps) == 2 && \$(record_starts) == 3 ]]"
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
sess_run "tap alpha and then calculate 10 / 2" "cortana done"
check "a sequence in rapid mode hands each step's words as spoken to its handler, operators kept" "session_gone && grep -qx 'calc calculate 10 / 2' '$log'"
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
check "and in rapid mode it does not: the steps run, then the bare 'done' gives the leave hint" "session_gone && toast_has 'say cortana done to leave' && ! toast_has 'stopped at step 2' && [[ \$(grep '^tap ' '$log' | paste -sd,) == 'tap alpha,tap beta' && \$(record_starts) == 3 ]]"
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
hold_in "$type_kind rapid/click" 3
check "'cortana type mode' in click mode opens type mode over it, clicking nothing" "mode_is '$type_kind rapid/click' && no_clicks"
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
for word in "cortana done" "cortana stop clicking" "cortana done clicking" "cortana exit click mode" "cortana exit" "Cortana, quit."; do
  sess_run "$word" "tap alpha"
  check "'$word' leaves click mode" "session_gone && no_clicks && [[ \$(taps) == 0 && \$(record_starts) == 1 ]]"
done
sess_start HOLD
hold_in 'click ' 1
check "click mode's hint names the wake word" "[[ \$(jq -r .exit_hint '$session_json') == 'say cortana done to stop' ]]"
sess_voxcmd_env session end
sess_wait
sess_start "cortana start typing" HOLD
hold_in "$type_kind click" 2
check "'cortana start typing' in click mode switches to type mode, clicking nothing" "mode_is '$type_kind click' && no_clicks"
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
hold_in "$type_kind rapid" 2
check "'type mode' in rapid mode still opens type mode bare" "mode_is '$type_kind rapid'"
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
check "type mode's session file names it, its hint, and that it is one recording the wake listener does not hear through" "[[ \$(jq -c '[.kind, .label, .exit_hint, .one_recording, .wake_listens, .stack]' '$session_json') == '[\"$type_kind\",\"Type mode\",\"say cortana stop, or cortana cancel\",true,false,[]]' ]]"
check "its one recording ends after 10 s of quiet or of no speech, and at 295 s" "log_has_soon 'no_speech_secs=10\$' && log_has_soon 'autostop min_speech_secs=0.4 silence_secs=10\$' && log_has_soon 'autostop max_secs=295\$'"
check "once its watcher owns the session, the hand-over is over" "! jq -e '.owner_handover' '$session_json' >/dev/null"
check "its one recording is watched by the binary under test" "owner_is_the_binary_under_test"
check "with the wake listener off, its start still says to say cortana stop" "log_has_soon '^notify-send .*voxcmd: Type mode Say \"cortana stop\" to type it'"
check "its detector checks the pauses of this recording, with the binary under test" "log_has_soon \"^voxcmd-autostop pause_check_recording=\$(recording_now)\$\" && log_has_soon \"^voxcmd-autostop pause_check_voxcmd=\$sess_pause_voxcmd\$\""
wake_heard "Cortana, stop."
sess_wait
check "cortana stop ends the recording and types it once, without the ending" "session_gone && wtype_is 'wtype -- Hello world.' && [[ \$(record_starts) == 1 ]] && grep -q '^voxtype record stop' '$log' && toast_has 'Type mode ended done'"

for ending in "Cortana stop typing." "Cortana, stop recording." "cortana done" "Cortana, stop dictation." "Cortana exit." "Cortana, quit."; do
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

# Endings heard at the recording's pauses: the stub detector's checker runs the confirmation the real one would, its
# transcriber hearing each line of pause-text (see sandbox.sh).
pause_says() { printf '%s\n' "$@" >"$SANDBOX_DIR/pause-text"; }
pause_checks_done() { wait_for_count '^voxcmd-autostop pause-check done' "$log" "$1"; }
pause_checks_off() { rm -f "$SANDBOX_DIR/pause-text" "$SANDBOX_DIR/pause-recording"; }
still_recording() { [[ $(voxtype_now) == recording ]] && ! grep -qE '^voxtype record (stop|cancel)' "$log" && ! jq -e .ending "$session_json" >/dev/null; }
for ending in "Cortana stop." "Cortana, stop typing." "Cortana done." "Cortana exit." "Cortana, quit."; do
  pause_says "Hello world. $ending"
  sess_start "UNTIL_STOP Hello world. $ending"
  sess_wait
  check "'$ending' before a pause types the dictation without it" "session_gone && wtype_is 'wtype -- Hello world.' && grep -q 'pause check: the wake word' '$debug_log' && grep -q 'dictation: ended by voice (type)' '$debug_log' && toast_has 'Type mode ended done'"
done
pause_says "Secret words. Cortana, cancel."
sess_start "UNTIL_STOP Secret words. Cortana, cancel."
sess_wait
check "'Cortana, cancel.' before a pause types nothing" "session_gone && ! grep -q '^wtype' '$log' && grep -q '^voxtype record cancel' '$log'"
pause_says "Ship it. Cortana, send it."
sess_start "UNTIL_STOP Ship it. Cortana, send it."
sess_wait
check "'Cortana, send it.' before a pause types it, then presses Return" "session_gone && wtype_is 'wtype -- Ship it.' 'wtype -k Return'"
pause_says "Hello. Cortana stop. Thank you."
sess_start "UNTIL_STOP Hello. Cortana stop. Thank you."
sess_wait
check "the transcriber's 'Thank you.' after the ending does not hide it" "session_gone && wtype_is 'wtype -- Hello.'"
pause_says "Hello world. Cortana stop. Cortana stop."
sess_start "UNTIL_STOP Hello world. Cortana stop. Cortana stop."
sess_wait
check "a retried ending is cut with the first, leaving none behind" "session_gone && wtype_is 'wtype -- Hello world.'"
pause_says "Hello world. Cortana exit. Cortana, quit."
sess_start "UNTIL_STOP Hello world. Cortana exit. Cortana, quit."
sess_wait
check "retried exit and quit endings are cut too" "session_gone && wtype_is 'wtype -- Hello world.'"

for heard in "I asked Cortana about it." "Hello world." "Cortana." "Cortana, new paragraph."; do
  pause_says "$heard"
  sess_start "UNTIL_STOP $heard More."
  pause_checks_done 1
  check "a pause after '$heard' leaves the recording running" "still_recording"
  sess_voxcmd_env listen
  sess_wait
  check "and the voice key types all of it" "session_gone && wtype_is 'wtype -- $heard More.'"
done
check "the wake word with no ending after it is logged as such" "grep -q 'dictation: the wake word, not an ending' '$debug_log'"

pause_says "Hello. Cortana new paragraph." "Hello. Cortana new paragraph. More. Cortana stop."
sess_start "UNTIL_STOP Hello. Cortana new paragraph. More. Cortana stop."
sess_wait
pause_checks_done 2
check "of two pauses, the one after the ending ends it, once" "session_gone && wtype_is 'wtype -- Hello. Cortana new paragraph. More.' && [[ \$(grep -c '^voxtype record stop' '$log') == 1 ]]"

sess_env+=(SANDBOX_PAUSE_CHECKS_AT_ONCE=1)
pause_says "Words. Cortana stop." "WAKE Cortana, stop." "Words. Cortana stop."
sess_start "UNTIL_STOP Words. Cortana stop."
sess_wait
pause_checks_done 3
check "pause checks and a wake confirmation hearing the ending at once end it exactly once" "session_gone && wtype_is 'wtype -- Words.' && [[ \$(grep -cE '^voxtype record (stop|cancel)' '$log') == 1 && \$(grep -c 'dictation: ended by voice' '$debug_log') == 1 ]]"
pause_says "Words. Cortana cancel." "WAKE Cortana, stop."
sess_start "UNTIL_STOP Words. Cortana stop."
sess_wait
pause_checks_done 2
check "a cancel and a stop at once: one wins, and what is typed follows it" "session_gone && [[ \$(grep -cE '^voxtype record (stop|cancel)' '$log') == 1 ]] && if grep -q '^voxtype record cancel' '$log'; then ! grep -q '^wtype' '$log'; else wtype_is 'wtype -- Words.'; fi"
# The stub itself, as the daemon: of a stop and a cancel sent together to one recording, one acts and the other is ignored.
stub_pairs_not_ending_once=0
for _ in $(seq 40); do
  echo recording >"$XDG_RUNTIME_DIR/voxtype/state"
  : >"$log"
  SANDBOX_VOXTYPE_TURNS="$sess_turns" voxtype record stop &
  SANDBOX_VOXTYPE_TURNS="$sess_turns" voxtype record cancel &
  wait
  [[ $(grep -cE '^voxtype record (stop|cancel)' "$log") == 1 && $(grep -c '^voxtype ignored record' "$log") == 1 ]] || stub_pairs_not_ending_once=$((stub_pairs_not_ending_once + 1))
done
check "the voxtype stub acts on one of a stop and a cancel sent together, and ignores the other" "[[ $stub_pairs_not_ending_once == 0 ]]"
echo idle >"$XDG_RUNTIME_DIR/voxtype/state"

unset 'sess_env[-1]'

pause_says "AFTER_END Cortana cancel."
sess_start "UNTIL_STOP Kept words."
owner_is_listening
sess_voxcmd_env listen
sess_wait
pause_checks_done 1
check "a pause check that finishes after its recording ended does nothing" "session_gone && wtype_is 'wtype -- Kept words.' && ! grep -q '^voxtype record cancel' '$log'"

# The quiet after the ending runs out while its check still transcribes.
pause_says "Secret words. Cortana, cancel."
sess_start "IDLE Secret words. Cortana, cancel."
sess_wait
check "'Cortana, cancel.' heard as the quiet runs out types nothing" "session_gone && ! grep -q '^wtype' '$log' && grep -q '^voxtype record cancel' '$log' && ! grep -q '^voxtype record stop' '$log'"
pause_says "Hello world."
sess_start "IDLE Hello world."
sess_wait
check "while a check that heard no ending lets the quiet type it" "session_gone && wtype_is 'wtype -- Hello world.'"

pause_checks_off
sess_start "UNTIL_STOP Earlier words."
owner_is_listening
recording_now >"$SANDBOX_DIR/pause-recording"
sess_voxcmd_env listen
sess_wait
pause_says "Cortana stop."
sess_start "UNTIL_STOP Newer words."
pause_checks_done 1
check "a pause check naming an earlier recording leaves the new one running" "still_recording && grep -q 'heard in an earlier recording' '$debug_log'"
sess_voxcmd_env listen
sess_wait
pause_checks_off

sess_phrase="rapid mode"
pause_says "All done. Cortana, stop listening."
sess_start "type mode" "UNTIL_STOP All done. Cortana, stop listening." "tap beta"
sess_wait
check "'Cortana, stop listening.' before a pause types it and ends the whole session" "session_gone && wtype_is 'wtype -- All done.' && [[ \$(taps) == 0 && \$(record_starts) == 2 ]] && toast_has 'Rapid mode ended stopped'"
check "and only type mode's recording had its pauses checked" "[[ \$(grep -c '^voxcmd-autostop pause_check_recording=' '$log') == 1 ]]"
pause_checks_off
sess_phrase="type mode"

sess_run "CAP A long talk."
check "at the length limit it types what was said, ends the mode with a toast, and records nothing more" "session_gone && wtype_is 'wtype -- A long talk.' && [[ \$(record_starts) == 1 ]] && toast_has 'Type mode ended it reached its recording limit (295 s)'"
# type_bounds <idle secs> <max secs>: the TOML listen of type mode is static, so a copy of it with other numbers is how a
# test sets them.
type_bounds() {
  sed "s/^listen = .*/listen = { silence_secs = $1, max_secs = $2, no_speech_secs = $1 }/" \
    "$package/.config/voxcmd/integrations/typing.toml" >"$modes_config/integrations/typing.toml"
}
type_bounds 10 60
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
sess_run "CAP A long talk."
check "the limit toast names the limit that was set" "session_gone && wtype_is 'wtype -- A long talk.' && toast_has 'Type mode ended it reached its recording limit (1 min)'"
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
copy_shipped_integrations "$modes_config" typing
sess_run "IDLE Words, then quiet."
check "10 s of quiet after speech type what was said, as a stop would" "session_gone && wtype_is 'wtype -- Words, then quiet.' && toast_has 'Type mode ended typed after 10 s of quiet'"
sess_run SILENCE
check "10 s with no speech end the mode, typing nothing" "session_gone && ! grep -q '^wtype' '$log' && [[ \$(record_starts) == 1 ]] && toast_has 'Type mode ended nothing was said for 10 s'"
type_bounds 30 60
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
sess_run SILENCE
check "type mode's listen bounds set the detector's" "every_detector_logged no_speech_secs= no_speech_secs=30 && grep -q 'silence_secs=30\$' '$log' && grep -q 'max_secs=60\$' '$log'"
sess_env=(SANDBOX_ACTIVEWINDOW_JSON="$focused_window")
copy_shipped_integrations "$modes_config" typing

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
hold_in "$type_kind rapid" 2
check "type mode's hint says where it returns to" "[[ \$(jq -r .exit_hint '$session_json') == 'say cortana stop, or cortana cancel (back to Rapid mode)' ]]"
wake_heard "Cortana stop."
sess_wait
check "cortana stop leaves only type mode, back to rapid mode" "session_gone && wtype_is 'wtype -- Back again.' && [[ \$(taps) == 1 && \$(record_starts) == 4 ]]"
sess_start "type mode" "UNTIL_STOP All done. Cortana, stop listening." "tap beta"
hold_in "$type_kind rapid" 2
wake_heard "Cortana, stop listening."
sess_wait
check "cortana stop listening types it and ends the whole session" "session_gone && wtype_is 'wtype -- All done.' && [[ \$(taps) == 0 && \$(record_starts) == 2 ]] && toast_has 'Rapid mode ended stopped'"
sess_start HOLD
owner_is_listening
wake_heard "Cortana, stop."
check "a mode that is not one recording is never ended by a confirmation" "[[ \$(voxtype_now) == recording ]] && ! grep -qE '^voxtype record (stop|cancel)' '$log'"
sess_voxcmd_env session end
sess_wait
sess_start "type mode" "UNTIL_STOP Stopped words." "tap beta"
hold_in "$type_kind rapid" 2
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
hold_in "$type_kind rapid" 2
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
check "a recording whose type mode was re-created while it was handled is not typed" "! grep -q '^wtype' '$log' && grep -qE 'type: not typed|handle_turn not run: the session ended' '$debug_log'"

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
check "type mode logs lengths, never the text" "wtype_is 'wtype -- Hello private words.' && ! grep -q 'private' '$debug_log' && grep -q 'a transcript of 35 characters goes to session_turn' '$debug_log' && ! grep -v '^wtype ' '$log' | grep -q private"
check "and the transcript is not left on disk" "[[ ! -e '$XDG_RUNTIME_DIR/voxcmd/transcript.txt' ]]"

sess_env=()
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
