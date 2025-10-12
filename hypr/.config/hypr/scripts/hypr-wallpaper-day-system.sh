#!/bin/bash
# hypr/.config/hypr/scripts/hypr-wallpaper-day-system.sh

# --- Defaults ---------------------------------------------------------------
DEFAULT_WALLPAPER_DIR="$HOME/Pictures/Wallpapers/Pixel Art"
DEFAULT_INTERVAL_MINUTES=15
SCRIPT_NAME=$(basename "$0")

# Period start hours (24h)
START_MORNING=6  # 06:00
START_DAY=11     # 11:00
START_EVENING=16 # 16:00
START_NIGHT=19   # 19:00

# Default per-period dirs (customize or override via flags)
DIR_MORNING="$HOME/Pictures/Wallpapers/Pixel Art/Morning"
DIR_DAY="$HOME/Pictures/Wallpapers/Pixel Art/Day"
DIR_EVENING="$HOME/Pictures/Wallpapers/Pixel Art/Evening"
DIR_NIGHT="$HOME/Pictures/Wallpapers/Pixel Art/Night"

# Location detection state (in-memory only)
CURRENT_IP=""
CURRENT_LAT=""
CURRENT_LON=""
SUNRISE_HOUR=""
SUNSET_HOUR=""
LOCATION_ENABLED=1
LAST_LOCATION_UPDATE=0
LOCATION_REFRESH_INTERVAL=14400 # 4 hours in seconds
MANUAL_LAT=""                   # User-provided latitude override
MANUAL_LON=""                   # User-provided longitude override

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
  --no-location)
    LOCATION_ENABLED=0
    shift
    ;;
  --latitude)
    MANUAL_LAT="$2"
    shift 2
    ;;
  --longitude)
    MANUAL_LON="$2"
    shift 2
    ;;
  --coordinates)
    if [[ "$2" =~ ^-?[0-9]+\.?[0-9]*,-?[0-9]+\.?[0-9]*$ ]]; then
      MANUAL_LAT=$(echo "$2" | cut -d, -f1)
      MANUAL_LON=$(echo "$2" | cut -d, -f2)
    else
      echo "Invalid coordinate format. Use: --coordinates lat,lon (e.g., --coordinates 40.7128,-74.0060)"
      exit 1
    fi
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

Location options (automatic detection enabled by default):
      --no-location      Disable location detection, use fixed times
      --latitude LAT     Manual latitude override (-90 to 90)
      --longitude LON    Manual longitude override (-180 to 180)
      --coordinates LAT,LON  Manual coordinates (e.g., 40.7128,-74.0060)
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

# --- Coordinate validation --------------------------------------------------
validate_coordinates() {
  local lat="$1" lon="$2"

  # Check if values are numeric
  if ! [[ "$lat" =~ ^-?[0-9]+\.?[0-9]*$ ]] || ! [[ "$lon" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
    echo "Error: Coordinates must be numeric values"
    return 1
  fi

  # Validate latitude range (-90 to 90)
  if (($(echo "$lat < -90 || $lat > 90" | bc -l 2>/dev/null || echo 1))); then
    echo "Error: Latitude must be between -90 and 90 degrees (got: $lat)"
    return 1
  fi

  # Validate longitude range (-180 to 180)
  if (($(echo "$lon < -180 || $lon > 180" | bc -l 2>/dev/null || echo 1))); then
    echo "Error: Longitude must be between -180 and 180 degrees (got: $lon)"
    return 1
  fi

  return 0
}

# --- Location detection functions -------------------------------------------
get_location_data() {
  local ip loc

  # Get IP address from plain text endpoint
  ip=$(curl -s --max-time 3 https://ipinfo.io/ip 2>/dev/null)

  if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # Get coordinates for this IP from plain text endpoint
    loc=$(curl -s --max-time 3 "https://ipinfo.io/${ip}/loc" 2>/dev/null)

    if [[ -n "$loc" && "$loc" =~ ^-?[0-9]+\.?[0-9]*,-?[0-9]+\.?[0-9]*$ ]]; then
      # Set global variables directly
      CURRENT_IP="$ip"
      CURRENT_LAT=$(echo "$loc" | cut -d, -f1)
      CURRENT_LON=$(echo "$loc" | cut -d, -f2)
      return 0
    fi
  fi

  return 1
}

get_coordinates_fallback() {
  local timezone
  timezone=$(timedatectl show -p Timezone --value 2>/dev/null)

  case "$timezone" in
  America/New_York | America/Detroit | America/Toronto) echo "40.7,-74.0" ;;
  America/Chicago | America/Winnipeg) echo "41.8,-87.6" ;;
  America/Denver | America/Edmonton) echo "39.7,-104.9" ;;
  America/Los_Angeles | America/Vancouver) echo "34.0,-118.2" ;;
  America/Phoenix) echo "33.4,-112.0" ;;
  Europe/London) echo "51.5,-0.1" ;;
  Europe/Paris | Europe/Berlin | Europe/Rome) echo "48.8,2.3" ;;
  Europe/Moscow) echo "55.7,37.6" ;;
  Asia/Tokyo) echo "35.6,139.6" ;;
  Asia/Shanghai | Asia/Hong_Kong) echo "31.2,121.4" ;;
  Australia/Sydney) echo "-33.8,151.2" ;;
  *) echo "40.0,-74.0" ;; # ISSUE: Should default instead to the fixed times
  esac
}

