#!/usr/bin/env bash

# Screenshot utility for Hyprland using Satty and hyprpicker
# Modes:
#   r | --region  = select area → open in Satty
#   s | --screen  = full screen → open in Satty
#   p | --pixel   = pick color with hyprpicker

set -e

require_input() {
  local input
  input="$("$@")" || exit 1
  [[ -z $input ]] && exit 1
  echo "$input"
}

timestamp() {
  date +%Y-%m-%d_%H-%M-%S
}

SCREENSHOT_DIR=~/Pictures/Screenshots
mkdir -p "$SCREENSHOT_DIR"
OUTPUT_FILE="$SCREENSHOT_DIR/satty-ss-$(timestamp).png"

case "$1" in
r | --region)
  grim -g "$(slurp -b '#000000b0' -c '#00000000')" - | satty --filename - --output-filename "$OUTPUT_FILE"
  ;;

s | --screen)
  grim -t ppm - | satty --filename - --output-filename "$OUTPUT_FILE"
  ;;

p | --pixel)
  color="$(require_input hyprpicker -a)"
  wl-copy "$color"
  notify-send 'Copied to Clipboard' "$color"
  ;;

*)
  echo "Usage: $0 [r|s|p|--region|--screen|--pixel]" >&2
  exit 1
  ;;
esac
