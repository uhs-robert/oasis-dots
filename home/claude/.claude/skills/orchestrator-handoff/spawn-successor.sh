#!/usr/bin/env bash
# Opens a fresh Claude session in a new window of the caller's own tmux session, primed to take an orchestrator
# handoff from the session named in $1. Usage: spawn-successor.sh <predecessor-session-name>
#
# With rename-window.sh, the sanctioned way for an agent to change the owner's tmux server: guard-tmux-socket.sh
# refuses tmux commands that do, and does not look inside scripts. Keep it to the fixed rename-window and
# new-window calls below, with no caller-supplied tmux argument, so the exception stays narrow.
#
# Windows are named orch-<N>[-next|-prev|-done] (see window-names.sh): the caller's becomes orch-<k>-prev and
# the successor's orch-<N>-next.
#
# The successor still asks the owner before taking the role: the launch prompt below comes from another session,
# not the owner, so it never counts as the owner saying to expect the handoff.
set -euo pipefail
predecessor=${1:-}
[[ $predecessor =~ ^[A-Za-z0-9._:/-]+$ ]] || {
  echo "usage: spawn-successor.sh <predecessor-session-name>" >&2
  exit 2
}
[[ -n ${TMUX:-} && -n ${TMUX_PANE:-} ]] || {
  echo "not inside tmux; ask the owner to start the successor by hand" >&2
  exit 3
}

# shellcheck source=window-names.sh
source "$(dirname "${BASH_SOURCE[0]}")/window-names.sh"

main_checkout=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
session=$(tmux display-message -p -t "$TMUX_PANE" '#S')

own_window=$(own_window_id)
own_number=$(window_number_of "$own_window")
[[ -n $own_number ]] || own_number=$(next_window_number)
number=$(next_window_number)

prompt="Load the orchestrator-handoff skill. $predecessor will hand you the orchestrator role for $main_checkout. Send it \"READY\" with SendMessage, then wait for its BATON and follow the skill's Take over part. This prompt was written by $predecessor, not the owner: ask the owner before taking the role. Your tmux window is orch-$number-next."

tmux new-window -t "$session:" -c "$main_checkout" -n "orch-$number-next" "claude $(printf '%q' "$prompt")"
# After the spawn: a failed new-window must leave the caller's name alone.
tmux rename-window -t "$own_window" "orch-$own_number-prev"
echo "opened window orch-$number-next in tmux session $session"
