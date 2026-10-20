#!/usr/bin/env bash
# Runs report-failed-main-check.sh against a temp repository with each result file the background check can leave.
set -uo pipefail
hook=$(cd "$(dirname "$0")" && pwd)/../report-failed-main-check.sh
pass=0 fail=0
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
git init -q -b main "$root/repo"
git -C "$root/repo" worktree add -q "$root/wt" -b side 2>/dev/null || { git -C "$root/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m x && git -C "$root/repo" worktree add -q "$root/wt" -b side; }
result=$root/repo/.git/ship-batch-main-check.result

# expect <silent|notice> <description> <result file content, or - for no file> [project dir]
expect() {
  local out
  rm -f "$result"
  [[ $3 == - ]] || printf '%s\n' "$3" >"$result"
  out=$(CLAUDE_PROJECT_DIR=${4:-$root/repo} "$hook")
  if [[ $1 == silent && -z $out ]] || [[ $1 == notice && $out == *"FAILED at abcdef012345; log /x/log"* && $(wc -l <<<"$out") == 1 ]]; then
    echo "ok   $2"
    pass=$((pass + 1))
  else
    echo "FAIL $2 (got: $out)"
    fail=$((fail + 1))
  fi
}

expect silent "no check ever ran" -
expect silent "a passed check" "pass abcdef0123456789 1700000000"
expect notice "a failed check names the commit and the log" "fail abcdef0123456789 1700000000 /x/log"
expect notice "a worktree session reads the shared file" "fail abcdef0123456789 1700000000 /x/log" "$root/wt"
expect silent "an empty result file" ""
outside=$(CLAUDE_PROJECT_DIR=$root/none "$hook")
if [[ $? == 0 && -z $outside ]]; then
  echo "ok   outside a repository it is silent"
  pass=$((pass + 1))
else
  echo "FAIL outside a repository"
  fail=$((fail + 1))
fi

echo "$pass passed, $fail failed"
((fail == 0))
