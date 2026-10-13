#!/usr/bin/env bash
# Merge PRs in order, carrying stacked PRs over to each base, then clean up local worktrees and branches.
set -euo pipefail

usage="usage: merge-prs.sh [--method rebase|squash|merge] [--keep-branch] [--skip-review-gate] [--wait-review] <pr>...
       merge-prs.sh --check [--wait-review] <pr>..."

die() {
  echo "merge-prs: $*" >&2
  exit 1
}

method=""
keep_branch=false
review_gate=true
wait_review=false
check_only=false
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
  --skip-review-gate)
    review_gate=false
    shift
    ;;
  --check)
    check_only=true
    shift
    ;;
  --wait-review)
    wait_review=true
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
# --check only reads; options that steer a merge are refused rather than silently ignored.
! $check_only || [[ -z $method && $keep_branch == false && $review_gate == true ]] ||
  die "--check cannot be combined with --method, --keep-branch or --skip-review-gate"

worktrees=$(git worktree list --porcelain) || die "not inside a git repository"
main_dir=$(awk '/^worktree /{print substr($0, 10); exit}' <<<"$worktrees")
cd "$main_dir"

repo_info=$(gh repo view --json nameWithOwner,defaultBranchRef,rebaseMergeAllowed,squashMergeAllowed,mergeCommitAllowed \
  --jq '[.nameWithOwner, .defaultBranchRef.name, .rebaseMergeAllowed, .squashMergeAllowed, .mergeCommitAllowed] | @tsv') ||
  die "cannot read the repository settings"
IFS=$'\t' read -r slug default rebase_ok squash_ok merge_ok <<<"$repo_info"
if ! $check_only; then
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
fi

