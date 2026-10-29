#!/usr/bin/env bash
shopt -s extglob
# hypr/.config/hypr/scripts/restart-bar.sh
# Usage: restart-bar.sh [stop|start]. Without an argument it stops the bar, then starts it; `stop` and `start` do one
# half each, so a caller (ship-batch) can run a step while the bar is down.
# Restarts the owner's Quickshell bar. `qs -n` exits at once while an old instance is still alive, so a bare
# `pkill; qs -n` leaves no bar when the old one is slow to die: wait for it to exit, SIGKILL it after a grace
# period, then start the new one. Starts the bar even when none is running.
# RESTART_BAR_GRACE: whole seconds to wait after SIGTERM before SIGKILL (default 5); anything else falls back to 5.
# Exits non-zero without starting a bar when the old one survives SIGKILL (stuck in D-state): `qs -n` would refuse to
# start and exit silently.
# `start` launches the bar through Hyprland (`hyprctl dispatch`), so it outlives the caller, and fails unless a bar is up
# within a few seconds; it needs a HYPRLAND_INSTANCE_SIGNATURE that answers. Without an argument the bar is exec'd in the
# caller's own environment, as the keybind needs.

# `qs list` shows only the owner's default-config instances (no test or shadow bars), and still finds a bar whose
# command line a crash turned into plain `quickshell`.
bar_pids() {
  local list
  list=$(qs list --json --any-display)
  # With no instance running, `qs list --json` prints a plain-text notice, not `[]`.
  [[ $list == "["* ]] || return 0
  jq -r '.[].pid' <<<"$list"
}
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
    [[ -n $(bar_pids) ]] || return 0
    sleep 0.1
  done
  [[ -z $(bar_pids) ]]
}

fail() {
  echo "restart-bar: $1" >&2
  command -v notify-send >/dev/null && notify-send -u critical "$2" "$1"
  exit 1
}

stop_bar() {
  bar_pids | xargs -r kill
  if ! wait_gone "$grace"; then
    bar_pids | xargs -r kill -KILL
    wait_gone 2 || fail "the old bar survived SIGKILL (stuck in uninterruptible sleep?); no new bar was started" "Bar restart failed"
  fi
}

start_bar() {
  hyprctl dispatch "hl.dsp.exec_cmd('qs -n')" >/dev/null ||
    fail "hyprctl could not relaunch qs; start it by hand: hyprctl dispatch \"hl.dsp.exec_cmd('qs -n')\"" "Bar start failed"
  local ticks=60
  while ((ticks-- > 0)); do
    [[ -z $(bar_pids) ]] || return 0
    sleep 0.1
  done
  fail "qs did not come back; read 'qs log'" "Bar start failed"
}

case ${1:-} in
stop) stop_bar ;;
start) start_bar ;;
'')
  stop_bar
  exec qs -n
  ;;
*)
  echo "usage: restart-bar.sh [stop|start]" >&2
  exit 2
  ;;
esac
