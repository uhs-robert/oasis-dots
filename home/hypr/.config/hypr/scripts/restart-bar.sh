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
# within a few seconds. Without an argument the bar is exec'd in the caller's own environment, as the keybind needs.
# The caller's HYPRLAND_INSTANCE_SIGNATURE is stale in a shell that outlives a login, so every mode finds the live
# instance with hypr-live first and exports it, which the exec'd bar then inherits. When none answers, the old bar is
# left running and the exit is non-zero: stopping it first left no bar at all (#969).

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

# hypr-live is on PATH once stowed; the path beside this script's link target serves a checkout that is not stowed yet.
hypr_live=$(command -v hypr-live || echo "$(dirname "$(readlink -f "$0")")/../../../.local/bin/hypr-live")

# Exports the live signature and runtime dir, or fails with $1 saying what was left alone.
use_live_hypr() {
  local lines line
  lines=$("$hypr_live" --env 2>/dev/null) || fail "no live Hyprland answers; $1" "Bar restart skipped"
  # shellcheck disable=SC2163 # each line is NAME=value, which export takes whole
  while IFS= read -r line; do export "$line"; done <<<"$lines"
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
stop)
  use_live_hypr "the bar was left running"
  stop_bar
  ;;
start)
  use_live_hypr "no bar was started"
  start_bar
  ;;
'')
  use_live_hypr "the bar was left running"
  stop_bar
  # Hyprland can exit while the old bar dies; a bar started on a dead instance has no desktop to attach to.
  use_live_hypr "the old bar is stopped and no bar was started"
  exec qs -n
  ;;
*)
  echo "usage: restart-bar.sh [stop|start]" >&2
  exit 2
  ;;
esac
