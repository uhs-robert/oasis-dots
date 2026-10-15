#!/usr/bin/env bash
# Tests for voxcmd's sequences, several steps in one phrase joined by "and then": order and waiting, what stops the
# rest, the one toast it sends, Stop Voice, the dry run; also what an action learns from a yes on the confirm card.
# run.sh runs this beside its own checks, in a sandbox of its own; run alone: home/voxcmd/tests/run-sequences.sh.
# Sequences inside voice sessions are in run-sessions.sh.
#
# voxcmd runs for real against the sandbox's stubs and a copy of the package whose card and picker are stubs that
# answer from files. A wait is observed by what its condition logs, never by sleeping.
# Read by name inside the strings check evals.
# shellcheck disable=SC2034
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
package=$(cd "$here/.." && pwd)
fixtures_dir=$here/fixtures
# shellcheck source-path=SCRIPTDIR source=../../../lib/check-lock.sh
. "$here/../../../lib/check-lock.sh"
check_lock_gate "voxcmd ${0##*/}" "$0" "$@"
if [ -z "${SANDBOX_DIR:-}" ]; then
  SANDBOX_CLIENTS_JSON=$(cat "$fixtures_dir/clients.json")
  SANDBOX_ACTIVEWINDOW_JSON=$(jq -c '.[] | select(.focusHistoryID == 0)' <<<"$SANDBOX_CLIENTS_JSON")
  SANDBOX_BINDS_JSON=$(cat "$fixtures_dir/binds.json")
  export SANDBOX_CLIENTS_JSON SANDBOX_ACTIVEWINDOW_JSON SANDBOX_BINDS_JSON
  # Installed apps come from the fixture's desktop entries alone; kitty and gnome-calendar must exist for "open a new kitty" and "open calendar" to start them.
  export XDG_DATA_HOME="$fixtures_dir" XDG_DATA_DIRS="$fixtures_dir" SANDBOX_EXTRA_STUBS="kitty gnome-calendar"
  unset VOXCMD_EXTRA_INTEGRATIONS
  exec "$here/sandbox.sh" "$0" "$@"
fi
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$here/lib.sh"

seq_pkg=$root/seq-pkg
seq_config=$root/config-seq
seq_bin=$seq_pkg/.local/bin/voxcmd
gate=$root/gate
mkdir -p "$seq_pkg" "$seq_config/integrations.d" "$seq_config/replacements.d"
cp -r "$package/.local" "$seq_pkg/.local"
for integration in apps calendar notifications answers rapid; do
  cp "$package/.config/voxcmd/integrations.d/$integration.sh" "$seq_config/integrations.d/"
done
# The card answers yes and the picker its first choice, unless $root/confirm-no or a $root/pick-answer says otherwise.
cat >"$seq_pkg/.local/bin/voxcmd-confirm" <<STUB
#!/bin/sh
echo "voxcmd-confirm \$*" >> "$log"
[ ! -e "$root/confirm-no" ]
STUB
cat >"$seq_pkg/.local/bin/voxcmd-pick" <<STUB
#!/bin/sh
echo "voxcmd-pick \$*" >> "$log"
answer=\$(cat "$root/pick-answer" 2>/dev/null || echo 0)
[ "\$answer" != CANCEL ] || exit 1
echo "\$answer"
STUB
chmod +x "$seq_pkg/.local/bin/voxcmd-confirm" "$seq_pkg/.local/bin/voxcmd-pick"

