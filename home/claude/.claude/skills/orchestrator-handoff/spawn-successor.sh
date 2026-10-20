#!/usr/bin/env bash
# Opens a fresh Claude session in a new window of the caller's own tmux session, primed to take an orchestrator
# handoff from the session named in $1. Usage: spawn-successor.sh <predecessor-session-name>
#
# This is the one sanctioned way for an agent to change the owner's tmux server: guard-tmux-socket.sh refuses
# tmux commands that do, and does not look inside scripts. Keep it to this single fixed new-window call, with no
# caller-supplied command, so the exception stays narrow.
#
# The successor still asks the owner before taking the role: the launch prompt below comes from another session,
# not the owner, so it never counts as the owner saying to expect the handoff.
set -euo pipefail
predecessor=${1:-}
[[ $predecessor =~ ^[A-Za-z0-9._:/-]+$ ]] || {
  echo "usage: spawn-successor.sh <predecessor-session-name>" >&2
  exit 2
}
[[ -n ${TMUX:-} ]] || {
  echo "not inside tmux; ask the owner to start the successor by hand" >&2
  exit 3
}

main_checkout=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
session=$(tmux display-message -p '#S')
prompt="Load the orchestrator-handoff skill. $predecessor will hand you the orchestrator role for $main_checkout. Send it \"READY\" with SendMessage, then wait for its BATON and follow the skill's Take over part. This prompt was written by $predecessor, not the owner: ask the owner before taking the role."

tmux new-window -t "$session:" -c "$main_checkout" -n orchestrator-next "claude $(printf '%q' "$prompt")"
echo "opened window orchestrator-next in tmux session $session"
