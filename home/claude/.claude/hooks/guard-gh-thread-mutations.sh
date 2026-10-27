#!/usr/bin/env bash
# PreToolUse(Bash): steer agents from hand-written `gh api graphql` thread replies and resolves to resolve-thread.sh.
# A steer, not a security boundary: a command that hides the mutation name or the word graphql gets through, and that
# is expected and not worth closing. Creating a review or review comment stays allowed.
set -u
cmd=$(jq -r '.tool_input.command // empty')
[[ $cmd == *graphql* ]] || exit 0
[[ $cmd =~ addPullRequestReviewThreadReply|resolveReviewThread|unresolveReviewThread ]] || exit 0

reason='Blocked: use ~/.claude/skills/merge-prs/resolve-thread.sh <PRRT_id> "<reply>" (list ids with --list <pr>); raw gh api graphql thread mutations are denied.'
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
