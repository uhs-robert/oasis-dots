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

# Forms that get past a plain "git is the first word" check.
expect deny agent 'sudo git stash'
expect deny agent 'sudo -u root git stash pop'
expect deny agent 'env FOO=1 git stash'
expect deny agent 'command git stash'
expect deny agent 'time git stash'
expect deny agent 'nice git stash'
expect deny agent 'nice -n 5 git stash'
expect deny agent 'timeout 5 git stash'
expect deny agent 'echo x | xargs git stash'
expect deny agent '! git stash'
expect deny agent 'exec git stash'
expect deny agent '/usr/bin/git stash'
expect deny agent 'env -i /opt/bin/git stash drop'
expect deny agent "bash -c 'git stash pop'"
expect deny agent 'sh -c "cd x && git stash"'
expect deny agent "bash -lc 'git stash'"
expect deny agent $'git status\ngit stash pop'
expect deny agent '(git stash)'
# shellcheck disable=SC2016 # the command text is data, not expanded here
expect deny agent 'echo $(git stash pop)'
expect deny agent 'echo hi & git stash'
expect deny agent '{ git stash; }'
expect deny agent 'if true; then git stash; fi'
expect deny agent 'if false; then :; else git stash; fi'
expect deny agent 'for i in 1; do git stash; done'
expect deny agent 'git "stash" pop'

# Quoted text and heredoc bodies are not commands.
expect allow agent 'git commit -m "wip; git stash pop later"'
expect allow agent "git commit -m 'run git stash && more'"
expect allow agent "echo 'git stash'"
expect allow agent $'cat <<EOF\ngit stash pop\nEOF'
expect allow agent $'cat <<-\'EOF\' > f\n\tgit stash\n\tEOF'
expect deny agent $'cat <<EOF\nhello\nEOF\ngit stash pop'
expect allow agent 'git log --grep="git stash"'

echo "$pass passed, $fail failed"
((fail == 0))
