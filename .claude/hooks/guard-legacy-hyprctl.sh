#!/usr/bin/env bash
# PreToolUse(Bash): refuse hyprctl forms the Lua config rejects: `keyword`, and `dispatch` with a classic dispatcher name.
set -u
cmd=$(jq -r '.tool_input.command // empty')
[[ $cmd == *hyprctl* ]] || exit 0

# Heredoc bodies are text (commit messages, files being written), not commands.
cmd=$(awk '
  skip { line = $0; if (tabs) sub(/^\t+/, "", line); if (line == word) skip = 0; next }
  { print }
  match($0, /<<[-~]?[ ]*["\x27]?[A-Za-z_][A-Za-z_0-9]*["\x27]?/) {
    w = substr($0, RSTART, RLENGTH); tabs = (w ~ /^<<-/)
    sub(/^<<[-~]?[ ]*["\x27]?/, "", w); sub(/["\x27]$/, "", w); word = w; skip = 1
  }' <<<"$cmd")

flags='([[:space:]]+(-[a-zA-Z]+|--[a-z-]+(=[^[:space:]]*)?|-i[[:space:]]+[0-9]+))*'
keyword="hyprctl${flags}[[:space:]]+keyword([[:space:]]|$)"
# `dispatch` takes a Lua expression; anything not starting with `hl.` is a classic dispatcher name.
dispatch="hyprctl${flags}[[:space:]]+dispatch[[:space:]]+[\"']?([^\"'[:space:]]+)"
batch="hyprctl${flags}[[:space:]]+--batch[[:space:]]+[\"']?[^\"']*(keyword|dispatch[[:space:]]+[^h[:space:]])"

legacy=""
if [[ $cmd =~ $keyword ]]; then
  legacy="hyprctl keyword"
elif [[ $cmd =~ $dispatch && ${BASH_REMATCH[-1]} != hl.* ]]; then
  legacy="hyprctl dispatch ${BASH_REMATCH[-1]}"
elif [[ $cmd =~ $batch ]]; then
  legacy="hyprctl --batch with a legacy keyword or dispatcher"
fi
[[ -n $legacy ]] || exit 0

reason="Blocked: '$legacy' is hyprlang syntax, but this Hyprland runs the Lua config (home/hypr/.config/hypr/hyprland.lua), so it fails or does nothing. Use the Lua API instead: \`hyprctl dispatch \"hl.dsp.exec_cmd('qs -n')\"\` (dispatch takes an hl.dsp.* expression), \`hyprctl eval 'hl.dispatch(hl.dsp.focus({ monitor = \"DP-8\" }))'\`, and \`hyprctl eval 'hl.config({ general = { gaps_in = 8 } })'\` in place of keyword. Read-only queries (clients, monitors, layers, activewindow) and \`hyprctl reload\` are fine."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
