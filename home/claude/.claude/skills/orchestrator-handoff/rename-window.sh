#!/usr/bin/env bash
# Renames the caller's own tmux window to orch-<N>[-prev|-done], keeping its number. Usage: rename-window.sh <active|prev|done>
#
# Like spawn-successor.sh, a sanctioned way for an agent to change the owner's tmux server (guard-tmux-socket.sh
# does not look inside scripts). The only tmux call that changes anything is the rename-window below, aimed at the
# window of $TMUX_PANE with a name built from the validated role and a number.
#
# Naming must never fail a handoff, so outside tmux it only prints a note.
set -euo pipefail
role=${1:-}
case $role in
active) suffix="" ;;
prev | done) suffix="-$role" ;;
*)
  echo "usage: rename-window.sh <active|prev|done>" >&2
  exit 2
  ;;
esac
if [[ -z ${TMUX:-} || -z ${TMUX_PANE:-} ]]; then
  echo "not inside tmux; window name left alone"
  exit 0
fi

# shellcheck source=window-names.sh
source "$(dirname "${BASH_SOURCE[0]}")/window-names.sh"
window=$(own_window_id)
number=$(window_number_of "$window")
if [[ -z $number ]]; then
  # A cold start has no number yet; prev and done mean it was an orchestrator, so a missing one is a mistake.
  [[ $role == active ]] || {
    echo "window has no orch-<N> number to keep; run 'rename-window.sh active' first" >&2
    exit 1
  }
  number=$(next_window_number)
fi
tmux rename-window -t "$window" "orch-$number$suffix"
echo "renamed window to orch-$number$suffix"
