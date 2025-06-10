#!/usr/bin/env bash

# Screenshot/Recording utility for Hyprland using Satty, Hyprshot, and hyprpicker

set -e

### CONFIG ###
MENU=(wofi --dmenu --columns 1 --width 50% --prompt "Take Screenshot or Record?")
RECORDER="wf-recorder"
SCREENSHOT_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
RECORDING_DIR="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"
mkdir -p "$SCREENSHOT_DIR" "$RECORDING_DIR"

NOTIFY=$(pidof mako || pidof dunst || pidof swaync || true)
timestamp() { date +'%Y-%m-%d_%Hh%Mm%Ss'; }

notify() {
  if [[ -n "$NOTIFY" ]]; then
    notify-send "$@"
  else
    echo "NOTIFY: $*"
  fi
}

# Lazy geometry helpers
get_focused() {
  hyprctl activewindow -j | jq -r '.at,.size | join(" ")' | awk '{printf "%s,%s %sx%s", $1,$2,$3,$4}'
}
get_outputs() {
  hyprctl monitors -j | jq -r '.[] | "\(.x),\(.y) \(.width)x\(.height)"'
}
get_windows() {
  hyprctl clients -j | jq -r '.[] | select(.at and .size) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
}

handle_screenshot() {
  local mode="$1"
  local extra_args=("${@:2}")
  local filename="$SCREENSHOT_DIR/screenshot-$(timestamp).png"
  hyprshot -m "$mode" "${extra_args[@]}" --raw | satty -f - -o "$filename"
  notify "Screenshot Saved" "$filename"
  wl-copy <"$filename"
}

handle_recording() {
  local region="$1"
  local filename="$RECORDING_DIR/recording-$(timestamp).mp4"
  $RECORDER -g "$region" -f "$filename"
  notify "Recording Complete" "$filename"
  wl-copy <"$filename"
}

# Stop recorder if already running
if REC_PID=$(pidof "$RECORDER" 2>/dev/null); then
  kill -SIGINT "$REC_PID"
  notify "Screen recorder stopped"
  exit 0
fi

# Choose action
CHOICE="$1"
if [[ -z "$CHOICE" ]]; then
  CHOICE=$(
    cat <<EOF | "${MENU[@]}"
📸 Screenshot Region    (Super + I)
📸 Screenshot Frozen Region
📸 Screenshot Screen
📸 Screenshot Window    (Super + Shift + I)
📸 Screenshot Focused
🎨 Pick Pixel Color     (Super + P)
EOF
  )
  case "$CHOICE" in
  "📸 Screenshot Region    (Super + I)") CHOICE="--region" ;;
  "📸 Screenshot Frozen Region") CHOICE="--freeze" ;;
  "📸 Screenshot Screen") CHOICE="--screen" ;;
  "📸 Screenshot Window    (Super + Shift + I)") CHOICE="--window" ;;
  "📸 Screenshot Focused") CHOICE="--focused" ;;
  "🎨 Pick Pixel Color     (Super + P)") CHOICE="--pixel" ;;
  *)
    notify "Cancelled" "No valid option selected"
    exit 1
    ;;
  esac
fi

# Main logic
case "$CHOICE" in
r | --region) handle_screenshot "region" ;;
z | --freeze) handle_screenshot "region" "--freeze" ;;
s | --screen) handle_screenshot "output" ;;
w | --window) handle_screenshot "window" ;;
f | --focused) handle_screenshot "window" -m active ;;
p | --pixel)
  COLOR="$(hyprpicker -a || exit 1)"
  wl-copy "$COLOR"
  notify "Picked Color" "$COLOR"
  ;;

--record-region) handle_recording "$(slurp)" ;;

--record-window) handle_recording "$(get_windows | slurp -r)" ;;

--record-output) handle_recording "$(get_outputs | slurp -r)" ;;

--record-focused) handle_recording "$(get_focused)" ;;

*)
  notify "Cancelled" "Unknown action"
  exit 1
  ;;
esac
