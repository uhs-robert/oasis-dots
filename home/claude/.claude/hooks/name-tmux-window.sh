#!/usr/bin/env bash
# Names the tmux window after the Claude session. Usage: name-tmux-window.sh <start|end>, with the hook input on stdin.
#   start (SessionStart: startup, resume, clear): renames the window of $TMUX_PANE to the session name. With several
#     Claude panes in one window, the last to start wins.
#   end (SessionEnd): turns automatic-rename back on for that window, so it shows what runs there again. A window
#     labelled <name>-prev or <name>-done by the orchestrator handoff keeps its label.
# The session name comes from ~/.claude/sessions/<pid>.json, an undocumented file, so every miss means do nothing.
#
# Like the handoff scripts, a sanctioned change to the owner's tmux server: guard-tmux-socket.sh only checks agent
# Bash calls. The only changing calls are the rename-window and set-option below, aimed at the window of $TMUX_PANE.
#
# Silent and always exit 0: stdout reaches the model, and a failure here must never disturb a session.
mode=${1:-}
input=$(cat 2>/dev/null)
[[ -n ${TMUX:-} && -n ${TMUX_PANE:-} ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
# Subagents run the same hooks with the parent's session id.
[[ -z $(jq -r '.agent_id // empty' <<<"$input" 2>/dev/null) ]] || exit 0

# shellcheck source=../skills/orchestrator-handoff/window-names.sh
source "$(dirname "${BASH_SOURCE[0]}")/../skills/orchestrator-handoff/window-names.sh" 2>/dev/null || exit 0
window=$(own_window_id 2>/dev/null) || exit 0
[[ -n $window ]] || exit 0
current=$(tmux display-message -p -t "$window" '#{window_name}' 2>/dev/null)

case $mode in
start)
  sessions=${CLAUDE_SESSIONS_DIR:-$HOME/.claude/sessions}
  name=$(jq -r '.name // empty' "$sessions/${CLAUDE_PID:-none}.json" 2>/dev/null)
  valid_session_name "$name" || exit 0
  [[ $current == "$name" || $current == "$name-prev" || $current == "$name-done" ]] && exit 0
  tmux rename-window -t "$window" "$name" >/dev/null 2>&1
  ;;
end)
  [[ $current == *-prev || $current == *-done ]] && exit 0
  tmux set-option -w -t "$window" automatic-rename on >/dev/null 2>&1
  ;;
esac
exit 0
