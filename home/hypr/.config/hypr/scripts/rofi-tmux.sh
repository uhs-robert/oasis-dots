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
config) pretty_name="Config" ;;
client-portal) pretty_name="Client Portal" ;;
oasis-swap) pretty_name="Oasis Swap" ;;
music) pretty_name="Music" ;;
esac

title="Tmux $pretty_name"

term_name="${TERMINAL:-kitty}"

address="$(
  hyprctl clients -j |
    jq -r --arg title "$title" --arg term "$term_name" '
      def norm: ascii_downcase | gsub("[^a-z0-9]"; "");
      [.[] | select(.class | ascii_downcase | contains($term))] as $wins
      | ($wins | map(select((.title | norm) == ($title | norm))))
        + ($wins | map(select(.title | ascii_downcase | startswith(($title | ascii_downcase) + " "))))
      | .[0].address // empty
    '
)"

if [[ -n "$address" ]]; then
  hyprctl dispatch "hl.dsp.focus({ window = 'address:$address' })"
  exit 0
fi

term="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/bin/term"
[ -x "$term" ] || term="$term_name"
"$term" -e tmuxifier load-session "$session" &
