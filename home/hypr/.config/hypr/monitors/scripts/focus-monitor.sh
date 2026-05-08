#!/usr/bin/env bash
# hypr/.config/hypr/monitors/focus-monitor.sh

set -euo pipefail

ACTIVE_LAYOUT="$HOME/.config/hypr/monitors/active.conf"

idx="${1:-}"

if [[ ! "$idx" =~ ^[1-9]$ ]]; then
  notify-send "Go Monitor" "Usage: go-monitor <1-9>"
  exit 1
fi

if [[ ! -f "$ACTIVE_LAYOUT" ]]; then
  notify-send "Go Monitor" "Missing active layout: $ACTIVE_LAYOUT"
  exit 1
fi

description="$(
  awk -v target="$idx" '
    /^[[:space:]]*monitor[[:space:]]*=[[:space:]]*desc:/ {
      line = $0

      # Remove leading monitor=desc:
      sub(/^[[:space:]]*monitor[[:space:]]*=[[:space:]]*desc:/, "", line)

      # Remove inline comments
      sub(/[[:space:]]+#.*$/, "", line)

      # Description is everything before the first comma
      split(line, parts, ",")

      desc = parts[1]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", desc)

      if (desc != "") {
        count++

        if (count == target) {
          print desc
          exit
        }
      }
    }
  ' "$ACTIVE_LAYOUT"
)"

if [[ -z "$description" ]]; then
  notify-send "Go Monitor" "No monitor mapped to $idx"
  exit 1
fi

monitor_name="$(
  hyprctl monitors -j |
    jq -r --arg desc "$description" '
      .[]
      | select(.description == $desc)
      | .name
    ' |
    head -n 1
)"

if [[ -z "$monitor_name" ]]; then
  notify-send "Go Monitor" "Monitor not active: $description"
  exit 1
fi

hyprctl dispatch focusmonitor "$monitor_name"
