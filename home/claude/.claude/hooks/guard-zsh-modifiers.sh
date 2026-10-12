#!/usr/bin/env bash
# PreToolUse(Bash): refuse `$var:x` when the Bash tool runs zsh, where `:h`, `:t`, `:r`, `:e`, `:l`... are history
# modifiers, so `git show $sha:home/file` silently becomes `git show <dirname of $sha>ome/file`.
set -u
[[ ${SHELL##*/} == zsh ]] || exit 0
cmd=$(jq -r '.tool_input.command // empty')
[[ $cmd == *'$'*:* ]] || exit 0

# Single-quoted text never expands; quoted heredocs are literal file bodies.
cmd=$(awk '
  skip { line = $0; if (tabs) sub(/^\t+/, "", line); if (line == word) skip = 0; next }
  { print }
  match($0, /<<[-~]?[ ]*["\x27][A-Za-z_][A-Za-z_0-9]*["\x27]/) {
    w = substr($0, RSTART, RLENGTH); tabs = (w ~ /^<<-/)
    sub(/^<<[-~]?[ ]*["\x27]/, "", w); sub(/["\x27]$/, "", w); word = w; skip = 1
  }' <<<"$cmd" | sed "s/'[^']*'//g")

modifier='\$[A-Za-z_][A-Za-z0-9_]*:[hrteaAcluqQPs&]'
[[ $cmd =~ $modifier ]] || exit 0
hit=${BASH_REMATCH[0]}
name=${hit%%:*}
name=${name#\$}

reason="Blocked: '$hit' in zsh (the Bash tool's shell) applies the history modifier ':${hit##*:}' to \$$name instead of appending text, e.g. \`git show \$sha:home/f\` reads \`\$sha\`'s dirname. Write \${$name}:... (braces end the name before the colon). Single-quoted text and quoted heredoc bodies are not checked."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
