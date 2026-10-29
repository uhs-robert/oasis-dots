#!/usr/bin/env bash
# PreToolUse(Bash): keep agents from killing the owner's tmux server. Sessions run inside the owner's tmux, so a bare
# `tmux kill-server` closes every one of the owner's sessions. Only that is caught (at the start of the command or
# after `&&`, `;`, `|`, with no -L/-S); every other tmux call passes. A nudge, not a defence: the owner wants agents
# free to use their tmux (new windows, sessions, send-keys), so do not widen this past kill-server.
set -u
cmd=$(jq -r '.tool_input.command // empty')
[[ $cmd == *kill-server* ]] || exit 0
while IFS= read -r call; do
  call=${call#"${call%%[![:space:]]*}"}
  [[ $call == tmux\ * && $call == *kill-server* && ! $call =~ \ -[LS] ]] || continue
  reason="Blocked: this kills the owner's tmux server. Kill only your own: \`tmux -L <name> kill-server\`."
  jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
done < <(sed -E 's/&&|;|\|/\n/g' <<<"$cmd")
