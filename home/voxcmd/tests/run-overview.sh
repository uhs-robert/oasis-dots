#!/usr/bin/env bash
# Tests for voxcmd's overview integration (overview.sh): phrases read against a fixture overview.json, the actions sent
# to the bar's `overview act`, the count before a close, the session that attaches while the overview is open and the one
# that ends with it. run.sh runs this beside its own checks, in a sandbox of its own; run alone:
# home/voxcmd/tests/run-overview.sh
#
# voxcmd runs for real against the sandbox's stubs: its bar answers `overview state` from a file and logs every `overview
# act`, and the confirm card and picker are stubs that answer from files.
# Read by name inside the strings check evals.
# shellcheck disable=SC2034
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
package=$(cd "$here/.." && pwd)
fixtures_dir=$here/fixtures
# shellcheck source-path=SCRIPTDIR source=window-fixtures.sh
source "$here/window-fixtures.sh"
[ -n "${SANDBOX_DIR:-}" ] || exec "$here/sandbox.sh" "$0" "$@"
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$here/lib.sh"

ov_pkg=$root/ov-pkg
ov_config=$root/config-ov
ov_voxcmd=$ov_pkg/tests/bin/voxcmd
ov_turns=$root/turns
mkdir -p "$ov_pkg" "$ov_config/integrations.d" "$ov_config/replacements.d" "$XDG_RUNTIME_DIR/voxcmd" "$XDG_RUNTIME_DIR/voxtype"
cp -r "$package/.local" "$ov_pkg/.local"
link_voxcmd_shim "$ov_pkg"
ln -sf "$SANDBOX_DIR/bin/voxcmd-autostop" "$ov_pkg/.local/bin/voxcmd-autostop"
for integration in apps keybinds overview rapid; do
  cp "$package/.config/voxcmd/integrations.d/$integration.sh" "$ov_config/integrations.d/"
done
# Overview, Rapid and Keybinds are TOML too: the Rust build takes the shipped file over the bash copy the bash build needs.
copy_shipped_integrations "$ov_config" keybinds overview rapid
# The confirm card answers yes unless $root/confirm-no exists.
cat >"$ov_pkg/.local/bin/voxcmd-confirm" <<STUB
#!/bin/sh
echo "voxcmd-confirm \$*" >> "$log"
[ ! -e "$root/confirm-no" ]
STUB
chmod +x "$ov_pkg/.local/bin/voxcmd-confirm"
stub_sleep=$root/stub-sleep
cp "$(command -v sleep)" "$stub_sleep"
trap 'pkill -f "$stub_sleep" 2>/dev/null; rm -rf "$root"' EXIT

overview_json=$XDG_RUNTIME_DIR/voxcmd/overview.json
overview_state=$SANDBOX_DIR/overview-state
session_json=$XDG_RUNTIME_DIR/voxcmd/session.json

# The attach after an action starts a session whose watcher listens, and a mode's ended hook (closing the overview) runs
# in the background after it: every run ends when both are gone, so nothing of one lands in the next.
ov_wait() { wait_until watchers_and_hooks_gone || echo "   voxcmd still running after ${test_wait_secs}s"; }
watchers_and_hooks_gone() { watchers_gone && ended_hooks_gone; }
# ov_run <turn>... -- <phrase>: the overview is open on the fixture, the turns are what a session hears, the phrase is said.
ov_state=open
ov_run() {
  # A skipped section's checks never read this run, and its waits return at once (wait_until), so a run there would leave
  # its session's watchers to land their calls in the log of the first run of a section that is kept.
  [ "$skipping_section" = 0 ] || return 0
  local turns=()
  while [ "$1" != -- ]; do
    turns+=("$1")
    shift
  done
  shift
  printf '%s\n' "${turns[@]}" >"$ov_turns"
  [ "${#turns[@]}" -gt 0 ] || : >"$ov_turns"
  mkdir -p "$(dirname "$debug_log")"
  : >"$log"
  : >"$debug_log"
  rm -f "$session_json" "$root/confirm-no"
  [ -z "${ov_confirm_no:-}" ] || touch "$root/confirm-no"
  echo idle >"$XDG_RUNTIME_DIR/voxtype/state"
  if [ -n "${ov_late_file:-}" ]; then
    rm -f "$overview_json"
    # As the bar writes it: late, here only once the session's first listen has started without it. A GATED turn is
    # spoken only after that, so the turn always finds the snapshot.
    rm -f "$SANDBOX_DIR/voxtype-release"
    (wait_for_line 'listen: recording started' "$debug_log" && cp "$fixtures_dir/overview.json" "$overview_json" &&
      : >"$SANDBOX_DIR/voxtype-release") &
  else
    cp "${ov_fixture:-$fixtures_dir/overview.json}" "$overview_json"
  fi
  echo "$ov_state" >"$overview_state"
  env SANDBOX_SETSID_RUN=1 SANDBOX_VOXTYPE_TURNS="$ov_turns" SANDBOX_AUTOSTOP_SLEEP="$stub_sleep" VOXCMD_CONFIG_DIR="$ov_config" \
    VOXCMD_APP_SETTLE_SECS=0 VOXCMD_DEBUG=1 SANDBOX_VOXTYPE_SPEAK_SECS=0 "$ov_voxcmd" run "$@" >/dev/null 2>&1
  ov_wait
  wait
}
acts() { grep '^qs-ipc call overview act' "$log" | sed -e 's/^qs-ipc call overview act //' -e 's/ *$//'; }
session_gone() { [[ ! -e $session_json ]]; }

