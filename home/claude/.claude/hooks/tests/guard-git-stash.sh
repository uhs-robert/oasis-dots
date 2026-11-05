#!/usr/bin/env bash
# Feeds commands to guard-git-stash.sh: a subagent's git stash is denied unless it only reads; the main session passes.
set -uo pipefail
hook=$(cd "$(dirname "$0")" && pwd)/../guard-git-stash.sh
pass=0 fail=0

# expect <allow|deny> <agent|main> <command>
expect() {
  local out got=allow
  out=$(jq -n --arg c "$3" --arg who "$2" '{tool_input: {command: $c}} + (if $who == "agent" then {agent_id: "a1"} else {} end)' |
    "$hook" | jq -r '.hookSpecificOutput.permissionDecision // empty')
  [[ $out == deny ]] && got=deny
  if [[ $got == "$1" ]]; then
    echo "ok   $1 ($2): $3"
    pass=$((pass + 1))
  else
    echo "FAIL $1 ($2): $3 (got $got)"
    fail=$((fail + 1))
  fi
}

for sub in "" push save pop apply drop clear create store branch "push -u" "-u" "pop stash@{1}"; do
  expect deny agent "git stash $sub"
done
expect allow agent 'git stash list'
expect allow agent 'git stash show -p stash@{0}'
expect allow main 'git stash'
expect allow main 'git stash pop'
expect deny agent 'git -C x stash pop'
expect deny agent 'git -c core.pager=cat --git-dir=x stash drop'
expect deny agent 'cd x && git stash'
expect deny agent 'git status; git stash pop'
expect deny agent 'git diff | git stash apply'
expect allow agent 'git stash list && git log'
expect allow agent 'echo stash'
expect allow agent 'git commit -m "stash"'
expect allow agent 'git log --grep stash'

echo "$pass passed, $fail failed"
((fail == 0))
