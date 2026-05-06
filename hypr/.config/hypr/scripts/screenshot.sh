#!/usr/bin/env bash
# hypr/.config/hypr/scripts/screenshot.sh

# Screenshot/Recording utility for Hyprland using Satty, Hyprshot, and hyprpicker

set -e

### CONFIG ###
MENU=(rofi -dmenu --columns 1 --width 50% --prompt "Take Screenshot or Record?")
RECORDER="wf-recorder"
SCREENSHOT_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
RECORDING_DIR="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"
mkdir -p "$SCREENSHOT_DIR" "$RECORDING_DIR"

NOTIFY=$(pidof mako || pidof dunst || pidof swaync || true)
timestamp() { date +'%Y-%m-%d_%Hh%Mm%Ss'; }

# Send a desktop notification if a notification daemon is running, otherwise print to stdout.
notify() {
  if [[ -n "$NOTIFY" ]]; then
    notify-send "$@"
  else
    echo "NOTIFY: $*"
  fi
}

# Assert a command exists; notify and exit if missing.
need() {
  command -v "$1" >/dev/null 2>&1 || {
    notify "Screenshot Failed" "Missing command: $1"
    exit 1
  }
}

# Return true if a command exists, false otherwise. Non-fatal alternative to need().
want() {
  command -v "$1" >/dev/null 2>&1
}

# Report presence of all hard and soft dependencies to stdout.
check_deps() {
  local hard_deps=(hyprshot wl-copy wf-recorder hyprpicker tesseract slurp jq)
  local soft_deps=(satty)
  local ok=true
  for dep in "${hard_deps[@]}"; do
    if want "$dep"; then
      echo "  [ok] $dep"
    else
      echo "  [missing] $dep"
      ok=false
    fi
  done
  for dep in "${soft_deps[@]}"; do
    if want "$dep"; then
      echo "  [ok] $dep (optional)"
    else
      echo "  [missing] $dep (optional)"
    fi
  done
  $ok && echo "All required dependencies satisfied." || echo "Some required dependencies are missing."
}

need wl-copy

# Geometry helpers — return region strings for use with slurp/wf-recorder.
# get_focused: returns the geometry of the active window.
get_focused() {
  hyprctl activewindow -j | jq -r '.at,.size | join(" ")' | awk '{printf "%s,%s %sx%s", $1,$2,$3,$4}'
}
# get_outputs: returns geometry of all monitors, one per line.
get_outputs() {
  hyprctl monitors -j | jq -r '.[] | "\(.x),\(.y) \(.width)x\(.height)"'
}
# get_windows: returns geometry of all open windows, one per line.
get_windows() {
  hyprctl clients -j | jq -r '.[] | select(.at and .size) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
}

# Capture a screenshot via hyprshot, annotate with satty if available, save to SCREENSHOT_DIR, and copy to clipboard.
handle_screenshot() {
  need hyprshot
  local mode="$1"
  local extra_args=("${@:2}")
  local ts filename
  ts="$(timestamp)"
  filename="$SCREENSHOT_DIR/screenshot-$ts.png"
  if want satty; then
    hyprshot -m "$mode" "${extra_args[@]}" --raw | satty -f - -o "$filename"
  else
    hyprshot -m "$mode" "${extra_args[@]}" --raw >"$filename"
  fi
  wl-copy <"$filename"
}

# Record a screen region with wf-recorder, save to RECORDING_DIR, and copy to clipboard.
handle_recording() {
  need wf-recorder
  need jq
  local region="$1"
  local ts filename
  ts="$(timestamp)"
  filename="$RECORDING_DIR/recording-$ts.mp4"
  notify-send "Recording begin" "Open the recorder again to stop."
  $RECORDER -g "$region" -f "$filename"
  notify-send "Recording Saved!" "$filename"
  wl-copy <"$filename"
}

# Capture a region screenshot, run tesseract OCR on it, and copy the extracted text to clipboard.
handle_text_ocr() {
  need hyprshot
  need tesseract
  local tmpfile ocr_text
  tmpfile=$(mktemp /tmp/clipocr-XXXXXX.png)

  # Hyprshot region select, output to tmpfile via tee
  hyprshot -m region --raw | tee "$tmpfile" >/dev/null

  # OCR
  if ocr_text=$(tesseract "$tmpfile" - 2>/dev/null); then
    echo "$ocr_text" | wl-copy
    notify-send "OCR Complete" "Text copied to clipboard"
  else
    notify-send "OCR Failed" "Tesseract failed to process image"
  fi

  rm -f "$tmpfile"
}

# Help / dependency check
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo "Usage: $(basename "$0") [option]"
  echo ""
  echo "Options:"
  echo "  -h, --help            Show this help and check all dependencies"
  echo "  r, --region           Screenshot region"
  echo "  z, --freeze           Screenshot frozen region"
  echo "  s, --screen           Screenshot screen"
  echo "  w, --window           Screenshot window"
  echo "  f, --focused          Screenshot focused window"
  echo "  t, --text             OCR text from region"
  echo "  p, --pixel            Pick pixel color"
  echo "  --record-region       Record region"
  echo "  --record-window       Record window"
  echo "  --record-screen       Record screen"
  echo "  --record-focused      Record focused window"
  echo ""
  echo "Dependencies:"
  check_deps
  exit 0
fi

# Stop recorder if already running
if REC_PID=$(pidof "$RECORDER" 2>/dev/null); then
  kill -SIGINT "$REC_PID"
  exit 0
fi

# Choose action
CHOICE="$1"
if [[ -z "$CHOICE" ]]; then
  CHOICE=$(
    cat <<EOF | "${MENU[@]}"
📸 Screenshot Region
📸 Screenshot Frozen Region
📸 Screenshot Screen
📸 Screenshot Window
📸 Screenshot Focused
📹 Record Region
📹 Record Window
📹 Record Screen
📹 Record Focused
🎨 Pick Pixel Color
📄 OCR Text from Region
EOF
  )
  case "$CHOICE" in
  "📸 Screenshot Region") CHOICE="--region" ;;
  "📸 Screenshot Frozen Region") CHOICE="--freeze" ;;
  "📸 Screenshot Screen") CHOICE="--screen" ;;
  "📸 Screenshot Window") CHOICE="--window" ;;
  "📸 Screenshot Focused") CHOICE="--focused" ;;
  "📹 Record Region") CHOICE="--record-region" ;;
  "📹 Record Window") CHOICE="--record-window" ;;
  "📹 Record Screen") CHOICE="--record-screen" ;;
  "📹 Record Focused") CHOICE="--record-focused" ;;
  "🎨 Pick Pixel Color") CHOICE="--pixel" ;;
  "📄 OCR Text from Region") CHOICE="--text" ;;
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
t | --text) handle_text_ocr ;;
p | --pixel)
  need hyprpicker
  COLOR="$(hyprpicker -a || exit 1)"
  wl-copy "$COLOR"
  echo "Picked Color" "$COLOR"
  ;;

--record-region) need slurp; handle_recording "$(slurp)" ;;
--record-window) need slurp; handle_recording "$(get_windows | slurp -r)" ;;
--record-screen) need slurp; handle_recording "$(get_outputs | slurp -r)" ;;
--record-focused) handle_recording "$(get_focused)" ;;

*)
  notify-send "Cancelled" "Unknown action"
  exit 1
  ;;
esac