section "overview: phrases while it is open"
# Each phrase's act, against the fixture: windows 1-5 (1-3 on workspace 1 on DP-1, 4-5 on workspace 2 on HDMI-A-1), 2 and 4
# marked, DP-1 on the left.
while IFS='|' read -r phrase expected; do
  ov_run -- "$phrase"
  check "'$phrase' acts '$expected'" "[[ \$(acts | head -n 1) == '$expected' ]]"
done <<'CASES'
two and four|mark aaa2 aaa4
mark one, three and five|mark aaa1 aaa3 aaa5
two|mark aaa2
unmark three|unmark aaa3
clear|clear
move two to workspace three|move 3 aaa2
move two and four to the left monitor|send DP-1 aaa2 aaa4
move four to the right monitor|send HDMI-A-1 aaa4
move two to monitor two|send HDMI-A-1 aaa2
move the marked windows to workspace 5|move 5
move the marked windows to workspace five|move 5
close the marked windows|close
move to workspace 7|move 7
move them to workspace 7|move 7
move these to workspace seven|move 7
move it to workspace number 7|move 7
move the selected windows to work space 7|move 7
send the marked windows to workspace 3|move 3
put them on workspace 4|move 4
move to the left monitor|send DP-1
send them to the right screen|send HDMI-A-1
send the selected window to the right monitor|send HDMI-A-1
close them|close
close these|close
close it|close
close the selected|close
close the selected window|close
mark two, no wait, mark four|mark aaa4
um, okay so mark two|mark aaa2
close two|close aaa2
focus two|focus aaa2
go to four|focus aaa4
go to workspace three|workspace 3
workspace two|workspace 2
move workspace three to the right monitor|workspace_to_monitor 3 HDMI-A-1
swap workspaces two and five|swap_workspaces 2 5
swap workspace 1 with 2|swap_workspaces 1 2
second|mark aaa2
mark first and third|mark aaa1 aaa3
mark the 2nd and 4th windows|mark aaa2 aaa4
focus the second window|focus aaa2
close the third one|close aaa3
unmark the fifth one|unmark aaa5
move the second window to the third workspace|move 3 aaa2
move to the twelfth workspace|move 12
move two to workspace twenty first|move 21 aaa2
go to the first workspace|workspace 1
go to workspace third|workspace 3
workspace 3rd|workspace 3
go to the 2nd desktop|workspace 2
move the third workspace to the right monitor|workspace_to_monitor 3 HDMI-A-1
swap the second and fifth workspaces|swap_workspaces 2 5
swap the 1st and 2nd workspaces|swap_workspaces 1 2
CASES

section "overview: collisions and what it leaves alone"
ov_run -- "close two"
check "close two goes to the overview, not Apps' close" "[[ \$(acts) == 'close aaa2' ]] && ! grep -q 'hyprctl dispatch.*window.close' '$log'"
ov_run -- "go to workspace 3"
check "go to workspace 3 goes to the overview, not Keybinds" "[[ \$(acts) == 'workspace 3' ]] && ! grep -q 'hyprctl dispatch' '$log'"
ov_run -- "focus the ninth window"
check "an ordinal past the windows shown is an error toast and no act" "[[ -z \$(acts) ]] && grep -q '^notify-send .*no window 9' '$log'"
ov_run -- "go to the 2th workspace"
check "an ordinal without its own suffix names nothing" "[[ -z \$(acts) ]]"
ov_run -- "open firefox"
check "a phrase that is not about the overview is routed as usual" "[[ -z \$(acts) ]] && grep -q 'hyprctl dispatch.*focus' '$log'"
ov_run -- "move nine to workspace 2"
check "a number the overview does not show is an error toast and no act" "[[ -z \$(acts) ]] && grep -q '^notify-send .*no window 9' '$log'"
ov_run -- "move two to the top monitor"
check "a position no monitor has is an error toast and no act" "[[ -z \$(acts) ]] && grep -q '^notify-send .*no top monitor' '$log'"
ov_state=closed
ov_run -- "two and four"
check "with the overview closed nothing reaches it" "[[ -z \$(acts) ]]"
ov_run -- "close two"
check "and close two is Apps' phrase again" "[[ -z \$(acts) ]]"
ov_state=open

