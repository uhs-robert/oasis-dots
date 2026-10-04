#!/usr/bin/env bash
# Merge PRs in order, carrying stacked PRs over to each base, then clean up local worktrees and branches.
set -euo pipefail

usage="usage: merge-prs.sh [--method rebase|squash|merge] [--keep-branch] <pr>..."

die() {
  echo "merge-prs: $*" >&2
  exit 1
}

method=""
keep_branch=false
prs=()
while (($#)); do
  case $1 in
  --method)
    (($# > 1)) || die "$usage"
    method=$2
    shift 2
    ;;
  --method=*)
    method=${1#*=}
    shift
    ;;
  --keep-branch)
    keep_branch=true
    shift
    ;;
  -h | --help)
    echo "$usage"
    exit 0
    ;;
  -*) die "$usage" ;;
  *)
    prs+=("$1")
    shift
    ;;
  esac
done
((${#prs[@]})) || die "$usage"
[[ -z $method || $method =~ ^(rebase|squash|merge)$ ]] || die "$usage"

worktrees=$(git worktree list --porcelain) || die "not inside a git repository"
main_dir=$(awk '/^worktree /{print substr($0, 10); exit}' <<<"$worktrees")
cd "$main_dir"

repo_info=$(gh repo view --json nameWithOwner,defaultBranchRef,rebaseMergeAllowed,squashMergeAllowed,mergeCommitAllowed \
  --jq '[.nameWithOwner, .defaultBranchRef.name, .rebaseMergeAllowed, .squashMergeAllowed, .mergeCommitAllowed] | @tsv') ||
  die "cannot read the repository settings"
IFS=$'\t' read -r slug default rebase_ok squash_ok merge_ok <<<"$repo_info"
declare -A allowed=([rebase]=$rebase_ok [squash]=$squash_ok [merge]=$merge_ok)
if [[ -n $method ]]; then
  [[ ${allowed[$method]} == true ]] || die "$method merges are not allowed in $slug"
else
  for candidate in rebase squash merge; do
    if [[ ${allowed[$candidate]} == true ]]; then
      method=$candidate
      break
    fi
  done
  [[ -n $method ]] || die "$slug allows no merge method"
fi

tmp_root=""
remove_tmp() {
  [[ -n $tmp_root ]] || return 0
  git worktree remove --force "$tmp_root/wt" >/dev/null 2>&1 || true
  rm -rf "$tmp_root"
  git worktree prune
  tmp_root=""
}
trap remove_tmp EXIT

fetch() {
  git fetch -q --prune origin || die "git fetch origin failed"
}

remote_sha() {
  git rev-parse --verify -q "refs/remotes/origin/$1" || die "origin/$1 not found"
}

clean_local() {
  local pr=$1 head=$2 head_oid=$3 wt
  git worktree prune
  if git show-ref --verify -q "refs/heads/$head" && ! git merge-base --is-ancestor "refs/heads/$head" "$head_oid"; then
    echo "kept $head: local commits not in PR #$pr"
    return
  fi
  wt=$(git worktree list --porcelain | awk -v line="branch refs/heads/$head" '/^worktree /{p=substr($0, 10)} $0 == line {print p; exit}')
  if [[ $wt == "$main_dir" ]]; then
    echo "kept branch $head: checked out in the main checkout $wt"
    return
  fi
  if [[ -n $wt ]]; then
    if [[ -n $(git -C "$wt" status --porcelain) ]]; then
      echo "skipped dirty worktree $wt"
      return
    fi
    git worktree remove "$wt" || die "cannot remove worktree $wt"
    echo "removed worktree $wt"
  fi
  if git show-ref --verify -q "refs/heads/$head"; then
    git branch -q -D "$head"
    echo "deleted branch $head"
  fi
  git worktree prune
}

rebase_child() {
  local child=$1 child_head=$2 old_child=$3 base=$4 old_parent=$5
  tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/merge-prs.XXXXXX")
  git worktree add -q --detach "$tmp_root/wt" "$old_child" || die "cannot create a worktree for $child_head"
  if ! git -C "$tmp_root/wt" rebase -q --onto "origin/$base" "$old_parent" >/dev/null 2>&1; then
    git -C "$tmp_root/wt" rebase --abort || true
    remove_tmp
    die "$child ($child_head) conflicts rebasing onto $base; rebase it by hand, then rerun for the remaining PRs:
  git fetch origin && git rebase --onto origin/$base $old_parent origin/$child_head
  git push --force-with-lease=$child_head:$old_child origin HEAD:$child_head"
  fi
  git -C "$tmp_root/wt" push -q --force-with-lease="$child_head:$old_child" origin "HEAD:refs/heads/$child_head" ||
    die "cannot push the rebased $child_head"
  remove_tmp
  echo "$child rebased onto $base"
  if git show-ref --verify -q "refs/heads/$child_head"; then
    echo "local branch $child_head is now behind the rebased origin/$child_head"
  fi
}

merge_pr() {
  local pr=$1 info head base state cross head_oid children_info="" number child_head child_sha
  local children=() child_heads=() child_shas=()
  info=$(gh pr view "$pr" --json headRefName,headRefOid,baseRefName,state,isCrossRepository \
    --jq '[.headRefName, .headRefOid, .baseRefName, .state, .isCrossRepository] | @tsv') || die "cannot read PR $pr"
  IFS=$'\t' read -r head head_oid base state cross <<<"$info"
  [[ $state == OPEN ]] || die "PR $pr is $state"
  if [[ $cross != true ]]; then
    children_info=$(gh pr list --limit 1000 --base "$head" --state open --json number,headRefName \
      --jq '.[] | "\(.number)\t\(.headRefName)"') || die "cannot list PRs based on $head"
  fi

  fetch
  if [[ $cross != true ]]; then
    git cat-file -e "$head_oid^{commit}" 2>/dev/null || die "PR $pr head $head_oid is not on origin/$head"
  fi
  while IFS=$'\t' read -r number child_head; do
    [[ -n $number ]] || continue
    children+=("$number")
    child_heads+=("$child_head")
    child_sha=$(remote_sha "$child_head")
    child_shas+=("$child_sha")
  done <<<"$children_info"

  for number in "${children[@]}"; do
    gh pr edit "$number" --base "$base" >/dev/null || die "cannot retarget $number to $base"
    echo "$number retargeted to $base"
  done

  local merge_args=("--$method" --repo "$slug" --match-head-commit "$head_oid")
  $keep_branch || merge_args+=(--delete-branch)
  gh pr merge "$pr" "${merge_args[@]}" >/dev/null || die "merge of $pr failed"
  state=$(gh pr view "$pr" --json state --jq .state) || die "cannot read the state of $pr"
  [[ $state == MERGED ]] || die "$pr is $state after the merge, stopping"
  echo "$pr merged ($method)"

  fetch
  if [[ $cross == true ]]; then
    echo "PR #$pr is from a fork; skipped local cleanup"
  elif ! $keep_branch; then
    clean_local "$pr" "$head" "$head_oid"
  fi
  [[ $method != merge ]] || return 0
  for i in "${!children[@]}"; do
    rebase_child "${children[i]}" "${child_heads[i]}" "${child_shas[i]}" "$base" "$head_oid"
  done
}

for pr in "${prs[@]}"; do
  merge_pr "$pr"
done

branch=$(git -C "$main_dir" branch --show-current)
if [[ $branch != "$default" ]]; then
  echo "skipped pull: $main_dir is on ${branch:-a detached HEAD}, not $default"
elif [[ -n $(git -C "$main_dir" status --porcelain --untracked-files=no) ]]; then
  echo "skipped pull: $main_dir has uncommitted changes"
else
  git -C "$main_dir" pull -q --ff-only || die "git pull --ff-only failed in $main_dir"
  echo "pulled $main_dir"
fi
