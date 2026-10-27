#!/usr/bin/env bash
# Feeds commands to guard-gh-thread-mutations.sh: gh api graphql thread mutations are denied, read queries and
# mere mentions pass.
# shellcheck disable=SC2016,SC2088 # the commands are fed to the hook literally, so nothing should expand
set -uo pipefail
hook=$(cd "$(dirname "$0")" && pwd)/../guard-gh-thread-mutations.sh
pass=0 fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'mutation { resolveReviewThread(input: {threadId: "x"}) { thread { id } } }\n' >"$tmp/mutation.graphql"
printf '{viewer{login}}\n' >"$tmp/read.graphql"
printf '{"query": "mutation { addPullRequestReviewThreadReply(input: {}) { clientMutationId } }"}\n' >"$tmp/body.json"

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

# Thread mutations
expect deny 'gh api graphql -f query='\''mutation { resolveReviewThread(input: {threadId: "PRRT_x"}) { thread { id } } }'\'
expect deny 'gh api graphql -f query='\''mutation { unresolveReviewThread(input: {threadId: "PRRT_x"}) { thread { id } } }'\'
expect deny 'gh api graphql -f query='\''mutation { addPullRequestReviewThreadReply(input: {}) { comment { id } } }'\'
expect deny 'gh -R o/r api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'
expect deny 'gh api -H "X-Y: z" graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'
expect deny 'git status && gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'
expect deny $'gh api graphql --input - <<\'EOF\'\n{"query":"mutation { resolveReviewThread(input: {}) { thread { id } } }"}\nEOF'
# Through a file
expect deny "gh api graphql -F query=@$tmp/mutation.graphql"
expect deny "gh api graphql -f query=@$tmp/mutation.graphql"
expect deny "gh api graphql --input $tmp/body.json"
expect deny "gh api graphql --input=$tmp/body.json"
expect deny "gh api graphql -F query=@$tmp/missing.graphql"
expect deny 'gh api graphql -F query=@$QUERY_FILE'
# Reads and mentions
expect allow 'gh api graphql -F owner=o -F name=r -F number=5 -f query='\''query { repository(owner: "o", name: "r") { pullRequest(number: 5) { reviewThreads(first: 100) { nodes { id isResolved } } } } }'\'
expect allow "gh api graphql -f query='{viewer{login}}'"
expect allow "gh api graphql -F query=@$tmp/read.graphql"
expect allow 'gh api graphql --input -'
expect allow '~/.claude/skills/merge-prs/resolve-thread.sh PRRT_x "fixed"'
expect allow '/home/roberth/.claude/skills/merge-prs/resolve-thread.sh --list 12'
expect allow 'echo resolveReviewThread'
expect allow 'grep -rn resolveReviewThread ~/.claude'
expect allow 'gh pr view 5'
expect allow 'gh api repos/o/r/pulls/5/comments'
# Prose that names the call is not a call
expect allow 'git commit -m "route gh api graphql resolveReviewThread through resolve-thread.sh"'
expect allow 'gh pr comment 5 --body "do not run gh api graphql with resolveReviewThread by hand"'
expect allow 'gh pr edit 5 --body "gh api graphql addPullRequestReviewThreadReply is denied"'
# A file argument of another command in the chain is not the query file
expect allow "gh api graphql -F query=@$tmp/read.graphql && foo --input $tmp/missing.txt"
expect deny $'echo hi\ngh api graphql -f query=\'mutation { resolveReviewThread(input: {}) { thread { id } } }\''
# Review creation stays allowed
expect allow 'gh api graphql -f query='\''mutation { addPullRequestReview(input: {pullRequestId: "x"}) { pullRequestReview { id } } }'\'

echo "$pass passed, $fail failed"
((fail == 0))
