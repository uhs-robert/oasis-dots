#!/bin/bash

# Configuration
INTERVAL_MINUTES=15
INTERVAL=$((INTERVAL_MINUTES * 60))
WALLPAPER_DIR="$HOME/Pictures/Wallpapers/Pixel Art"

# Ensure Hyprpaper is running
if ! pgrep -x "hyprpaper" >/dev/null; then
  hyprpaper &
  sleep 1 # Allow time for initialization
fi

# Function to get a new random wallpaper
get_random_wallpaper() {
  find "$WALLPAPER_DIR" -type f | shuf -n 1
}

# Function to apply wallpapers
apply_wallpapers() {
  mapfile -t MONITORS < <(hyprctl monitors | awk '/Monitor/ {print $2}')

  for MONITOR in "${MONITORS[@]}"; do
    WALLPAPER=$(get_random_wallpaper)

    if [[ -f "$WALLPAPER" ]]; then
      echo "Preloading wallpaper: $WALLPAPER"
      hyprctl hyprpaper preload "$WALLPAPER"
      sleep 0.15 # Allow preload to complete

      echo "Setting wallpaper on $MONITOR: $WALLPAPER"
      hyprctl hyprpaper wallpaper "$MONITOR,$WALLPAPER"
      hyprctl hyprpaper unload unused
    else
      echo "Error: No valid wallpapers found in $WALLPAPER_DIR!"
    fi
  done
}

# Apply wallpapers initially
apply_wallpapers

# Rotate wallpapers every X minutes
while true; do
  sleep "$INTERVAL"
  apply_wallpapers
done
