#!/usr/bin/env bash
# screenshot.sh

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

# Stop recorder if already running
if REC_PID=$(pidof "$RECORDER" 2>/dev/null); then
  kill -SIGINT "$REC_PID"
  exit 0
fi

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
  local ts filename
  ts="$(timestamp)"
  filename="$SCREENSHOT_DIR/screenshot-$ts.png"
  hyprshot -m "$mode" "${extra_args[@]}" --raw | satty -f - -o "$filename"
  wl-copy <"$filename"
}

handle_recording() {
  local region="$1"
  local ts filename
  ts="$(timestamp)"
  filename="$RECORDING_DIR/recording-$ts.mp4"
  notify-send "Recording begin" "Open the recorder again to stop."
  $RECORDER -g "$region" -f "$filename"
  notify-send "Recording Saved!" "$filename"
  wl-copy <"$filename"
}

handle_text_ocr() {
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

# Stop recorder if already running
if REC_PID=$(pidof "$RECORDER" 2>/dev/null); then
  kill -SIGINT "$REC_PID"
  notify-send "Screen recorder stopped"
  exit 0
fi

# Choose action
CHOICE="$1"
if [[ -z "$CHOICE" ]]; then
  CHOICE=$(
    cat <<EOF | "${MENU[@]}"
📸 Screenshot Region     (Super + I)
📸 Screenshot Frozen Region
📸 Screenshot Screen
📸 Screenshot Window     (Super + Shift + I)
📸 Screenshot Focused
📹 Record Region         (Super + Alt + I)
📹 Record Window
📹 Record Screen
📹 Record Focused
🎨 Pick Pixel Color      (Super + P)
📄 OCR Text from Region  (Super + T)
EOF
  )
  case "$CHOICE" in
  "📸 Screenshot Region     (Super + I)") CHOICE="--region" ;;
  "📸 Screenshot Frozen Region") CHOICE="--freeze" ;;
  "📸 Screenshot Screen") CHOICE="--screen" ;;
  "📸 Screenshot Window     (Super + Shift + I)") CHOICE="--window" ;;
  "📸 Screenshot Focused") CHOICE="--focused" ;;
  "📹 Record Region         (Super + Alt + I)") CHOICE="--record-region" ;;
  "📹 Record Window") CHOICE="--record-window" ;;
  "📹 Record Screen") CHOICE="--record-screen" ;;
  "📹 Record Focused") CHOICE="--record-focused" ;;
  "🎨 Pick Pixel Color      (Super + P)") CHOICE="--pixel" ;;
  "📄 OCR Text from Region  (Super + T)") CHOICE="--text" ;;
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
  COLOR="$(hyprpicker -a || exit 1)"
  wl-copy "$COLOR"
  echo "Picked Color" "$COLOR"
  ;;

--record-region) handle_recording "$(slurp)" ;;
--record-window) handle_recording "$(get_windows | slurp -r)" ;;
--record-screen) handle_recording "$(get_outputs | slurp -r)" ;;
--record-focused) handle_recording "$(get_focused)" ;;

*)
  notify-send "Cancelled" "Unknown action"
  exit 1
  ;;
esac
