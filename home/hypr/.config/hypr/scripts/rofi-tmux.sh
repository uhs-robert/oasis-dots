#!/usr/bin/env bash
# ~/.config/hypr/scripts/rofi-tmux

set -euo pipefail

LAYOUT_DIR="$HOME/.tmuxifier/layouts"

session="$(
  find -L "$LAYOUT_DIR" -maxdepth 1 -type f -name "*.session.sh" |
    sed -E 's|.*/([^/]+)\.session\.sh$|\1|' |
    sort |
    rofi -dmenu -p "Project"
)"

[[ -z "$session" ]] && exit 0

pretty_name="$(
  printf '%s\n' "$session" |
    sed -E 's/[-_]+/ /g' |
    awk '{
      for (i = 1; i <= NF; i++) {
        $i = toupper(substr($i, 1, 1)) substr($i, 2)
      }
      print
    }'
)"

case "$session" in
uphill) pretty_name="UpHill" ;;
client-dev) pretty_name="Client App" ;;
config) pretty_name="Config" ;;
client-portal) pretty_name="Client Portal" ;;
oasis-swap) pretty_name="Oasis Swap" ;;
music) pretty_name="Music" ;;
esac

title="Tmux $pretty_name"

address="$(
  hyprctl clients -j |
    jq -r --arg title "$title" '
      .[]
      | select(.class == "kitty")
      | select(.title == $title or (.title | startswith($title + " ")))
      | .address
    ' |
    head -n 1
)"

if [[ -n "$address" ]]; then
  hyprctl dispatch "hl.dsp.focus({ window = 'address:$address' })"
  exit 0
fi

kitty -e tmuxifier load-session "$session" &
