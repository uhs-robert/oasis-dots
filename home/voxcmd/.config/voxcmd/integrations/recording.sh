# shellcheck shell=bash
# Hook library of recording.toml: sourced before every hook of the integration.

screenshot_tool="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/screenshot.sh"

# Any wf-recorder counts, like the bar's chip: screenshot.sh and the demo recorder both run it.
recorder_pid() {
  pidof -s wf-recorder
}

# The -f argument of the running wf-recorder.
recording_file() {
  tr '\0' '\n' <"/proc/$1/cmdline" | sed -n '/^-f$/{n;p;q}'
}

# The focused monitor in wf-recorder's logical "x,y wxh": a scaled or rotated monitor's pixel size is not its size in
# layout coordinates.
focused_monitor_geometry() {
  hyprctl monitors -j | jq -r 'first(.[] | select(.focused))
    | .scale as $scale
    | (if .transform % 2 == 1 then [.height, .width] else [.width, .height] end | map(. / $scale | round)) as [$w, $h]
    | "\(.x),\(.y) \($w)x\($h)"'
}

# Silent actions print nothing on success, so being told "already recording" needs its own notification.
start_recording() {
  local pid
  if [ ! -x "$screenshot_tool" ]; then
    echo "$screenshot_tool is missing"
    return 1
  fi
  if pid=$(recorder_pid); then
    notify-send --transient --app-name=voxcmd "Already recording" "$(recording_file "$pid")"
    return
  fi
  # screenshot.sh waits for the recording to end; detached, voxcmd does not.
  setsid -f "$screenshot_tool" "$@" >/dev/null 2>&1 </dev/null
}

# screenshot.sh with no argument stops a running recording, as pressing Print again does.
stop_recording() {
  local pid file waited
  if ! pid=$(recorder_pid); then
    notify-send --transient --app-name=voxcmd "Not recording"
    return
  fi
  file=$(recording_file "$pid")
  "$screenshot_tool" >/dev/null 2>&1 </dev/null
  for ((waited = 0; waited < 50; waited++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  if kill -0 "$pid" 2>/dev/null; then
    echo "wf-recorder is still finishing $file"
    return 1
  fi
  if [ ! -s "$file" ]; then
    echo "wf-recorder wrote no video"
    return 1
  fi
}

recording_status() {
  local pid seconds
  if ! pid=$(recorder_pid); then
    echo "not recording"
    return
  fi
  seconds=$(ps -o etimes= -p "$pid" | tr -d ' ')
  printf 'recording for %d:%02d to %s\n' "$((seconds / 60))" "$((seconds % 60))" "$(recording_file "$pid")"
}
