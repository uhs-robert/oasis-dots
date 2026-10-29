#!/usr/bin/env bash
shopt -s extglob
# hypr/.config/hypr/scripts/restart-bar.sh
# Restarts the owner's Quickshell bar. `qs -n` exits at once while an old instance is still alive, so a bare
# `pkill; qs -n` leaves no bar when the old one is slow to die: wait for it to exit, SIGKILL it after a grace
# period, then start the new one. Starts the bar even when none is running.
# RESTART_BAR_GRACE: whole seconds to wait after SIGTERM before SIGKILL (default 5); anything else falls back to 5.
# Exits non-zero without starting a bar when the old one survives SIGKILL (stuck in D-state): `qs -n` would refuse to
# start and exit silently.

# The owner's bar is found by asking Quickshell, not by command line: after a crash Quickshell relaunches the bar as a bare
# `quickshell`, and test, shadow and greeter instances run other configs or in other runtime dirs. `qs list` without
# --all lists only instances of the default config in this runtime dir (a shadow bar has a runtime dir of its own).
# --any-display keeps a shell on a TTY, over SSH or in a shadow's environment, whose WAYLAND_DISPLAY is not the owner's,
# from missing the bar. `restart-bar.sh --pids` prints those pids (ship-batch uses it); a crash reporter is not an
# instance and never appears. With no bar `qs list` prints "No running instances" on stdout and exits 0, even with
# --json: that is an empty list; any other failure (qs missing, no config, unparsable output) is an error, never "no bar".
bar_pids() {
  local out
  # env -u: a caller's QS_CONFIG_PATH/QS_CONFIG_NAME would point qs (here and in the relaunch) at a test config.
  out=$(env -u QS_CONFIG_PATH -u QS_CONFIG_NAME qs list --json --any-display 2>&1) || return 1
  [[ $out == "No running instances"* ]] && return 0
  jq -r '.[].pid' <<<"$out"
}
if [[ ${1:-} == --pids ]]; then
  bar_pids
  exit
fi

default_grace=5
grace=${RESTART_BAR_GRACE:-$default_grace}
if [[ $grace != +([0-9]) ]]; then
  echo "restart-bar: RESTART_BAR_GRACE='$grace' is not a whole number of seconds; using $default_grace" >&2
  grace=$default_grace
fi

# Polls in tenths of a second; returns 0 once no owner bar is listed, 1 on timeout.
wait_gone() {
  local ticks=$((10#$1 * 10)) # 10#: a leading zero (08) is not octal
  while ((ticks-- > 0)); do
    bar_gone && return 0
    sleep 0.1
  done
  bar_gone
}
# A failed listing is not "gone".
bar_gone() {
  local pids
  pids=$(bar_pids) && [[ -z $pids ]]
}

pids=$(bar_pids) || {
  echo "restart-bar: could not list the bar with 'qs list'; nothing was stopped" >&2
  exit 1
}
# shellcheck disable=SC2086 # one word per pid
[[ -z $pids ]] || kill $pids 2>/dev/null
if ! wait_gone "$grace"; then
  # shellcheck disable=SC2046
  kill -KILL $(bar_pids) 2>/dev/null
  if ! wait_gone 2; then
    message="the old bar survived SIGKILL (stuck in uninterruptible sleep?); no new bar was started"
    echo "restart-bar: $message" >&2
    command -v notify-send >/dev/null && notify-send -u critical "Bar restart failed" "$message"
    exit 1
  fi
fi
exec env -u QS_CONFIG_PATH -u QS_CONFIG_NAME qs -n
