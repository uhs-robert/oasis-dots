# shellcheck shell=bash
# Hook library of monitors.toml: sourced before every hook and action of the integration.

# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=monitor-words.sh
source "$VOXCMD_SHARE_DIR/monitor-words.sh"

# id<TAB>label<TAB>match_text for the one monitor the target words name, or the reason they name none ("error:..."
# becomes the label and fails the action). $1 is the action. Words that are no monitor vocabulary at all ("system
# monitor") print nothing, which leaves the phrase to the apps.
monitor_candidates() {
  local target=$VOXCMD_ARG_TARGET monitor
  if [[ "$1" == *_laptop ]]; then
    [[ "${target#the }" =~ ^($monitor_builtin_words)$ ]] || return 0
  else
    monitor_words_known "$target" || return 0
  fi
  monitor=$(monitor_named "$target" "$(monitor_places)")
  printf '%s\t%s\t%s\n' "$monitor" "${monitor#error:}" "$target"
}

# $1 is a monitor name or an "error:" line from monitor_candidates. Names go into a Lua string, so only a connector name passes.
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
