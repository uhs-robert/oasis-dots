#!/bin/bash
# hypr/.config/hypr/scripts/hypr-wallpaper-day-system.sh

# --- Defaults ---------------------------------------------------------------
DEFAULT_WALLPAPER_DIR="$HOME/Pictures/Wallpapers/Pixel Art"
DEFAULT_INTERVAL_MINUTES=15
SCRIPT_NAME=$(basename "$0")

# Period start hours (24h)
START_MORNING=7  # 07:00
START_DAY=10     # 10:00
START_EVENING=16 # 16:00
START_NIGHT=19   # 19:00

# Default per-period dirs (customize or override via flags)
DIR_MORNING="$HOME/Pictures/Wallpapers/Pixel Art/Morning"
DIR_DAY="$HOME/Pictures/Wallpapers/Pixel Art/Day"
DIR_EVENING="$HOME/Pictures/Wallpapers/Pixel Art/Evening"
DIR_NIGHT="$HOME/Pictures/Wallpapers/Pixel Art/Night"

# --- Args -------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
  --interval | -i)
    INTERVAL_MINUTES="$2"
    shift 2
    ;;
  --dir | -d)
    WALLPAPER_DIR="$2"
    WALLPAPER_DIR_FORCED=1
    shift 2
    ;;
  --dir-morning)
    DIR_MORNING="$2"
    shift 2
    ;;
  --dir-day)
    DIR_DAY="$2"
    shift 2
    ;;
  --dir-evening)
    DIR_EVENING="$2"
    shift 2
    ;;
  --dir-night)
    DIR_NIGHT="$2"
    shift 2
    ;;
  --morning-hour)
    START_MORNING="$2"
    shift 2
    ;;
  --day-hour)
    START_DAY="$2"
    shift 2
    ;;
  --evening-hour)
    START_EVENING="$2"
    shift 2
    ;;
  --night-hour)
    START_NIGHT="$2"
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
    cat <<USAGE
Usage: $SCRIPT_NAME [options]

Rotation:
  -i, --interval MIN     Minutes between rotations (default: $DEFAULT_INTERVAL_MINUTES)
  -o, --once             Run once and exit

Verbosity:
  -v, --verbose          Log to system logger

Folders:
  -d, --dir DIR          Force one folder (disables time-based switching)
      --dir-morning DIR  Folder for morning
      --dir-day DIR      Folder for day
      --dir-evening DIR  Folder for evening
      --dir-night DIR    Folder for night

Period boundaries (24h, integers):
      --morning-hour H   Start of morning (default: $START_MORNING)
      --day-hour H       Start of day     (default: $START_DAY)
      --evening-hour H   Start of evening (default: $START_EVENING)
      --night-hour H     Start of night   (default: $START_NIGHT)
USAGE
    exit 0
    ;;
  *)
    echo "Unknown argument: $1"
    exit 1
    ;;
  esac
done

# --- Config -----------------------------------------------------------------
INTERVAL_MINUTES="${INTERVAL_MINUTES:-$DEFAULT_INTERVAL_MINUTES}"
INTERVAL_SECONDS=$((INTERVAL_MINUTES * 60))

log() { [[ -n "$VERBOSE" ]] && logger -t "$SCRIPT_NAME" "$1"; }

# --- Single instance guard --------------------------------------------------
terminate_other_instances() {
  local self="$0"
  local count
  count=$(pgrep -fc "$self")
  if [[ "$count" -gt 1 ]]; then
    local pids
    pids=$(pgrep -fx "$self")
    log "Another instance is running (PIDs: $pids); killing them..."
    pkill -fx "$self"
    sleep 1
  fi
}

# --- Hyprpaper --------------------------------------------------------------
launch_hyprpaper() {
  if ! pgrep -x "hyprpaper" >/dev/null; then
    log "Launching hyprpaper..."
    hyprpaper &
    disown
    sleep 1
  fi
}

