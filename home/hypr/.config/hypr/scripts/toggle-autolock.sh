#!/usr/bin/env bash
# hypr/.config/hypr/scripts/toggle-autolock.sh
# Toggles hypridle, which dims and locks the screen when idle.

if pgrep -x hypridle >/dev/null; then
  pkill -x hypridle
  notify-send -a "Auto-lock" -i system-lock-screen "Auto-lock off" "The screen will not lock when idle."
else
  hyprctl dispatch "hl.dsp.exec_cmd('hypridle')" >/dev/null
  notify-send -a "Auto-lock" -i system-lock-screen "Auto-lock on" "The screen locks after 5 minutes idle."
fi