section "overview: closing asks first, with a count"
ov_run -- "close the marked windows"
check "the card says how many" "grep -q '^voxcmd-confirm .*Close 2 windows?' '$log'"
check "and the windows are closed once it is answered yes" "[[ \$(acts) == 'close' ]]"
ov_run -- "close two"
check "one window is counted too" "grep -q '^voxcmd-confirm .*Close 1 window?' '$log'"
ov_confirm_no=1
ov_run -- "close two and four"
ov_confirm_no=
check "a no from the card closes nothing" "[[ -z \$(acts) ]]"
ov_run -- "mark two and four"
check "marking asks nothing" "! grep -q '^voxcmd-confirm' '$log'"

section "overview: opening and the session"
ov_state=closed
ov_run "done" -- "show workspaces"
check "show workspaces opens the overview" "grep -q '^qs-ipc call overview open' '$log'"
check "and the session is the overview's, until done" "session_gone && grep -q 'session: overview begins' '$debug_log'"
check "done closes the overview too" "wait_for_line '^qs-ipc call overview close' '$log'"
for word in "exit" "stop" "cancel" "quit"; do
  ov_state=closed
  ov_run "$word" "close two" -- "show workspaces"
  check "bare '$word' closes the overview and ends the session, acting on nothing" "session_gone && wait_for_line '^qs-ipc call overview close' '$log' && [[ -z \$(acts) ]] && ! grep -q '^playerctl' '$log'"
done
ov_state=closed
ov_run -- "open overview"
check "open overview does too" "grep -q '^qs-ipc call overview open' '$log'"
check "a session that hears nothing ends and leaves the overview open" "session_gone && ! grep -q '^qs-ipc call overview close' '$log'"

# "Show numbers" attaches a session only while the overview is up; closed, it is left unmatched.
ov_state=closed
ov_run -- "show numbers"
check "show numbers with the overview closed starts no session" "! grep -q 'session: overview begins' '$debug_log' && [[ -z \$(acts) ]]"
ov_state=open
ov_run -- "show numbers"
check "show numbers with the overview open attaches the session" "grep -q 'session: overview begins' '$debug_log'"

# A special workspace's name may hold spaces, which act's argument split would cut: references travel percent-encoded.
special_fixture=$root/overview-special.json
jq -c '.special = true | .items |= map(select(.kind == "workspace")) | .items[0].id = "sp:project scratch" | .items[1].id = "sp:50%"' "$fixtures_dir/overview.json" >"$special_fixture"
ov_fixture=$special_fixture
ov_run -- "go to workspace 1"
check "a spaced special workspace is one argument" "[[ \$(acts) == 'workspace sp:project%20scratch' ]]"
ov_run -- "swap workspaces 1 and 2"
check "a swap carries both references encoded" "[[ \$(acts) == 'swap_workspaces sp:project%20scratch sp:50%25' ]]"
ov_fixture=

# The bar writes overview.json after the overview is open, so the first listen sees a stale or missing snapshot.
ov_state=closed
ov_late_file=1
ov_run "GATED done" -- "show workspaces"
ov_late_file=
check "the session survives its first listen while the snapshot is still being written" "! grep -q 'screen is gone\|its screen closed' '$debug_log' '$log' && grep -q '^qs-ipc call overview close' '$log'"
check "and its first turn was heard by the overview session" "grep -q 'listen: recording started' '$debug_log' && grep -q 'Overview ended done' '$log'"

