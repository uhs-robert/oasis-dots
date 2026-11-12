#!/usr/bin/env bash
# Sourced by launch.sh and watch.sh: whether a claude process runs in a pane.

# Claude is the pane's process or runs below it, under a wrapper such as systemd-run or node. A shell prompt or a
# shell with background jobs is not claude.
claude_runs_in() { # <pid>
  local pid=$1 child
  [[ $(ps -o comm= -p "$pid" 2>/dev/null) == claude ]] && return 0
  for child in $(pgrep -P "$pid"); do
    claude_runs_in "$child" && return 0
  done
  return 1
}
