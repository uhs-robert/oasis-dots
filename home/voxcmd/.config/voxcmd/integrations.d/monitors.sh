# shellcheck shell=bash disable=SC2034,SC2016,SC2154
# Focuses a monitor, or moves the active window to one, by where it sits, its slot or "laptop". Format: ~/.config/voxcmd/README.md

name="Monitors"
confirm=0
# The monitor taking focus, or the window leaving, is the feedback; a name that fits no monitor still toasts as a failure.
silent=1

# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=monitor-words.sh
source "$voxcmd_share_dir/monitor-words.sh"

# The noun is part of each pattern, so "go to firefox" and "move it to workspace 3" never reach candidates(). Moving takes
# only the active window ("this window", "it"); "move two and four to the left monitor" belongs to the overview.
moved_window='(this|the|that)( active| current| focused)? window|it|this|that'
verbs=(
  "focus {focus} (the )?(monitor|screen|display) {target}"
  "focus {focus} (the )?{target} (monitor|screen|display)"
  "move  (move|send|put|take|bring) ($moved_window)( over)? (to|onto|on) (the )?(monitor|screen|display) {target}"
  "move  (move|send|put|take|bring) ($moved_window)( over)? (to|onto|on) (the )?{target} (monitor|screen|display)"
)

examples=(
  "go to the left monitor"
  "focus the center monitor"
  "switch to the top right screen"
  "go to monitor two"
  "focus the laptop display"
  "move this window to the right monitor"
  "move it to monitor three"
  "send the window to the laptop screen"
)

declare -A actions=(
  [focus]='focus_monitor "$id"'
  [move]='move_window_to_monitor "$id"'
)

# One candidate: the monitor the words name, or the reason they name none. Words that are no monitor vocabulary at all
# ("system monitor") offer nothing, which leaves the phrase to the apps.
candidates() {
  local monitor
  monitor_words_known "$2" || {
    echo '[]'
    return
  }
  monitor=$(monitor_named "$2" "$(monitor_places)")
  jq -n -c --arg id "$monitor" --arg match_text "$2" '[{id: $id, label: ($id | sub("^error:"; "")), match_text: $match_text}]'
}

# $1 is a monitor name or an "error:" line from candidates(). Names go into a Lua string, so only a connector name passes.
monitor_dispatch() {
  local output
  [[ "$1" =~ ^[A-Za-z0-9_.:-]+$ ]] || {
    echo "${1#error:}"
    return 1
  }
  output=$(hyprctl dispatch "$2" 2>&1) || {
    echo "$output"
    return 1
  }
  [ "$output" = ok ] || [ -z "$output" ] || {
    echo "$output"
    return 1
  }
}

focus_monitor() {
  monitor_dispatch "$1" "hl.dsp.focus({ monitor = '$1' })"
}

# Leaves focus where it is and lands on the monitor's visible workspace, as the overview's own move to a monitor does.
move_window_to_monitor() {
  local address
  [[ "$1" != error:* ]] || {
    echo "${1#error:}"
    return 1
  }
  address=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')
  [ -n "$address" ] || {
    echo "no window is focused"
    return 1
  }
  monitor_dispatch "$1" "hl.dsp.window.move({ window = 'address:$address', monitor = '$1', follow = false })"
}
