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
rebased_oid=""
wait_s=${MERGE_PRS_WAIT:-600}
poll_s=${MERGE_PRS_POLL:-10}
known_heads=()
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

list_children() {
  gh pr list --limit 1000 --base "$1" --state open --json number,headRefName,headRefOid,isCrossRepository \
    --jq '.[] | [.number, .headRefName, .headRefOid, .isCrossRepository] | @tsv' || die "cannot list PRs based on $1"
}

# A local branch is safe to drop when all its commits came from PR heads seen before this run rewrote them.
clean_local() {
  local pr=$1 head=$2 head_oid=$3 wt
  git worktree prune
  if git show-ref --verify -q "refs/heads/$head" &&
    [[ -n $(git rev-list -n 1 "refs/heads/$head" --not "$head_oid" "${known_heads[@]}") ]]; then
    echo "kept $head: local commits not in PR #$pr"
    return
  fi
  wt=$(git worktree list --porcelain | awk -v line="branch refs/heads/$head" '/^worktree /{p=substr($0, 10)} $0 == line {print p; exit}')
  if [[ $wt == "$main_dir" ]]; then
    if [[ -n $(git -C "$main_dir" status --porcelain --untracked-files=no) ]]; then
      echo "kept branch $head: checked out in the main checkout $wt, which has uncommitted changes"
      return
    fi
    # The PR is already merged here, so a failed switch (say, the default branch held by another worktree)
    # must not abort the PRs still queued in this run.
    local switch_err
    if ! switch_err=$(git -C "$main_dir" switch -q "$default" 2>&1); then
      echo "kept branch $head: the main checkout $wt could not switch to $default: ${switch_err##*$'\n'}"
      return
    fi
    echo "switched $main_dir to $default"
    wt=""
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
  local child=$1 child_head=$2 old_child=$3 onto=$4 label=$5 upstream=$6 grandchildren new_child line
  local number gc_head gc_oid gc_cross
  git cat-file -e "$old_child^{commit}" 2>/dev/null || die "$child head $old_child is not on origin/$child_head"
  grandchildren=$(list_children "$child_head") || exit 1
  tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/merge-prs.XXXXXX")
  known_heads+=("$old_child")
  git worktree add -q --detach "$tmp_root/wt" "$old_child" || die "cannot create a worktree for $child_head"
  if ! git -C "$tmp_root/wt" rebase -q --onto "$onto" "$upstream" >/dev/null 2>&1; then
    git -C "$tmp_root/wt" rebase --abort || true
    remove_tmp
    die "$child ($child_head) conflicts rebasing onto $label; rebase it and any PRs stacked on it by hand, then rerun for the remaining PRs:
  git fetch origin && git rebase --onto $onto $upstream $old_child
  git push --force-with-lease=$child_head:$old_child origin HEAD:$child_head"
  fi
  new_child=$(git -C "$tmp_root/wt" rev-parse HEAD)
  git -C "$tmp_root/wt" push -q --force-with-lease="$child_head:$old_child" origin "HEAD:refs/heads/$child_head" ||
    die "cannot push the rebased $child_head"
  remove_tmp
  echo "$child rebased onto $label"
  if git show-ref --verify -q "refs/heads/$child_head"; then
    echo "local branch $child_head is now behind the rebased origin/$child_head"
  fi

  local -a lines=()
  [[ -z $grandchildren ]] || mapfile -t lines <<<"$grandchildren"
  for line in "${lines[@]}"; do
    IFS=$'\t' read -r number gc_head gc_oid gc_cross <<<"$line"
    if [[ $gc_cross == true ]]; then
      echo "child #$number is from a fork; rebase it onto $child_head by hand"
    else
      rebase_child "$number" "$gc_head" "$gc_oid" "$new_child" "$child_head" "$old_child"
    fi
  done
}

# GitHub recomputes mergeability lazily after a push; merging before it settles fails with "Head branch was modified".
await_mergeable() {
  local pr=$1 oid=$2 info="" deadline=$((SECONDS + 60))
  while :; do
    info=$(gh pr view "$pr" --json headRefOid,mergeable --jq '[.headRefOid, .mergeable] | @tsv') ||
      die "cannot read the mergeability of $pr"
    [[ $info == "$oid"$'\t'@(MERGEABLE|CONFLICTING) ]] && break
    ((SECONDS < deadline)) || break
    sleep 2
  done
  printf '%s\n' "${info#*$'\t'}"
}

