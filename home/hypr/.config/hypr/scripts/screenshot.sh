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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

timestamp() { date +'%Y-%m-%d_%Hh%Mm%Ss'; }

# Tell the Quickshell bar about recordings; silent when no bar is running.
qs_call() {
  "$SCRIPT_DIR/qs-ipc" call screenshot "$@" >/dev/null 2>&1 || true
}

# Assert a command exists; notify and exit if missing.
need() {
  command -v "$1" >/dev/null 2>&1 || {
    notify-send "Screenshot Failed" "Missing command: $1"
    exit 1
  }
}

# Return true if a command exists, false otherwise. Non-fatal alternative to need().
want() {
  command -v "$1" >/dev/null 2>&1
}

# Report presence of all hard and soft dependencies to stdout.
check_deps() {
  local hard_deps=(hyprshot grim wl-copy wf-recorder hyprpicker tesseract slurp jq)
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

# Notify about a saved file with Open and Show in folder actions, in the background so the script never waits.
notify_saved() {
  local title="$1" file="$2"
  (
    choice="$(timeout 600 notify-send --action=open=Open --action=folder="Show in folder" --wait "$title" "$file")" || true
    case "$choice" in
    open) xdg-open "$file" ;;
    folder) "$SCRIPT_DIR/term" -e yazi "$file" ;;
    esac
  ) >/dev/null 2>&1 &
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
  [[ -s "$filename" ]] || {
    rm -f -- "$filename"
    return 0
  }
  wl-copy <"$filename"
  notify_saved "Screenshot Saved" "$filename"
}

# Record a screen region with wf-recorder, save to RECORDING_DIR, and copy to clipboard.
handle_recording() {
  need wf-recorder
  need jq
  local region="$1"
  local ts filename
  ts="$(timestamp)"
  filename="$RECORDING_DIR/recording-$ts.mp4"
  [[ -n "$region" ]] || {
    notify-send "Recording Cancelled" "No region selected"
    exit 1
  }
  notify-send "Recording begin" "Open the recorder again to stop."
  local rec_pid
  $RECORDER -g "$region" -f "$filename" &
  rec_pid=$!
  qs_call recording_started "$rec_pid"
  wait "$rec_pid" || true
  qs_call recording_stopped
  [[ -s "$filename" ]] || {
    rm -f -- "$filename"
    notify-send "Recording Failed" "wf-recorder wrote no video"
    exit 1
  }
  wl-copy <"$filename"
  notify_saved "Recording Saved!" "$filename"
}

# Open the Quickshell region selector; false when no bar answers. preset: toolbar, ocr or record.
qs_select() {
  [[ "$("$SCRIPT_DIR/qs-ipc" call screenshot select "$1" "$2" 2>/dev/null)" == ok ]]
}

# Open a Quickshell selector mode (pixel, window, screen); false when no bar answers.
qs_pick() {
  [[ "$("$SCRIPT_DIR/qs-ipc" call screenshot pick "$1" "$2" 2>/dev/null)" == ok ]]
}

# Copy the colour of one pixel at "x,y 1x1" as lowercase hex, like hyprpicker -a.
handle_pixel_at() {
  need grim
  need magick
  local color
  color="$(grim -g "$1" -t ppm - | magick - -format '#%[hex:p{0,0}]' info:)"
  color="${color,,}"
  [[ "$color" =~ ^#[0-9a-f]{6} ]] || {
    notify-send "Pick Failed" "Could not read the pixel"
    exit 1
  }
  color="${color:0:7}"
  wl-copy "$color"
  notify-send "Picked Color" "$color"
}

# Act on a captured image: copy, save, annotate or ocr. The image file is removed on exit.
handle_image() {
  local image="$1" action="$2"
  local filename
  CLEANUP_IMAGE="$image"
  trap 'rm -f -- "$CLEANUP_IMAGE"' EXIT
  [[ -s "$image" ]] || {
    notify-send "Screenshot Failed" "No image captured"
    exit 1
  }
  filename="$SCREENSHOT_DIR/screenshot-$(timestamp).png"
  case "$action" in
  copy)
    wl-copy --type image/png <"$image"
    notify-send "Screenshot Copied" "Image copied to clipboard"
    ;;
  save)
    cp -- "$image" "$filename"
    wl-copy --type image/png <"$filename"
    notify_saved "Screenshot Saved" "$filename"
    ;;
  annotate)
    if want satty; then
      satty -f "$image" -o "$filename"
      if [[ -f "$filename" ]]; then
        wl-copy --type image/png <"$filename"
        notify_saved "Screenshot Saved" "$filename"
      fi
    else
      cp -- "$image" "$filename"
      wl-copy --type image/png <"$filename"
      notify_saved "Screenshot Saved" "$filename"
    fi
    ;;
  ocr)
    need tesseract
    local ocr_text
    if ocr_text=$(tesseract "$image" - 2>/dev/null); then
      printf '%s' "$ocr_text" | wl-copy
      notify-send "OCR Complete" "Text copied to clipboard"
    else
      notify-send "OCR Failed" "Tesseract failed to process image"
    fi
    ;;
  *)
    notify-send "Screenshot Failed" "Unknown image action: $action"
    ;;
  esac
}

