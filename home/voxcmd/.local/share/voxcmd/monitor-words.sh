# shellcheck shell=bash
# Names monitors for voice: by position ("left", "top right", "center"), by slot ("monitor two", "the second screen", "the
# 2nd display", the one SUPER + CTRL + 2 focuses) or as the built-in panel ("laptop"). Sourced by overview.sh and the
# tests; monitors.toml uses the Rust provider (src/provider/monitors.rs). The position words come from overview.json's
# "monitors", which mirror the Quickshell overview's own rule (features/overview/Voice.js), so the two never disagree.

monitors_share_dir="${BASH_SOURCE[0]%/*}"
# shellcheck source-path=SCRIPTDIR source=spoken-position.sh
source "$monitors_share_dir/spoken-position.sh"

monitor_builtin_words='laptop|builtin|built in|internal'

# Prints the slot a word names: a number ("two", "2") or an ordinal ("second", "2nd"), or fails. A slot past the monitors
# count says there is no such monitor, as "nine" does.
monitor_slot_word() { spoken_position "$1"; }

# monitor_named <words> <monitors json>: prints the name of the monitor the words name, or an "error:" line. The JSON is
# overview.json's "monitors" or monitor-places.jq's output.
monitor_named() {
  local words="$1" monitors="$2" found count named slot slot_asked=""
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
    slot_asked=1
    found=$(jq -c --argjson slot "$slot" '[.[] | select(.slot == $slot and $slot > 0) | .id]' <<<"$monitors")
  else
    found=$(jq -c --arg words "$words" '
      ($words | split(" ")) as $spoken
      | [.[] | . as $m | select($spoken | all(. as $word | $m.horizontal == $word or $m.vertical == $word)) | .id]' <<<"$monitors")
  fi
  count=$(jq length <<<"$found")
  case "$count" in
  1) jq -r '.[0]' <<<"$found" ;;
  0)
    # A monitor with no known slot may be the one asked for, so the answer is "can't tell", not "no such monitor".
    if [ -n "$slot_asked" ] && jq -e 'any(.[]; .slot == 0)' <<<"$monitors" >/dev/null; then
      echo "error:can't tell which monitor is slot $slot"
    else
      echo "error:no $named"
    fi
    ;;
  *) echo "error:more than one $named" ;;
  esac
}
