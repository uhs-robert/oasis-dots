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

echo "== packages a merge left out of date"
stow_repo=$root/stow-repo
fake_home=$root/home
git init -q -b main "$stow_repo"
mkdir -p "$stow_repo/home/tools/.local/bin" "$stow_repo/home/folded/.config/folded" "$stow_repo/home/absent/.local/bin" "$fake_home/.local/bin" "$fake_home/.config"
echo a >"$stow_repo/home/tools/.local/bin/old"
echo a >"$stow_repo/home/folded/.config/folded/old"
echo a >"$stow_repo/home/absent/.local/bin/old"
g -C "$stow_repo" add -A
g -C "$stow_repo" commit -q -m base
stow_before=$(git -C "$stow_repo" rev-parse HEAD)
# tools is stowed unfolded (a link per file), folded as a whole folder, absent not at all.
ln -s "$stow_repo/home/tools/.local/bin/old" "$fake_home/.local/bin/old"
ln -s "$stow_repo/home/folded/.config/folded" "$fake_home/.config/folded"
echo b >"$stow_repo/home/tools/.local/bin/new"
echo b >"$stow_repo/home/folded/.config/folded/new"
echo b >"$stow_repo/home/absent/.local/bin/new"
g -C "$stow_repo" add -A
g -C "$stow_repo" commit -q -m add
stow_added=$(git -C "$stow_repo" rev-parse HEAD)
echo c >>"$stow_repo/home/tools/.local/bin/old"
g -C "$stow_repo" commit -q -am edit
stow_edited=$(git -C "$stow_repo" rev-parse HEAD)
restow() { HOME=$fake_home packages_to_restow "$stow_repo" "$@" | paste -sd,; }
check "an added file restows each installed package, folded or not" "[[ \$(restow '$stow_before' '$stow_added') == folded,tools ]]"
check "a package that is not stowed here is left alone" "[[ \$(restow '$stow_before' '$stow_added') != *absent* ]]"
check "an edit alone needs no restow" "[[ -z \$(restow '$stow_added' '$stow_edited') ]]"
g -C "$stow_repo" rm -q "$stow_repo/home/tools/.local/bin/new"
g -C "$stow_repo" commit -q -m remove
check "a removed file restows its package" "[[ \$(restow '$stow_edited' HEAD) == tools ]]"
mkdir -p "$stow_repo/home/units/.config/units"
echo a >"$stow_repo/home/units/.config/units/only"
g -C "$stow_repo" add -A
g -C "$stow_repo" commit -q -m units
stow_units=$(git -C "$stow_repo" rev-parse HEAD)
mkdir -p "$fake_home/.config/units"
ln -s "$stow_repo/home/units/.config/units/only" "$fake_home/.config/units/only"
g -C "$stow_repo" mv "$stow_repo/home/units/.config/units/only" "$stow_repo/home/units/.config/units/renamed"
g -C "$stow_repo" commit -q -m rename
check "renaming a package's only linked file restows it, though its link now dangles" "[[ \$(restow '$stow_units' HEAD) == units ]]"

echo "== a branch with no local worktree, and recording its pass"
origin=$root/origin.git
work=$root/work
git init -q --bare -b main "$origin"
git clone -q "$origin" "$work" 2>/dev/null
mkdir -p "$work/lib"
cp "$here/../../../../lib/check-passed.sh" "$work/lib/"
# shellcheck disable=SC2016 # the stub expands its own variable
printf '#!/bin/sh\nexit "${STUB_CHECK_STATUS:-0}"\n' >"$work/lib/check.sh"
chmod +x "$work/lib/check.sh"
g -C "$work" add -A
g -C "$work" commit -q -m base
git -C "$work" push -q origin main 2>/dev/null
git -C "$work" fetch -q origin
base_tree=$(git -C "$work" rev-parse 'HEAD^{tree}')
g -C "$work" switch -q -c pr-branch
echo change >"$work/file"
g -C "$work" add -A
g -C "$work" commit -q -m change
branch_tree=$(git -C "$work" rev-parse 'HEAD^{tree}')
# What a forge serves for a PR whose branch was pushed from elsewhere.
git -C "$work" push -q origin pr-branch:refs/pull/7/head 2>/dev/null
passed_file=$(git -C "$work" rev-parse --path-format=absolute --git-common-dir)/claude-check-passed-trees
check "the branch tree has not passed yet" "! (cd '$work' && lib/check-passed.sh passed-somewhere HEAD)"
check "a pass on an unrecorded base is not recorded" "(cd '$work' && check_branch_here) && ! grep -sq '$branch_tree' '$passed_file'"
printf '%s no-repos\n' "$base_tree" >"$passed_file"
check "a pass on a recorded base is recorded" "(cd '$work' && check_branch_here) && grep -qx '$branch_tree no-repos' '$passed_file'"
check "a no-repos pass does not stand in for a checkout with repos/" "(mkdir -p '$work/repos/x' && cd '$work' && ! lib/check-passed.sh is-passed '$branch_tree' && lib/check-passed.sh passed-somewhere '$branch_tree'); rm -rf '$work/repos'"
check "a failing check fails the branch" "! (cd '$work' && STUB_CHECK_STATUS=1 check_branch_here)"
add_temp_worktree "$work" pull/7/head
check "the temporary worktree is the PR head" "[[ \$(git -C '$temp_worktree' rev-parse HEAD) == \$(git -C '$work' rev-parse pr-branch) ]]"
tmp_path=$temp_worktree
remove_temp_worktree
check "removing it deletes the directory and the registration" "[[ ! -e '$tmp_path' ]] && ! git -C '$work' worktree list | grep -q '$tmp_path'"
check "a second removal is harmless" "remove_temp_worktree"
check "an unknown ref fails without leaving a worktree" "! add_temp_worktree '$work' pull/99/head && [[ -z \$temp_worktree ]]"
(
  add_temp_worktree "$work" pull/7/head
  echo "$temp_worktree" >"$root/exit-path"
  trap remove_temp_worktree EXIT
  exit 1
)
check "the EXIT trap removes it on a failing exit" "[[ ! -e \$(<'$root/exit-path') ]]"

echo "$pass passed, $fail failed"
((fail == 0))
