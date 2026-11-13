# shellcheck shell=bash
# Hook library of monitors.toml: sourced before every hook and action of the integration.

# $1 is a monitor name or an "error:" line from the monitors provider. Names go into a Lua string, so only a connector name passes.
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