# Parse the Quickshell selector's flags: --image FILE plus one action flag.
handle_region_args() {
  local image="" action="annotate"
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --image)
      image="$2"
      shift 2
      ;;
    --copy | --save | --annotate | --ocr)
      action="${1#--}"
      shift
      ;;
    *)
      notify-send "Cancelled" "Unknown option: $1"
      exit 1
      ;;
    esac
  done
  [[ -n "$image" ]] || {
    notify-send "Cancelled" "No image given"
    exit 1
  }
  handle_image "$image" "$action"
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
  echo "  --record-geometry G   Record the region G (\"x,y wxh\")"
  echo "  --image FILE [act]    Act on an already captured image (FILE is removed)"
  echo "                        act: --copy, --save, --annotate (default), --ocr"
  echo "  --pixel-at G          Copy the colour of the pixel at G (\"x,y 1x1\")"
  echo ""
  echo "Without an option, opens the Quickshell screenshot menu, or rofi when no bar answers."
  echo ""
  echo "Dependencies:"
  check_deps
  exit 0
fi

# The Quickshell selector's image and pixel flags never stop a recording.
case "$1" in
--image)
  handle_region_args "$@"
  exit 0
  ;;
--pixel-at)
  handle_pixel_at "$2"
  exit 0
  ;;
esac

# Stop recorder if already running
if REC_PID=$(pidof "$RECORDER" 2>/dev/null); then
  kill -SIGINT "$REC_PID"
  exit 0
fi

# Choose action
CHOICE="$1"
if [[ -z "$CHOICE" ]] && [[ "$("$SCRIPT_DIR/qs-ipc" call screenshot open 2>/dev/null)" == ok ]]; then
  exit 0
fi
if [[ -z "$CHOICE" ]]; then
  CHOICE=$(
    cat <<EOF | "${MENU[@]}"
Screenshot Region
Screenshot Frozen Region
Screenshot Screen
Screenshot Window
Screenshot Focused
Record Region
Record Window
Record Screen
Record Focused
Pick Pixel Color
OCR Text from Region
EOF
  )
  case "$CHOICE" in
  "Screenshot Region") CHOICE="--region" ;;
  "Screenshot Frozen Region") CHOICE="--freeze" ;;
  "Screenshot Screen") CHOICE="--screen" ;;
  "Screenshot Window") CHOICE="--window" ;;
  "Screenshot Focused") CHOICE="--focused" ;;
  "Record Region") CHOICE="--record-region" ;;
  "Record Window") CHOICE="--record-window" ;;
  "Record Screen") CHOICE="--record-screen" ;;
  "Record Focused") CHOICE="--record-focused" ;;
  "Pick Pixel Color") CHOICE="--pixel" ;;
  "OCR Text from Region") CHOICE="--text" ;;
  *)
    notify-send "Cancelled" "No valid option selected"
    exit 1
    ;;
  esac
fi

# Main logic
case "$CHOICE" in
r | --region) qs_select false toolbar || handle_screenshot "region" ;;
z | --freeze) qs_select true toolbar || handle_screenshot "region" "--freeze" ;;
s | --screen) qs_pick screen toolbar || handle_screenshot "output" ;;
w | --window) qs_pick window toolbar || handle_screenshot "window" ;;
f | --focused) handle_screenshot "window" -m active ;;
t | --text) qs_select false ocr || handle_text_ocr ;;
p | --pixel)
  qs_pick pixel toolbar && exit 0
  need hyprpicker
  COLOR="$(hyprpicker -a || exit 1)"
  wl-copy "$COLOR"
  echo "Picked Color" "$COLOR"
  ;;

--record-region) qs_select false record || {
  need slurp
  handle_recording "$(slurp)"
} ;;
--record-window) qs_pick window record || {
  need slurp
  handle_recording "$(get_windows | slurp -r)"
} ;;
--record-screen) qs_pick screen record || {
  need slurp
  handle_recording "$(get_outputs | slurp -r)"
} ;;
--record-focused) handle_recording "$(get_focused)" ;;
--record-geometry) handle_recording "$2" ;;

*)
  notify-send "Cancelled" "Unknown action"
  exit 1
  ;;
esac
