#!/usr/bin/env bash
# Tests for voxcmd's monitor phrases (monitors.sh): which monitor each word names on several layouts, the dispatch that
# follows, phrases that must keep their old route, and that the words agree with the Quickshell overview's rule
# (overview/Voice.js, mirrored by monitor-places.jq). run.sh runs this beside its own checks; run alone:
# home/voxcmd/tests/run-monitors.sh
# shellcheck disable=SC2034
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
package=$(cd "$here/.." && pwd)
fixtures_dir=$here/fixtures
layouts_dir=$fixtures_dir/monitors
if [ -z "${SANDBOX_DIR:-}" ]; then
  SANDBOX_CLIENTS_JSON=$(cat "$fixtures_dir/clients.json")
  SANDBOX_ACTIVEWINDOW_JSON=$(jq -c '.[] | select(.focusHistoryID == 0)' <<<"$SANDBOX_CLIENTS_JSON")
  SANDBOX_BINDS_JSON=$(cat "$fixtures_dir/binds.json")
  export SANDBOX_CLIENTS_JSON SANDBOX_ACTIVEWINDOW_JSON SANDBOX_BINDS_JSON
  export XDG_DATA_HOME="$fixtures_dir" XDG_DATA_DIRS="$fixtures_dir"
  unset VOXCMD_EXTRA_INTEGRATIONS
  exec "$here/sandbox.sh" "$0" "$@"
fi
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$here/lib.sh"
# shellcheck source=/dev/null # the resolver is a share file; its functions are the ones checked here
source "$package/.local/share/voxcmd/monitor-words.sh"

# id_order_slots <layout>: the slot lookup a layout answers when none is given: the monitors in id order.
id_order_slots() {
  jq -r '[.[] | select(.disabled | not)] | sort_by(.id) | map(.name) | join(" ")' "$layouts_dir/$1.json"
}

# dispatches <layout> <phrase>: the hyprctl dispatches the phrase causes on that layout, one per line. SANDBOX_MONITOR_SLOTS
# overrides the slot lookup; set empty, the lookup answers nothing.
dispatches() {
  local slots
  slots="${SANDBOX_MONITOR_SLOTS-$(id_order_slots "$1")}"
  : >"$log"
  SANDBOX_MONITOR_SLOTS=$slots SANDBOX_MONITORS_JSON=$(cat "$layouts_dir/$1.json") voxcmd "$2" >/dev/null 2>&1
  sed -n 's/^hyprctl dispatch //p' "$log"
}
# named_of <words> <layout> <slots>: what monitor_named answers for the words on a layout, given the slot lookup's answer.
named_of() {
  monitor_named "$1" "$(jq -c --arg slots "$3" -f "$package/.local/share/voxcmd/monitor-places.jq" "$layouts_dir/$2.json")"
}
focus_of() { echo "hl.dsp.focus({ monitor = '$1' })"; }
move_of() { echo "hl.dsp.window.move({ window = 'address:$(jq -r .address <<<"$SANDBOX_ACTIVEWINDOW_JSON")', monitor = '$1', follow = false })"; }

section "monitors: which monitor a word names"
# layout|phrase|monitor focused ("-" when the phrase must do nothing)
while IFS='|' read -r layout phrase expected; do
  if [ "$expected" = - ]; then
    check "$layout: '$phrase' does nothing" "[[ -z \$(dispatches '$layout' '$phrase') ]]"
  else
    check "$layout: '$phrase' focuses $expected" "[[ \$(dispatches '$layout' '$phrase') == \$(focus_of '$expected') ]]"
  fi
