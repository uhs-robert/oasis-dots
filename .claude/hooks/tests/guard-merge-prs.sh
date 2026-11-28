#!/usr/bin/env bash
# shellcheck disable=SC2016 # single quotes hold literal $ and backticks the hook must see
# Feeds commands to guard-merge-prs.sh with real throwaway repos: a project repo with a worktree and an unrelated repo.
set -uo pipefail
hook=$(cd "$(dirname "$0")" && pwd)/../guard-merge-prs.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0

git_quiet() { git -c user.name=t -c user.email=t@t "$@" >/dev/null 2>&1; }
project=$tmp/project other=$tmp/other worktree=$tmp/project-wt
for r in "$project" "$other"; do
  mkdir -p "$r"
  git_quiet -C "$r" init -b main
  git_quiet -C "$r" commit --allow-empty -m init
done
git_quiet -C "$project" worktree add -b side "$worktree"
mkdir -p "$project/sub" "$tmp/plain"
script=~/.claude/skills/merge-prs/merge-prs.sh

# expect <block|allow> <session cwd> <command>
expect() {
  local err got=allow
  err=$(jq -n --arg c "$3" --arg d "$2" '{cwd: $d, tool_input: {command: $c}}' | CLAUDE_PROJECT_DIR=$project "$hook" 2>&1 >/dev/null)
  (($? == 2)) && got=block
  if [[ $got == "$1" ]] && [[ $got == allow || $err == *ship-batch* ]]; then
    echo "ok   $1: ${3//$'\n'/\\n}"
    pass=$((pass + 1))
  else
    echo "FAIL $1: ${3//$'\n'/\\n} (got $got) $err"
    fail=$((fail + 1))
  fi
}

# Session in this repo: any merge is blocked, whatever flags come before the number.
for dir in "$project" "$project/sub" "$worktree"; do
  expect block "$dir" 'merge-prs.sh 12'
  expect block "$dir" "$script 12"
  expect block "$dir" 'merge-prs.sh --keep-branch 5'
  expect block "$dir" 'merge-prs.sh --method squash 5'
  expect block "$dir" 'merge-prs.sh --method=merge --skip-review-gate 5'
done
expect block "$other" "cd $worktree && merge-prs.sh 5"
expect block "$other" "cd $project/sub && $script 5"
expect block "$other" "cd $worktree; merge-prs.sh --keep-branch 5"
expect block "$project" "bash -c 'merge-prs.sh 5'"
expect block "$project" 'bash -c "cd . && merge-prs.sh 5"'
expect block "$project" 'env X=1 merge-prs.sh 5'
expect block "$project" 'X=1 timeout 60 merge-prs.sh 5'
expect block "$project" 'echo $(merge-prs.sh 5)'
expect block "$project" 'echo `merge-prs.sh 5`'
expect block "$project" "bash $script 5"
expect block "$project" $'echo hi\nmerge-prs.sh 5'
expect block "$project" 'merge-prs.sh --check 1 && merge-prs.sh 5'
expect block "$project" "(cd $other && merge-prs.sh 1); merge-prs.sh 2"
expect block "$project" 'cat x | merge-prs.sh 5'
expect block "$project" 'm=merge-prs.sh; ./$m 5'

# A merge in another repo is allowed, from a session in this repo or elsewhere.
expect allow "$project" "cd $other && $script 353"
expect allow "$project" "cd $other && merge-prs.sh --keep-branch 353"
expect allow "$project" "cd '$other' && merge-prs.sh 353"
expect allow "$worktree" "cd $other && merge-prs.sh 353"
expect allow "$other" 'merge-prs.sh 12'
expect allow "$other" "$script 12"
expect allow "$tmp/plain" 'merge-prs.sh 12'
expect allow "$project" "(cd $other && merge-prs.sh 1)"
expect allow "$project" "bash -c 'cd $other && merge-prs.sh 1'"
expect allow "$other" "cd $worktree && cd $other && merge-prs.sh 1"

# --check is read only, anywhere.
expect allow "$project" 'merge-prs.sh --check 12'
expect allow "$worktree" "$script --check --wait-review 12"
expect allow "$other" 'merge-prs.sh --check 12'

# Commands that only mention the script are not calls.
expect allow "$project" 'grep -n merge-prs.sh AGENTS.md'
expect allow "$project" 'git diff -- home/claude/.claude/skills/merge-prs/merge-prs.sh'
expect allow "$project" 'echo merge-prs.sh 5'
expect allow "$project" 'ls'

# A target the hook cannot resolve is blocked.
expect block "$other" "cd $tmp/missing && merge-prs.sh 5"
expect block "$other" 'cd $SOMEWHERE && merge-prs.sh 5'
expect block "$other" 'cd - && merge-prs.sh 5'
expect block "$other" 'cd "$(mktemp -d)" && merge-prs.sh 5'
expect block "$tmp/missing" 'merge-prs.sh 5'

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