get_sun_times_api() {
  local lat="$1" lon="$2"
  local json sunrise_utc sunset_utc sunrise_local sunset_local

  # Call Open-Meteo API for sunrise/sunset data
  json=$(curl -s --max-time 3 "https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&daily=sunrise,sunset&timezone=auto" 2>/dev/null)

  if [[ -z "$json" ]]; then
    return 1
  fi

  # Extract today's sunrise and sunset using grep and cut (no jq required)
  sunrise_utc=$(echo "$json" | grep -o '"sunrise":\["[^"]*"' | cut -d'"' -f4)
  sunset_utc=$(echo "$json" | grep -o '"sunset":\["[^"]*"' | cut -d'"' -f4)

  if [[ -n "$sunrise_utc" && -n "$sunset_utc" ]]; then
    # Convert to local time and extract hour and minute
    local sunrise_local_time sunset_local_time sunrise_h sunrise_m sunset_h sunset_m
    sunrise_local_time=$(date -d "$sunrise_utc" +%H%M 2>/dev/null)
    sunset_local_time=$(date -d "$sunset_utc" +%H%M 2>/dev/null)

    if [[ -n "$sunrise_local_time" && -n "$sunset_local_time" ]]; then
      # Extract hour and minute from HHMM format
      sunrise_h=$(echo "$sunrise_local_time" | cut -c1-2)
      sunrise_m=$(echo "$sunrise_local_time" | cut -c3-4)
      sunset_h=$(echo "$sunset_local_time" | cut -c1-2)
      sunset_m=$(echo "$sunset_local_time" | cut -c3-4)

      # Remove leading zeros for arithmetic
      sunrise_h=$((10#$sunrise_h))
      sunrise_m=$((10#$sunrise_m))
      sunset_h=$((10#$sunset_h))
      sunset_m=$((10#$sunset_m))

      # Round minutes down to nearest 15-minute interval (0, 15, 30, 45)
      sunrise_m=$(((sunrise_m / 15) * 15))
      sunset_m=$(((sunset_m / 15) * 15))

      # Use the base hour for period calculations
      SUNRISE_HOUR=$sunrise_h
      SUNSET_HOUR=$sunset_h

      log "Sun times via API: sunrise=${sunrise_h}:$(printf "%02d" $sunrise_m) (${SUNRISE_HOUR}h), sunset=${sunset_h}:$(printf "%02d" $sunset_m) (${SUNSET_HOUR}h)"
      return 0
    fi
  fi

  return 1
}

get_sun_times() {
  local lat="$1" lon="$2"

  # Try sunwait first (more precise, local calculation)
  if command -v sunwait >/dev/null 2>&1; then
    local lat_formatted lon_formatted sunwait_output sunrise_time sunset_time

    # Convert coordinates to sunwait format (e.g., 40.7128N 74.0060W)
    if (($(echo "$lat >= 0" | bc -l 2>/dev/null || echo 0))); then
      lat_formatted="${lat#-}N"
    else
      lat_formatted="${lat#-}S"
    fi

    if (($(echo "$lon >= 0" | bc -l 2>/dev/null || echo 0))); then
      lon_formatted="${lon#-}E"
    else
      lon_formatted="${lon#-}W"
    fi

    sunwait_output=$(sunwait -p "$lat_formatted" "$lon_formatted" 2>/dev/null)

    if [[ -n "$sunwait_output" ]]; then
      # Extract sunrise and sunset times from the output
      sunrise_time=$(echo "$sunwait_output" | grep "Sun rises" | awk '{print $3}' | cut -d, -f1)
      sunset_time=$(echo "$sunwait_output" | grep "Sun rises" | awk '{print $6}')

      if [[ -n "$sunrise_time" && -n "$sunset_time" ]]; then
        # Extract hour and minute from HHMM format (e.g., 0646 -> 06:46, 1848 -> 18:48)
        local sunrise_h sunrise_m sunset_h sunset_m
        sunrise_h=$(echo "$sunrise_time" | cut -c1-2)
        sunrise_m=$(echo "$sunrise_time" | cut -c3-4)
        sunset_h=$(echo "$sunset_time" | cut -c1-2)
        sunset_m=$(echo "$sunset_time" | cut -c3-4)

        # Remove leading zeros for arithmetic
        sunrise_h=$((10#$sunrise_h))
        sunrise_m=$((10#$sunrise_m))
        sunset_h=$((10#$sunset_h))
        sunset_m=$((10#$sunset_m))

        # Round minutes down to nearest 15-minute interval (0, 15, 30, 45)
        sunrise_m=$(((sunrise_m / 15) * 15))
        sunset_m=$(((sunset_m / 15) * 15))

        SUNRISE_HOUR=$(echo "$sunrise_h + $sunrise_m / 60.0" | bc -l 2>/dev/null || echo "$sunrise_h")
        SUNSET_HOUR=$(echo "$sunset_h + $sunset_m / 60.0" | bc -l 2>/dev/null || echo "$sunset_h")

        log "Sun times via sunwait: sunrise=${sunrise_h}:$(printf "%02d" $sunrise_m) (${SUNRISE_HOUR}h), sunset=${sunset_h}:$(printf "%02d" $sunset_m) (${SUNSET_HOUR}h)"
        return 0
      fi
    fi
  fi

  # Fallback to Open-Meteo API if sunwait unavailable or failed
  log "sunwait unavailable or failed, trying Open-Meteo API..."
  if get_sun_times_api "$lat" "$lon"; then
    log "Sun times via Open-Meteo API: sunrise=${SUNRISE_HOUR}h, sunset=${SUNSET_HOUR}h"
    return 0
  fi

  log "All sunrise/sunset methods failed"
  return 1
}

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

# --- Location management functions ------------------------------------------
initialize_location() {
  local json coords lat lon

  # Priority 1: Manual coordinates override everything
  if [[ -n "$MANUAL_LAT" && -n "$MANUAL_LON" ]]; then
    if ! validate_coordinates "$MANUAL_LAT" "$MANUAL_LON"; then
      echo "Invalid manual coordinates provided"
      exit 1
    fi

    CURRENT_LAT="$MANUAL_LAT"
    CURRENT_LON="$MANUAL_LON"
    log "Using manual coordinates: $MANUAL_LAT,$MANUAL_LON"

    if get_sun_times "$CURRENT_LAT" "$CURRENT_LON"; then
      LOCATION_ENABLED=1
      LAST_LOCATION_UPDATE=$(date +%s)
      log "Location initialized with manual coordinates"
      return 0
    else
      log "Failed to get sun times for manual coordinates, falling back to fixed periods"
      LOCATION_ENABLED=0
      return 1
    fi
  fi

  # Priority 2: Automatic location detection
  log "Initializing automatic location detection..."

  if get_location_data; then
    log "Got coordinates from IP: $CURRENT_LAT,$CURRENT_LON"
    if get_sun_times "$CURRENT_LAT" "$CURRENT_LON"; then
      LOCATION_ENABLED=1
      LAST_LOCATION_UPDATE=$(date +%s)
      log "Location initialized via IP geolocation"
      return 0
    fi
  fi

  # Priority 3: Timezone fallback
  log "Trying timezone-based location fallback..."
  coords=$(get_coordinates_fallback)
  lat=$(echo "$coords" | cut -d, -f1)
  lon=$(echo "$coords" | cut -d, -f2)
  CURRENT_LAT="$lat"
  CURRENT_LON="$lon"

  if get_sun_times "$lat" "$lon"; then
    LOCATION_ENABLED=1
    LAST_LOCATION_UPDATE=$(date +%s)
    log "Location initialized via timezone fallback"
    return 0
  fi

  log "All location methods failed, using fixed time periods"
  LOCATION_ENABLED=0
  return 1
}

check_location_refresh() {
  # Skip refresh if using manual coordinates
  if [[ -n "$MANUAL_LAT" && -n "$MANUAL_LON" ]]; then
    return 0
  fi

  local current_time time_since_update json old_lat old_lon

  current_time=$(date +%s)
  time_since_update=$((current_time - LAST_LOCATION_UPDATE))

  # Only refresh if it's been 4+ hours since last successful lookup
  if [[ $time_since_update -lt $LOCATION_REFRESH_INTERVAL ]]; then
    return 0
  fi

  log "Location data is ${time_since_update}s old (>${LOCATION_REFRESH_INTERVAL}s), refreshing..."

  # Store current values for comparison
  old_lat="$CURRENT_LAT"
  old_lon="$CURRENT_LON"

  if get_location_data; then
    LAST_LOCATION_UPDATE=$current_time

    if [[ "$CURRENT_LAT" != "$old_lat" || "$CURRENT_LON" != "$old_lon" ]]; then
      log "Location changed: $old_lat,$old_lon → $CURRENT_LAT,$CURRENT_LON"

      if get_sun_times "$CURRENT_LAT" "$CURRENT_LON"; then
        log "Updated sun times: sunrise=${SUNRISE_HOUR}h, sunset=${SUNSET_HOUR}h"
        update_sun_based_periods
      fi
    else
      log "Location unchanged after refresh: $CURRENT_LAT,$CURRENT_LON"
    fi
  else
    log "Location refresh failed, keeping last known location (will retry in 4h)"
    # Don't update LAST_LOCATION_UPDATE on failure - will retry sooner
  fi
}

update_sun_based_periods() {
  if [[ "$LOCATION_ENABLED" -eq 1 && -n "$SUNRISE_HOUR" && -n "$SUNSET_HOUR" ]]; then
    # Adjust periods based on precise sunrise/sunset times
    ## Morning: 4.25 hours
    ## Day: Variable
    ## Evening: 3 Hours
    ## Night: Variable
    START_MORNING=$(echo "$SUNRISE_HOUR - 0.25" | bc -l 2>/dev/null || echo "$((${SUNRISE_HOUR%%.*} - 1))") # Morning starts 15min before sunrise
    START_DAY=$(echo "$SUNRISE_HOUR + 4" | bc -l 2>/dev/null || echo "$((${SUNRISE_HOUR%%.*} + 4))")        # Longer morning
    START_EVENING=$(echo "$SUNSET_HOUR - 2.75" | bc -l 2>/dev/null || echo "$((${SUNSET_HOUR%%.*} - 3))")   # Evening before sunset
    START_NIGHT=$(echo "$SUNSET_HOUR + 0.25" | bc -l 2>/dev/null || echo "$((${SUNSET_HOUR%%.*} + 1))")     # Night starts 15min after sunset

    # Ensure bounds are reasonable (handle decimal wrap-around)
    if (($(echo "$START_MORNING < 0" | bc -l 2>/dev/null || echo 0))); then
      START_MORNING="0"
    fi
    if (($(echo "$START_DAY > 23.75" | bc -l 2>/dev/null || echo 0))); then # 23:45
      START_DAY="23.75"
    fi
    if (($(echo "$START_EVENING > 23.75" | bc -l 2>/dev/null || echo 0))); then
      START_EVENING="23.75"
    fi
    if (($(echo "$START_NIGHT > 23.75" | bc -l 2>/dev/null || echo 0))); then
      START_NIGHT="0" # Wrap to next day
    fi

    log "Updated time periods: morning=${START_MORNING}h, day=${START_DAY}h, evening=${START_EVENING}h, night=${START_NIGHT}h"
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
  local h m current_time
  h=$(date +%H) # 00..23
  m=$(date +%M) # 00..59
  current_time=$(echo "$h + $m / 60.0" | bc -l 2>/dev/null || echo "$h")

  # Use bc for decimal comparisons if sun times are decimal, otherwise use integer comparison
  if [[ "$START_MORNING" =~ \. ]] || [[ "$START_DAY" =~ \. ]] || [[ "$START_EVENING" =~ \. ]] || [[ "$START_NIGHT" =~ \. ]]; then
    # Decimal comparison using bc
    if (($(echo "$current_time >= $START_NIGHT || $current_time < $START_MORNING" | bc -l 2>/dev/null || echo 0))); then
      echo "night"
    elif (($(echo "$current_time >= $START_MORNING && $current_time < $START_DAY" | bc -l 2>/dev/null || echo 0))); then
      echo "morning"
    elif (($(echo "$current_time >= $START_DAY && $current_time < $START_EVENING" | bc -l 2>/dev/null || echo 0))); then
      echo "day"
    else
      echo "evening"
    fi
  else
    # Integer comparison (fallback for static schedule)
    local m_int=$((10#${START_MORNING%%.*}))
    local d_int=$((10#${START_DAY%%.*}))
    local e_int=$((10#${START_EVENING%%.*}))
    local n_int=$((10#${START_NIGHT%%.*}))

    if ((h >= n_int || h < m_int)); then
      echo "night"
    elif ((h >= m_int && h < d_int)); then
      echo "morning"
    elif ((h >= d_int && h < e_int)); then
      echo "day"
    else
      echo "evening"
    fi
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
    [[ "$LOCATION_ENABLED" -eq 1 ]] && check_location_refresh
    apply_wallpapers || log "Wallpaper application failed; will retry."
    sleep "$INTERVAL_SECONDS"
  done
}

# --- Main -------------------------------------------------------------------
main() {
  terminate_other_instances
  launch_hyprpaper

  # Initialize location detection if enabled
  if [[ "$LOCATION_ENABLED" -eq 1 ]]; then
    initialize_location
    update_sun_based_periods
  else
    log "Location detection disabled"
  fi

  if [[ -n "$RUN_ONCE" ]]; then
    log "Running only once..."
    apply_wallpapers
    exit $?
  fi

  rotate_wallpapers
}

main