done <<'CASES'
owner|go to the left monitor|DP-8
owner|focus the center monitor|HDMI-A-1
owner|switch to the centre screen|HDMI-A-1
owner|take me to the middle display|HDMI-A-1
owner|go to the right monitor|DP-13
owner|go to the bottom monitor|eDP-1
owner|focus the laptop screen|eDP-1
owner|go to the built in display|eDP-1
owner|go to the internal monitor|eDP-1
owner|go to the top left monitor|DP-8
owner|go to the top right monitor|DP-13
owner|go to the top monitor|-
owner|go to the bottom left monitor|-
owner|go to monitor two|DP-8
owner|go to the third monitor|HDMI-A-1
owner|go to monitor number four|DP-13
owner|go to monitor nine|-
owner|go to the first monitor|eDP-1
owner|go to the second screen|DP-8
owner|focus the 2nd display|DP-8
owner|go to the fourth monitor|DP-13
owner|go to the 4th monitor|DP-13
owner|go to the tenth monitor|-
owner|go to the 10th monitor|-
owner_real|go to the left monitor|DP-8
owner_real|go to the center monitor|HDMI-A-1
owner_real|go to the right monitor|DP-13
owner_real|go to the bottom monitor|eDP-1
laptop|go to the laptop monitor|eDP-1
laptop|go to the left monitor|-
laptop|go to the center monitor|-
laptop|go to monitor one|eDP-1
laptop|go to monitor two|-
laptop|go to the second monitor|-
laptop|go to the 2nd display|-
laptop|go to the 10th monitor|-
side_by_side|go to the left monitor|DP-1
side_by_side|go to the right monitor|DP-2
side_by_side|go to the center monitor|-
side_by_side|go to the second monitor|DP-2
side_by_side|go to the third monitor|-
side_by_side|go to the top monitor|-
side_by_side|go to the laptop monitor|-
stacked|go to the top monitor|DP-1
stacked|go to the bottom monitor|DP-2
stacked|go to the left monitor|-
grid|go to the top left monitor|DP-1
grid|go to the bottom right monitor|DP-4
grid|go to the left monitor|-
five_in_a_row|go to the left monitor|DP-1
five_in_a_row|go to the right monitor|DP-5
five_in_a_row|go to the center monitor|-
CASES

section "monitors: slots follow the slot lookup"
check "monitor two is the second slot Hyprland names, not the second monitor" "[[ \$(SANDBOX_MONITOR_SLOTS='HDMI-A-1 - eDP-1 DP-8 DP-13' dispatches owner 'go to monitor three') == \$(focus_of eDP-1) ]]"
check "an empty slot names nothing" "[[ -z \$(SANDBOX_MONITOR_SLOTS='HDMI-A-1 - eDP-1 DP-8 DP-13' dispatches owner 'go to monitor two') ]]"
check "a monitor the lookup does not list has no slot, so monitor two is not guessed" "[[ -z \$(SANDBOX_MONITOR_SLOTS='HDMI-A-1 - eDP-1' dispatches owner 'go to monitor two') ]]"
check "a monitor the lookup does not list says it cannot tell which is slot two" "[[ \$(named_of 'monitor two' owner 'HDMI-A-1 - eDP-1') == \"error:can't tell which monitor is slot 2\" ]]"
check "a slot the lookup places still focuses with an unlisted monitor" "[[ \$(SANDBOX_MONITOR_SLOTS='HDMI-A-1 - eDP-1' dispatches owner 'go to monitor one') == \$(focus_of HDMI-A-1) ]]"

section "monitors: when Hyprland cannot say which monitor is which slot"
check "the first monitor focuses nothing with no slot lookup" "[[ -z \$(SANDBOX_MONITOR_SLOTS= dispatches owner 'go to the first monitor') ]]"
check "monitor two focuses nothing with no slot lookup" "[[ -z \$(SANDBOX_MONITOR_SLOTS= dispatches owner 'go to monitor two') ]]"
check "a 2nd monitor move moves nothing with no slot lookup" "[[ -z \$(SANDBOX_MONITOR_SLOTS= dispatches owner 'move this window to the 2nd monitor') ]]"
check "the position words still focus with no slot lookup" "[[ \$(SANDBOX_MONITOR_SLOTS= dispatches owner 'go to the left monitor') == \$(focus_of DP-8) ]]"
check "the laptop still focuses with no slot lookup" "[[ \$(SANDBOX_MONITOR_SLOTS= dispatches owner 'go to the laptop screen') == \$(focus_of eDP-1) ]]"
check "a slot with no lookup says it cannot tell" "[[ \$(named_of 'monitor two' owner '') == \"error:can't tell which monitor is slot 2\" ]]"
check "an ordinal past the layout with no lookup still says it cannot tell" "[[ \$(named_of 'tenth monitor' owner '') == \"error:can't tell which monitor is slot 10\" ]]"
check "a slot past the layout with the lookup answered says no such monitor" "[[ \$(named_of 'tenth monitor' owner 'eDP-1 DP-8 HDMI-A-1 DP-13') == 'error:no monitor tenth' ]]"

