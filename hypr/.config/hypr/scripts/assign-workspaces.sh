#!/bin/bash
# hypr/.config/hypr/scripts/assign-workspaces.sh

# ========== CONFIG ========== #

# Define monitor description variables
LAPTOP="BOE 0x0C8E"
LEFT="HP Inc. HP Z22n G2 6CM8411J1Z"
CENTER="GIGA-BYTE TECHNOLOGY CO. LTD. G27QC A 0x00000D48"
VERTICAL="HP Inc. HP Z22n G2 6CM8411J22"

# Set primary monitor for XWayland
PRIMARY=CENTER

# Define workspace → monitor description mapping using variables
declare -A WORKSPACE_MAP=(
  [1]="$LAPTOP"
  [2]="$LEFT"
  [3]="$CENTER"
  [4]="$VERTICAL"
  [5]="$LAPTOP"
  [6]="$LAPTOP"
  [7]="$CENTER"
  [8]="$LEFT"
  [9]="$VERTICAL"
)

# ========== SCRIPT STATE (Global Arrays) ========== #

declare -A MONITOR_IDS
declare -A MONITOR_NAMES

# ========== HELPERS ========== #

# Log to journal and echo
log() {
  echo "$1"
  logger -t hypr-monitor "$1"
}

# ========== LOCIC ========== #

# Discover and map all connected monitors
map_monitors() {
  log "Discovering monitors..."
  # Clear previous state
  MONITOR_IDS=()
  MONITOR_NAMES=()

  mapfile -t MONITORS < <(hyprctl monitors -j | jq -r '.[] | "\(.description)|\(.id)|\(.name)"')
  for entry in "${MONITORS[@]}"; do
    # Use parameter expansion to split the string by the '|' delimiter
    DESC="${entry%%|*}"
    ID_NAME="${entry#*|}"
    ID="${ID_NAME%%|*}"
    NAME="${ID_NAME#*|}"

    MONITOR_IDS["$DESC"]="$ID"
    MONITOR_NAMES["$DESC"]="$NAME"
    log "Found monitor: '$DESC' with ID $ID on port $NAME"
  done
}

# Assign workspaces and focus the primary one on each monitor
update_hyprland_workspaces() {
  log "Updating Hyprland workspaces..."
  # Assign workspaces to monitors
  for WS in "${!WORKSPACE_MAP[@]}"; do
    DESC="${WORKSPACE_MAP[$WS]}"
    MON_ID="${MONITOR_IDS[$DESC]}"
    if [[ -n "$MON_ID" ]]; then
      log "Assigning workspace $WS to monitor '$DESC' (ID $MON_ID)"
      hyprctl dispatch moveworkspacetomonitor "$WS $MON_ID"
    else
      log "Monitor description '$DESC' not found — skipping workspace $WS"
    fi
  done

  # Focus the lowest workspace number per monitor
  for DESC in "${!MONITOR_IDS[@]}"; do
    MON_ID="${MONITOR_IDS[$DESC]}"
    FIRST_WS=""
    for WS in "${!WORKSPACE_MAP[@]}"; do
      [[ "${WORKSPACE_MAP[$WS]}" == "$DESC" ]] &&
        { [[ -z "$FIRST_WS" || "$WS" -lt "$FIRST_WS" ]] && FIRST_WS="$WS"; }
    done
    if [[ -n "$FIRST_WS" ]]; then
      log "Focusing workspace $FIRST_WS on monitor '$DESC' (ID $MON_ID)"
      hyprctl dispatch focusmonitor "$MON_ID"
      hyprctl dispatch workspace "$FIRST_WS"
    fi
  done
}

# Set the primary monitor for XWayland applications
update_xwayland_primary() {
  log "Setting primary monitor for XWayland..."
  PRIMARY_MONITOR_DESC="${!PRIMARY}"
  PRIMARY_PORT_NAME="${MONITOR_NAMES[$PRIMARY_MONITOR_DESC]}"

  if [[ -n "$PRIMARY_PORT_NAME" ]]; then
    log "Setting XWayland primary monitor to '$PRIMARY_MONITOR_DESC' on port '$PRIMARY_PORT_NAME'"
    xrandr --output "$PRIMARY_PORT_NAME" --primary
  else
    log "Primary monitor description '$PRIMARY_MONITOR_DESC' not found for XWayland setup."
  fi
}

# ========== MAIN ========== #

# This function orchestrates the main routine
assign_workspaces() {
  log "Starting monitor configuration..."
  map_monitors
  update_hyprland_workspaces
  update_xwayland_primary
  log "Monitor configuration finished."
}

# ========== EVENT LISTENER ========== #

# Always watch for monitor events to update workspaces
monitor_socket() {
  SOCKET_PATH="$XDG_RUNTIME_DIR/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

  # Avoid duplicate listeners
  if pgrep -f "socat - UNIX-CONNECT:$SOCKET_PATH" >/dev/null; then
    log "socat already running, skipping listener setup"
    exit 0
  fi

  log "Starting socat listener for Hyprland monitor events"

  socat - "UNIX-CONNECT:$SOCKET_PATH" |
    while read -r line; do
      if [[ "$line" == monitoradded* || "$line" == monitorremoved* ]]; then
        log "Triggering assign_workspaces due to: $line"
        assign_workspaces
      fi
    done
}

# ========== SCIPT ENTRY =========== #

# Parse named arguments
for arg in "$@"; do
  case "$arg" in
  --assign)
    DO_ASSIGN=true
    ;;
  --watch)
    DO_WATCH=true
    ;;
  esac
done

# Default to both if no args are provided
if [[ -z "$DO_ASSIGN" && -z "$DO_WATCH" ]]; then
  DO_ASSIGN=true
  DO_WATCH=true
fi

[[ "$DO_ASSIGN" == true ]] && assign_workspaces
[[ "$DO_WATCH" == true ]] && monitor_socket
