#!/usr/bin/env bash
# shellcheck disable=SC2088,SC2016  # ~ and $ stay literal: the hook matches the command text, not its expansion
# Feeds commands to guard-gh-merge.sh: a PR merge through the gh CLI and a merging merge-prs.sh run are denied, also
# behind wrappers and inside code strings; --check, --help, ship-batch and mentions in quoted text pass.
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

# Wrappers and compound commands around a real call.
expect deny 'for p in 1 2; do merge-prs.sh $p; done'
expect deny 'while read p; do merge-prs.sh $p; done'
expect deny 'if true; then merge-prs.sh 1; fi'
expect deny 'if false; then :; else merge-prs.sh 1; fi'
expect deny 'cd x && { merge-prs.sh 1; }'
expect deny '(merge-prs.sh 1)'
expect deny 'sudo merge-prs.sh 1'
expect deny 'sudo -u root merge-prs.sh 1'
expect deny 'nice merge-prs.sh 1'
expect deny 'nice -n 5 merge-prs.sh 1'
expect deny 'stdbuf -oL merge-prs.sh 1'
expect deny 'env -i merge-prs.sh 1'
expect deny 'timeout -s KILL 5 merge-prs.sh 1'
expect deny "timeout 5 $gh_merge 1"
expect deny 'echo 1 | xargs merge-prs.sh'
expect deny 'xargs -n1 merge-prs.sh <<< 1'
expect deny 'echo 1 | xargs -I{} merge-prs.sh {}'
expect deny 'true || merge-prs.sh 1'
expect deny 'true | merge-prs.sh 1'
expect deny 'merge-prs.sh 1 2>&1 | tee log'
expect deny '>/dev/null merge-prs.sh 1'
expect deny "'merge-prs.sh' 1"
expect deny 'merge-prs\.sh 1'
expect deny $'merge-prs.sh \\\n  1'
expect deny "gh -R x pr merge 1"
expect deny "gh pr -R x merge 1"
expect deny "gh --repo x pr merge 1"
expect deny "/usr/bin/$gh_merge 1"
# Code strings are re-scanned.
expect deny 'bash -c "merge-prs.sh 1"'
expect deny "sh -c 'merge-prs.sh 1'"
expect deny "bash -lc 'cd x && merge-prs.sh 1'"
expect deny "bash -c \"$gh_merge 1\""
expect deny 'eval "merge-prs.sh 1"'
expect deny "timeout 5 bash -c \"$gh_merge 1\""
expect deny 'echo $(merge-prs.sh 1)'
expect deny 'echo `merge-prs.sh 1`'
expect deny 'git commit -m "$(merge-prs.sh 1)"'
expect deny "gh pr create --body \"\`merge-prs.sh 1\`\""
expect deny "gh pr create --body \"see \`$gh_merge 1\`\""
expect deny 'x=$( (true); merge-prs.sh 1 )'
expect deny 'cat <(merge-prs.sh 1)'
expect deny $'cat <<EOF\n$(merge-prs.sh 1)\nEOF'
expect deny $'cat <<EOF\nok\nEOF\nmerge-prs.sh 1'
# Commands that run a string argument as code (ssh, watch, trap, alias, su -c) get it re-scanned too.
expect deny "ssh host \"$gh_merge 1\""
expect deny 'watch "merge-prs.sh 1"'
expect deny "trap '$gh_merge 1' EXIT"
expect deny "alias m='$gh_merge'"
expect deny 'su -c "merge-prs.sh 1"'
expect deny "git rebase --exec '$gh_merge 1' main"
expect deny "git -c alias.m='!$gh_merge' m 1"
# What the tokenizer cannot follow falls back to the raw-text match, which denies these.
expect deny $'bash <<\'EOF\'\nmerge-prs.sh 1\nEOF'
expect deny 'echo "x; merge-prs.sh 1" | bash'
expect deny "printf '$gh_merge 1' | sh"
expect deny $'eval "$(cat <<\'EOF\'\nmerge-prs.sh 1\nEOF\n)"'
expect deny $'bash -c "$(cat <<\'EOF\'\nmerge-prs.sh 1\nEOF\n)"'
expect deny '"$(git rev-parse --show-toplevel)"/x/merge-prs.sh 1'
expect deny 'env -S "merge-prs.sh 1"'
expect deny 'x=$(case a in a) echo;; esac; merge-prs.sh 1)'
expect deny "bash -c \"bash -c 'bash -c \\\"bash -c merge-prs.sh\\\\ 1\\\"'\""
# Quoting and nesting the tokenizer has to get exactly right, or a call would hide behind it.
expect deny 'echo "$(bash -c "merge-prs.sh 1")"'
expect deny 'echo ${x:-$(merge-prs.sh 1)}'
expect deny 'echo $(( $(merge-prs.sh 1) + 1 ))'
expect deny "echo \$'c\\'d'; merge-prs.sh 1"
expect deny 'echo "\""; merge-prs.sh 1'
expect deny 'echo \"; merge-prs.sh 1'
expect deny "echo \\'; merge-prs.sh 1"
expect deny "echo '\"'; merge-prs.sh 1"
expect deny 'echo a#b; merge-prs.sh 1'
expect deny 'echo hi;merge-prs.sh 1'
expect deny '"merge-prs.sh" "1"'
expect deny 'f() { merge-prs.sh 1; }; f'
expect deny 'coproc merge-prs.sh 1'
expect deny "zsh -c 'merge-prs.sh 1'"
expect deny "xargs sh -c 'merge-prs.sh \"\$@\"' _"
# A heredoc or here-string feeds code to anything but a data command.
expect deny $'ssh host <<\'EOF\'\nmerge-prs.sh 1\nEOF'
expect deny 'ssh host <<< "x; merge-prs.sh 1"'
expect deny $'while read l; do eval "$l"; done <<\'EOF\'\nmerge-prs.sh 1\nEOF'
# Unbalanced quotes.
expect deny 'echo "unclosed; merge-prs.sh 1'
expect deny "echo 'unclosed; merge-prs.sh 1"
expect deny "git commit -m \"it's \\\" odd; $gh_merge 1"
expect deny 'echo $(merge-prs.sh 1'