# The owner opened it by key: the first phrase heard goes to it and the session attaches.
ov_state=open
ov_run four "close overview" -- "two"
check "a phrase spoken while the overview is open attaches the session" "grep -q 'session: overview begins' '$debug_log'"
check "its turns go to the overview" "[[ \$(acts | paste -sd,) == 'mark aaa2,mark aaa4' ]]"
check "close overview ends the session and closes the overview" "session_gone && wait_for_line '^qs-ipc call overview close' '$log'"
ov_run "exit, exit overview" -- "two"
check "a turn that repeats itself runs its last attempt: exit, exit overview leaves" "session_gone && wait_for_line '^qs-ipc call overview close' '$log'"
ov_run "mark four, no wait, mark five" -- "two"
check "a spoken correction in a turn marks the corrected window only" "[[ \$(acts | paste -sd,) == 'mark aaa2,mark aaa5' ]]"
ov_run four five -- "two"
check "a turn that names no overview thing is not understood, not run as something else" "[[ \$(acts | paste -sd,) == 'mark aaa2,mark aaa4,mark aaa5' ]]"
ov_run "open firefox" four -- "two"
check "an unknown phrase in the session is not routed to other integrations" "[[ \$(acts | paste -sd,) == 'mark aaa2,mark aaa4' ]] && ! grep -q 'hyprctl dispatch' '$log'"
ov_run "close two" -- "mark two"
check "the confirm card works inside the session" "grep -q '^voxcmd-confirm .*Close 1 window?' '$log' && [[ \$(acts | paste -sd,) == 'mark aaa2,close aaa2' ]]"
ov_run "focus two" four -- "two"
check "focusing a window ends the session with the overview" "session_gone && [[ \$(acts | paste -sd,) == 'mark aaa2,focus aaa2' ]]"
# Opened by key, with no session yet: the focus attaches one, and the overview it closes ends it as expected, not as a failure.
ov_state=open
ov_run -- "focus two and then open firefox"
check "a focus that ends the session it started is a success, so the next step runs" "[[ \$(acts) == 'focus aaa2' ]] && grep -q 'hyprctl dispatch.*focus' '$log' && ! grep -q 'could not listen' '$debug_log'"
# The bar is still hiding when the act returns: only overview_act's wait for it ends the session before the next turn.
SANDBOX_OVERVIEW_CLOSE_LAG=3 ov_run "focus two" four -- "two"
check "a focus act waits for the bar to hide, so the session ends before the next turn" "session_gone && [[ \$(acts | paste -sd,) == 'mark aaa2,focus aaa2' ]]"

# The owner closes the overview by key while the session listens: the next listen ends it.
printf '%s\n' four five >"$ov_turns"
: >"$log"
: >"$debug_log"
rm -f "$session_json"
cp "$fixtures_dir/overview.json" "$overview_json"
echo open >"$overview_state"
(
  wait_for_line 'overview act mark aaa4' "$log" && echo closed >"$overview_state"
) &
closer=$!
env SANDBOX_SETSID_RUN=1 SANDBOX_VOXTYPE_TURNS="$ov_turns" SANDBOX_AUTOSTOP_SLEEP="$stub_sleep" VOXCMD_CONFIG_DIR="$ov_config" \
  VOXCMD_APP_SETTLE_SECS=0 VOXCMD_DEBUG=1 SANDBOX_VOXTYPE_SPEAK_SECS=0 "$ov_voxcmd" run two >/dev/null 2>&1
ov_wait
wait "$closer"
check "closing the overview by key ends the session" "session_gone && [[ \$(acts | paste -sd,) == 'mark aaa2,mark aaa4' ]] && grep -q 'its screen closed' '$log'"
check "and leaves the closed overview alone" "! grep -q '^qs-ipc call overview close' '$log'"

# The overview closes while a turn is recorded and that turn opens another mode: the new mode listens once, itself.
printf '%s\n' "GATED rapid mode" HOLD >"$ov_turns"
: >"$log"
: >"$debug_log"
rm -f "$session_json" "$SANDBOX_DIR/voxtype-release"
cp "$fixtures_dir/overview.json" "$overview_json"
echo open >"$overview_state"
(
  wait_for_line '^voxtype record start' "$log" && echo closed >"$overview_state" && : >"$SANDBOX_DIR/voxtype-release"
) &
closer=$!
env SANDBOX_SETSID_RUN=1 SANDBOX_VOXTYPE_TURNS="$ov_turns" SANDBOX_AUTOSTOP_SLEEP="$stub_sleep" VOXCMD_CONFIG_DIR="$ov_config" \
  VOXCMD_APP_SETTLE_SECS=0 VOXCMD_DEBUG=1 SANDBOX_VOXTYPE_SPEAK_SECS=0 "$ov_voxcmd" run two >/dev/null 2>&1
wait "$closer"
wait_for_line 'session: rapid begins' "$debug_log"
# A second listen would come from the watcher that heard "rapid mode", so once it is gone there can be none.
wait_until_gone "$(sed -n 's/.* listen: recording started, watcher \([0-9]*\) .*/\1/p' "$debug_log" | head -n 1)"
rm -f "$SANDBOX_DIR/voxtype-release"
check "the mode the turn opened is the open session" "[[ \$(jq -r .kind '$session_json') == rapid ]]"
check "with one listen of its own, not a second one on top, and no second listen attempt" "! grep -q 'another listen took over' '$debug_log' && [[ \$(grep -c '^voxtype record start' '$log') == 2 ]] && ! grep -q 'microphone could not be opened' '$log'"
env VOXCMD_CONFIG_DIR="$ov_config" "$ov_voxcmd" session end >/dev/null 2>&1
ov_wait

finish
