#!/usr/bin/env bash
# hypr/.config/hypr/scripts/kbptr.sh
# Runs wl-kbptr to pick a spot, then moves the pointer and clicks through Hyprland instead of wl-kbptr.
# wl-kbptr rotates its target for a rotated output, and Hyprland rotates virtual-pointer motion again,
# so on a portrait monitor the pointer lands in the wrong place (moverest/wl-kbptr#53).
# Usage: kbptr.sh [wl-kbptr args...]

out=$(wl-kbptr --only-print "$@") || exit
# A cancelled pick prints nothing.
[[ -n $out ]] || exit 0

# Format: WxH+X+Y +OX+OY C, in logical pixels. X/Y are relative to the output at OX/OY; C is the click (l/r/m/n).
re='^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+) \+(-?[0-9]+)\+(-?[0-9]+) ([lrmn])$'
if [[ ! $out =~ $re ]]; then
  echo "kbptr.sh: unexpected wl-kbptr output: $out" >&2
  exit 1
fi
w=${BASH_REMATCH[1]} h=${BASH_REMATCH[2]} x=${BASH_REMATCH[3]} y=${BASH_REMATCH[4]}
ox=${BASH_REMATCH[5]} oy=${BASH_REMATCH[6]} click=${BASH_REMATCH[7]}

hyprctl dispatch "hl.dsp.cursor.move({ x = $((ox + x + w / 2)), y = $((oy + y + h / 2)) })" >/dev/null

case $click in
  l) wlrctl pointer click left ;;
  r) wlrctl pointer click right ;;
  m) wlrctl pointer click middle ;;
esac
