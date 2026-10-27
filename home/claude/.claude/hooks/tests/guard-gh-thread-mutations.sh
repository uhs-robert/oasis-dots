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

# expect <allow|deny> <command> [cwd field of the hook input [directory the hook process runs in]]
expect() {
  local out got=allow
  out=$(jq -n --arg c "$2" --arg d "${3-}" '{tool_input: {command: $c}} + (if $d == "" then {} else {cwd: $d} end)' | (cd "${4:-.}" && "$hook") | jq -r '.hookSpecificOutput.permissionDecision // empty')
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
# Wrappers, loops and subshells around gh still run it
expect deny 'bash -c "gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\''"'
expect deny 'sh -c '\''gh api graphql -f query="mutation { resolveReviewThread(input: {}) { thread { id } } }"'\'''
expect deny 'eval gh api graphql -f query="'\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\''"'
expect deny 'GH_TOKEN=x gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'env X=1 Y=2 gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'sudo -u root gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'time gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'xargs -I{} gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'command gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'exec gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'nice -n 5 gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny '/usr/bin/gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'if true; then gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\''; fi'
expect deny 'for i in 1; do gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\''; done'
expect deny '{ gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\''; }'
expect deny '! gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'echo $(gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'')'
expect deny 'true || gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
# Wrappers and spellings of gh the hook does not list: anything naming the mutation with graphql is denied
expect deny 'timeout 5 gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'timeout -k 2 5 gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'parallel gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'watch gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'stdbuf -o0 gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'ionice -c3 gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'setsid gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'flock /tmp/l gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'chrt -i 0 gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny '\gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny '"gh" api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny '$GH api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'''
expect deny 'grep -r "gh api graphql resolveReviewThread" .'
# Any heredoc in a command naming a mutation is denied, even one fed to a prose command
expect deny $'git commit -F - <<\'EOF\'\nroute gh api graphql resolveReviewThread through the script\nEOF'
expect deny $'git commit -F - <<EOF\nroute gh api graphql resolveReviewThread through the script\nEOF'
expect deny $'cat <<\'EOF\'\ngh api graphql resolveReviewThread\nEOF'
expect deny 'echo "$(gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\'')"'
expect deny 'GIT_AUTHOR_NAME=x git commit -m "mention gh api graphql resolveReviewThread"'
expect deny 'GIT_EDITOR=gh${IFS}api${IFS}graphql${IFS}-f${IFS}query=mutation\{resolveReviewThread\(input:\{\}\)\{thread\{id\}\}\} git commit --allow-empty'
expect deny 'GH_EDITOR=gh${IFS}api${IFS}graphql${IFS}-f${IFS}query=mutation\{resolveReviewThread\(input:\{\}\)\{thread\{id\}\}\} gh pr comment 5'

# Bypasses of an earlier prose exception: echo and printf are no prose, and a pipe or input feed voids it
expect deny 'echo "gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\''" | bash'
expect deny 'echo "gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\''" | sh'
expect deny 'printf '\''%s'\'' "gh api graphql -f query='\''mutation { resolveReviewThread(input: {}) { thread { id } } }'\''" | sh'
expect deny 'echo '\''graphql mutation { resolveReviewThread(input: {}) { thread { id } } }'\'' | gh api graphql --input -'
expect deny 'echo '\''graphql mutation { resolveReviewThread(input: {}) { thread { id } } }'\'' | gh api graphql -F query=@-'
expect deny 'git commit -m "gh api graphql resolveReviewThread" | bash'
expect deny 'git commit -m "gh api graphql resolveReviewThread" > >(bash)'
expect deny 'git commit -m "gh api graphql resolveReviewThread" && bash <(echo hi)'
expect deny 'echo "gh api graphql resolveReviewThread"'
expect deny 'printf "gh api graphql resolveReviewThread"'
expect deny $'echo graphql "<<\'XX\'"\ngh api graphql -f query=\'mutation { resolveReviewThread(input: {}) { thread { id } } }\'\nXX'
expect deny $'echo graphql <<\'XX\' | bash\ngh api graphql -f query=\'mutation { resolveReviewThread(input: {}) { thread { id } } }\'\nXX'
expect deny $'git commit -F - <<\'EOF\'\nmentions gh api graphql resolveReviewThread\nEOF'
expect allow 'git commit -F msg.txt -m "mentions gh api graphql resolveReviewThread"'
# Query files must be given by absolute path: a relative one cannot be located
cp "$tmp/read.graphql" "$tmp/q.graphql"
expect deny 'gh api graphql -F query=@q.graphql' "$tmp"
expect deny 'gh api graphql --input payload.json' "$tmp"
expect deny 'cd /elsewhere && gh api graphql --input payload.json' "$tmp"
expect deny 'env -C /elsewhere gh api graphql --input payload.json' "$tmp"
expect deny 'env --chdir=/elsewhere gh api graphql -F query=@q.graphql' "$tmp"
expect deny 'gh api graphql -F query=@./q.graphql' "$tmp"
expect allow "gh api graphql -F query=@$tmp/q.graphql"
# stdin from a pipe or a file is unseen; a bare heredoc is the command's own text
expect deny 'cat /tmp/m.json | gh api graphql --input -'
expect deny 'gh api graphql --input - < /tmp/m.json'
expect deny 'gh api graphql -F query=@- < /tmp/m.json'
expect allow $'gh api graphql --input - <<\'EOF\'\n{"query":"{viewer{login}}"}\nEOF'
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
expect allow 'gh pr edit 5 --body "raw gh api graphql addPullRequestReviewThreadReply is denied"'
# A file argument of another command in the chain is not the query file
expect allow "gh api graphql -F query=@$tmp/read.graphql && foo --input $tmp/missing.txt"
expect deny $'echo hi\ngh api graphql -f query=\'mutation { resolveReviewThread(input: {}) { thread { id } } }\''
# Review creation stays allowed
expect allow 'gh api graphql -f query='\''mutation { addPullRequestReview(input: {pullRequestId: "x"}) { pullRequestReview { id } } }'\'

echo "$pass passed, $fail failed"
((fail == 0))
