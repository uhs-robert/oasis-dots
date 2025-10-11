#!/usr/bin/env bash
# monitors/toggle-monitor-layout.sh

CONFIG_DIR="$HOME/.config/hypr"
MAIN_CONF="$CONFIG_DIR/hyprland.conf"

# Get all available configs
layouts=$(find "$CONFIG_DIR/monitors" -type f -name "monitors-*.conf" | sed -E 's|.*/monitors-(.*)\.conf|\1|' | sort)

# Ask user which one to load
layout=$(printf "%s\n" "$layouts" | rofi -dmenu -p "Choose monitor layout")

[[ -z "$layout" ]] && exit 1

# Replace the variable assignment line
sed -i "s|^\$MONITOR_CONFIG = .*|\$MONITOR_CONFIG = $layout|" "$MAIN_CONF"

notify-send "Hyprland Monitor Layout" "Switched to: $layout"
hyprctl reload