section "monitors: moving the active window"
active_address=$(jq -r .address <<<"$SANDBOX_ACTIVEWINDOW_JSON")
check "move this window to the right monitor" "[[ \$(dispatches owner 'move this window to the right monitor') == \$(move_of DP-13) ]]"
check "move this window to the second monitor" "[[ \$(dispatches owner 'move this window to the second monitor') == \$(move_of DP-8) ]]"
check "move it to the 3rd screen" "[[ \$(dispatches owner 'move it to the 3rd screen') == \$(move_of HDMI-A-1) ]]"
check "a 10th monitor on the owner's four moves nothing" "[[ -z \$(dispatches owner 'move this window to the 10th monitor') ]]"
check "move it to the laptop screen" "[[ \$(dispatches owner 'move it to the laptop screen') == \$(move_of eDP-1) ]]"
check "send the window to monitor two" "[[ \$(dispatches owner 'send the window to monitor two') == \$(move_of DP-8) ]]"
check "a monitor no word fits moves nothing" "[[ -z \$(dispatches side_by_side 'move this window to the center monitor') ]]"
check "no focused window moves nothing" "[[ -z \$(SANDBOX_ACTIVEWINDOW_JSON='{}' dispatches owner 'move this window to the left monitor') ]]"

section "monitors: other phrases keep their route"
route_of() { SANDBOX_MONITORS_JSON=$(cat "$layouts_dir/owner.json") voxcmd --dry-run "$1" 2>/dev/null | sed -n 's/^option 1: *\([^ ]*\) .* action=\([^ ]*\) .*/\1\/\2/p'; }
check "set a timer for 30 seconds stays with Timers" "[[ \$(route_of 'set a timer for 30 seconds') == Timers/timer ]]"
check "move firefox to workspace 3 stays with Apps" "[[ \$(route_of 'move firefox to workspace 3') == Apps/move ]]"
check "go to firefox stays with Apps" "[[ \$(route_of 'go to firefox') == Apps/focus ]]"
check "a monitor that is no monitor word is left to the apps" "[[ \$(route_of 'go to the system monitor') != Monitors/* ]]"
check "move two and four to the left monitor is not ours with the overview closed" "[[ \$(route_of 'move two and four to the left monitor') != Monitors/* ]]"

section "monitors: the shell words agree with the overview's rule"
voice_js=$package/../quickshell/.config/quickshell/overview/Voice.js
if command -v node >/dev/null 2>&1; then
  agree() {
    local layout="$1" expected actual
    # Voice.js is a QML library: its pragma line is the only thing node cannot read.
    expected=$(jq -c '[.[] | select(.disabled | not)]' "$layouts_dir/$layout.json" | node -e '
      const fs = require("fs");
      const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library/m, "");
      const positions = new Function(src + "; return positions;")();
      const monitors = JSON.parse(fs.readFileSync(0, "utf8"));
      const groups = monitors.map(m => {
        const turned = (m.transform || 0) % 2 === 1;
        const s = m.scale > 0 ? m.scale : 1;
        return { name: m.name, x: m.x, y: m.y, w: (turned ? m.height : m.width) / s, h: (turned ? m.width : m.height) / s };
      });
      const places = positions(groups);
      console.log(JSON.stringify(groups.map((g, i) => [g.name, places[i].horizontal, places[i].vertical]).sort()));
    ' "$voice_js")
    actual=$(jq -c --arg slots "" -f "$package/.local/share/voxcmd/monitor-places.jq" "$layouts_dir/$layout.json" |
      jq -c 'map([.id, .horizontal, .vertical]) | sort')
    [[ $expected == "$actual" ]]
  }
  for layout_file in "$layouts_dir"/*.json; do
    layout=$(basename "$layout_file" .json)
    check "$layout: Voice.js and monitor-places.jq give every monitor the same words" "agree '$layout'"
  done
else
  echo "skip: node is not installed, so Voice.js is not compared"
fi

finish