export SEQ_LOG=$log SEQ_GATE=$gate
cat >"$seq_config/integrations.d/seq.sh" <<'STUB'
name="Seq"
verbs=(
  "one one"
  "two two"
  "three three"
  "gate gate"
  "never never"
  "fail fail"
  "pick pick {target}"
  "take take {target}"
  "note note {target}"
)
free_text_actions=(take note)
candidates() {
  case "$1" in
  pick) echo '[{"id": "left", "label": "side left"}, {"id": "right", "label": "side right"}]' ;;
  note) echo '[]' ;;
  esac
}
declare -A actions=(
  [one]='echo "ran one" >> "$SEQ_LOG"'
  [two]='echo "ran two" >> "$SEQ_LOG"'
  [three]='echo "ran three" >> "$SEQ_LOG"'
  [gate]='echo "ran gate" >> "$SEQ_LOG"'
  [never]='echo "ran never" >> "$SEQ_LOG"'
  [fail]='echo "boom: the reason"; exit 1'
  [pick]='echo "ran pick $id" >> "$SEQ_LOG"'
  [take]='echo "ran take $target" >> "$SEQ_LOG"'
  [note]='echo "ran note" >> "$SEQ_LOG"'
)
# The condition logs each poll, so a test waits for polls instead of sleeping.
declare -A step_waits=(
  [gate]='echo poll >> "$SEQ_LOG"; [ -e "$SEQ_GATE" ]'
  [never]='echo poll >> "$SEQ_LOG"; false'
)
STUB
cat >"$seq_config/integrations.d/ask.sh" <<'STUB'
name="Ask"
confirm=1
verbs=("ask ask")
declare -A actions=([ask]='echo "ran ask" >> "$SEQ_LOG"')
STUB
cat >"$seq_config/integrations.d/priv.sh" <<'STUB'
name="Priv"
private_labels=1
verbs=("secret {target}")
candidates() { echo '[{"id": "x", "label": "SECRET-TEXT"}]'; }
declare -A actions=([secret]='echo "denied"; exit 1')
STUB

