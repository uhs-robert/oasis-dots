#!/usr/bin/env bash
# hypr/.config/hypr/scripts/auto-launch-apps-split-monitor.sh

# ─── Globals ────────────────────────────────────────────────────────────────
PAIRS=()
WORKSPACES=()
FIREFOX_WORKSPACES=()
FIREFOX_WINDOWS=()
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

# ─── Monitors ────────────────────────────────────────────────────────────────
declare -A MONITOR_IDS MONITOR_NAMES

map_monitors() {
  MONITOR_IDS=()
  MONITOR_NAMES=()
  mapfile -t MONS < <(hyprctl -j monitors | jq -r '.[] | select(.disabled==false) | "\(.description)|\(.id)|\(.name)"')
  for m in "${MONS[@]}"; do
    local DESC="${m%%|*}"
    local rest="${m#*|}"
    local ID="${rest%%|*}"
    local NAME="${rest#*|}"
    MONITOR_IDS["$DESC"]="$ID"
    MONITOR_NAMES["$DESC"]="$NAME"
  done
}
map_monitors

# ─── Workspace ring per monitor (discover from Hyprland) ────────────────────
# We will discover the 5 persistent workspaces assigned to each monitor.
# If discovery fails, we fall back to ranges:
#   mon 0 -> [1..5], mon 1 -> [6..10], mon 2 -> [11..15], mon 3 -> [16..20]
declare -A MON_WS_RING # key: mon -> "w1 w2 w3 w4 w5"
declare -A MON_WS_IDX  # key: mon -> next index (0..4)

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/hypr-launcher"
mkdir -p "$STATE_DIR"

_save_state() {
  : >"$STATE_DIR/ws_idx.state"
  for k in "${!MON_WS_IDX[@]}"; do
    echo "$k ${MON_WS_IDX[$k]}" >>"$STATE_DIR/ws_idx.state"
  done
}

_load_state() {
  [[ -f "$STATE_DIR/ws_idx.state" ]] || return 0
  while read -r k v; do
    [[ -n "$k" && -n "$v" ]] && MON_WS_IDX["$k"]="$v"
  done <"$STATE_DIR/ws_idx.state"
}

