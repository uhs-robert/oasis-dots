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
mkdir -p "$repo/lib"
cp "$repo_lib/check-passed.sh" "$repo/lib/"
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

# expect <allow|deny> <description>
expect() {
  local reason
  rm -f "$root/check-ran"
  reason=$(jq -n --arg c 'gh pr create --fill' --arg d "$repo" '{tool_input: {command: $c}, cwd: $d}' | "$hook" |
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
(cd "$repo" && lib/check-passed.sh record-changed "$base")
expect allow "HEAD's tree passed --changed against the merge-base"
echo dirty >>"$repo/file"
expect allow "uncommitted edits do not change what the PR sends"
g checkout -q -- file
: >"$trees_file"
(cd "$repo" && lib/check-passed.sh record-changed HEAD)
expect deny "a pass against another base"
printf '%s no-repos\n' "$(g rev-parse 'HEAD^{tree}')" >"$trees_file"
expect allow "a full pass of HEAD's tree, made anywhere"
g commit -q --allow-empty -m empty
expect allow "a new commit with the same tree"
echo more >>"$repo/file"
g commit -qam more
expect deny "a new tree after the pass"
if [[ -z $(jq -n --arg c 'gh pr view 1' --arg d "$repo" '{tool_input: {command: $c}, cwd: $d}' | "$hook") ]]; then
  echo "ok   other gh commands pass through"
  pass=$((pass + 1))
else
  echo "FAIL other gh commands pass through"
  fail=$((fail + 1))
fi

echo "$pass passed, $fail failed"
((fail == 0))
