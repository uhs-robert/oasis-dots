#!/usr/bin/env bash
# PreToolUse(Bash): refuse tmux commands that could reach the owner's tmux server.
# Agent sessions run inside the owner's tmux, so $TMUX names the owner's socket and tmux prefers it over TMUX_TMPDIR;
# only -L or -S points elsewhere. Fails closed instead of parsing the shell: every `tmux` word must be followed (past
# its global flags) by a -L/-S naming a socket that is plainly not the owner's, else the whole command must be one
# plain read-only call. So wrappers, `bash -c` and heredocs need no entry, and a command that only mentions tmux is
# denied too: put that text in a file, or quote it away from the word. Tmux inside a script file is not inspected.
set -u
cmd=$(jq -r '.tool_input.command // empty')
cmd=${cmd//$'\\\n'/}
word='(^|[[:space:];&|(`"'"'"'/])tmux($|[[:space:];&|)`"'"'"'])'
[[ $cmd =~ $word ]] || exit 0

total=$(grep -oE "$word" <<<"$cmd" | wc -l)
# tmux, global flags (-f/-c/-T take a word), then -L name or -S path.
own='tmux( +(-[fcT] +[^[:space:]]+|-[^LSfcT[:space:]]+))* +-[LS] ?[^[:space:]]+'
safe=0 owner=${TMUX%%,*}
while IFS= read -r call; do
  value=${call##*-[LS]} value=${value# }
  [[ $call == *" -L"* ]] && ok=${value:+1} || ok=
  if [[ $call =~ \ -S ]]; then
    ok=1 resolved=$(realpath -m -- "$value" 2>/dev/null)
    [[ $value == /* && $resolved != */tmux-[0-9]*/* && $resolved != "$(realpath -m -- "$owner")" ]] || ok=
  elif [[ $value == default || $value == "${owner##*/}" ]]; then ok=; fi
  [[ $value == *[\$\`~]* ]] && ok=
  [[ -n $ok ]] && safe=$((safe + 1))
done < <(grep -oE "$own" <<<"$cmd")
((safe == total)) && exit 0

read_only='^[[:space:]]*tmux +(ls|list-[a-z-]+|has-session|has|show-options|show|show-environment|showenv|display(-message)? +(-[A-Za-z]+ +)*-p)( |$)'
if [[ $cmd =~ $read_only && $cmd != *[\;\&\|\`\(\)\<\>\\$'\n']* && ! $cmd =~ \ -[A-Za-z]*I ]]; then exit 0; fi

reason="Blocked: this command has a tmux word that is not tied to a socket other than the owner's. This session runs inside the owner's tmux, so \$TMUX points at the owner's socket and tmux prefers it over TMUX_TMPDIR. Run your own server: \`env -u TMUX tmux -L <unique-name> ...\` for every call, including the final kill-server. -L must be a literal name other than \`default\`, -S a literal absolute path outside /tmp/tmux-<uid>/; a value with \$, a backtick or ~ cannot be verified. Without -L or -S only a single read-only call passes (ls, list-*, has-session, display-message -p, show-options, show-environment). A command that only mentions tmux is denied too; keep that text out of the command line."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
