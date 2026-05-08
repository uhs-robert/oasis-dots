#!/usr/bin/env sh
# hypr/.config/hypr/scripts/hyprlock-shot.sh

set -eu

# Monitor descriptions and output image names.
MONITOR_LAPTOP_DESC="BOE 0x0C8E"
MONITOR_LEFT_DESC="HP Inc. HP Z22n G2 6CM8411J1Z"
MONITOR_CENTER_DESC="GIGA-BYTE TECHNOLOGY CO. LTD. G27QC A 0x00000D48"
MONITOR_RIGHT_DESC="HP Inc. HP Z22n G2 6CM8411J22"

# Cache directory
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hyprlock"
mkdir -p "$CACHE_DIR"

# Screenshots each monitor and save image
if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && command -v grim >/dev/null 2>&1; then
  hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.disabled == false) | [.name, .description] | @tsv' |
    while IFS="$(printf '\t')" read -r mon_name mon_desc; do
      out="$CACHE_DIR/${mon_name}.png"
      case "$mon_desc" in
      "$MONITOR_LAPTOP_DESC") out="$CACHE_DIR/Laptop.png" ;;
      "$MONITOR_LEFT_DESC") out="$CACHE_DIR/Left.png" ;;
      "$MONITOR_CENTER_DESC") out="$CACHE_DIR/Center.png" ;;
      "$MONITOR_RIGHT_DESC") out="$CACHE_DIR/Right.png" ;;
      esac
      grim -o "$mon_name" "$out" >/dev/null 2>&1 || true
    done
fi

# Run hyprlock
exec hyprlock --immediate-render --no-fade-in "$@"
