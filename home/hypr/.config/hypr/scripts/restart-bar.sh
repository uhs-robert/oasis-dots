#!/usr/bin/env bash
shopt -s extglob
# hypr/.config/hypr/scripts/restart-bar.sh
# Restarts the owner's Quickshell bar. `qs -n` exits at once while an old instance is still alive, so a bare
# `pkill; qs -n` leaves no bar when the old one is slow to die: wait for it to exit, SIGKILL it after a grace
# period, then start the new one. Starts the bar even when none is running.
# RESTART_BAR_GRACE: whole seconds to wait after SIGTERM before SIGKILL (default 5); anything else falls back to 5.
# Exits non-zero without starting a bar when the old one survives SIGKILL (stuck in D-state): `qs -n` would refuse to
# start and exit silently.

# -u keeps other users' bars out of the pattern's match.
# shellcheck source=./bar-pattern.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/bar-pattern.sh"
pattern=$bar_pattern
default_grace=5
grace=${RESTART_BAR_GRACE:-$default_grace}
if [[ $grace != +([0-9]) ]]; then
  echo "restart-bar: RESTART_BAR_GRACE='$grace' is not a whole number of seconds; using $default_grace" >&2
  grace=$default_grace
fi

# Polls in tenths of a second; returns 0 once no owner bar is left, 1 on timeout.
wait_gone() {
  local ticks=$((10#$1 * 10)) # 10#: a leading zero (08) is not octal
  while ((ticks-- > 0)); do
    pgrep -u "$UID" -f "$pattern" >/dev/null || return 0
    sleep 0.1
  done
  ! pgrep -u "$UID" -f "$pattern" >/dev/null
}

pkill -u "$UID" -f "$pattern"
if ! wait_gone "$grace"; then
  pkill -KILL -u "$UID" -f "$pattern"
  if ! wait_gone 2; then
    message="the old bar survived SIGKILL (stuck in uninterruptible sleep?); no new bar was started"
    echo "restart-bar: $message" >&2
    command -v notify-send >/dev/null && notify-send -u critical "Bar restart failed" "$message"
    exit 1
  fi
fi
exec qs -n
