#!/usr/bin/env bash
# hypr/.config/hypr/scripts/keybind-help-launcher.sh

HYPRCONF="$HOME/.config/hypr/hyprland.conf"
KEYMAP_DIR="$HOME/.config/hypr/config/"
KEYMAP=$(grep "^\$KEYMAP" "$HYPRCONF" | awk -F= '{print $2}' | xargs)
KEYMAP_FILE="$KEYMAP_DIR/$KEYMAP.conf"

# Validate file exists
if [[ ! -f "$KEYMAP_FILE" ]]; then
  notify-send "Hypr Keymap Viewer" "Keymap file not found: $KEYMAP_FILE"
  exit 1
fi

# Extract keybinds with 'exec'
mapfile -t OPTIONS < <(
  grep '^bindd' "$KEYMAP_FILE" | while IFS= read -r line; do
    mod=$(echo "$line" | cut -d',' -f1 | cut -d= -f2 | xargs)
    key=$(echo "$line" | cut -d',' -f2 | xargs)
    description=$(echo "$line" | cut -d',' -f3 | xargs)
    dispatcher=$(echo "$line" | cut -d',' -f4 | xargs)
    command=$(echo "$line" | cut -d',' -f5- | xargs)

    # Only include lines that use 'exec'
    [[ "$dispatcher" != "exec" ]] && continue

    mod_readable=$(echo "$mod" | sed "s/\$leader/SUPER/g" | tr '[:lower:]' '[:upper:]')
    printf "%-35s %-20s → %s\n" "$description" "$mod_readable+$key" "$command"
  done | sort
)

# Prompt the user
CHOICE=$(printf "%s\n" "${OPTIONS[@]}" | rofi -dmenu -p "Run keybind command")
[[ -z "$CHOICE" ]] && exit 0

# Extract command after the arrow
CMD=$(echo "$CHOICE" | awk -F '→ ' '{print $2}' | xargs)

# Execute it
bash -c "$CMD"
