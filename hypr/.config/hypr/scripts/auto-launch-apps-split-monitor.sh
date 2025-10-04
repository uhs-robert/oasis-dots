#!/usr/bin/env bash
# hypr/.config/hypr/scripts/auto-launch-apps-split-monitor.sh

# ─── Globals ────────────────────────────────────────────────────────────────
PAIRS=()
WORKSPACES=()
FIREFOX_WORKSPACES=()
FIREFOX_WINDOWS=()

# Monitor mapping: names to indices
declare -A MONITOR_MAP=(
  ["LAPTOP"]=0
  ["LEFT"]=1
  ["RIGHT"]=2
  ["CENTER"]=3
)

# Runtime tracking
declare -A MONITOR_CURRENT_WS # track current workspace per monitor name
declare -A WORKSPACE_USAGE    # track number of apps assigned to each workspace
if [[ "$1" == "--startup" ]]; then
  IS_STARTUP=true
else
  IS_STARTUP=false
fi

# ─── Exit Routine ───────────────────────────────────────────────────────────
clean_up() {
  log "Exiting session selection..."
  if [[ "$IS_STARTUP" == true ]]; then
    wait_for_windows
    hyprctl dispatch focusmonitor 0
    hyprctl dispatch workspace 1
  fi
}
trap clean_up EXIT

# ─── Reusable Application Blocks ────────────────────────────────────────────
declare -A APPS

## Firefox: triple monitor default
FIREFOX_TRIPLE_MONITORS=("CENTER+:firefox" "LAPTOP+:firefox" "LEFT+:firefox")
APPS["Firefox"]=$(
  IFS='|'
  echo "${FIREFOX_TRIPLE_MONITORS[*]}"
)

## Email client
APPS["Email"]="LAPTOP+:flatpak run eu.betterbird.Betterbird"

## Terminal sessions
### tmuxifier: load a tmuxifier session on a monitor (default monitor=RIGHT)
tmuxifier() {
  local session="$1"
  local monitor="${2:-RIGHT}"
  echo "${monitor}+:kitty -e tmuxifier load-session $session"
}

### tmux: create or attach to a tmux session by name on a monitor (default monitor=RIGHT)
tmux() {
  local name="$1"
  local monitor="${2:-RIGHT}"
  echo "${monitor}+:kitty -e tmux new -A -s $name"
}

## Slack
APPS["Slack"]="LAPTOP+:slack"

## File manager
APPS["Yazi"]="RIGHT+:kitty -e yazi"
APPS["Dolphin"]="CENTER+:dolphin"

## Monitoring tools
APPS["Journal"]="CENTER+:kitty -e journalctl -f"
APPS["Btop"]="RIGHT+:kitty -e btop"

# ─── Setup Definitions ──────────────────────────────────────────────────────

declare -A SETUPS
SETUPS["🌐 Browsing"]="${APPS["Firefox"]}|$(tmuxifier config)"
SETUPS["🧱 Client"]="${APPS["Firefox"]}|$(tmuxifier client-dev)|$(tmuxifier config CENTER)|${APPS["Slack"]}|${APPS["Email"]}"
SETUPS["🛠 Config"]="${APPS["Firefox"]}|$(tmuxifier config)|${APPS["Email"]}"
SETUPS["🗂 Files"]="${APPS["Dolphin"]}|${APPS["Yazi"]}"
SETUPS["🧩 Game Mods"]="LEFT+:steam|CENTER+:kitty -d ~/Downloads/ yazi|RIGHT+:kitty -d ~/.steam/steam/steamapps/ yazi"
SETUPS["🎮 Game"]="LEFT+:steam"
SETUPS["📅 Meeting"]="LAPTOP+:firefox https://calendar.google.com/|CENTER+:firefox"
SETUPS["📊 System Monitor"]="${APPS["Journal"]}|${APPS["Btop"]}"
SETUPS["🛡️ DNF Update"]="LEFT+:kitty -e sysup|${APPS["Journal"]}"
SETUPS["💼 Work"]="${APPS["Firefox"]}|$(tmuxifier uphill)|$(tmuxifier config CENTER)|${APPS["Slack"]}|${APPS["Email"]}"

# Log to journal and echo
log() {
  echo "$1" >&2
  logger -t hypr-launcher "$1"
}

# Get workspace range for a monitor name
get_monitor_workspaces() {
  local monitor_name="$1"
  local index="${MONITOR_MAP[$monitor_name]}"

  if [[ -z "$index" ]]; then
    log "Error: Unknown monitor name '$monitor_name'"
    return 1
  fi

  local start=$((index * 5 + 1))
  local end=$((index * 5 + 5))
  echo "$start $end"
}

