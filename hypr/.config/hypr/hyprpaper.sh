#!/bin/bash

# Defaults
DEFAULT_WALLPAPER_DIR="$HOME/Pictures/Wallpapers/Pixel Art"
DEFAULT_INTERVAL_MINUTES=15
SCRIPT_NAME=$(basename "$0")

# Parse named arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
  --interval | -i)
    INTERVAL_MINUTES="$2"
    shift 2
    ;;
  --dir | -d)
    WALLPAPER_DIR="$2"
    shift 2
    ;;
  --once | -o)
    RUN_ONCE=1
    shift
    ;;
  --verbose | -v)
    VERBOSE=1
    shift
    ;;
  --help | -h)
    echo "Usage: $SCRIPT_NAME [--interval|-i MINUTES] [--dir|-d DIR] [--verbose|-v] [--once|-o]"
    exit 0
    ;;
  *)
    echo "Unknown argument: $1"
    exit 1
    ;;
  esac
done

# Configuration
INTERVAL_MINUTES="${INTERVAL_MINUTES:-$DEFAULT_INTERVAL_MINUTES}"
WALLPAPER_DIR="${WALLPAPER_DIR:-$DEFAULT_WALLPAPER_DIR}"
INTERVAL_SECONDS=$((INTERVAL_MINUTES * 60))

# Log function using system logger
log() {
  [[ -n "$VERBOSE" ]] && logger -t "$SCRIPT_NAME" "$1"
}

# Ensure only one instance is running
terminate_other_instances() {
  SCRIPT_PID=$(pgrep -fx "$0")
  if [[ $(pgrep -fc "$0") -gt 1 ]]; then
    log "Another instance is already running (PID: $SCRIPT_PID), killing it..."
    pkill -fx "$0"
    sleep 1
  fi
}

# Ensure Hyprpaper is running
launch_hyprpaper() {
  if ! pgrep -x "hyprpaper" >/dev/null; then
    log "Launching hyprpaper..."
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
    log "No wallpapers found in $WALLPAPER_DIR. Exiting."
    exit 1
  fi
  mapfile -t MONITORS < <(hyprctl monitors | awk '/Monitor/ {print $2}')

  for MONITOR in "${MONITORS[@]}"; do
    WALLPAPER=$(get_random_wallpaper)

    if [[ -f "$WALLPAPER" ]]; then
      log "Preloading wallpaper: $WALLPAPER"
      hyprctl hyprpaper preload "$WALLPAPER"
      sleep 0.15

      log "Setting wallpaper on $MONITOR: $WALLPAPER"
      hyprctl hyprpaper wallpaper "$MONITOR,$WALLPAPER"
      hyprctl hyprpaper unload unused
    else
      log "Error: No valid wallpapers found in $WALLPAPER_DIR!"
    fi
  done
}

# Rotate wallpapers every X minutes
rotate_wallpapers() {
  while true; do
    apply_wallpapers || log "Wallpaper application failed, retrying..."
    sleep "$INTERVAL_SECONDS"
  done
}

main() {
  terminate_other_instances
  launch_hyprpaper
  if [[ -n "$RUN_ONCE" ]]; then
    log "Running only once..."
    apply_wallpapers
    exit 0
  fi
  rotate_wallpapers
}

main
