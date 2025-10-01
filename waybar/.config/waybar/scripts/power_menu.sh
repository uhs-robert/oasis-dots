#!/usr/bin/env bash
# waybar/.config/waybar/scripts/power_menu.sh
set -euo pipefail

# items: "label<TAB>action"
menu_items=$(
  cat <<'EOF'
<span size='48pt'> </span>  <span size='16pt' rise='6000'>Lock</span>	lock
<span size='48pt'> 󰒲</span>  <span size='16pt' rise='6000'>Suspend</span>	suspend
<span size='48pt'> 󰍃</span>  <span size='16pt' rise='6000'>Logout</span>	logout
<span size='48pt'> 󰜉</span>  <span size='16pt' rise='6000'>Reboot</span>	reboot
<span size='48pt'> 󰐥</span>  <span size='16pt' rise='6000'>Shutdown</span>	poweroff
EOF
)

# Show only the DISPLAY column to wofi
choice_display="$(
  printf '%s\n' "$menu_items" |
    awk -F'\t' '{print $1}' |
    wofi --dmenu \
      --prompt "Power" \
      --allow-markup \
      --style ~/.config/wofi/powermenu.css \
      --columns 1 \
      --width 30% \
      --cache-file /dev/null
)"

[ -z "${choice_display}" ] && exit 0

# Lookup action by matching the chosen DISPLAY
action="$(printf '%s\n' "$menu_items" | awk -F'\t' -v c="$choice_display" '$1==c{print $2; exit}')"
[ -z "${action:-}" ] && exit 0

# Make a clean label for confirm prompt (strip markup)
label_plain="$(printf '%s' "$choice_display" | sed -E 's/<[^>]+>//g; s/^[[:space:]]+|[[:space:]]+$//g')"

confirm="$(
  printf 'No\nYes\n' |
    wofi --dmenu \
      --prompt "Confirm ${label_plain}?" \
      --style ~/.config/wofi/powermenu.css \
      --cache-file /dev/null
)"

[ "$confirm" != "Yes" ] && exit 0

case "$action" in
lock) hyprlock ;;
suspend) systemctl suspend ;;
logout) hyprctl dispatch exit ;;
reboot) systemctl reboot ;;
poweroff) systemctl poweroff ;;
esac
