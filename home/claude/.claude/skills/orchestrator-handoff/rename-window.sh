#!/usr/bin/env bash
# Renames the caller's own tmux window after its Claude session. Usage: rename-window.sh <next|active|prev|done> <session-name>
# The window becomes <name>-next, <name>, <name>-prev or <name>-done.
#
# Like spawn-successor.sh, a sanctioned way for an agent to change the owner's tmux server (guard-tmux-socket.sh
# does not look inside scripts). The only tmux call that changes anything is the rename-window below, aimed at the
# window of $TMUX_PANE with a name built from the validated role and session name.
#
# Naming must never fail a handoff, so outside tmux it only prints a note.
set -euo pipefail
usage="usage: rename-window.sh <next|active|prev|done> <session-name>"
role=${1:-}
name=${2:-}
case $role in
active) suffix="" ;;
next | prev | done) suffix="-$role" ;;
*)
  echo "$usage" >&2
  exit 2
  ;;
esac

# shellcheck source=window-names.sh
source "$(dirname "${BASH_SOURCE[0]}")/window-names.sh"
valid_session_name "$name" || {
  echo "$usage" >&2
  exit 2
}
if [[ -z ${TMUX:-} || -z ${TMUX_PANE:-} ]]; then
  echo "not inside tmux; window name left alone"
  exit 0
fi

tmux rename-window -t "$(own_window_id)" "$name$suffix"
echo "renamed window to $name$suffix"
