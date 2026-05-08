#!/usr/bin/env bash
# ~/.config/hypr/scripts/toggle-monitor-layout.sh

set -euo pipefail

CONFIG_DIR="$HOME/.config/hypr"
MONITOR_DIR="$CONFIG_DIR/monitors"
LAYOUT_DIR="$MONITOR_DIR/layouts"
ACTIVE_LAYOUT="$MONITOR_DIR/active.conf"

# Get all layouts
layouts="$(
  find "$LAYOUT_DIR" -type f -name "monitors-*.conf" |
    sed -E 's|.*/monitors-(.*)\.conf|\1|' |
    sort
)"

# Ask user which one to load
layout="$(printf "%s\n" "$layouts" | rofi -dmenu -p "Choose monitor layout")"
[[ -z "$layout" ]] && exit 0

# Handle missing layouts
selected_layout="$LAYOUT_DIR/monitors-$layout.conf"
if [[ ! -f "$selected_layout" ]]; then
  notify-send "Hyprland Monitor Layout" "Missing layout: $selected_layout"
  exit 1
fi

# Copy layout to active and reload
cp "$selected_layout" "$ACTIVE_LAYOUT"
notify-send "Hyprland Monitor Layout" "Switched to: $layout"
sleep 1
hyprctl reload
