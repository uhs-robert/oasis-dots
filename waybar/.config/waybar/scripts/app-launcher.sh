#!/usr/bin/env bash
# waybar/.config/waybar/scripts/app-launcher.sh
set -euo pipefail

# Use your overlay opacity if exported (fallback 0.95)
OPAC="${overlay_window_opacity:-0.95}"

exec kitty -1 \
  --class=applicationMenu \
  --title=applicationMenu \
  -o allow_remote_control=yes \
  -o remember_window_size=no \
  -o initial_window_width=60c \
  -o initial_window_height=22c \
  -o background_opacity="$OPAC" \
  -o window_padding_width=0 \
  -o window_margin_width=0 \
  -o confirm_os_window_close=0 \
  -o enable_audio_bell=no \
  bash -lc 'jiffy -x wl-copy -r'
