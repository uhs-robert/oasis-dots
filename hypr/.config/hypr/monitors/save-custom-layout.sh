#!/usr/bin/env bash

# File to save the current layout
SAVE_PATH="$HOME/.config/hypr/monitors/monitors-custom.conf"

echo "# Auto-generated monitor config" >"$SAVE_PATH"

# Dump current monitor layout
hyprctl monitors | grep -E '^Monitor|^[[:space:]]+[0-9]+x[0-9]+@' | while read -r line; do
  if [[ $line == Monitor* ]]; then
    # e.g., Monitor HDMI-A-1 (ID 0):
    mon=$(echo "$line" | awk '{print $2}')
  elif [[ $line == *"@"* && $line == *"at"* ]]; then
    # e.g., 2560x1440@144.00 at 0x0
    res=$(echo "$line" | awk '{print $1}')
    hz=$(echo "$res" | awk -F@ '{print $2}')
    dims=$(echo "$res" | awk -F@ '{print $1}')
    pos=$(echo "$line" | awk '{print $3}')
    echo "monitor=$mon,$dims@$hz,$pos,1" >>"$SAVE_PATH"
  fi
done

echo "Saved monitor layout to $SAVE_PATH"
