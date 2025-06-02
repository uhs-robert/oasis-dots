#!/usr/bin/env bash

HYPRCONF="$HOME/.config/hypr/hyprland.conf"
KEYMAP_DIR="$HOME/.config/hypr/keymaps"
TEMP_FILE="/tmp/keybinds_cheatsheet.txt"

# Get current keymap name from hyprland.conf
KEYMAP=$(grep "^\$KEYMAP" "$HYPRCONF" | awk -F= '{print $2}' | xargs)
KEYMAP_FILE="$KEYMAP_DIR/$KEYMAP.conf"

# Validate file exists
if [[ ! -f "$KEYMAP_FILE" ]]; then
  notify-send "Hypr Keymap Viewer" "Keymap file not found: $KEYMAP_FILE"
  exit 1
fi

# Header
echo "🔑 Keybindings ($KEYMAP)" >"$TEMP_FILE"
echo "" >>"$TEMP_FILE"

# Parse keybinds
grep '^bind' "$KEYMAP_FILE" | while IFS= read -r line; do
  mod=$(echo "$line" | cut -d',' -f1 | cut -d= -f2 | xargs)
  key=$(echo "$line" | cut -d',' -f2 | xargs)
  action=$(echo "$line" | cut -d',' -f4- | xargs)

  # Replace $leader with SUPER (just for readability)
  mod_readable=$(echo "$mod" | sed "s/\$leader/SUPER/g" | tr '[:lower:]' '[:upper:]')

  printf "%-15s → %s\n" "$mod_readable+$key" "$action"
done >>"$TEMP_FILE"

# Show in wofi
wofi --dmenu -p "Keybindings: $KEYMAP" <"$TEMP_FILE"
