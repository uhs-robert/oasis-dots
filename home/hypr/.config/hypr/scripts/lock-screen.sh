#!/usr/bin/env bash
# hypr/.config/hypr/scripts/lock-screen.sh
# Locks with the Quickshell lock screen; falls back to hyprlock when the bar is not running or cannot lock.

ipc="$HOME/.config/hypr/scripts/qs-ipc"
flag_script="$HOME/.config/quickshell/scripts/lock-flag"
pidof hyprlock >/dev/null && exit 0

# Serialized with lock-flag's hyprlock; a hyprlock that ran over 1s held the lock, so its exit is a real unlock.
fallback() {
  exec 9>"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/qs-hyprlock.lock"
  flock -n 9 || exit 0
  pidof hyprlock >/dev/null && exit 0
  start=$(date +%s%N)
  hyprlock --immediate-render --no-fade-in || exit 0
  if [ $(($(date +%s%N) - start)) -gt 1000000000 ] && [ -x "$flag_script" ]; then "$flag_script" clear; fi
  exit 0
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
