# shellcheck shell=bash
# Names monitors for voice: by position ("left", "top right", "center"), by slot ("monitor two", "the second screen", "the
# 2nd display", the one SUPER + CTRL + 2 focuses) or as the built-in panel ("laptop"). Sourced by overview.sh and monitors.sh
# (the integration). The position words come from monitor-places.jq, which mirrors the Quickshell overview's own rule (overview/Voice.js) so the two never disagree.

monitors_share_dir="${BASH_SOURCE[0]%/*}"
# shellcheck source-path=SCRIPTDIR source=spoken-time.sh
source "$monitors_share_dir/spoken-time.sh"

# Prints the monitor name of each slot, space separated ("-" for an empty one). Hyprland's Lua owns the slot order, and
# `hyprctl eval` prints nothing back, so the answer goes through a file, as the overview gets it. Prints nothing when
# Hyprland cannot answer, which leaves the slots in monitor id order.
monitor_slot_names() {
  local file="${XDG_RUNTIME_DIR:-/tmp}/voxcmd/monitor-slots"
  mkdir -p "${file%/*}"
  rm -f "$file"
  hyprctl eval "local W = require('lib.workspaces'); local t = {}; for i = 1, 10 do t[i] = W.get_monitor_for_slot(i) or '-' end; local f = io.open('$file', 'w'); f:write(table.concat(t, ' ')); f:close()" >/dev/null 2>&1 || true
  cat "$file" 2>/dev/null || true
}

# Prints the connected monitors as overview.json's "monitors" array: [{id, slot, horizontal, vertical, focused}].
monitor_places() {
  local monitors
  monitors=$(hyprctl monitors -j 2>/dev/null) || return 1
  jq -c --arg slots "$(monitor_slot_names)" -f "$monitors_share_dir/monitor-places.jq" <<<"$monitors"
}

monitor_position_words='left|right|middle|center|centre|top|bottom'
monitor_builtin_words='laptop|builtin|built in|internal'
declare -gA ordinal_words=(
  [first]=1 [second]=2 [third]=3 [fourth]=4 [fifth]=5 [sixth]=6 [seventh]=7 [eighth]=8 [ninth]=9 [tenth]=10
)

# Prints the slot a word names: a number ("two", "2") or an ordinal ("second", "2nd"), or fails. Any ordinal digits are
# taken as the number; one above the monitors count says there is no such monitor, as "nine" does.
monitor_slot_word() {
  if [ -n "${number_words[$1]+set}" ]; then
    echo "${number_words[$1]}"
  elif [ -n "${ordinal_words[$1]+set}" ]; then
    echo "${ordinal_words[$1]}"
  elif [[ "$1" =~ ^[0-9]+(st|nd|rd|th)?$ ]]; then
    echo "$((10#${1%%[a-z]*}))"
  else
    return 1
  fi
}

# Succeeds when every word of $1 (with "monitor", "screen" or "display" around it dropped) is one this file understands, so
# "system monitor" is left to the apps and "bottom right" is answered even when no monitor sits there.
monitor_words_known() {
  local words="$1" word
  words="${words#the }"
  words="${words% monitor}" words="${words% screen}" words="${words% display}"
  words="${words#monitor }" words="${words#screen }" words="${words#display }"
  [ -n "$words" ] || return 1
  for word in $words; do
    [[ "$word" =~ ^($monitor_position_words|laptop|builtin|built|in|internal|number)$ ]] || monitor_slot_word "$word" >/dev/null || return 1
  done
}

# monitor_named <words> <monitors json>: prints the name of the monitor the words name, or an "error:" line. The JSON is
# monitor_places' or overview.json's "monitors".
monitor_named() {
  local words="$1" monitors="$2" found count named slot
  words="${words#the }"
  words="${words% monitor}" words="${words% screen}" words="${words% display}"
  words="${words#monitor }" words="${words#screen }" words="${words#display }"
  words="${words#number }"
  words="${words//center/middle}"
  words="${words//centre/middle}"
  named="$words monitor"
  if [[ "$words" =~ ^($monitor_builtin_words)$ ]]; then
    found=$(jq -c '[.[] | select(.id | test("^(eDP|LVDS|DSI)-")) | .id]' <<<"$monitors")
  elif slot=$(monitor_slot_word "$words"); then
    named="monitor $words"
    found=$(jq -c --argjson slot "$slot" '[.[] | select(.slot == $slot and $slot > 0) | .id]' <<<"$monitors")
  else
    found=$(jq -c --arg words "$words" '
      ($words | split(" ")) as $spoken
      | [.[] | . as $m | select($spoken | all(. as $word | $m.horizontal == $word or $m.vertical == $word)) | .id]' <<<"$monitors")
  fi
  count=$(jq length <<<"$found")
  case "$count" in
  1) jq -r '.[0]' <<<"$found" ;;
  0) echo "error:no $named" ;;
  *) echo "error:more than one $named" ;;
  esac
}
