#!/usr/bin/env bash
# hypr/.config/hypr/scripts/go-to-terminal.sh

set -euo pipefail

address="$(
  hyprctl clients -j |
    jq -r '
      .[]
      | select(.class == "kitty")
      | select((.title | startswith("Tmux")) | not)
      | .address
    ' |
    head -n 1
)"

if [[ -n "$address" ]]; then
  hyprctl dispatch focuswindow "address:$address"
  exit 0
fi

kitty &
