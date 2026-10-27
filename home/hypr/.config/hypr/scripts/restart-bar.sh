#!/usr/bin/env bash
# hypr/.config/hypr/scripts/restart-bar.sh
# Restarts the owner's Quickshell bar. `qs -n` exits at once while an old instance is still alive, so a bare
# `pkill; qs -n` leaves no bar when the old one is slow to die: wait for it to exit, SIGKILL it after a grace
# period, then start the new one. Starts the bar even when none is running.
# RESTART_BAR_GRACE: seconds to wait after SIGTERM before SIGKILL (default 5).

# The owner's bar and test bars launch as `qs -n ...`; a shadow bar runs as `qs-shadow` and never matches. -u keeps
# other users' bars out.
pattern='^qs -n'
grace=${RESTART_BAR_GRACE:-5}

# Polls in tenths of a second; returns 0 once no owner bar is left, 1 on timeout.
wait_gone() {
  local ticks=$(($1 * 10))
  while ((ticks-- > 0)); do
    pgrep -u "$UID" -f "$pattern" >/dev/null || return 0
    sleep 0.1
  done
  ! pgrep -u "$UID" -f "$pattern" >/dev/null
}

pkill -u "$UID" -f "$pattern"
if ! wait_gone "$grace"; then
  pkill -KILL -u "$UID" -f "$pattern"
  wait_gone 2
fi
exec qs -n
