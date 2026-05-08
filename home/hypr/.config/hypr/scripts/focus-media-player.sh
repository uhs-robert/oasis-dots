#!/usr/bin/env bash
# hypr/.config/hypr/scripts/focus-media-player.sh
# Focus the window currently playing media via MPRIS.
# Matches the active track title against Hyprland window titles.

title=$(playerctl metadata --format '{{title}}' 2>/dev/null) || exit 1
title=$(echo "$title" | tr -s ' ')
addr=$(hyprctl clients -j | jq -r --arg t "$title" '.[] | select(.title | gsub("\\s+"; " ") | contains($t)) | .address' | head -1)
[ -n "$addr" ] && hyprctl dispatch focuswindow "address:$addr"