_discover_workspace_ring() {
  # Build mapping: monitorId -> list of WS ids (sorted)
  # Try to read from hyprctl (persistent workspaces show up if defined)
  declare -A tmp
  while IFS= read -r row; do
    # Format: wsId|monId
    IFS='|' read -r ws mon <<<"$row"
    tmp["$mon"]+="$ws "
  done < <(hyprctl -j workspaces | jq -r '.[] | "\(.id)|\(.monitor)"' | sort -n)

  # For each known monitor id, keep first 5 sorted (or fallback range)
  for mon in "${!MON_ID_TO_NAME[@]}"; do
    ws_list="${tmp[$mon]}"
    if [[ -n "$ws_list" ]]; then
      # normalize, sort, take 5
      read -r -a arr <<<"$(tr ' ' '\n' <<<"$ws_list" | sort -n | head -n 5 | xargs)"
      if ((${#arr[@]} == 5)); then
        MON_WS_RING["$mon"]="${arr[*]}"
      fi
    fi
    if [[ -z "${MON_WS_RING[$mon]}" ]]; then
      # fallback ring: 5 per monitor
      start=$((mon * 5 + 1))
      MON_WS_RING["$mon"]="$start $((start + 1)) $((start + 2)) $((start + 3)) $((start + 4))"
    fi
  done
}

_init_ws_indices() {
  # default pointer = first slot unless we restored state
  for mon in "${!MON_ID_TO_NAME[@]}"; do
    [[ -n "${MON_WS_IDX[$mon]}" ]] || MON_WS_IDX["$mon"]=0
  done
}

workspace_for_mon_current() {
  local mon="$1"
  read -r -a ring <<<"${MON_WS_RING[$mon]}"
  echo "${ring[${MON_WS_IDX[$mon]}]}"
}

workspace_for_mon_next_and_advance() {
  local mon="$1"
  read -r -a ring <<<"${MON_WS_RING[$mon]}"
  local idx=${MON_WS_IDX[$mon]}
  local ws="${ring[$idx]}"
  # advance ring pointer modulo 5
  MON_WS_IDX["$mon"]=$(((idx + 1) % 5))
  _save_state
  echo "$ws"
}

place_workspace_on_monitor() {
  local ws="$1" mon="$2"
  hyprctl dispatch moveworkspacetomonitor "$ws $mon"
}

# Call once during startup
_discover_workspace_ring
_load_state
_init_ws_indices

# ─── Reusable Application Blocks ────────────────────────────────────────────
declare -A APPS

## Firefox: triple workspace default
FIREFOX_TRIPLE_WS=("3:firefox" "6:firefox" "2:firefox")
APPS["Firefox"]=$(
  IFS='|'
  echo "${FIREFOX_TRIPLE_WS[*]}"
)

## Email client
APPS["Email"]="1:flatpak run eu.betterbird.Betterbird"

## Terminal sessions
### tmuxifier: load a tmuxifier session on a workspace (default ws=4)
tmuxifier() {
  local session="$1"
  local ws="${2:-4}"
  echo "${ws}:kitty -e tmuxifier load-session $session"
}

### tmux: create or attach to a tmux session by name on a workspace (default ws=4)
tmux() {
  local name="$1"
  local ws="${2:-4}"
  echo "${ws}:kitty -e tmux new -A -s $name"
}

## Slack
APPS["Slack"]="5:slack"

## File manager
APPS["Yazi"]="4:kitty -e yazi"
APPS["Dolphin"]="3:dolphin"

## Monitoring tools
APPS["Journal"]="3:kitty -e journalctl -f"
APPS["Btop"]="4:kitty -e btop"

# ─── Setup Definitions ──────────────────────────────────────────────────────

declare -A SETUPS
SETUPS["🌐 Browsing"]="${APPS["Firefox"]}|$(tmuxifier config)"
SETUPS["🧱 Client"]="${APPS["Email"]}|${APPS["Firefox"]}|$(tmuxifier client-dev)|$(tmuxifier config 7)|${APPS["Slack"]}"
SETUPS["🛠 Config"]="${APPS["Email"]}|${APPS["Firefox"]}|$(tmuxifier config)"
SETUPS["🗂 Files"]="${APPS["Dolphin"]}|${APPS["Yazi"]}"
SETUPS["🧩 Game Mods"]="2:steam|3:kitty -d ~/Downloads/ yazi|4:kitty -d ~/.steam/steam/steamapps/ yazi"
SETUPS["🎮 Game"]="2:steam"
SETUPS["📅 Meeting"]="5:firefox https://calendar.google.com/|7:firefox"
SETUPS["📊 System Monitor"]="${APPS["Journal"]}|${APPS["Btop"]}"
SETUPS["🛡️ DNF Update"]="2:kitty -e sysup|${APPS["Journal"]}"
SETUPS["💼 Work"]="${APPS["Email"]}|${APPS["Firefox"]}|$(tmuxifier uphill)|$(tmuxifier config 7)|${APPS["Slack"]}"

# Log to journal and echo
log() {
  echo "$1" >&2
  logger -t hypr-launcher "$1"
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

# Parse selected session into PAIRS array of "workspace:command"
parse_pairs() {
  IFS='|' read -ra PAIRS <<<"${SETUPS["$1"]}"
}

# Collect workspaces and identify which ones will launch Firefox
collect_workspaces() {
  WORKSPACES=()
  FIREFOX_WORKSPACES=()
  for pair in "${PAIRS[@]}"; do
    local WS="${pair%%:*}"
    local CMD="${pair#*:}"
    WORKSPACES+=("$WS")
    [[ "$CMD" == "firefox" ]] && FIREFOX_WORKSPACES+=("$WS")
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
  for pair in "${PAIRS[@]}"; do
    local WS="${pair%%:*}"
    local CMD="${pair#*:}"
    if [[ "$CMD" != "firefox" ]]; then
      if [[ "$CMD" == flatpak\ run* ]]; then
        log "hyprctl dispatch exec '$CMD'"
        hyprctl dispatch exec "$CMD"
      else
        log "hyprctl dispatch exec '[workspace $WS silent] $CMD'"
        hyprctl dispatch exec "[workspace $WS silent] $CMD"
      fi
    fi
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
  parse_pairs "$CHOICE"
  collect_workspaces
  map_workspaces
  launch_non_firefox_apps
  handle_firefox
}

launch_selector