# Check if a workspace has windows
workspace_has_windows() {
  local workspace="$1"
  local window_count=$(hyprctl workspaces -j | jq -r ".[] | select(.id==$workspace) | .windows")
  [[ "${window_count:-0}" -gt 0 ]]
}

# Find the workspace with the least windows in a range
find_least_used_workspace() {
  local start_ws="$1"
  local end_ws="$2"

  local least_used_ws="$start_ws"
  local min_windows=$(hyprctl workspaces -j | jq -r ".[] | select(.id==$start_ws) | .windows // 0")

  for ws in $(seq $((start_ws + 1)) $end_ws); do
    local window_count=$(hyprctl workspaces -j | jq -r ".[] | select(.id==$ws) | .windows // 0")
    if [[ $window_count -lt $min_windows ]]; then
      min_windows="$window_count"
      least_used_ws="$ws"
    fi
  done

  log "Least used workspace in range $start_ws-$end_ws: $least_used_ws ($min_windows windows)"
  echo "$least_used_ws"
}

# Get next available workspace on a monitor
get_next_workspace() {
  local monitor_name="$1"
  local force_increment="${2:-false}"

  read -r start_ws end_ws < <(get_monitor_workspaces "$monitor_name")
  [[ $? -ne 0 ]] && return 1

  local current_ws="${MONITOR_CURRENT_WS[$monitor_name]:-$start_ws}"

  if [[ "$force_increment" == "true" ]]; then
    # For + syntax: find first available workspace or increment from current
    if [[ -z "${MONITOR_CURRENT_WS[$monitor_name]}" ]]; then
      # First assignment for this monitor - find first empty workspace with no pending usage
      current_ws="$start_ws"
      while [[ $current_ws -le $end_ws ]]; do
        if ! workspace_has_windows "$current_ws" && [[ "${WORKSPACE_USAGE[$current_ws]:-0}" -eq 0 ]]; then
          log "Found empty workspace $current_ws on monitor $monitor_name"
          break
        fi
        current_ws=$((current_ws + 1))
      done
      # If all workspaces have windows, find the least-used one
      if [[ $current_ws -gt $end_ws ]]; then
        current_ws=$(find_least_used_workspace "$start_ws" "$end_ws")
        log "All workspaces on $monitor_name have windows, using least-used: $current_ws"
      fi
    elif workspace_has_windows "$current_ws" || [[ "${WORKSPACE_USAGE[$current_ws]:-0}" -gt 0 ]]; then
      # Current workspace has windows OR we've already assigned something to it in this run
      local prev_ws="$current_ws"
      current_ws=$((current_ws + 1))
      if [[ $current_ws -gt $end_ws ]]; then
        current_ws=$start_ws # Wrap around
      fi
      log "Workspace $prev_ws has windows or assignments, incrementing to $current_ws"
    else
      # Current workspace is empty and unused, reuse it
      log "Workspace $current_ws is empty and unused, reusing it"
    fi
  else
    # Non-increment behavior (though all our setups now use +)
    if [[ -z "${MONITOR_CURRENT_WS[$monitor_name]}" ]]; then
      current_ws="$start_ws"
    fi
  fi

  # Update tracking
  MONITOR_CURRENT_WS["$monitor_name"]="$current_ws"
  WORKSPACE_USAGE["$current_ws"]=$((${WORKSPACE_USAGE[$current_ws]:-0} + 1))

  log "Assigned workspace $current_ws on monitor $monitor_name (usage: ${WORKSPACE_USAGE[$current_ws]})"
  echo "$current_ws"
}

# Prompt to select a setup session, optionally on workspace 1 (for startup)
select_session() {
  local selected
  if [[ "$IS_STARTUP" == true ]]; then
    hyprctl dispatch workspace 1
    sleep 0.1
    selected=$(printf "%s\n" "${!SETUPS[@]}" | WOFI_MONITOR=0 wofi --dmenu --columns 1 -p "Select session")
  else
    selected=$(printf "%s\n" "${!SETUPS[@]}" | wofi --dmenu --columns 1 -p "Select session")
  fi
  echo "$selected"
}

# Parse selected session into PAIRS array of "monitor:command" or "monitor+:command"
parse_pairs() {
  IFS='|' read -ra PAIRS <<<"${SETUPS["$1"]}"
}

# Resolve monitor assignments to actual workspaces and collect Firefox assignments
resolve_monitor_assignments() {
  WORKSPACES=()
  FIREFOX_WORKSPACES=()

  for pair in "${PAIRS[@]}"; do
    # Parse monitor assignment: MONITOR[:+]:command
    local monitor_part="${pair%%:*}"
    local cmd="${pair#*:}"

    # Check for increment flag
    local force_increment="false"
    if [[ "$monitor_part" == *"+" ]]; then
      force_increment="true"
      monitor_part="${monitor_part%+}"
    fi

    # Get workspace for this monitor
    local ws
    ws=$(get_next_workspace "$monitor_part" "$force_increment")
    if [[ $? -eq 0 && -n "$ws" ]]; then
      WORKSPACES+=("$ws")
      [[ "$cmd" == "firefox" ]] && FIREFOX_WORKSPACES+=("$ws")
      log "Resolved $pair -> workspace $ws"
    else
      log "Warning: Failed to resolve monitor assignment: $pair"
    fi
  done
}

