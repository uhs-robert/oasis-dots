#!/usr/bin/env bash
# PreToolUse(Bash): refuse a while or until loop whose condition runs pgrep -f on a literal pattern.
set -u
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ -n $cmd ]] || exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# Heredoc bodies are text (commit messages, files being written), not commands.
cmd=$(awk '
  skip { line = $0; if (tabs) sub(/^\t+/, "", line); if (line == word) skip = 0; next }
  { print }
  match($0, /<<[-~]?[ ]*["\x27]?[A-Za-z_][A-Za-z_0-9]*["\x27]?/) {
    w = substr($0, RSTART, RLENGTH); tabs = (w ~ /^<<-/)
    sub(/^<<[-~]?[ ]*["\x27]?/, "", w); sub(/["\x27]$/, "", w); word = w; skip = 1
  }' <<<"$cmd")
# One line: line continuations joined, fd redirections and |& out of the way, a newline read as the ; it is.
flat=$(sed -E ':a; /\\$/ { N; s/\\\n/ /; ba }; s/[0-9]*>&[0-9-]*/ /g; s/&>>?/>/g; s/\|&/|/g' <<<"$cmd" | tr '\n' ';')

# The Bash tool runs every command inside a live `bash -c ... eval '<command>'`, so a literal pgrep -f pattern matches
# that wrapper's own command line and the loop never ends. A $var pattern or a [x] bracket does not match itself.
loop='(^|[^[:alnum:]_.-])(while|until)[[:space:]]+([^;]*)[[:space:]]*;[[:space:]]*do([[:space:]]|;|$)'
full_flag='[[:space:]](-[a-zA-Z]*f[a-zA-Z]*|--full)([[:space:]]|$)'
under_timeout='(^|[;&|(`{[:space:]])timeout[[:space:]]+[^;&|]*$'
unchecked=$flat
while [[ $unchecked =~ $loop ]]; do
  whole=${BASH_REMATCH[0]}
  cond=${BASH_REMATCH[3]}
  before=${unchecked%%"$whole"*}
  unchecked=${unchecked#*"$whole"}
  # A wait under timeout still ends.
  [[ $before =~ $under_timeout ]] && continue
  scan=$cond
  while [[ $scan == *pgrep* ]]; do
    scan=${scan#*pgrep}
    args=${scan%%pgrep*}
    args=${args%%&&*}
    args=${args%%||*}
    args=${args%%[\);>]*}
    [[ $args =~ $full_flag ]] || continue
    [[ $args == *[\$\[]* ]] ||
      deny "pgrep -f with a literal pattern in a wait loop matches the loop's own command line (the Bash tool keeps it in a live process), so the loop never ends: wait <pid> for a child, tail --pid=<pid> -f /dev/null, flock, a [p]attern bracket form, a \$var pattern, or put a timeout around the wait"
  done
done
exit 0
