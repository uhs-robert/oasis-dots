#!/usr/bin/env bash
# PreToolUse(Bash): steer agents off the owner's tmux server. Sessions run inside the owner's tmux, so a bare `tmux`
# uses $TMUX's socket. This only catches a command that starts with `tmux` (also after `&&`, `;`, `|`) and names no
# -L/-S, unless it is read-only or opens a window (new-window/neww). It is a nudge, not a defence, so wrappers and
# `bash -c` strings are not inspected.
set -u
cmd=$(jq -r '.tool_input.command // empty')
[[ $cmd == *tmux* ]] || exit 0
unscoped_ok='^tmux +(ls|list-[a-z-]+|has-session|show[a-z-]*|new-window|neww|display(-message)? +(-[A-Za-z]+ +)*-p)( |$)'
while IFS= read -r call; do
  call=${call#"${call%%[![:space:]]*}"}
  [[ $call == tmux || $call == tmux\ * ]] || continue
  [[ $call =~ \ -[LS] || $call =~ $unscoped_ok ]] && continue
  reason="Blocked: this runs tmux against the owner's server. Use your own: \`env -u TMUX tmux -L <unique-name> ...\`, and kill-server on it when done. Only read-only calls (ls, list-*, display -p, show*) and new-window may omit -L."
  jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
done < <(sed -E 's/&&|;|\|/\n/g' <<<"$cmd")
