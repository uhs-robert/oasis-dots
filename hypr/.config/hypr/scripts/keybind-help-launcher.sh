#!/usr/bin/env bash

HYPRCONF="$HOME/.config/hypr/hyprland.conf"
KEYMAP_DIR="$HOME/.config/hypr/keymaps"
KEYMAP=$(grep "^\$KEYMAP" "$HYPRCONF" | awk -F= '{print $2}' | xargs)
KEYMAP_FILE="$KEYMAP_DIR/$KEYMAP.conf"

# Validate file exists
if [[ ! -f "$KEYMAP_FILE" ]]; then
  notify-send "Hypr Keymap Viewer" "Keymap file not found: $KEYMAP_FILE"
  exit 1
fi

# Extract keybinds with 'exec'
mapfile -t OPTIONS < <(
  grep '^bind' "$KEYMAP_FILE" | while IFS= read -r line; do
    mod=$(echo "$line" | cut -d',' -f1 | cut -d= -f2 | xargs)
    key=$(echo "$line" | cut -d',' -f2 | xargs)
    action=$(echo "$line" | cut -d',' -f4- | xargs)

    # Only include lines that use 'exec,'
    [[ "$action" != exec,* ]] && continue

    # Strip `exec,` prefix and format
    command="${action#exec,}"
    mod_readable=$(echo "$mod" | sed "s/\$leader/SUPER/g" | tr '[:lower:]' '[:upper:]')
    printf "%-20s → %s\n" "$mod_readable+$key" "$command"
  done
)

# Prompt the user
CHOICE=$(printf "%s\n" "${OPTIONS[@]}" | wofi --dmenu -p "Run keybind command")
[[ -z "$CHOICE" ]] && exit 0

# Extract command after the arrow
CMD=$(echo "$CHOICE" | awk -F '→ ' '{print $2}' | xargs)

# Execute it
bash -c "$CMD"
