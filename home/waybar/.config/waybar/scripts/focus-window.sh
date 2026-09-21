#!/bin/sh
# waybar/.config/waybar/scripts/focus-window.sh

address=$1

# https://api.gtkd.org/gdk.c.types.GdkEventButton.button.html
button=$2

if [ $button -eq 1 ]; then
  # Left click: focus window
  hyprctl eval "hl.config({ cursor = { no_warps = true } })"
  hyprctl dispatch "hl.dsp.focus({ window = 'address:$address' })"
  hyprctl eval "hl.config({ cursor = { no_warps = false } })"
elif [ $button -eq 2 ]; then
  # Middle click: close window
  hyprctl dispatch "hl.dsp.window.close({ window = 'address:$address' })"
fi