# --- Time-of-day logic ------------------------------------------------------
current_period() {
  local h
  h=$(date +%H) # 00..23
  # Normalize boundaries in case user makes them weird
  local m=$((10#$START_MORNING))
  local d=$((10#$START_DAY))
  local e=$((10#$START_EVENING))
  local n=$((10#$START_NIGHT))

  # Assume monotonic m<d<e<n (reasonable defaults). If not, the order below still segments the day.
  if ((h >= n || h < m)); then
    echo "night"
  elif ((h >= m && h < d)); then
    echo "morning"
  elif ((h >= d && h < e)); then
    echo "day"
  else
    echo "evening"
  fi
}

resolve_wallpaper_dir() {
  # If user forced a single directory, honor it
  if [[ -n "$WALLPAPER_DIR_FORCED" && -n "$WALLPAPER_DIR" ]]; then
    echo "$WALLPAPER_DIR"
    return
  fi

  local period dir
  period=$(current_period)
  case "$period" in
  morning) dir="$DIR_MORNING" ;;
  day) dir="$DIR_DAY" ;;
  evening) dir="$DIR_EVENING" ;;
  night) dir="$DIR_NIGHT" ;;
  esac

  # Fallback chain: period dir -> default dir -> Pixel Art default
  if [[ -d "$dir" ]] && find_wallpaper_files "$dir" | grep -q .; then
    echo "$dir"
  elif [[ -n "$DEFAULT_WALLPAPER_DIR" ]] && [[ -d "$DEFAULT_WALLPAPER_DIR" ]]; then
    echo "$DEFAULT_WALLPAPER_DIR"
  else
    # Last resort: use period dir even if empty; apply_wallpapers will error out cleanly
    echo "$dir"
  fi
}

# --- Selection helpers ------------------------------------------------------
find_wallpaper_files() {
  local dir="$1"
  find -L "$dir" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.bmp' \)
}

get_unique_wallpapers() {
  local dir="$1"
  local count="$2"
  local available_wallpapers wallpaper_count

  mapfile -t available_wallpapers < <(find_wallpaper_files "$dir")
  wallpaper_count=${#available_wallpapers[@]}

  if [[ $wallpaper_count -eq 0 ]]; then
    return 1
  fi

  if [[ $wallpaper_count -ge $count ]]; then
    # Enough wallpapers for unique selection
    printf '%s\n' "${available_wallpapers[@]}" | shuf | head -n "$count"
  else
    # Not enough wallpapers - repeat as needed, but still randomized
    for ((i = 0; i < count; i++)); do
      echo "${available_wallpapers[$((i % wallpaper_count))]}"
    done | shuf
  fi
}

# --- Apply to monitors ------------------------------------------------------
apply_wallpapers() {
  local dir
  dir=$(resolve_wallpaper_dir)
  local period
  period=$(current_period)

  if ! find_wallpaper_files "$dir" | grep -q .; then
    log "No wallpapers found in $dir (period: $period). Exiting."
    return 1
  fi

  mapfile -t MONITORS < <(hyprctl monitors | awk '/Monitor/ {print $2}')
  local monitor_count=${#MONITORS[@]}

  # Get unique wallpapers for all monitors at once
  mapfile -t WALLPAPERS < <(get_unique_wallpapers "$dir" "$monitor_count")

  log "Period: $period → Directory: $dir"
  log "Found ${#WALLPAPERS[@]} unique wallpapers for $monitor_count monitors"

  for i in "${!MONITORS[@]}"; do
    local MONITOR="${MONITORS[$i]}"
    local WALLPAPER="${WALLPAPERS[$i]}"

    if [[ -f "$WALLPAPER" ]]; then
      log "Preloading wallpaper: $WALLPAPER"
      hyprctl hyprpaper preload "$WALLPAPER"
      sleep 0.15
      log "Setting wallpaper on $MONITOR: $WALLPAPER"
      hyprctl hyprpaper wallpaper "$MONITOR,$WALLPAPER"
      hyprctl hyprpaper unload unused
    else
      log "Error: Unable to pick a wallpaper from $dir for monitor $MONITOR"
    fi
  done
}

# --- Rotation loop ----------------------------------------------------------
rotate_wallpapers() {
  while true; do
    apply_wallpapers || log "Wallpaper application failed; will retry."
    sleep "$INTERVAL_SECONDS"
  done
}

# --- Main -------------------------------------------------------------------
main() {
  terminate_other_instances
  launch_hyprpaper

  if [[ -n "$RUN_ONCE" ]]; then
    log "Running only once..."
    apply_wallpapers
    exit $?
  fi

  rotate_wallpapers
}

main
