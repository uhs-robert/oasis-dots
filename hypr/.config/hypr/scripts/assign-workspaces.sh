#!/bin/bash

# Define workspace → monitor description mapping
declare -A WORKSPACE_MAP=(
  [1]="BOE 0x0C8E" # Laptop
  [5]="BOE 0x0C8E" # Laptop

  [2]="GIGA-BYTE TECHNOLOGY CO. LTD. G27QC A 0x00000D48" # Center
  [6]="GIGA-BYTE TECHNOLOGY CO. LTD. G27QC A 0x00000D48" # Center

  [3]="HP Inc. HP Z22n G2 6CM8411J1Z" # Left
  [7]="HP Inc. HP Z22n G2 6CM8411J1Z" # Left

  [4]="HP Inc. HP Z22n G2 6CM8411J22" # Vertical right
  [8]="HP Inc. HP Z22n G2 6CM8411J22" # Vertical right

  [9]="GIGA-BYTE TECHNOLOGY CO. LTD. G27QC A 0x00000D48" # Extra one on center maybe
)

assign_workspaces() {
  # Get monitor descriptions and IDs from hyprctl
  mapfile -t MONITORS < <(hyprctl monitors -j | jq -r '.[] | "\(.description):\(.id)"')

  # Build description → ID map
  declare -A MONITOR_IDS
  for entry in "${MONITORS[@]}"; do
    DESC="${entry%%:*}"
    ID="${entry##*:}"
    MONITOR_IDS["$DESC"]="$ID"
  done

  # Assign each workspace to its described monitor
  for WS in "${!WORKSPACE_MAP[@]}"; do
    DESC="${WORKSPACE_MAP[$WS]}"
    MON_ID="${MONITOR_IDS[$DESC]}"
    if [[ -n "$MON_ID" ]]; then
      hyprctl dispatch moveworkspacetomonitor "$WS $MON_ID"
    else
      echo "Monitor description '$DESC' not found — skipping workspace $WS" >&2
    fi
  done
}

# Run once at launch (in case monitors already connected)
assign_workspaces

# Listen for monitor changes and re-run
socat - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock" |
  while read -r line; do
    if [[ "$line" == monitoradded* || "$line" == monitorremoved* ]]; then
      assign_workspaces
    fi
  done
