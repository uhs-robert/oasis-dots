#!/usr/bin/env bash
# Merge PRs in order, carrying stacked PRs over to each base, then clean up local worktrees and branches.
set -euo pipefail

usage="usage: merge-prs.sh [--method rebase|squash|merge] [--keep-branch] [--skip-review-gate] [--wait-review] <pr>...
       merge-prs.sh --check [--wait-review [--request-review]] <pr>..."

die() {
  echo "merge-prs: $*" >&2
  exit 1
}

method=""
keep_branch=false
review_gate=true
wait_review=false
request_review=false
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
  --request-review)
    request_review=true
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
# --check only reads, unless --request-review lets it ask for a review of a changed head (a caller waiting for reviews
# before it merges); options that steer a merge are refused rather than silently ignored.
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

review_start_s=${MERGE_PRS_REVIEW_START:-300}
# It is spliced into the jq program below, where anything but a number fails as "cannot read the review state".
[[ $review_start_s =~ ^[0-9]+$ ]] || die "MERGE_PRS_REVIEW_START must be a number of seconds, not $review_start_s"

# One query per PR: unresolved review threads, and the Codex summary comment's status and reviewed commit, if the repo uses Codex.
# Codex posts that comment about a minute after a PR opens, so with none yet its eyes reaction counts as Running, and a
# PR younger than review_start_s is Pending rather than "none": a repo without Codex only waits out that window.
# A Completed summary with no commit in its table is Unreviewed: Codex writes one when it never ran a review (quota,
# outage), so it pins nothing and must not pass as a clean review of the head.
# shellcheck disable=SC2016 # GraphQL and jq variables, not shell ones.
review_query='query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) { pullRequest(number: $number) {
    headRefOid
    createdAt
    reviewThreads(first: 100) { nodes { isResolved } }
    comments(last: 100) { nodes { body } }
    reactions(content: EYES, first: 20) { nodes { user { login } } }
  } }
}'
# shellcheck disable=SC2016
review_jq='.data.repository.pullRequest as $p
  | ([$p.comments.nodes[] | select(.body | contains("codex-pull-request-review-summary"))] | last | .body // "") as $codex
  | (if any($p.reactions.nodes[]; (.user.login // "") | startswith("chatgpt-codex")) then "Running"
     elif (now - ($p.createdAt | fromdateiso8601)) < '"$review_start_s"' then "Pending"
     else "none" end) as $no_summary
  | ($codex | capture("\\*\\*(?<s>Running|Completed|Failed)\\*\\*").s // $no_summary) as $status
  | ($codex | capture("\\| `(?<c>[0-9a-f]{7,40})` \\|").c // "-") as $commit
  | [([$p.reviewThreads.nodes[] | select(.isResolved | not)] | length),
     (if $status == "Completed" and $commit == "-" then "Unreviewed" else $status end),
     $commit,
     $p.headRefOid] | @tsv'

review_wait_s=${MERGE_PRS_REVIEW_WAIT:-1200}
review_poll_s=${MERGE_PRS_REVIEW_POLL:-20}

read_review() {
  gh api graphql -F owner="${slug%%/*}" -F name="${slug#*/}" -F number="$1" -f query="$review_query" \
    --jq "$review_jq" || die "cannot read the review state of #$1"
}

# Path prefixes a repo lists in .claude/generated-paths (build output a hook commits), one per line, # for comments.
generated_prefixes() {
  local top line
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  [[ -f $top/.claude/generated-paths ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [[ -z $line || $line == '#'* ]] || printf '%s\n' "$line"
  done <"$top/.claude/generated-paths"
}

# Whether the file sits under any of the prefixes given after it.
under_prefix() {
  local file=$1 prefix
  shift
  for prefix in "$@"; do
    [[ $file == "$prefix"* ]] && return 0
  done
  return 1
}

# Sets rereview_why to the reason the commits after Codex's review need a review of their own; empty when they only fix
# what it covered. Sets generated_skipped when a commit was ignored for touching only generated paths.
# Compares each side against the default branch, so commits picked up by a rebase after the review are not counted.
# Not run in a subshell, so the two variables reach the caller.
rereview_reason() {
  local reviewed=$1 head=$2 cross=$3 reviewed_subjects head_commits covered changed new_file sha subject file sha_files_text only_generated
  local -a prefixes=() sha_files=()
  rereview_why=""
  generated_skipped=false
  # A fork PR is never rebuilt by the pre-merge step, so its generated paths are not known to be output.
  [[ $cross == true ]] || mapfile -t prefixes < <(generated_prefixes)
  reviewed_subjects=$(gh api "repos/$slug/compare/$default...$reviewed" --jq '.commits[].commit.message | split("\n")[0]') ||
    die "cannot compare $reviewed with $default"
  head_commits=$(gh api "repos/$slug/compare/$default...$head" --jq '.commits[] | [.sha, (.commit.message | split("\n")[0])] | @tsv') ||
    die "cannot compare $head with $default"
  while IFS=$'\t' read -r sha subject; do
    [[ -n $sha ]] || continue
    ! grep -qxF -- "$subject" <<<"$reviewed_subjects" || continue
    # A commit of only generated files is the hook's rebuild, not work to review. Files are fetched per post-review commit.
    if ((${#prefixes[@]})); then
      sha_files_text=$(gh api "repos/$slug/commits/$sha" --jq '.files[].filename') || die "cannot read the files of $sha"
      mapfile -t sha_files <<<"$sha_files_text"
      [[ -n $sha_files_text ]] || sha_files=()
      only_generated=${#sha_files[@]}
      for file in "${sha_files[@]}"; do
        under_prefix "$file" "${prefixes[@]}" || only_generated=0
      done
      if ((only_generated)); then
        generated_skipped=true
        continue
      fi
    fi
    if ! grep -Eq '^(fix|test)(\([^)]*\))?!?: ' <<<"$subject"; then
      rereview_why="\"$subject\" is not a fix or test"
      return
    fi
  done <<<"$head_commits"
  covered=$(gh api "repos/$slug/compare/$default...$reviewed" --jq '.files[].filename')
  changed=$(gh api "repos/$slug/compare/$default...$head" --jq '.files[].filename')
  new_file=""
  while IFS= read -r file; do
    [[ -n $file ]] || continue
    ! grep -qxF -- "$file" <<<"$covered" || continue
    ((${#prefixes[@]})) && under_prefix "$file" "${prefixes[@]}" && continue
    new_file=$file
    break
  done <<<"$changed"
  [[ -z $new_file ]] || rereview_why="$new_file was not in the reviewed changes"
}

# Polls until the Codex review stops running and, given "head", until it covers the PR's head commit.
# Timed by the clock rather than by summing sleeps, so a zero poll interval still stops at the limit.
poll_review() {
  local number=$1 until=${2:-} started=$SECONDS
  while ((waited < review_wait_s)); do
    if [[ $status != Running && $status != Pending ]]; then
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
  local pr number info open status reviewed head waited reason cross rereview_why generated_skipped rerun_flags
  local -a problems=()
  for pr in "${prs[@]}"; do
    number=${pr#\#}
    info=$(read_review "$number")
    IFS=$'\t' read -r open status reviewed head <<<"$info"
    waited=0
    if [[ $status == Running || $status == Pending ]] && $wait_review; then
      echo "merge-prs: waiting up to ${review_wait_s}s for #$number's Codex review" >&2
      poll_review "$number"
    fi
    if [[ $status == Unreviewed ]]; then
      if $wait_review && { ! $check_only || $request_review; }; then
        echo "merge-prs: #$number has no Codex review (its summary records no commit); requesting one and waiting up to ${review_wait_s}s" >&2
        gh pr comment "$number" --body "@codex review" >/dev/null || die "cannot request a Codex review on #$number"
        poll_review "$number" head
        [[ $status != Unreviewed ]] ||
          problems+=("#$number: Codex has not reviewed the head ${head:0:7} after ${waited}s; rerun with --wait-review once it has")
      else
        rerun_flags="--wait-review"
        ! $check_only || rerun_flags="--check --wait-review --request-review"
        problems+=("#$number: Codex completed without a commit, so nothing was reviewed; comment @codex review, or rerun with $rerun_flags")
      fi
    fi
    # A fix that does what the review asked does not need another round; new work or new files after it do.
    if [[ $status == Completed && $head != "$reviewed"* ]]; then
      cross=$(gh pr view "$number" --json isCrossRepository --jq .isCrossRepository) || die "cannot read #$number"
      rereview_reason "$reviewed" "$head" "$cross"
      reason=$rereview_why
      if [[ -z $reason ]]; then
        if $generated_skipped; then
          echo "note: #$number's Codex review covers $reviewed, not the head ${head:0:7}; the later commits only fix files it reviewed or touch generated paths"
        else
          echo "note: #$number's Codex review covers $reviewed, not the head ${head:0:7}; the later commits only fix files it reviewed"
        fi
      elif $wait_review && { ! $check_only || $request_review; }; then
        echo "merge-prs: #$number changed since Codex reviewed $reviewed ($reason); requesting a review and waiting up to ${review_wait_s}s" >&2
        gh pr comment "$number" --body "@codex review" >/dev/null || die "cannot request a Codex review on #$number"
        poll_review "$number" head
        [[ $status != Completed || $head == "$reviewed"* ]] ||
          problems+=("#$number: Codex has not reviewed the head ${head:0:7} after ${waited}s; rerun with --wait-review once it has")
      else
        # --check alone never comments on the PR, so the rerun it needs takes --request-review as well.
        rerun_flags="--wait-review"
        ! $check_only || rerun_flags="--check --wait-review --request-review"
        problems+=("#$number: commits since Codex reviewed $reviewed need their own review ($reason); rerun with $rerun_flags to request one and wait")
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
    Pending)
      if ((waited)); then
        problems+=("#$number: still no Codex review after ${waited}s; rerun with --wait-review once one has started")
      else
        problems+=("#$number: opened under ${review_start_s}s ago and Codex has not started on it; wait for its review, or rerun with --wait-review")
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
# Prints UNKNOWN unless GitHub reports the expected head with a settled state, since it can report the old head's state.
mergeable_wait_s=${MERGE_PRS_MERGEABLE_WAIT:-60}
await_mergeable() {
  local pr=$1 oid=$2 info="" deadline=$((SECONDS + mergeable_wait_s))
  while :; do
    info=$(gh pr view "$pr" --json headRefOid,mergeable --jq '[.headRefOid, .mergeable] | @tsv') ||
      die "cannot read the mergeability of $pr"
    [[ $info == "$oid"$'\t'@(MERGEABLE|CONFLICTING) ]] && break
    ((SECONDS < deadline)) || break
    sleep 2
  done
  [[ $info == "$oid"$'\t'@(MERGEABLE|CONFLICTING) ]] || info="$oid"$'\t'UNKNOWN
  printf '%s\n' "${info#*$'\t'}"
}

# Rebases the detached worktree's HEAD (at $old) onto origin/$base. With a pre-merge step, commits touching only generated
# paths are dropped first, since the step rebuilds that output and the old build would only conflict with the base's.
rebase_dropping_generated() {
  local old=$1 base=$2 commit file generated
  local -a prefixes=() skip=() files=()
  [[ -x $main_dir/.claude/pre-merge ]] && mapfile -t prefixes < <(generated_prefixes)
  for commit in $(git rev-list --reverse --no-merges "origin/$base..$old"); do
    ((${#prefixes[@]})) || break
    mapfile -t files < <(git diff-tree --root --no-commit-id --name-only -r "$commit")
    generated=${#files[@]}
    for file in "${files[@]}"; do
      under_prefix "$file" "${prefixes[@]}" || generated=0
    done
    ((generated == 0)) || skip+=("$commit")
  done
  generated_dropped=${#skip[@]}
  if ((${#skip[@]} == 0)); then
    git -C "$tmp_root/wt" rebase -q "origin/$base" >/dev/null 2>&1
  elif ((${#skip[@]} == $(git rev-list --count --no-merges "origin/$base..$old"))); then
    git -C "$tmp_root/wt" checkout -q --detach "origin/$base"
  else
    # Full ids in the todo list, so the filter cannot match a shorter abbreviation of another commit.
    GIT_SEQUENCE_EDITOR="sed -i -E '/^(pick|p) ($(IFS='|' && echo "${skip[*]}")) /d'" \
      git -c core.abbrev=40 -C "$tmp_root/wt" rebase -q -i "origin/$base" >/dev/null 2>&1
  fi
}

# Rebases a PR head onto origin/$base and force-pushes it, recording the new head in rebased_oid. A PR stacked on a parent
# that was rebase- or squash-merged outside this run still carries the parent's old commits, so GitHub reports it as
# conflicting; rebasing drops them, because git skips commits whose changes are already there. With require_drop, a rebase
# that drops nothing means a real conflict, which stays with the owner.
rebase_head() {
  local pr=$1 head=$2 old=$3 base=$4 require_drop=$5 before after generated_dropped=0 msg
  tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/merge-prs.XXXXXX")
  git worktree add -q --detach "$tmp_root/wt" "$old" || die "cannot create a worktree for $head"
  before=$(git rev-list --count "origin/$base..$old")
  if ! rebase_dropping_generated "$old" "$base"; then
    git -C "$tmp_root/wt" rebase --abort >/dev/null 2>&1 || true
    remove_tmp
    die "#$pr conflicts with $base; rebase $head onto origin/$base by hand, then rerun for the remaining PRs"
  fi
  after=$(git -C "$tmp_root/wt" rev-list --count "origin/$base..HEAD")
  if $require_drop && ((after >= before)); then
    remove_tmp
    die "#$pr conflicts with $base and carries no commits already merged there; resolve it by hand, then rerun for the remaining PRs"
  fi
  rebased_oid=$(git -C "$tmp_root/wt" rev-parse HEAD)
  git -C "$tmp_root/wt" push -q --force-with-lease="$head:$old" origin "HEAD:refs/heads/$head" ||
    die "cannot push the rebased $head"
  pushed_heads[$head]=$rebased_oid
  known_heads+=("$rebased_oid")
  remove_tmp
  msg="#$pr rebased onto $base"
  if ((before - after - generated_dropped)); then
    msg+=", dropping $((before - after - generated_dropped)) commit(s) already merged there"
    ((generated_dropped == 0)) || msg+=" and $generated_dropped generated-only commit(s) the pre-merge step rebuilds"
  elif ((generated_dropped)); then
    msg+=", dropping $generated_dropped generated-only commit(s) the pre-merge step rebuilds"
  fi
  echo "$msg"
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

# Runs the repo's .claude/pre-merge on a detached checkout of the PR head, so build output it commits lands in the PR and
# is merged with it. Sets head_oid to the head to merge: the script's commit, pushed and seen by GitHub, if it made one.
# The gate has already run by now, so a commit made here is never held to it. Not run by --check.
run_pre_merge() {
  local pr=$1 head=$2 base=$3 cross=$4 hook new_oid pre_merge_oid=$head_oid
  hook=$main_dir/.claude/pre-merge
  [[ -x $hook ]] || return 0
  if [[ $cross == true ]]; then
    echo "warning: #$pr is from a fork, so the pre-merge step was skipped; its commits could not be pushed"
    return 0
  fi
  # Output built on a head that is behind its base would conflict with what the base already built. A merge commit keeps
  # the head as it is, so it is left alone.
  if [[ $method != merge ]] && ! git merge-base --is-ancestor "origin/$base" "$head_oid"; then
    rebase_head "$pr" "$head" "$head_oid" "$base" false
    head_oid=$rebased_oid
    pre_merge_oid=$head_oid
    [[ $(await_mergeable "$pr" "$head_oid") != UNKNOWN ]] ||
      die "GitHub has not caught up with the rebased $head on #$pr; rerun for #$pr and the PRs after it"
  fi
  tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/merge-prs.XXXXXX")
  git worktree add -q --detach "$tmp_root/wt" "$head_oid" || die "cannot create a worktree for $head"
  echo "merge-prs: pre-merge #$pr"
  if ! (cd "$tmp_root/wt" && MERGE_PRS_PR=$pr MERGE_PRS_BRANCH=$head MERGE_PRS_BASE=$base MERGE_PRS_REPO_ROOT=$main_dir "$hook"); then
    remove_tmp
    die "the pre-merge step failed on #$pr; fix it and rerun for #$pr and the PRs after it"
  fi
  if [[ -n $(git -C "$tmp_root/wt" status --porcelain) ]]; then
    echo "warning: the pre-merge step left uncommitted changes on #$pr; they are not merged"
  fi
  new_oid=$(git -C "$tmp_root/wt" rev-parse HEAD)
  if [[ $new_oid != "$head_oid" ]]; then
    git -C "$tmp_root/wt" push -q origin "HEAD:refs/heads/$head" || {
      remove_tmp
      die "cannot push the pre-merge commits to $head"
    }
    pushed_heads[$head]=$new_oid
    known_heads+=("$new_oid")
    head_oid=$new_oid
    echo "#$pr pre-merge committed ${new_oid:0:7}"
  fi
  remove_tmp
  [[ $new_oid != "$pre_merge_oid" ]] || return 0
  # GitHub reports the old head, and an unknown mergeable state, for a moment after a push.
  case $(await_mergeable "$pr" "$head_oid") in
  MERGEABLE) ;;
  CONFLICTING) die "the pre-merge commit ${head_oid:0:7} on #$pr conflicts with $base; rebase $head onto origin/$base by hand, rerun its pre-merge step, then rerun for #$pr and the PRs after it" ;;
  *) die "GitHub has not caught up with the pre-merge commit $head_oid on #$pr; rerun for #$pr and the PRs after it" ;;
  esac
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

  if [[ $(await_mergeable "$pr" "$head_oid") == CONFLICTING && $cross != true ]]; then
    rebase_head "$pr" "$head" "$head_oid" "$base" true
    head_oid=$rebased_oid
    known_heads+=("$head_oid")
    await_mergeable "$pr" "$head_oid" >/dev/null
  fi

  run_pre_merge "$pr" "$head" "$base" "$cross"

  # Only now that nothing can stop the merge short of GitHub itself, so a failed step leaves the children where they were.
  for line in "${lines[@]}"; do
    IFS=$'\t' read -r number _ <<<"$line"
    gh pr edit "$number" --base "$base" >/dev/null || die "cannot retarget $number to $base"
    echo "$number retargeted to $base"
  done

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
