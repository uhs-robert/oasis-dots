#!/usr/bin/env bash
# PreToolUse(Bash): route PR review-thread replies and resolves through resolve-thread.sh instead of hand-written
# `gh api graphql` mutations. Creating a review or review comment stays allowed.
# Known limit, left open because only a contrived command reaches it: a mutation name built at run time
# (`m=resolve; ...${m}ReviewThread`), or a query file another call wrote and this one only names through a variable
# the hook cannot read (that one is denied, as unreadable).
set -u
cmd=$(jq -r '.tool_input.command // empty')
[[ $cmd == *graphql* ]] || exit 0

gh_graphql='(^|[[:space:];&|(])gh[^;&|]*[[:space:]]api[[:space:]][^;&|]*graphql'
[[ $cmd =~ $gh_graphql ]] || exit 0

mutations='addPullRequestReviewThreadReply|resolveReviewThread|unresolveReviewThread'
denied=false
[[ $cmd =~ $mutations ]] && denied=true

# A query read from a file (`-F query=@F`, `-f query=@F`, `--input F`) is checked by its content. An unreadable file
# (a missing one, or a path through a variable) is denied, since its content cannot be seen; `--input -` is the
# command's own heredoc, already covered above.
quote=$'\''
file_arg="(query=@|--input[[:space:]=]+)[$quote\"]?([^[:space:];&|$quote\"]+)"
rest=$cmd
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
