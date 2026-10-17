#!/usr/bin/env bash
# shellcheck disable=SC2088  # the tilde stays literal: the hook matches the command text, not an expanded path
# Feeds commands to guard-gh-merge.sh: a PR merge through the gh CLI and a merging merge-prs.sh run are denied;
# --check, --help, ship-batch and mere mentions pass.
set -uo pipefail
hook=$(cd "$(dirname "$0")" && pwd)/../guard-gh-merge.sh
pass=0 fail=0

# expect <allow|deny> <command>
expect() {
  local decision
  decision=$(jq -n --arg c "$2" '{tool_input: {command: $c}}' | "$hook" | jq -r '.hookSpecificOutput.permissionDecision // empty')
  decision=${decision:-allow}
  if [[ $decision == "$1" ]]; then
    echo "ok   $1: $2"
    pass=$((pass + 1))
  else
    echo "FAIL $1: $2 (got $decision)"
    fail=$((fail + 1))
  fi
}

gh_merge="gh pr"" merge"
expect deny "$gh_merge 994 --rebase"
expect deny 'merge-prs.sh 994'
expect deny '~/.claude/skills/merge-prs/merge-prs.sh 994'
expect deny '~/.claude/skills/merge-prs/merge-prs.sh --method rebase 1 2'
expect deny 'cd x && merge-prs.sh 994'
expect deny 'cd x; ./merge-prs.sh --keep-branch 994'
expect deny 'bash ~/.claude/skills/merge-prs/merge-prs.sh 994'
expect deny $'echo hi\nmerge-prs.sh 994'
expect deny 'merge-prs.sh --check 1 && merge-prs.sh 2'
expect deny 'timeout 600 ~/.claude/skills/merge-prs/merge-prs.sh 1'
expect deny 'env X=1 merge-prs.sh 1'
expect deny 'X=1 nohup sh merge-prs.sh 1'
expect allow 'timeout 600 merge-prs.sh --check 1'
expect allow 'merge-prs.sh --check 994'
expect allow 'merge-prs.sh --check --wait-review 994'
expect allow '~/.claude/skills/merge-prs/merge-prs.sh --check --wait-review --request-review 994'
expect allow 'merge-prs.sh --help'
expect allow 'merge-prs.sh'
expect allow '.claude/skills/ship-batch/ship-batch.sh 994'
expect allow '.claude/skills/ship-batch/ship-batch.sh'
expect allow 'grep merge-prs.sh x'
expect allow 'cat ~/.claude/skills/merge-prs/SKILL.md'
expect allow 'git log -- home/claude/.claude/skills/merge-prs/merge-prs.sh'
expect allow 'gh pr view 994'

echo "$pass passed, $fail failed"
((fail == 0))
