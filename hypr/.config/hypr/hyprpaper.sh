#!/bin/bash

# Configuration
WALLPAPER_DIR="$HOME/Pictures/Wallpapers/Pixel Art"
DEFAULT_INTERVAL_MINUTES=15
if [[ "$1" =~ ^[0-9]+$ ]]; then
  INTERVAL_MINUTES="$1"
else
  INTERVAL_MINUTES="$DEFAULT_INTERVAL_MINUTES"
fi
INTERVAL=$((INTERVAL_MINUTES * 60))

# Ensure only one instance is running
terminate_other_instances() {
  SCRIPT_PID=$(pgrep -fx "$0")

  if [[ $(pgrep -fc "$0") -gt 1 ]]; then
    echo "Another instance is already running (PID: $SCRIPT_PID), killing it..."
    pkill -fx "$0"
    sleep 1
  fi
}

# Ensure Hyprpaper is running
launch_hyprpaper() {
  if ! pgrep -x "hyprpaper" >/dev/null; then
    hyprpaper &
    sleep 1
  fi
}

# Function to get a new random wallpaper
get_random_wallpaper() {
  find "$WALLPAPER_DIR" -type f | shuf -n 1
}

# Function to apply wallpapers
apply_wallpapers() {
  if ! find "$WALLPAPER_DIR" -type f | grep -q .; then
    echo "No wallpapers found in $WALLPAPER_DIR. Exiting."
    exit 1
  fi
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

# Rotate wallpapers every X minutes
rotate_wallpapers() {
  while true; do
    apply_wallpapers || echo "Wallpaper application failed, retrying..."
    sleep "$INTERVAL"
  done
}

main() {
  terminate_other_instances
  launch_hyprpaper
  rotate_wallpapers
}

main