# One query per PR: unresolved review threads, and the Codex summary comment's status and reviewed commit, if the repo uses Codex.
# shellcheck disable=SC2016 # GraphQL and jq variables, not shell ones.
review_query='query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) { pullRequest(number: $number) {
    headRefOid
    reviewThreads(first: 100) { nodes { isResolved } }
    comments(last: 100) { nodes { body } }
  } }
}'
# shellcheck disable=SC2016
review_jq='.data.repository.pullRequest as $p
  | ([$p.comments.nodes[] | select(.body | contains("codex-pull-request-review-summary"))] | last | .body // "") as $codex
  | [([$p.reviewThreads.nodes[] | select(.isResolved | not)] | length),
     ($codex | capture("\\*\\*(?<s>Running|Completed|Failed)\\*\\*").s // "none"),
     ($codex | capture("\\| `(?<c>[0-9a-f]{7,40})` \\|").c // "-"),
     $p.headRefOid] | @tsv'

review_wait_s=${MERGE_PRS_REVIEW_WAIT:-1200}
review_poll_s=${MERGE_PRS_REVIEW_POLL:-20}

read_review() {
  gh api graphql -F owner="${slug%%/*}" -F name="${slug#*/}" -F number="$1" -f query="$review_query" \
    --jq "$review_jq" || die "cannot read the review state of #$1"
}

# Why the commits after Codex's review need a review of their own; prints nothing when they only fix what it covered.
# Compares each side against the default branch, so commits picked up by a rebase after the review are not counted.
rereview_reason() {
  local reviewed=$1 head=$2 reviewed_subjects head_subjects covered changed new_work new_file
  reviewed_subjects=$(gh api "repos/$slug/compare/$default...$reviewed" --jq '.commits[].commit.message | split("\n")[0]') ||
    die "cannot compare $reviewed with $default"
  head_subjects=$(gh api "repos/$slug/compare/$default...$head" --jq '.commits[].commit.message | split("\n")[0]') ||
    die "cannot compare $head with $default"
  new_work=$(grep -vxFf <(printf '%s\n' "$reviewed_subjects") <<<"$head_subjects" | grep -Ev '^(fix|test)(\([^)]*\))?!?: ' | head -n 1 || true)
  if [[ -n $new_work ]]; then
    echo "\"$new_work\" is not a fix or test"
    return
  fi
  covered=$(gh api "repos/$slug/compare/$default...$reviewed" --jq '.files[].filename')
  changed=$(gh api "repos/$slug/compare/$default...$head" --jq '.files[].filename')
  new_file=$(grep -vxFf <(printf '%s\n' "$covered") <<<"$changed" | head -n 1 || true)
  [[ -z $new_file ]] || echo "$new_file was not in the reviewed changes"
}

# Polls until the Codex review stops running and, given "head", until it covers the PR's head commit.
# Timed by the clock rather than by summing sleeps, so a zero poll interval still stops at the limit.
poll_review() {
  local number=$1 until=${2:-} started=$SECONDS
  while ((waited < review_wait_s)); do
    if [[ $status != Running ]]; then
      [[ $until == head && $status != Failed && $head != "$reviewed"* ]] || return 0
    fi
    sleep "$review_poll_s"
    waited=$((SECONDS - started))
    info=$(read_review "$number")
    IFS=$'\t' read -r open status reviewed head <<<"$info"
  done
}

# Checks every PR before merging any, so a run never stops halfway through a stack over a review it could have seen up front.
check_reviews() {
  local pr number info open status reviewed head waited reason
  local -a problems=()
  for pr in "${prs[@]}"; do
    number=${pr#\#}
    info=$(read_review "$number")
    IFS=$'\t' read -r open status reviewed head <<<"$info"
    waited=0
    if [[ $status == Running ]] && $wait_review; then
      echo "merge-prs: waiting up to ${review_wait_s}s for #$number's Codex review" >&2
      poll_review "$number"
    fi
    # A fix that does what the review asked does not need another round; new work or new files after it do.
    if [[ $status == Completed && $head != "$reviewed"* ]]; then
      reason=$(rereview_reason "$reviewed" "$head")
      if [[ -z $reason ]]; then
        echo "note: #$number's Codex review covers $reviewed, not the head ${head:0:7}; the later commits only fix files it reviewed"
      elif $wait_review && ! $check_only; then
        echo "merge-prs: #$number changed since Codex reviewed $reviewed ($reason); requesting a review and waiting up to ${review_wait_s}s" >&2
        gh pr comment "$number" --body "@codex review" >/dev/null || die "cannot request a Codex review on #$number"
        poll_review "$number" head
        [[ $status != Completed || $head == "$reviewed"* ]] ||
          problems+=("#$number: Codex has not reviewed the head ${head:0:7} after ${waited}s; rerun with --wait-review once it has")
      else
        problems+=("#$number: commits since Codex reviewed $reviewed need their own review ($reason); rerun with --wait-review to request one and wait")
      fi
    fi
    ((open == 0)) || problems+=("#$number: $open unresolved review thread(s); answer and resolve them")
    case $status in
    Running)
      if ((waited)); then
        problems+=("#$number: the Codex review is still running after ${waited}s; rerun with --wait-review once it finishes")
      else
        problems+=("#$number: the Codex review is still running; wait for it to finish, or rerun with --wait-review")
      fi
      ;;
    Failed) problems+=("#$number: the Codex review failed at $reviewed; comment \"@codex review\" on the PR and wait for it") ;;
    esac
  done
  ((${#problems[@]} == 0)) && return 0
  if $check_only; then
    die "not ready:"$'\n'"$(printf '  %s\n' "${problems[@]}")"
  fi
  die "not merging:"$'\n'"$(printf '  %s\n' "${problems[@]}")"$'\n'"Rerun with --skip-review-gate only if the owner waived the review."
}

tmp_root=""
rebased_oid=""
wait_s=${MERGE_PRS_WAIT:-600}
poll_s=${MERGE_PRS_POLL:-10}
known_heads=()
# Head commits this run force-pushed, by branch. GitHub can keep reporting the old head for a moment after a push, so
# merging a PR rebased earlier in the run waits for this commit instead of trusting the first head GitHub reports.
declare -A pushed_heads=()
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
  if git show-ref --verify -q "refs/heads/$head"; then
    local extra
    # A failed rev-list (a head commit missing locally) must keep the branch, not read as "no extra commits".
    if ! extra=$(git rev-list -n 1 "refs/heads/$head" --not "$head_oid" "${known_heads[@]}" 2>/dev/null); then
      echo "kept $head: cannot compare its commits with PR #$pr"
      return
    fi
    if [[ -n $extra ]]; then
      echo "kept $head: local commits not in PR #$pr"
      return
    fi
  fi
  wt=$(git worktree list --porcelain | awk -v line="branch refs/heads/$head" '/^worktree /{p=substr($0, 10)} !found && $0 == line {print p; found = 1}')
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
  pushed_heads[$child_head]=$new_child
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
  pushed_heads[$head]=$rebased_oid
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

# An interrupted earlier run already merged it; finish its local cleanup. Everything here needs the PR's head commit
# locally: without it the branch cannot be shown to hold nothing the PR lacks, so it is kept. Nothing is pushed:
# the interrupted run may have retargeted the children already, so the stack is only reported, for the owner to rebase.
merge_pr_already_merged() {
  local pr=$1 head=$2 head_oid=$3 base=$4 cross=$5 line number child_head child_oid child_cross
  echo "#$pr already merged"
  fetch
  if [[ $cross == true ]]; then
    echo "PR #$pr is from a fork; skipped local cleanup"
    return 0
  fi
  if ! git cat-file -e "$head_oid^{commit}" 2>/dev/null; then
    echo "kept $head: the head of #$pr ($head_oid) is not available locally, so its local commits cannot be checked"
    return 0
  fi
  known_heads+=("$head_oid")
  $keep_branch || clean_local "$pr" "$head" "$head_oid"
  # Open children: still based on the head, or retargeted to the base but still carrying the merged head's commits.
  while IFS=$'\t' read -r number child_head child_oid child_cross; do
    [[ -n $number ]] || continue
    echo "warning: #$number ($child_head) is stacked on the merged #$pr and was not rebased; rebase it by hand:"
    if [[ $child_cross == true ]]; then
      echo "  it is from a fork; ask its author to rebase it onto $base"
    else
      echo "  git fetch origin && git rebase --onto origin/$base $head_oid $child_oid"
      echo "  git push --force-with-lease=$child_head:$child_oid origin HEAD:$child_head"
      echo "  gh pr edit $number --base $base"
    fi
  done < <(
    list_children "$head"
    # A head already in the base (merge commit) leaves nothing to rebase, and every later PR would match.
    ! git merge-base --is-ancestor "$head_oid" "origin/$base" || exit 0
    list_children "$base" | while IFS=$'\t' read -r number child_head child_oid child_cross; do
      git merge-base --is-ancestor "$head_oid" "$child_oid" 2>/dev/null &&
        printf '%s\t%s\t%s\t%s\n' "$number" "$child_head" "$child_oid" "$child_cross"
    done
  )
}

merge_pr() {
  local pr=$1 info head base state cross head_oid children_info="" line number child_head child_oid child_cross
  local -a lines=()
  info=$(gh pr view "$pr" --json headRefName,headRefOid,baseRefName,state,isCrossRepository \
    --jq '[.headRefName, .headRefOid, .baseRefName, .state, .isCrossRepository] | @tsv') || die "cannot read PR $pr"
  IFS=$'\t' read -r head head_oid base state cross <<<"$info"
  if [[ $state == MERGED ]]; then
    merge_pr_already_merged "$pr" "$head" "$head_oid" "$base" "$cross"
    return 0
  fi
  [[ $state == OPEN ]] || die "PR $pr is $state"
  head_oid=${pushed_heads[$head]:-$head_oid}
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

if $check_only; then
  check_reviews
  echo "ready: no unresolved review threads and no Codex review running or failed"
  exit 0
fi

! $review_gate || check_reviews

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