seq_env=()
seq_voxcmd() {
  env VOXCMD_CONFIG_DIR="$seq_config" VOXCMD_APP_SETTLE_SECS=0 VOXCMD_DEBUG=1 "${seq_env[@]}" "$seq_bin" "$@" >/dev/null 2>&1
}
# fresh: empties the logs and the state a test leaves behind.
fresh() {
  mkdir -p "$XDG_RUNTIME_DIR/voxcmd"
  : >"$log"
  : >"$debug_log"
  rm -f "$gate" "$root/confirm-no" "$root/pick-answer" "$SANDBOX_DIR/popup-state"
  seq_env=()
}
ran() { grep '^ran ' "$log" | sed 's/^ran //' | paste -sd,; }
# toasts <pattern>: how many notifications hold it, a multi-line body counting once for its first line.
toasts() { grep -c "^notify-send .*$1" "$log"; }
# "no match" toasts go through setsid, which the sandbox only logs. voxcmd starts it in the background, so the line can
# land after voxcmd has exited: a toast that should be there is waited for, and one that should not is looked for only
# once nothing the run started is left to log it.
detached_toast_has() { wait_for_line "^setsid .*$1" "$log"; }
no_detached_toast() { wait_until run_finished && ! grep -q "^setsid .*$1" "$log"; }
run_finished() { ! pgrep -f -- "$seq_bin( |\$)" >/dev/null && stub_calls_done; }
polls_reach() { wait_for_count "$1" "$log" "$2"; }
sequence_dir=$XDG_RUNTIME_DIR/voxcmd/sequences
sequence_files() { ls "$sequence_dir"/*.json 2>/dev/null; }
sequences_running() { [[ $(sequence_files | wc -l) == "$1" ]]; }

section "order"
fresh
seq_voxcmd "one and then two and then three"
check "steps run in order" "[[ \$(ran) == one,two,three ]]"
check "each step that succeeds keeps its own toast" "[[ \$(toasts 'Seq: one') == 1 && \$(toasts 'Seq: two') == 1 && \$(toasts 'Seq: three') == 1 ]]"
check "the sequence leaves no state behind" "[[ -z \$(sequence_files) ]] && ! ls '$XDG_RUNTIME_DIR'/voxcmd/discard.* >/dev/null 2>&1"
fresh
seq_status=0
seq_stderr=$(env VOXCMD_CONFIG_DIR="$seq_config" VOXCMD_APP_SETTLE_SECS=0 "$seq_bin" "one and then two" 2>&1 >/dev/null) || seq_status=$?
check "run from a terminal, a sequence that ran exits 0 and its cleanup trap raises no error" "[[ $seq_status == 0 && \$(ran) == one,two ]] && ! grep -q 'unbound variable' <<<\"\$seq_stderr\""
fresh
seq_voxcmd "One, then two."
check "a comma before then splits, whatever the case and the full stop" "[[ \$(ran) == one,two ]]"
fresh
seq_voxcmd "one then two"
check "a bare then does not split" "[[ -z \$(ran) ]] && detached_toast_has 'one then two'"
fresh
seq_voxcmd "Cortana, one and then two"
check "a leading wake word is stripped from the whole phrase" "[[ \$(ran) == one,two ]]"
fresh
seq_voxcmd "one and then"
check "a trailing and then runs the steps before it" "[[ \$(ran) == one ]]"

section "free text"
fresh
seq_voxcmd "take milk and then one"
check "a free-text action takes the rest of the phrase" "[[ \$(ran) == 'take milk and then one' ]]"
fresh
seq_voxcmd "one and then take milk and then two"
check "also as a later step, after which nothing else is split" "[[ \$(ran) == 'one,take milk and then two' ]]"
fresh
seq_voxcmd "one and then note something and then two"
check "a free-text step that matches nothing stops the rest, without quoting its words" "[[ \$(ran) == one ]] && detached_toast_has 'stopped at step 2 of 2' && ! grep -q something '$log'"

section "waiting"
fresh
seq_voxcmd "gate and then two" &
seq_pid=$!
polls_reach '^poll' 3
check "the next step does not run while the wait's condition fails" "[[ \$(ran) == gate ]]"
check "the sequence names itself for Stop Voice" "[[ \$(sequence_files | wc -l) == 1 ]] && process_running \$(jq -r .pid \$(sequence_files))"
touch "$gate"
wait "$seq_pid"
check "it runs once the condition holds" "[[ \$(ran) == gate,two ]]"
check "and the sequence file is gone" "[[ -z \$(sequence_files) ]]"

fresh
seq_env=(VOXCMD_STEP_TIMEOUT_SECS=0.3)
seq_voxcmd "never and then two and then three"
check "a wait that times out stops the rest" "[[ \$(ran) == never ]]"
check "with one error toast naming the step, the timeout and the steps not run" "[[ \$(toasts 'voxcmd: stopped at step 1 of 3') == 1 ]] && grep -q 'timed out after 0.3s' '$log' && grep -q '^2 more steps not run' '$log' && ! grep '^notify-send .*stopped at step' '$log' | grep -q -- --transient"

fresh
seq_voxcmd "gate and then two" &
seq_pid=$!
polls_reach '^poll' 3
seq_voxcmd stop
wait "$seq_pid"
check "Stop Voice during a wait ends the sequence without running the rest" "[[ \$(ran) == gate ]]"
check "and without a toast" "[[ \$(toasts 'stopped at step') == 0 ]] && no_detached_toast 'stopped at step'"
check "leaving no state behind" "[[ -z \$(sequence_files) ]] && ! ls '$XDG_RUNTIME_DIR'/voxcmd/discard.* >/dev/null 2>&1"

fresh
seq_voxcmd "gate and then two" &
first_pid=$!
seq_voxcmd "gate and then three" &
second_pid=$!
wait_until sequences_running 2
polls_reach '^poll' 6
seq_voxcmd stop
wait "$first_pid" "$second_pid"
check "Stop Voice ends every running sequence, not only the newest" "[[ \$(ran) == gate,gate ]] && [[ -z \$(sequence_files) ]]"
mkdir -p "$sequence_dir"
echo '{"pid": 999999, "start": "1"}' >"$sequence_dir/999999.json"
seq_voxcmd stop
check "and a file left by a dead sequence is cleaned up" "[[ -z \$(sequence_files) ]]"

section "stopping"
fresh
seq_voxcmd "one and then fail and then two"
check "a failing step stops the rest" "[[ \$(ran) == one ]]"
check "with one error toast holding its output, and not the step's own" "[[ \$(toasts 'voxcmd: stopped at step 2 of 3') == 1 && \$(toasts 'voxcmd failed') == 0 ]] && grep -q 'boom: the reason' '$log' && grep -q '^1 more step not run' '$log'"
fresh
seq_voxcmd "one and then bogus words and then two"
check "a step that matches nothing stops the rest" "[[ \$(ran) == one ]]"
check "with one toast quoting its words, carrying the Voice Help button, and no no-match toast of its own" "detached_toast_has 'stopped at step 2 of 3' && detached_toast_has 'no match for \"bogus words\"' && no_detached_toast 'voxcmd: no match'"
fresh
echo CANCEL >"$root/pick-answer"
seq_voxcmd "one and then pick side and then two"
check "a cancelled picker stops the rest" "[[ \$(ran) == one ]] && [[ \$(toasts 'Stopped at step 2 of 3: cancelled') == 1 ]]"
fresh
seq_voxcmd "one and then pick side and then two"
check "a picker answered lets it go on" "[[ \$(ran) == 'one,pick left,two' ]]"
fresh
: >"$root/confirm-no"
seq_voxcmd "one and then ask and then two"
check "a declined confirm stops the rest" "[[ \$(ran) == one ]] && [[ \$(toasts 'Stopped at step 2 of 3: not confirmed') == 1 ]]"
fresh
seq_voxcmd "one and then ask and then two"
check "a confirmed one runs, and the steps after it" "[[ \$(ran) == one,ask,two ]]"
fresh
seq_voxcmd "one and then secret text and then two"
check "a private step's label reaches neither a toast nor the log" "[[ \$(ran) == one ]] && [[ \$(toasts 'voxcmd: stopped at step 2 of 3') == 1 ]] && grep -q 'denied' '$log' && ! grep -q SECRET-TEXT '$log' '$debug_log'"

section "refused"
fresh
seq_voxcmd "one and then two and then three and then one and then two and then three"
check "more than 5 steps run nothing" "[[ -z \$(ran) ]] && [[ \$(toasts 'Nothing ran: a phrase can have at most 5 steps') == 1 ]]"
fresh
seq_voxcmd "one and then two and then three and then one and then two"
check "5 steps run" "[[ \$(ran) == one,two,three,one,two ]]"
fresh
seq_voxcmd "rapid mode and then one"
check "a mode switch before the last step runs nothing" "[[ -z \$(ran) ]] && [[ \$(toasts 'Nothing ran: a mode switch can only be the last step') == 1 ]] && [[ ! -e '$XDG_RUNTIME_DIR/voxcmd/session.json' ]]"

section "apps and popups"
new_window='{"address":"0x1004","class":"kitty","title":"new"}'
slack_window='{"address":"0x1002","class":"Slack","title":"general - Acme - Slack"}'
other_class_window='{"address":"0x1005","class":"org.example.Other","title":"new"}'
# gated_run <phrase>: runs it with the active window flipping only once $gate exists, waits for voxcmd to poll while it
# does not, and leaves ran() as it was at that point in $before_gate.
gated_run() {
  seq_voxcmd "$1" &
  seq_pid=$!
  polls_reach 'activewindow gated' 3
  before_gate=$(ran)
  touch "$gate"
  wait "$seq_pid"
}
fresh
seq_env=(SANDBOX_ACTIVEWINDOW_AFTER_LAUNCH_JSON="$new_window" SANDBOX_ACTIVEWINDOW_GATE="$gate")
gated_run "open a new kitty and then one"
check "a new window holds the next step until another window than the one before has focus" "[[ -z \$before_gate && \$(ran) == one ]] && grep -n -e '^setsid' -e '^ran one' '$log' | cut -d: -f2 | head -n1 | grep -q setsid"
fresh
seq_env=(VOXCMD_STEP_TIMEOUT_SECS=0.3)
seq_voxcmd "open a new kitty and then one"
check "and times out when none does" "[[ -z \$(ran) ]] && [[ \$(toasts 'voxcmd: stopped at step 1 of 2') == 1 ]]"
fresh
seq_env=(SANDBOX_ACTIVEWINDOW_AFTER_FOCUS_JSON="$slack_window" SANDBOX_ACTIVEWINDOW_GATE="$gate")
gated_run "open slack and then one"
check "opening a running app holds the next step until its window has focus" "[[ -z \$before_gate && \$(ran) == one ]]"
fresh
seq_env=(SANDBOX_ACTIVEWINDOW_AFTER_LAUNCH_JSON="$other_class_window" SANDBOX_ACTIVEWINDOW_GATE="$gate")
gated_run "open calendar and then one"
check "an app whose window class is not its desktop id counts once focus has moved to a new window" "[[ -z \$before_gate && \$(ran) == one ]]"
fresh
seq_env=(VOXCMD_STEP_TIMEOUT_SECS=0.3)
seq_voxcmd "open firefox and then one"
check "and times out when another window has it" "[[ -z \$(ran) ]] && grep -q 'timed out after 0.3s' '$log'"
fresh
seq_env=(SANDBOX_POPUP_OPENS=1)
seq_voxcmd "what's on my calendar tomorrow and then one"
check "a day view waits for the clock popup" "[[ \$(ran) == one ]]"
fresh
seq_env=(SANDBOX_POPUP_OPENS=1)
seq_voxcmd "open notifications and then one"
check "opening the notification center waits for its popup" "[[ \$(ran) == one ]]"
fresh
seq_env=(SANDBOX_POPUP_OPENS=1)
seq_voxcmd "what's the weather and then one"
check "the weather waits for its popup" "[[ \$(ran) == one ]]"
fresh
seq_env=(VOXCMD_STEP_TIMEOUT_SECS=0.3)
seq_voxcmd "what's the weather and then one"
check "and times out when the popup never opens" "[[ -z \$(ran) ]] && grep -q 'timed out after 0.3s' '$log'"
fresh
echo "opening notifications" >"$SANDBOX_DIR/popup-state"
seq_env=(VOXCMD_STEP_TIMEOUT_SECS=0.3)
seq_voxcmd "one and then two"
check "the default wait times out while a popup is still opening" "[[ \$(ran) == one ]] && grep -q 'timed out after 0.3s' '$log'"
fresh
echo "open notifications" >"$SANDBOX_DIR/popup-state"
seq_voxcmd "one and then two"
check "but not for a popup that is open" "[[ \$(ran) == one,two ]]"

section "a confirmed keybind"
# Keybinds alone, so no other integration takes the phrases.
keybinds_config=$root/config-keybinds
mkdir -p "$keybinds_config/integrations.d"
cp "$package/.config/voxcmd/integrations.d/keybinds.sh" "$keybinds_config/integrations.d/"
keybind_voxcmd() { env VOXCMD_CONFIG_DIR="$keybinds_config" "$seq_bin" "$@" >/dev/null 2>&1; }
skips_power_prompt() { grep -q "call power run" "$log"; }
runs_bind() { grep -qF "getregistry()[$1]" "$log"; }
fresh
keybind_voxcmd "power off the computer"
check "a yes on the card runs the Power Off bind past the bar's own prompt" "grep -q '^voxcmd-confirm .*Power Off' '$log' && runs_bind 133 && skips_power_prompt"
fresh
: >"$root/confirm-no"
keybind_voxcmd "power off the computer"
check "a no runs nothing" "! grep -q 'getregistry()' '$log'"
fresh
keybind_voxcmd "toggle auto-lock"
check "a bind voxcmd did not confirm runs unchanged" "! grep -q '^voxcmd-confirm' '$log' && runs_bind 134 && ! skips_power_prompt"

section "dry run"
fresh
before=$(cat "$log")
out=$(env VOXCMD_CONFIG_DIR="$seq_config" "$seq_bin" --dry-run "one and then gate and then take milk and then two" 2>&1)
check "a dry run prints the sequence header, each step, its wait and what a free-text action took" "grep -q '^sequence: *3 steps' <<<\"\$out\" && grep -q '^step 2 of 3' <<<\"\$out\" && grep -q '^waits for: .*poll' <<<\"\$out\" && grep -q 'free-text action takes the rest' <<<\"\$out\" && grep -q '^waits for: *nothing, it is the last step' <<<\"\$out\""
check "and touches neither the log of calls nor anything else" "[[ -z \$(ran) && \$(cat '$log') == \"\$before\" ]] && [[ -z \$(sequence_files) ]]"
out=$(env VOXCMD_CONFIG_DIR="$seq_config" "$seq_bin" --dry-run "rapid mode and then one" 2>&1)
check "a refused phrase prints result: refused" "grep -q '^result: *refused' <<<\"\$out\""

finish
