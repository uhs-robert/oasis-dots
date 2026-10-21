#!/usr/bin/env bash
# shellcheck disable=SC2088  # the tilde stays literal: the hook matches the command text, not an expanded path
# Feeds commands to guard-gh-merge.sh: a PR merge through the gh CLI and a merging merge-prs.sh run are denied;
# --check, --help, ship-batch and mentions (also in commit or PR messages) pass.
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

# gh global flags before or after pr.
expect deny "gh -R x pr merge 1"
expect deny "gh pr -R x merge 1"
expect deny "gh --repo o/r pr merge 1 --rebase"
expect allow "gh -R x pr view 1"
# Mentions inside commit or PR message arguments and heredoc bodies are no call.
expect allow $'git commit -m "fix\nmerge-prs.sh is slow"'
expect allow "git commit -m 'note: ; merge-prs.sh 1'"
expect allow "gh pr create --body \"use $gh_merge for x\""
expect allow "gh pr create --title 'x' --body 'run \`merge-prs.sh 1\` by hand'"
expect allow $'git commit -F - <<\'EOF\'\nfix: x\n\nmerge-prs.sh 1 and '"$gh_merge"$' 2\nEOF'
expect allow $'gh pr create --body "$(cat <<\'EOF\'\nuse '"$gh_merge"$' it\'s\nEOF\n)"'
# A real call beside a message, an unterminated quote, or text after a heredoc still denies.
expect deny "git commit -m 'x' && merge-prs.sh 1"
expect deny "git commit -m 'x'; $gh_merge 1"
expect deny $'cat <<EOF\nok\nEOF\nmerge-prs.sh 1'
expect deny "git commit -m \"unclosed; merge-prs.sh 1"
expect deny "git commit -m 'it's'; merge-prs.sh 1"
# Text the shell still runs is not stripped: a command substitution in a message, a heredoc fed to a shell.
# shellcheck disable=SC2016  # the hook is fed the literal text, not its expansion
expect deny 'git commit -m "$(merge-prs.sh 1)"'
expect deny "git commit -m \"\`merge-prs.sh 1\`\""
expect deny $'bash <<\'EOF\'\nmerge-prs.sh 1\nEOF'
expect deny $'eval "$(cat <<\'EOF\'\nmerge-prs.sh 1\nEOF\n)"'
expect deny $'cat <<EOF | sh\nmerge-prs.sh 1\nEOF'

echo "$pass passed, $fail failed"
((fail == 0))