# A PR stacked on a parent that was rebase- or squash-merged outside this run still carries the parent's old commits,
# so GitHub reports it as conflicting. Rebasing onto the base drops them, because git skips commits whose changes are
# already there; a rebase that drops nothing means a real conflict, which stays with the owner.
rebase_stale_head() {
  local pr=$1 head=$2 old=$3 base=$4 before after
  tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/merge-prs.XXXXXX")
  git worktree add -q --detach "$tmp_root/wt" "$old" || die "cannot create a worktree for $head"
  before=$(git rev-list --count "origin/$base..$old")
  if ! git -C "$tmp_root/wt" rebase -q "origin/$base" >/dev/null 2>&1; then
    git -C "$tmp_root/wt" rebase --abort || true
    remove_tmp
    die "#$pr conflicts with $base; rebase $head onto origin/$base by hand, then rerun for the remaining PRs"
  fi
  after=$(git -C "$tmp_root/wt" rev-list --count "origin/$base..HEAD")
  if ((after >= before)); then
    remove_tmp
    die "#$pr conflicts with $base and carries no commits already merged there; resolve it by hand, then rerun for the remaining PRs"
  fi
  rebased_oid=$(git -C "$tmp_root/wt" rev-parse HEAD)
  git -C "$tmp_root/wt" push -q --force-with-lease="$head:$old" origin "HEAD:refs/heads/$head" ||
    die "cannot push the rebased $head"
  remove_tmp
  echo "#$pr rebased onto $base, dropping $((before - after)) commit(s) already merged there"
}

pr_state() {
  gh pr view "$1" --json state --jq .state || die "cannot read the state of $1"
}

not_merged() {
  local pr=$1 state=$2 base=$3 head_oid=$4 line number child_head child_oid child_cross
  local msg="#$pr is $state, not MERGED, after waiting ${wait_s}s; stopping"
  shift 4
  (($#)) && msg+=". Its children were retargeted to $base and still carry its commits; once it merges, rebase them by hand:"
  for line in "$@"; do
    IFS=$'\t' read -r number child_head child_oid child_cross <<<"$line"
    [[ $child_cross != true ]] || continue
    msg+=$'\n'"$number ($child_head):"
    msg+=$'\n'"  git fetch origin && git rebase --onto origin/$base $head_oid $child_oid"
    msg+=$'\n'"  git push --force-with-lease=$child_head:$child_oid origin HEAD:$child_head"
  done
  die "$msg"
}

merge_pr() {
  local pr=$1 info head base state cross head_oid children_info="" line number child_head child_oid child_cross
  local -a lines=()
  info=$(gh pr view "$pr" --json headRefName,headRefOid,baseRefName,state,isCrossRepository \
    --jq '[.headRefName, .headRefOid, .baseRefName, .state, .isCrossRepository] | @tsv') || die "cannot read PR $pr"
  IFS=$'\t' read -r head head_oid base state cross <<<"$info"
  [[ $state == OPEN ]] || die "PR $pr is $state"
  if [[ $cross != true ]]; then
    children_info=$(list_children "$head") || exit 1
  fi
  [[ -z $children_info ]] || mapfile -t lines <<<"$children_info"

  fetch
  known_heads+=("$head_oid")
  if [[ $cross != true ]]; then
    git cat-file -e "$head_oid^{commit}" 2>/dev/null || die "PR $pr head $head_oid is not on origin/$head"
  fi

  for line in "${lines[@]}"; do
    IFS=$'\t' read -r number _ <<<"$line"
    gh pr edit "$number" --base "$base" >/dev/null || die "cannot retarget $number to $base"
    echo "$number retargeted to $base"
  done

  if [[ $(await_mergeable "$pr" "$head_oid") == CONFLICTING && $cross != true ]]; then
    rebase_stale_head "$pr" "$head" "$head_oid" "$base"
    head_oid=$rebased_oid
    known_heads+=("$head_oid")
    await_mergeable "$pr" "$head_oid" >/dev/null
  fi

  local merge_args=("--$method" --repo "$slug" --match-head-commit "$head_oid")
  $keep_branch || merge_args+=(--delete-branch)
  gh pr merge "$pr" "${merge_args[@]}" >/dev/null || die "merge of $pr failed"
  state=$(pr_state "$pr")
  if [[ $state == OPEN ]]; then
    echo "waiting for #$pr to merge (queued)"
    local deadline=$((SECONDS + wait_s))
    while [[ $state == OPEN ]] && ((SECONDS < deadline)); do
      sleep "$poll_s"
      state=$(pr_state "$pr")
    done
  fi
  [[ $state == MERGED ]] || not_merged "$pr" "$state" "$base" "$head_oid" "${lines[@]}"
  echo "$pr merged ($method)"

  fetch
  if [[ $cross == true ]]; then
    echo "PR #$pr is from a fork; skipped local cleanup"
  elif ! $keep_branch; then
    clean_local "$pr" "$head" "$head_oid"
  fi
  [[ $method != merge ]] || return 0
  for line in "${lines[@]}"; do
    IFS=$'\t' read -r number child_head child_oid child_cross <<<"$line"
    if [[ $child_cross == true ]]; then
      echo "child #$number is from a fork; rebase it onto $base by hand"
    else
      rebase_child "$number" "$child_head" "$child_oid" "origin/$base" "$base" "$head_oid"
    fi
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
