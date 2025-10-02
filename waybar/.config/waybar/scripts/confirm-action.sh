#!/usr/bin/env bash
# confirm-action.sh
# waybar/.config/waybar/scripts/confirm-action.sh
# Minimal yes/no dialog, then run a command on Yes.
# Works with zenity (preferred) or kdialog; no-op if neither exists.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/lib/hypr.sh" ] && . "$SCRIPT_DIR/lib/hypr.sh"

TITLE=""
ICON=""
GLYPH=""
COLOR=""
EXEC_CMD=""

usage() {
  cat <<EOF
Usage:
  $0 --title <Title> [--icon <path|themed-name>] [--glyph <nf-glyph>] [--color <#hex>]
     --exec '<command to run if confirmed>'

Examples:
  $0 --title Logout --glyph '󰍃' --color '#89dceb' --exec 'hyprctl dispatch exit'
  $0 --title Reboot --glyph '󰜉' --color '#f9e2af' --exec 'systemctl reboot'
  $0 --title Power\ Off --glyph '󰐥' --color '#f38ba8' --exec 'systemctl poweroff'
  $0 --title Lock --glyph '󰌾' --color '#cdd6f4' --exec 'loginctl lock-session'
EOF
}

# --- parse args (long options) ---
while [[ $# -gt 0 ]]; do
  case "$1" in
  --title)
    TITLE="${2:-}"
    shift 2
    ;;
  --icon)
    ICON="${2:-}"
    shift 2
    ;;
  --glyph)
    GLYPH="${2:-}"
    shift 2
    ;;
  --color)
    COLOR="${2:-}"
    shift 2
    ;;
  --exec)
    EXEC_CMD="${2:-}"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    usage
    exit 2
    ;;
  esac
done

[[ -z "$TITLE" || -z "$EXEC_CMD" ]] && {
  usage
  exit 2
}

# Lowercase verb for sentence (Logout -> logout, Power Off -> power off)
_lower() { tr '[:upper:]' '[:lower:]'; }
VERB="$(printf '%s' "$TITLE" | _lower)"

# Build dialog text; include a colored glyph if provided (zenity supports Pango)
if [[ -n "$GLYPH" ]]; then
  if [[ -n "$COLOR" ]]; then
    PROMPT="<span foreground='$COLOR'>$GLYPH</span>  Are you sure you want to ${VERB}?"
  else
    PROMPT="$GLYPH  Are you sure you want to ${VERB}?"
  fi
else
  PROMPT="Are you sure you want to ${VERB}?"
fi

confirm_with_zenity() {
  local args=(--question --title="$TITLE" --text="$PROMPT" --width=340 --ok-label="Yes" --cancel-label="No")
  [[ -n "$ICON" ]] && args+=(--window-icon="$ICON")
  # zenity supports Pango markup by default; no extra flags needed
  zenity "${args[@]}"
}

confirm_with_kdialog() {
  # kdialog doesn't do Pango, so strip markup tags if present
  local plain_prompt
  plain_prompt="$(printf '%s' "$PROMPT" | sed -E 's/<[^>]+>//g')"
  local args=(--warningyesno "$plain_prompt" --title "$TITLE")
  [[ -n "$ICON" ]] && args+=(--icon "$ICON")
  kdialog "${args[@]}"
}

focus_monitor_under_cursor() {
  # needs: hyprctl + jq; no-op if missing
  command -v hyprctl >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local cursor monitors cx cy mon
  cursor="$(hyprctl -j cursorpos)" || return 0
  monitors="$(hyprctl -j monitors)" || return 0
  cx="$(jq -r '.x' <<<"$cursor")"
  cy="$(jq -r '.y' <<<"$cursor")"

  # pick the monitor whose rect contains (cx, cy)
  mon="$(
    jq -r --argjson cx "$cx" --argjson cy "$cy" '
      .[] | select(.disabled==false) as $m |
      ($m.x <= $cx and $cx < ($m.x + $m.width) and
       $m.y <= $cy and $cy < ($m.y + $m.height)) |
      select(.) | $m.name
    ' <<<"$monitors" | head -n1
  )"

  # fallback: focused monitor
  [[ -z "$mon" ]] && mon="$(jq -r '.[] | select(.focused==true) | .name' <<<"$monitors" | head -n1)"

  [[ -n "$mon" ]] && hyprctl dispatch focusmonitor "$mon" >/dev/null 2>&1 || true
}

if command -v zenity >/dev/null 2>&1; then
  focus_monitor_under_cursor || true
  if confirm_with_zenity; then eval "$EXEC_CMD"; fi
elif command -v kdialog >/dev/null 2>&1; then
  focus_monitor_under_cursor || true
  if confirm_with_kdialog; then eval "$EXEC_CMD"; fi
else
  # No GUI prompt available — fail gracefully
  command -v notify-send >/dev/null 2>&1 && notify-send "$TITLE" "No dialog program found" -u low
  exit 0
fi
