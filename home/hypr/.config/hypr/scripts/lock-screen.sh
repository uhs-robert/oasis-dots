#!/usr/bin/env bash
# hypr/.config/hypr/scripts/lock-screen.sh
# Locks with the Quickshell lock screen; falls back to hyprlock when the bar is not running or cannot lock.

ipc="$HOME/.config/hypr/scripts/qs-ipc"
pidof hyprlock >/dev/null && exit 0

fallback() {
  pidof hyprlock >/dev/null && exit 0
  exec hyprlock --immediate-render --no-fade-in
}

pgrep -x qs >/dev/null || fallback

reply=$(timeout 1 "$ipc" call lock lock 2>/dev/null)
[ -z "$reply" ] && reply=$(timeout 1 "$ipc" call lock state 2>/dev/null)
case "$reply" in
locked | secure) exit 0 ;;
ok | pending) ;;
*) fallback ;;
esac

# Hyprland confirms within 5s even when a surface never draws, so pending at the end counts as locked.
for _ in $(seq 24); do
  case "$(timeout 1 "$ipc" call lock state 2>/dev/null)" in
  secure) exit 0 ;;
  unlocked | failed) fallback ;;
  esac
  sleep 0.25
done
