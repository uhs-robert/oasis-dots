#!/usr/bin/env bash
# Feeds `gh pr create` to check-before-pr.sh against a throwaway repo whose lib/check.sh only notes that it ran: the hook
# must answer from the recorded passes alone.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
hook=$here/../check-before-pr.sh
repo_lib=$here/../../../lib
pass=0 fail=0
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }

repo=$root/repo
git init -q --bare -b main "$root/origin.git"
git clone -q "$root/origin.git" "$repo" 2>/dev/null
mkdir -p "$repo/lib/check"
cp "$repo_lib/check/passed.sh" "$repo_lib/check/passed.py" "$repo/lib/check/"
printf '#!/bin/sh\ntouch "%s/check-ran"\n' "$root" >"$repo/lib/check.sh"
chmod +x "$repo/lib/check.sh"
g add -A
g commit -qm base
g push -q origin main 2>/dev/null
g switch -q -c topic
echo change >"$repo/file"
g add -A
g commit -qm change
base=$(g rev-parse origin/main)
trees_file=$(g rev-parse --path-format=absolute --git-common-dir)/claude-check-passed-trees

# expect <allow|deny> <description> [command] [cwd]
expect() {
  local reason
  rm -f "$root/check-ran"
  reason=$(jq -n --arg c "${3:-gh pr create --fill}" --arg d "${4:-$repo}" '{tool_input: {command: $c}, cwd: $d}' | "$hook" |
    jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
  if [[ -e $root/check-ran ]]; then
    echo "FAIL $2: the hook ran lib/check.sh"
    fail=$((fail + 1))
  elif [[ $1 == deny && $reason == *"lib/check.sh --changed $base"* ]] || [[ $1 == allow && -z $reason ]]; then
    echo "ok   $1: $2"
    pass=$((pass + 1))
  else
    echo "FAIL $1: $2 (got: ${reason:-allowed})"
    fail=$((fail + 1))
  fi
}

expect deny "no recorded pass"
(cd "$repo" && lib/check/passed.sh record-changed "$base")
expect allow "HEAD's tree passed --changed against the merge-base"
echo dirty >>"$repo/file"
expect allow "uncommitted edits do not change what the PR sends"
g checkout -q -- file
: >"$trees_file"
(cd "$repo" && lib/check/passed.sh record-changed HEAD)
expect deny "a pass against another base"
printf '%s no-repos\n' "$(g rev-parse 'HEAD^{tree}')" >"$trees_file"
expect allow "a full pass of HEAD's tree, made anywhere"
g commit -q --allow-empty -m empty
expect allow "a new commit with the same tree"
echo more >>"$repo/file"
g commit -qam more
expect deny "a new tree after the pass"
# The agent's cwd stays in the main checkout while its PR comes from a worktree named in a leading `cd`.
for wt in wt-pass wt-fail; do
  g worktree add -q -b "$wt" "$root/$wt" "$base"
  echo "$wt" >"$root/$wt/file"
  git -C "$root/$wt" -c user.name=t -c user.email=t@t add -A
  git -C "$root/$wt" -c user.name=t -c user.email=t@t commit -qm change
done
(cd "$root/wt-pass" && lib/check/passed.sh record-changed "$base")
create='gh pr create --fill'
expect allow "cd into a worktree whose tree passed, while the cwd's did not" "cd $root/wt-pass && $create"
expect allow "a ; after the cd" "cd $root/wt-pass; $create"
expect deny "cd into a worktree with no pass" "cd $root/wt-fail && $create"
expect allow "a single-quoted path" "cd '$root/wt-pass' && $create"
expect allow "a double-quoted path" "cd \"$root/wt-pass\" && $create"
expect allow "a path relative to the cwd" "cd ../wt-pass && $create"
expect deny "a relative path to a worktree with no pass, from a passing cwd" "cd ../wt-fail && $create" "$root/wt-pass"
expect deny "no cd: the cwd's own tree decides" "$create" "$root/wt-fail"
expect deny "a cd behind an earlier command, into a worktree with no pass, from a passing cwd" "tail -1 file; cd $root/wt-fail && git status; $create" "$root/wt-pass"
expect allow "a cd behind an earlier command, into a worktree that passed" "tail -1 file; cd $root/wt-pass && git status; $create" "$root/wt-fail"
expect allow "cds in turn, the second relative to the first" "cd $root && cd wt-pass && $create" "$root/wt-fail"
expect deny "a cd after || runs only on a failure, so it does not count" "true || cd $root/wt-pass; $create" "$root/wt-fail"
expect deny "a cd after the PR command does not count" "cd $root/wt-fail && $create; cd $root/wt-pass && true" "$root/wt-pass"

# The extra sentence is for a check chained into the blocked command, and only then.
chain_hint='cannot count'
deny_reason() { jq -n --arg c "$1" --arg d "$root/wt-fail" '{tool_input: {command: $c}, cwd: $d}' | "$hook" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'; }
for chained in "lib/check.sh --changed $base; $create" "just check && $create" "cd $root/wt-fail && lib/check.sh --changed $base; $create" "./lib/check.sh; $create" "/abs/lib/check.sh --changed $base && $create"; do
  if [[ $(deny_reason "$chained") == *"$chain_hint"* ]]; then
    echo "ok   deny: a chained check gets the judged-before-it-runs hint ($chained)"
    pass=$((pass + 1))
  else
    echo "FAIL a chained check gets the judged-before-it-runs hint ($chained)"
    fail=$((fail + 1))
  fi
done
for unchained in "$create" "gh pr create --body 'Tested with lib/check.sh'" "just checkfoo && $create"; do
  plain=$(deny_reason "$unchained")
  if [[ -n $plain && $plain != *"$chain_hint"* ]]; then
    echo "ok   deny: no chained-check hint ($unchained)"
    pass=$((pass + 1))
  else
    echo "FAIL no chained-check hint (got: ${plain:-allowed}) ($unchained)"
    fail=$((fail + 1))
  fi
done

if [[ -z $(jq -n --arg c 'gh pr view 1' --arg d "$repo" '{tool_input: {command: $c}, cwd: $d}' | "$hook") ]]; then
  echo "ok   other gh commands pass through"
  pass=$((pass + 1))
else
  echo "FAIL other gh commands pass through"
  fail=$((fail + 1))
fi

echo "$pass passed, $fail failed"
((fail == 0))
