#!/usr/bin/env bash

# Define setups: "workspace:command"
declare -A SETUPS
SETUPS["Work"]="2:firefox 4:kitty 1:thunderbird 1:slack"
SETUPS["Admin"]="2:firefox 4:kitty 1:thunderbird"
SETUPS["Gaming"]="2:steam"
SETUPS["Browsing"]="2:firefox"
#SETUPS["Files"]="4:kitty -e yazi"

# Prompt selection
CHOICE=$(printf "%s\n" "${!SETUPS[@]}" | wofi --dmenu --columns 1 -p "Select session")
[[ -z "$CHOICE" ]] && exit 0

# Launch each app silently on specific workspace
for pair in ${SETUPS["$CHOICE"]}; do
  IFS=':' read -r WS CMD <<<"$pair"
  hyprctl dispatch exec "[workspace $WS silent] $CMD"
done
