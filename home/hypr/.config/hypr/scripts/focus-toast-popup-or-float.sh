#!/usr/bin/env bash
# hypr/.config/hypr/scripts/focus-toast-popup-or-float.sh
# Focus Quickshell's notification toasts, else take the keyboard back for an open bar popup, else cycle floating windows.
dir="${1:-next}"
qs_ipc="$(dirname "$0")/qs-ipc"
[ "$("$qs_ipc" call notifications focus_toast "$dir" 2>/dev/null)" = toast ] && exit 0
[ "$("$qs_ipc" call popup focus 2>/dev/null)" = popup ] && exit 0
hyprctl dispatch "_hv_cycle_float(\"$dir\")"
