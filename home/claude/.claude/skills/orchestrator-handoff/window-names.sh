#!/usr/bin/env bash
# Sourced by spawn-successor.sh and rename-window.sh: the orchestrator window names, built from the Claude session
# name (as `ListAgents` shows it): `next` (placeholder), `<name>-next`, `<name>`, `<name>-prev`, `<name>-done`.
# Names need not be unique, so there is no counter.

# True for a session name safe to hand to tmux. The first character is not `-`, so tmux cannot read it as a flag.
valid_session_name() {
  [[ $1 =~ ^[A-Za-z0-9._:/][A-Za-z0-9._:/-]*$ ]]
}

# The caller's own window id, from $TMUX_PANE: the active window may be a different one.
own_window_id() {
  tmux display-message -p -t "${TMUX_PANE:?}" '#{window_id}'
}
