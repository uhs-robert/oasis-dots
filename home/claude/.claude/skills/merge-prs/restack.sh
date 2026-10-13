#!/usr/bin/env bash
# Rebase a stack of branches, bottom to top, onto their updated parents, each in its own worktree when it has one.
#
# Each child is moved with `git rebase --onto <parent> <old parent tip> <child>`, so commits the parent rewrote
# (amended, or rebased onto main) are left behind instead of replayed. The old parent tip is known exactly for the
# branches this run rebases. For the first branch, which was updated before the run, it is the merge-base of the
# child with the first branch's pre-update ref: origin/<first> while it still differs from the local branch (not
# pushed yet), otherwise <first>@{1}, the reflog entry before its last update.
set -euo pipefail

usage='usage: restack.sh [--check "<cmd>"] [--no-push] <branch>...   (bottom to top; the first is already updated)'

die() {
  echo "restack: $*" >&2
  exit 1
}

check_cmd=""
push=true
branches=()
while (($#)); do
  case $1 in
  --check)
    (($# > 1)) || die "$usage"
    check_cmd=$2
    shift 2
    ;;
  --no-push)
    push=false
    shift
    ;;
  -h | --help)
    echo "$usage"
    exit 0
    ;;
  -*) die "$usage" ;;
  *)
    branches+=("$1")
    shift
    ;;
  esac
done
((${#branches[@]} > 1)) || die "$usage"

git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"
for branch in "${branches[@]}"; do
  git show-ref -q --verify "refs/heads/$branch" || die "no local branch $branch"
done

worktree_of() {
  git worktree list --porcelain | awk -v line="branch refs/heads/$1" '/^worktree /{p=substr($0, 10)} $0 == line {print p; exit}'
}

tmp_root=""
remove_tmp() {
  [[ -n $tmp_root ]] || return 0
  git worktree remove --force "$tmp_root/wt" >/dev/null 2>&1 || true
  rm -rf "$tmp_root"
  git worktree prune
  tmp_root=""
}
trap remove_tmp EXIT

first=${branches[0]}
pre_update=""
if git show-ref -q --verify "refs/remotes/origin/$first" &&
  [[ $(git rev-parse "origin/$first") != $(git rev-parse "$first") ]]; then
  pre_update=origin/$first
elif git rev-parse -q --verify "$first@{1}" >/dev/null; then
  pre_update="$first@{1}"
else
  die "cannot tell where $first was before its update: origin/$first matches it and it has no reflog entry"
fi
echo "restack: $first was at $(git rev-parse --short "$pre_update") ($pre_update) before its update"

old_parent_tip=$(git rev-parse "$pre_update")
for ((i = 1; i < ${#branches[@]}; i++)); do
  parent=${branches[i - 1]}
  child=${branches[i]}
  old_child_tip=$(git rev-parse "$child")
  if git merge-base --is-ancestor "$parent" "$child"; then
    echo "$child: already on $parent"
    old_parent_tip=$old_child_tip
    continue
  fi
  old_base=$(git merge-base "$child" "$old_parent_tip") || die "$child shares no history with the old $parent"

  wt=$(worktree_of "$child")
  if [[ -n $wt ]]; then
    [[ -z $(git -C "$wt" status --porcelain --untracked-files=no) ]] || die "$child's worktree $wt has uncommitted changes"
  else
    tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/restack.XXXXXX")
    git worktree add -q "$tmp_root/wt" "$child" || die "cannot create a worktree for $child"
    wt=$tmp_root/wt
  fi
  if ! git -C "$wt" rebase -q --onto "$parent" "$old_base" >/dev/null 2>&1; then
    files=$(git -C "$wt" diff --name-only --diff-filter=U | paste -sd ' ')
    # A temporary worktree is kept, since the half-done rebase lives in it.
    tmp_root=""
    rerun=("$0")
    [[ -z $check_cmd ]] || rerun+=(--check "$(printf %q "$check_cmd")")
    $push || rerun+=(--no-push)
    rerun+=("${branches[@]:i}")
    die "$child conflicts rebasing onto $parent in ${files:-(no unmerged files listed)}. Finish it by hand, then restack the rest:
  cd $wt  # resolve the files, then:
  git add ${files:-<files>} && git rebase --continue
  ${rerun[*]}
or give up with: git -C $wt rebase --abort"
  fi
  if markers=$(git -C "$wt" grep -n '^<<<<<<< ' HEAD); then
    echo "$markers" >&2
    die "$child has conflict markers committed after the rebase (above); fix them in $wt"
  fi
  echo "$child: rebased onto $parent"

  if [[ -n $check_cmd ]]; then
    log=$(git -C "$wt" rev-parse --absolute-git-dir)/restack-check.log
    if ! (cd "$wt" && bash -c "$check_cmd") >"$log" 2>&1; then
      tail -n 25 "$log" >&2
      die "check failed on $child in $wt (last 25 lines above; full log: $log); not pushed"
    fi
    echo "$child: check passed"
  fi
  if $push; then
    git -C "$wt" push -q --force-with-lease origin "refs/heads/$child:refs/heads/$child" || die "cannot push $child"
    echo "$child: pushed"
  fi
  remove_tmp
  old_parent_tip=$old_child_tip
done
