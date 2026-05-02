#!/usr/bin/env sh
# hypr/.config/hypr/config/set-plugin-keybinds.sh

set -eu

leader='SUPER'

hyprpm reload || exit 0

for n in 1 2 3 4 5 6 7 8 9; do
  hyprctl keyword bindu "$leader, $n, split-workspace, $n"
  hyprctl keyword bind "$leader+SHIFT, $n, split-movetoworkspace, $n"
done

hyprctl keyword bindu "$leader, 0, split-workspace, 10"
hyprctl keyword bind "$leader+SHIFT, 0, split-movetoworkspace, 10"

hyprctl keyword binddu "$leader+CTRL, h, Switch to previous WS, split-cycleworkspaces, prev"
hyprctl keyword binddu "$leader+CTRL, l, Switch to next WS, split-cycleworkspaces, next"
hyprctl keyword binddu "$leader+CTRL, k, Move WS up one, split-movetoworkspace, +1"
hyprctl keyword binddu "$leader+CTRL, j, Move WS down one, split-movetoworkspace, -1"

hyprctl keyword bindd "$leader+SHIFT, Q, Move rogue windows to current monitor, split-grabroguewindows"
