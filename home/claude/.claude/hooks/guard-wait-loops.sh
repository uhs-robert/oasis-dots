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
  { opener = $0; gsub(/<<</, "   ", opener) } # a here-string takes no body
  match(opener, /<<[-~]?[ ]*["\x27]?[A-Za-z_][A-Za-z_0-9]*["\x27]?/) {
    w = substr(opener, RSTART, RLENGTH); tabs = (w ~ /^<<-/)
    sub(/^<<[-~]?[ ]*["\x27]?/, "", w); sub(/["\x27]$/, "", w); word = w; skip = 1
  }' <<<"$cmd")
# One line: line continuations joined, fd redirections and |& out of the way, a newline read as the ; it is.
flat=$(sed -E ':a; /\\$/ { N; s/\\\n/ /; ba }; s/[0-9]*>&[0-9-]*/ /g; s/&>>?/>/g; s/\|&/|/g' <<<"$cmd" | tr '\n' ';')

# Same length as flat, with the text inside quotes blanked, so a loop that a commit message or an echo only mentions
# is not found. A loop inside bash -c "..." is missed for the same reason. The loop's own condition is read from flat,
# where its quoted pattern is still there.
masked=$(awk '{
  out = ""; q = ""
  for (i = 1; i <= length($0); i++) {
    c = substr($0, i, 1)
    if (q == "") { out = out c; if (c == "\"" || c == "\x27") q = c }
    else if (c == q) { out = out c; q = "" }
    else if (c == "\\" && q == "\"") { out = out "__"; i++ }
    else out = out "_"
  }
  print out
}' <<<"$flat")

# The Bash tool runs every command inside a live `bash -c ... eval '<command>'`, so a literal pgrep -f pattern matches
# that wrapper's own command line and the loop never ends. A $var pattern or a [x] bracket does not match itself.
# The condition is cut at the first ;, so a compound condition has to join its parts with && or ||.
loop='(^|[^[:alnum:]_.-])(while|until)([[:space:]]+)([^;]*)[[:space:]]*;[[:space:]]*do([[:space:]]|;|$)'
full_flag='[[:space:]](-[a-zA-Z]*f[a-zA-Z]*|--full)([[:space:]]|$)'
pos=0
while [[ ${masked:pos} =~ $loop ]]; do
  rest=${masked:pos}
  whole=${BASH_REMATCH[0]}
  lead=${#BASH_REMATCH[1]}
  cond_len=${#BASH_REMATCH[4]}
  cond_offset=$((lead + ${#BASH_REMATCH[2]} + ${#BASH_REMATCH[3]}))
  after_match=${rest#*"$whole"}
  start=$((pos + ${#rest} - ${#after_match} - ${#whole}))
  pos=$((start + ${#whole}))
  cond=${flat:start+cond_offset:cond_len}
  scan=$cond
  while [[ $scan == *pgrep* ]]; do
    scan=${scan#*pgrep}
    args=${scan%%pgrep*}
    args=${args%%&&*}
    args=${args%%||*}
    args=${args%%|*}
    args=${args%%[\);>]*}
    [[ $args =~ $full_flag ]] || continue
    # Only the pattern can make the loop safe: -u "$USER" does not. It is the word that is neither an option nor the
    # value of one. pgrep options that take a value: -d -g -G -P -s -t -u -U -F and --delimiter --pgroup --group
    # --parent --session --terminal --euid --uid --pidfile --ns --nslist --signal.
    read -ra arg_words <<<"$args"
    pattern=""
    skip_value=false
    for arg_word in "${arg_words[@]}"; do
      if $skip_value; then
        skip_value=false
      elif [[ $arg_word == --* ]]; then
        [[ $arg_word == *=* || ! $arg_word =~ ^--(delimiter|pgroup|group|parent|session|terminal|euid|uid|pidfile|ns|nslist|signal)$ ]] ||
          skip_value=true
      elif [[ $arg_word == -* ]]; then
        # In a cluster the first value option takes the rest of the word as its value, or the next word if none is left.
        cluster=${arg_word#-}
        value_option=${cluster#"${cluster%%[dgGPstuUF]*}"}
        ((${#value_option} == 1)) && skip_value=true
      else
        pattern=$arg_word
      fi
    done
    [[ -n $pattern ]] || continue
    [[ $pattern == *[\$\[]* ]] ||
      deny "pgrep -f with a literal pattern in a wait loop matches the loop's own command line (the Bash tool keeps it in a live process), so the loop never ends: wait <pid> for a child, tail --pid=<pid> -f /dev/null, flock, a [p]attern bracket form, a \$var pattern, or put a timeout around the wait"
  done
done
exit 0
