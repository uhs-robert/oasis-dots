# shellcheck shell=bash disable=SC2034,SC2016
# Screen recording through the screenshot tool's own wf-recorder flags (hypr/scripts/screenshot.sh), so the bar's
# recording chip, the file names under ~/Videos/Recordings and the "Recording Saved!" notification stay the same as
# from the Print key. Format: ~/.config/voxcmd/README.md

name="Recording"
confirm=0
# A started recording shows on the bar's recording chip, or screenshot.sh says so when no bar shows it.
silent_actions=(record_screen record_window pick_window record_region)

screenshot_tool="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/screenshot.sh"

# "stop" alone is left to Media; "stop recording" there would look for a player named "recording" and find none.
verbs=(
  "status         (is it|is the screen|are we|am i|is something) (still )?recording|(is there a|any) (screen )?recording( running| going)?|recording status"
  "stop           (stop|end|finish)( the| my)?( screen)? recording|stop recording( the screen)?"
  "record_window  record (this|the|my) window|record (the )?(current|focused|active) window"
  "pick_window    record a window"
  "record_region  record (a |an |the )?(region|area|selection|part of the screen)"
  "record_screen  (start|begin)( a| the)?( screen)? recording( the screen)?|record (the |my |this )?(screen|display|monitor)"
)

examples=(
  "start recording"
  "record this window"
  "record a region"
  "is it recording"
  "stop recording"
)

declare -A actions=(
  [record_screen]='start_recording --record-geometry "$(focused_monitor_geometry)"'
  [record_window]='start_recording --record-focused'
  [pick_window]='start_recording --record-window'
  [record_region]='start_recording --record-region'
  [stop]='stop_recording'
  [status]='recording_status'
)

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

# Any screenshot.sh call stops a running recording first, as pressing Print again does.
stop_recording() {
  local pid file waited
  if ! pid=$(recorder_pid); then
    echo "not recording"
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
  echo "saved $file"
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
