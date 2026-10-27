#!/usr/bin/env bash
# PreToolUse(Bash): route PR review-thread replies and resolves through resolve-thread.sh instead of hand-written
# `gh api graphql` mutations. Creating a review or review comment stays allowed.
# Known limit, left open because only a contrived command reaches it: a mutation name built at run time
# (`m=resolve; ...${m}ReviewThread`), or a query file another call wrote and this one only names through a variable
# the hook cannot read (that one is denied, as unreadable). Also open: a query fed from outside the command text
# (`-f query="$(cat f)"`, `cat q | gh api graphql --input -`).
set -u
cmd=$(jq -r '.tool_input.command // empty')
[[ $cmd == *graphql* ]] || exit 0

# `gh` must be run, not mentioned: only a command boundary may precede it (start, ; & | ( { ! backtick, newline, an
# opening quote for `bash -c "gh ..."`, or the keywords then/do/else/elif), then any VAR=val assignments and wrapper
# words with their flags, and an optional path. Prose such as `git commit -m "see gh api graphql ..."` has a plain word
# before gh and passes; a message that begins with gh is denied, which is fail-closed. Only flags may sit between gh and
# `api`, so `gh pr comment --body "... api graphql"` passes too. The match runs to the next ; & |, which is where file
# arguments are read from; a ; inside quotes ends it early (left open: the mutation-name check still sees everything).
nl=$'\n'
boundary="(^|[;&|(\`{!'\"$nl]|[[:space:]](then|do|else|elif)[[:space:]])[[:space:]]*"
wrapper_flags='([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*'
wrappers="(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|(env|sudo|time|command|exec|eval|nice|nohup|xargs|timeout)${wrapper_flags})[[:space:]]+)*"
gh_flags='(-[^[:space:]]+[[:space:]]+([^-[:space:]][^[:space:]]*[[:space:]]+)?)*'
gh_graphql="${boundary}${wrappers}([^[:space:]]*/)?gh[[:space:]]+${gh_flags}api[[:space:]][^;&|]*graphql[^;&|]*"
[[ $cmd =~ $gh_graphql ]] || exit 0
graphql_call=${BASH_REMATCH[0]}

mutations='addPullRequestReviewThreadReply|resolveReviewThread|unresolveReviewThread'
denied=false
[[ $cmd =~ $mutations ]] && denied=true

# A query read from a file (`-F query=@F`, `-f query=@F`, `--input F`) is checked by its content. An unreadable file
# (a missing one, or a path through a variable) is denied, since its content cannot be seen; `--input -` is the
# command's own heredoc, already covered above.
quote=$'\''
file_arg="(query=@|--input[[:space:]=]+)[$quote\"]?([^[:space:];&|$quote\"]+)"
rest=$graphql_call
while ! $denied && [[ $rest =~ $file_arg ]]; do
  path=${BASH_REMATCH[2]}
  rest=${rest#*"${BASH_REMATCH[0]}"}
  [[ $path == - ]] && continue
  path=${path/#\~\//$HOME/}
  if [[ -r $path && -f $path ]]; then
    ! grep -Eq "$mutations" "$path" || denied=true
  else
    denied=true
  fi
done
$denied || exit 0

reason='Blocked: use ~/.claude/skills/merge-prs/resolve-thread.sh <PRRT_id> "<reply>" (list ids with --list <pr>); raw gh api graphql thread mutations are denied.'
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
