#!/usr/bin/env bash
# hypr/.config/hypr/scripts/focus-toast-or-float.sh
# Focus Quickshell's notification toasts, or cycle floating windows when none is showing.
dir="${1:-next}"
[ "$(qs ipc call notifications focus_toast "$dir" 2>/dev/null)" = toast ] || hyprctl dispatch "_hv_cycle_float(\"$dir\")"
