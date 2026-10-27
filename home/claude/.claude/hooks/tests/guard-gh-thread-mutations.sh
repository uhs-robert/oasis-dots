#!/usr/bin/env bash
# Feeds commands to guard-gh-thread-mutations.sh: raw thread mutations are denied, everything else passes.
# shellcheck disable=SC2016,SC2088 # the commands are fed to the hook literally, so nothing should expand
set -uo pipefail
hook=$(cd "$(dirname "$0")" && pwd)/../guard-gh-thread-mutations.sh
pass=0 fail=0

# expect <allow|deny> <command>
expect() {
  local out got=allow
  out=$(jq -n --arg c "$2" '{tool_input: {command: $c}}' | "$hook" | jq -r '.hookSpecificOutput.permissionDecision // empty')
  [[ $out == deny ]] && got=deny
  if [[ $got == "$1" ]]; then
    echo "ok   $1: $2"
    pass=$((pass + 1))
  else
    echo "FAIL $1: $2 (got $got)"
    fail=$((fail + 1))
  fi
}

expect deny 'gh api graphql -f query='\''mutation { resolveReviewThread(input: {threadId: "PRRT_x"}) { thread { id } } }'\'
expect deny 'gh api graphql -f query='\''mutation { unresolveReviewThread(input: {threadId: "PRRT_x"}) { thread { id } } }'\'
expect deny 'gh api graphql -f query='\''mutation { addPullRequestReviewThreadReply(input: {}) { comment { id } } }'\'
expect allow '~/.claude/skills/merge-prs/resolve-thread.sh PRRT_x "fixed"'
expect allow 'gh api graphql -F number=5 -f query='\''query { repository(owner: "o", name: "r") { pullRequest(number: 5) { reviewThreads(first: 100) { nodes { id isResolved } } } } }'\'
expect allow "gh api graphql -f query='{viewer{login}}'"
expect allow 'gh api graphql -f query='\''mutation { addPullRequestReview(input: {pullRequestId: "x"}) { pullRequestReview { id } } }'\'
expect allow 'echo resolveReviewThread'

echo "$pass passed, $fail failed"
((fail == 0))