# Preload all required workspaces to ensure proper window placement
map_workspaces() {
  for WS in "${WORKSPACES[@]}"; do
    log "Preloading workspace $WS"
    hyprctl dispatch workspace "$WS"
    sleep 0.1
  done
  hyprctl dispatch workspace 1
}

# Launch all non-Firefox applications on their assigned workspaces
launch_non_firefox_apps() {
  local workspace_index=0

  for pair in "${PAIRS[@]}"; do
    # Parse the monitor assignment
    local monitor_part="${pair%%:*}"
    local cmd="${pair#*:}"

    # Skip Firefox (handled separately)
    if [[ "$cmd" == "firefox" ]]; then
      ((workspace_index++))
      continue
    fi

    # Get the resolved workspace for this assignment
    local ws="${WORKSPACES[$workspace_index]}"

    if [[ -n "$ws" ]]; then
      if [[ "$cmd" == flatpak\ run* ]]; then
        log "hyprctl dispatch exec '$cmd'"
        hyprctl dispatch exec "$cmd"
      else
        log "hyprctl dispatch exec '[workspace $ws silent] $cmd'"
        hyprctl dispatch exec "[workspace $ws silent] $cmd"
      fi
    else
      log "Warning: No workspace resolved for $pair"
    fi

    ((workspace_index++))
  done
}

# Launch Firefox and distribute windows to specified workspaces
handle_firefox() {
  [[ ${#FIREFOX_WORKSPACES[@]} -eq 0 ]] && return

  log "[workspace ${FIREFOX_WORKSPACES[0]} silent] firefox"
  hyprctl dispatch exec "[workspace ${FIREFOX_WORKSPACES[0]} silent] firefox"

  local EXPECTED=${#FIREFOX_WORKSPACES[@]}
  local TIMEOUT=10 ELAPSED=0
  while ((ELAPSED < TIMEOUT)); do
    mapfile -t FIREFOX_WINDOWS < <(hyprctl clients -j | jq -r '.[] | select(.class=="org.mozilla.firefox") | .address')
    log "Waiting for Firefox windows... found ${#FIREFOX_WINDOWS[@]}"
    ((${#FIREFOX_WINDOWS[@]} >= EXPECTED)) && break
    sleep 1
    ((ELAPSED++))
  done

  for i in "${!FIREFOX_WORKSPACES[@]}"; do
    [[ -n "${FIREFOX_WINDOWS[$i]}" ]] || continue
    WS="${FIREFOX_WORKSPACES[$i]}"
    ADDR="${FIREFOX_WINDOWS[$i]}"
    log "Moving Firefox window $ADDR to workspace $WS"
    hyprctl dispatch focuswindow address:$ADDR
    hyprctl dispatch movetoworkspacesilent "$WS"
  done
}

# (STARTUP Only) Waits until all expected windows from PAIRS are visible
wait_for_windows() {
  local expected=${#PAIRS[@]}
  local timeout=10
  local waited=0

  log "Waiting for $expected windows to appear..."

  while ((waited < timeout)); do
    window_count=$(hyprctl clients -j | jq length)
    if ((window_count >= expected)); then
      log "Detected $window_count windows of $expected."
      return
    fi
    sleep 1
    ((waited++))
  done

  log "Warning - Detected only $window_count windows of $expected after $waited seconds."
}

# Main control function: runs session selection and setup sequence
launch_selector() {
  log "Prompting user session selection..."
  # Prompt user selection
  local CHOICE
  if [[ "$IS_STARTUP" == true ]]; then
    hyprctl dispatch workspace 1
    sleep 0.1
    CHOICE=$(printf "%s\n" "${!SETUPS[@]}" | WOFI_MONITOR=0 wofi --dmenu --columns 1 -p "Select session")
  else
    CHOICE=$(printf "%s\n" "${!SETUPS[@]}" | wofi --dmenu --columns 1 -p "Select session")
  fi
  [[ -z "$CHOICE" ]] && exit 0

  log "User selected $CHOICE"

  # Parse and resolve monitor assignments
  parse_pairs "$CHOICE"
  resolve_monitor_assignments

  # Preload workspaces and launch apps
  map_workspaces
  launch_non_firefox_apps
  handle_firefox
}

launch_selector
