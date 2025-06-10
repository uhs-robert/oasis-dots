#!/usr/bin/env bash

sleep 1
~/.config/hypr/scripts/assign-workspaces.sh
hyprctl dispatch exec "[workspace 1 silent] ~/.config/hypr/scripts/auto-launch-apps.sh"
