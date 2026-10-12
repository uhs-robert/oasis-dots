#!/usr/bin/env bash
# PreToolUse(Bash): refuse `$var:x` when the Bash tool runs zsh, where `:h`, `:t`, `:r`, `:e`, `:l`, `:f`... are
# history modifiers, so `git show $sha:home/file` silently becomes `git show <dirname of $sha>ome/file`.
set -u
[[ ${SHELL##*/} == zsh ]] || exit 0
cmd=$(jq -r '.tool_input.command // empty')
[[ $cmd == *'$'*:* ]] || exit 0

# Quoted heredoc bodies are literal file text, and single-quoted spans never expand. Quote state is tracked per
# character so an apostrophe inside double quotes or after a backslash stays literal, as zsh treats it.
cmd=$(awk '
  skip { line = $0; if (tabs) sub(/^\t+/, "", line); if (line == word) skip = 0; next }
  {
    out = ""; n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (sq) { if (c == "\047") sq = 0; continue }
      if (c == "\\") { out = out c substr($0, i + 1, 1); i++; continue }
      if (c == "\"") dq = !dq
      else if (c == "\047" && !dq) { sq = 1; continue }
      out = out c
    }
    print out
  }
  match($0, /<<[-~]?[ ]*["\047][A-Za-z_][A-Za-z_0-9]*["\047]/) {
    w = substr($0, RSTART, RLENGTH); tabs = (w ~ /^<<-/)
    sub(/^<<[-~]?[ ]*["\047]/, "", w); sub(/["\047]$/, "", w); word = w; skip = 1
  }' <<<"$cmd")

modifier='\$[A-Za-z_][A-Za-z0-9_]*:[hrteaAcluqQPsfFwW&]'
[[ $cmd =~ $modifier ]] || exit 0
hit=${BASH_REMATCH[0]}
name=${hit%%:*}
name=${name#\$}

reason="Blocked: '$hit' in zsh (the Bash tool's shell) applies the history modifier ':${hit##*:}' to \$$name instead of appending text, e.g. \`git show \$sha:home/f\` reads \`\$sha\`'s dirname. Write \${$name}:... (braces end the name before the colon). Single-quoted text and quoted heredoc bodies are not checked."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