# Mentions in quoted text, after a separator, newline or backtick inside the quotes.
expect allow $'git commit -m "fix\nmerge-prs.sh is slow"'
expect allow "git commit -m 'note: ; merge-prs.sh 1'"
expect allow 'git commit -m "note: && merge-prs.sh 1 | x"'
expect allow "gh pr create --body \"use $gh_merge for x\""
expect allow "gh pr create --title 'x' --body 'run \`merge-prs.sh 1\` by hand'"
expect allow "gh pr create --body \"run \\\`merge-prs.sh 1\\\` by hand\""
expect allow "gh pr create --body \"see \`merge-prs.sh\`\""
expect allow "grep -r \"$gh_merge\" ."
expect allow "echo $gh_merge 1"
expect allow "echo 'a;' merge-prs.sh 1"
expect allow 'echo hi # merge-prs.sh 1'
expect allow $'git commit -F - <<\'EOF\'\nfix: x\n\nmerge-prs.sh 1 and '"$gh_merge"$' 2\nEOF'
expect allow $'git commit -m "$(cat <<\'EOF\'\nfix: x\n\nmerge-prs.sh 1; '"$gh_merge"$' 2 `x`\nEOF\n)"'
expect allow $'cat <<EOF\nmerge-prs.sh 1\nEOF'
expect allow $'cat <<-EOF\n\tmerge-prs.sh 1\n\tEOF\necho ok'
expect allow 'for p in 1 2; do merge-prs.sh --check $p; done'
expect allow 'sudo merge-prs.sh --check 1'
expect allow 'bash -c "merge-prs.sh --check 1"'
expect allow 'echo "$(merge-prs.sh --check 1)"'
expect allow "gh pr view 1 --json body | grep '$gh_merge 1'"
expect allow '"$(git rev-parse --show-toplevel)"/.claude/skills/ship-batch/ship-batch.sh 1 2'
expect allow "notify-send 'done: merge-prs.sh 1'"
expect allow 'echo "$(echo "nested; merge-prs.sh 1")"'
expect allow "echo \$'c\\'d; merge-prs.sh 1'"
expect allow 'cat <<< "x; merge-prs.sh 1"'
expect allow $'gh pr create --body-file - <<\'EOF\'\nrun merge-prs.sh 1\nEOF'
expect allow $'cat > /tmp/notes <<\'EOF\'\nmerge-prs.sh 1\nEOF'

# Known gaps, deliberate evasion the tokenizer does not follow (see the hook's header): variable indirection, a script
# file, find -exec and the merge endpoint through gh api.
expect allow 'x=merge-prs.sh; $x 1'
expect allow 'bash /tmp/run-merge.sh'
expect allow 'find . -name merge-prs.sh -exec {} 1 \;'
expect allow 'gh api -X PUT repos/o/r/pulls/1/merge'

echo "$pass passed, $fail failed"
((fail == 0))
