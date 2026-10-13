#!/usr/bin/env bash
# Base selection of ship-batch against a temp repository: no GitHub, no merge.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../base.sh
source "$here/../base.sh"
pass=0 fail=0
check() { if eval "$2"; then
  echo "ok   $1"
  pass=$((pass + 1))
else
  echo "FAIL $1"
  fail=$((fail + 1))
fi; }
g() { git -c user.name=t -c user.email=t@t "$@"; }

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
repo=$root/repo
git init -q -b main "$repo"
g -C "$repo" commit -q --allow-empty -m one
first=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" worktree add -q "$root/wt" -b side
file=$(base_file "$repo")

echo "== fresh run records HEAD"
out=$(select_base "$repo" 2>"$root/err")
check "prints HEAD" "[[ $out == '$first' ]]"
check "records HEAD" "[[ \$(<'$file') == '$first' ]]"
check "says nothing" "[[ ! -s $root/err ]]"
check "a worktree sees the same file" "[[ \$(base_file '$root/wt') == '$file' ]]"

echo "== rerun after an unfinished run keeps the old base"
g -C "$repo" commit -q --allow-empty -m two
out=$(select_base "$repo" 2>"$root/err")
check "prints the recorded commit" "[[ $out == '$first' ]]"
check "keeps the file" "[[ \$(<'$file') == '$first' ]]"
check "announces the resume" "grep -q 'resuming from ${first:0:12}' $root/err"
check "recorded base is an ancestor of main" "base_is_ancestor '$repo' '$first' main"

echo "== finish removes the file"
finish_base "$repo"
check "file gone" "[[ ! -e '$file' ]]"
out=$(select_base "$repo" 2>/dev/null)
check "next run starts from the new HEAD" "[[ $out == '$(git -C "$repo" rev-parse HEAD)' ]]"
finish_base "$repo"

echo "== unusable bases"
g -C "$repo" switch -q --orphan other
g -C "$repo" commit -q --allow-empty -m unrelated
check "a commit main does not descend from is refused" "! base_is_ancestor '$repo' '$first' other"
check "a missing commit is refused" "! base_is_ancestor '$repo' 0000000000000000000000000000000000000001 main"

echo "== one batch at a time"
check "the first run takes the lock" "take_lock '$repo'"
check "a second run is refused" "! (take_lock '$repo')"
exec 9>&-
check "the lock is free once the first run exits" "(take_lock '$repo')"

echo "$pass passed, $fail failed"
((fail == 0))
