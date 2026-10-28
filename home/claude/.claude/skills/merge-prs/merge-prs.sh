#!/usr/bin/env bash
# Merge PRs into the default branch in order, then clean up local worktrees and branches.
set -euo pipefail

usage="usage: merge-prs.sh [--method rebase|squash|merge] [--keep-branch] [--skip-review-gate] [--wait-review] <pr>...
       merge-prs.sh --check [--skip-review-gate] [--wait-review [--request-review]] <pr>..."

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
# before it merges); options that steer a merge are refused rather than silently ignored. --skip-review-gate is not one:
# it narrows what is read to the unresolved threads.
! $check_only || [[ -z $method && $keep_branch == false ]] ||
  die "--check cannot be combined with --method or --keep-branch"

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
# The summary's machine-readable codex-review-state marker is read first, its status table as the fallback.
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
  | ([$codex | capture("codex-review-state:v1 (?<j>\\{.*?\\}) -->")? | .j | fromjson? | .code_review?] | first // null) as $state
  | ({running: "Running", completed: "Completed", failed: "Failed"}[($state.status // "" | ascii_downcase)]) as $state_status
  | ($state_status // ($codex | capture("\\*\\*(?<s>Running|Completed|Failed)\\*\\*").s) // $no_summary) as $status
  | ($state.commit_sha // ($codex | capture("\\| `(?<c>[0-9a-f]{7,40})` \\|").c) // "-") as $commit
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
  local reviewed=$1 head=$2 reviewed_subjects head_commits covered changed new_file sha subject file sha_files_text only_generated
  local -a prefixes=() sha_files=()
  rereview_why=""
  generated_skipped=false
  mapfile -t prefixes < <(generated_prefixes)
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

# Polls until the Codex review stops running and, given "head", until it covers the PR's head commit, or, given "retry",
# until it is no longer the Failed one a re-request was made over.
# Timed by the clock rather than by summing sleeps, so a zero poll interval still stops at the limit.
poll_review() {
  local number=$1 until=${2:-} started=$SECONDS
  # Each poll gets the whole wait: a request made after an earlier poll ran out of time must still be waited for.
  waited=0
  while ((waited < review_wait_s)); do
    if [[ $status != Running && $status != Pending ]]; then
      case $until in
      head) [[ $status != Failed && $head != "$reviewed"* ]] || return 0 ;;
      retry) [[ $status == Failed ]] || return 0 ;;
      *) return 0 ;;
      esac
    fi
    sleep "$review_poll_s"
    waited=$((SECONDS - started))
    info=$(read_review "$number")
    IFS=$'\t' read -r open status reviewed head <<<"$info"
  done
}

# The reviewer registry decides who gates: reviewers.sh merges the built-in file and the repo's.
reviewers_sh=${MERGE_PRS_REVIEWERS:-$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../orchestrator/reviewers.sh}
reviewers_json=""
gating=()

# One field of one registry entry, as raw jq output.
rjq() {
  jq -r --arg n "$1" ".[] | select(.name == \$n) | $2" <<<"$reviewers_json"
}

# Login forms differ by API: "app/x" and "x[bot]" are both "x".
bare_login() {
  local login=${1#app/}
  printf '%s\n' "${login%\[bot\]}"
}

suite_slugs="" suites_loaded=false history_logins="" history_loaded=false

# Whether a reviewer is installed on the repo, for a gate of auto. An app reviewer shows as a check suite on the default
# branch head; the suite's own status stays queued for CodeRabbit, so only its slug counts. A reviewer that is only a
# commenting bot (no app slug) shows as an author among the comments of the last 10 PRs. Each source is read once per run.
infer_connected() {
  local name=$1 app_slug=$2 login
  if [[ -n $app_slug ]]; then
    if ! $suites_loaded; then
      suite_slugs=$(gh api --paginate "repos/$slug/commits/$default/check-suites?per_page=100" --jq '.check_suites[].app.slug') ||
        die "cannot read the check suites of $default"
      suites_loaded=true
    fi
    grep -qxF -- "$app_slug" <<<"$suite_slugs"
    return
  fi
  if ! $history_loaded; then
    history_logins=$(gh pr list --state all --limit 10 --json comments --jq '.[].comments[].author.login') ||
      die "cannot read the recent PR comments"
    history_logins=$(while IFS= read -r login; do [[ -z $login ]] || bare_login "$login"; done <<<"$history_logins")
    history_loaded=true
  fi
  while IFS= read -r login; do
    [[ -n $login ]] || continue
    grep -qxF -- "$(bare_login "$login")" <<<"$history_logins" && return 0
  done < <(rjq "$name" '.github.logins // [] | .[]')
  return 1
}

# Sets gating to the reviewers this run waits for: gate always, or auto with the reviewer installed on the repo.
# A reviewer with no github signal this script reads cannot be waited for, so it never gates.
resolve_gates() {
  local name gate signal app_slug
  reviewers_json=$(bash "$reviewers_sh" list "$main_dir") || die "cannot resolve the reviewers with $reviewers_sh"
  gating=()
  while IFS=$'\t' read -r name gate signal app_slug; do
    if [[ $signal != summary_comment && $signal != check_run ]]; then
      # Fail closed: a reviewer the owner said must be waited for cannot be skipped because this script cannot read it.
      [[ $gate != always ]] || die "reviewer $name has gate always but its signal \"$signal\" is not one merge-prs reads"
      continue
    fi
    case $gate in
    never) continue ;;
    always) ;;
    *) infer_connected "$name" "$app_slug" || continue ;;
    esac
    gating+=("$name")
  done < <(jq -r '.[] | select(.github != null) | [.name, .gate, (.github.signal // "-"), (.github.app_slug // "")] | @tsv' <<<"$reviewers_json")
}

comments_json=""
# The PR's issue comments as one JSON object per line, for the unavailable patterns and CodeRabbit's summary marker.
load_comments() {
  comments_json=$(gh api --paginate "repos/$slug/issues/$1/comments?per_page=100" \
    --jq '.[] | {login: (.user.login // ""), created_at, body} | tojson') || die "cannot read the comments of #$1"
}

commit_date() {
  gh api "repos/$slug/commits/$1" --jq .commit.committer.date || die "cannot read the commit $1"
}

# Whether a comment by the reviewer, created at or after $2, holds one of its unavailable patterns (case-insensitive).
# The date cut keeps a quota comment about an older head from excusing a newer one.
unavailable_hit() {
  jq -ne --argjson r "$(rjq "$1" .)" --arg since "$2" '
    def bare: sub("^app/"; "") | sub("\\[bot\\]$"; "");
    ($r.github.logins // [] | map(bare)) as $logins
    | ($r.github.unavailable // [] | map(ascii_downcase)) as $patterns
    | [inputs | select((.login | bare) as $l | $logins | index($l) != null)
        | select(.created_at >= $since)
        | select((.body // "" | ascii_downcase) as $b | any($patterns[]; . as $p | $b | contains($p)))]
    | length > 0' <<<"$comments_json" >/dev/null
}

# The commit CodeRabbit's summary comment says it covered, or empty; the marker is CodeRabbit-internal, so it may be absent.
summary_covered_commit() {
  jq -nr '[inputs | select(.login | test("^(app/)?coderabbitai(\\[bot\\])?$")) | select(.body | contains("final_review_risk_coverage"))
    | .body | capture("coveredCommitId\\W{1,12}(?<c>[0-9a-f]{7,40})").c] | last // ""' <<<"$comments_json"
}

# Whether the reviewer posted a PR review of exactly this commit.
reviewed_head() {
  local number=$1 name=$2 head=$3 login commit login_pattern
  login_pattern=$(rjq "$name" '.github.logins // [] | map(sub("^app/"; "") | sub("\\[bot\\]$"; "")) | join(" ")')
  while IFS='|' read -r login commit; do
    [[ $commit == "$head" && " $login_pattern " == *" $(bare_login "$login") "* ]] && return 0
  done < <(gh api --paginate "repos/$slug/pulls/$number/reviews?per_page=100" --jq '.[] | [(.user.login // ""), (.commit_id // "")] | join("|")')
  return 1
}

# When the head reached GitHub: the earliest check suite on it, since a push opens one for every installed app. The commit
# date is only when the commit was made, so it is the fallback and the floor.
head_push_time() {
  local committed suite
  committed=$(commit_date "$1") || exit 1
  suite=$(gh api "repos/$slug/commits/$1/check-suites" --jq '[.check_suites[].created_at] | min // empty') ||
    die "cannot read the check suites of $1"
  if [[ -n $suite && $suite > $committed ]]; then echo "$suite"; else echo "$committed"; fi
}

epoch() {
  date -u -d "$1" +%s || die "cannot read the time $1"
}

# Sets cr_state (Pending, Running, Done, Failed, Unavailable or NotStarted), cr_msg (the reason, for notes and problems)
# and cr_final (true for a Failed that asking again cannot fix) from the reviewer's check run on the PR head.
# CodeRabbit posts findings as a PR review that can land minutes after its check turns success, and a clean pass posts
# none, so success alone is not done: it needs a review of the head, or the summary's coverage marker and then settle_s
# seconds for a review that is still coming. A cancelled run is a superseded one, so it is Pending until start_s passes.
eval_check_run() {
  local name=$1 number=$2 head=$3 start_s settle_s now head_epoch rname rstatus rconc rstart rdone run="" run_start=""
  local covered covers_head settled label age sort_key runs_out push_time since check_name is_check done_epoch
  local -a check_names=()
  label=$(rjq "$name" .label)
  start_s=${MERGE_PRS_REVIEW_START:-$(rjq "$name" '.github.start_s // 300')}
  settle_s=${MERGE_PRS_SETTLE:-$(rjq "$name" '.github.settle_s // 180')}
  cr_state="" cr_msg="" cr_final=false
  now=$(date +%s)
  # Assigned apart from the call that uses it: a failure inside "$(...)" in an argument would only end that subshell and
  # leave an empty time that matches every comment.
  push_time=$(head_push_time "$head") || exit 1
  head_epoch=$(epoch "$push_time") || exit 1
  since=$(date -u -d "@$head_epoch" +%FT%TZ) || exit 1
  mapfile -t check_names < <(rjq "$name" '.github.check_names // [] | .[]')
  # Read outside the loop's process substitution, which would hide a failed call as "no runs" and let the PR through.
  runs_out=$(gh api --paginate "repos/$slug/commits/$head/check-runs?per_page=100" \
    --jq '.check_runs[] | [.name, .status, (.conclusion // ""), (.started_at // ""), (.completed_at // "")] | join("|")') ||
    die "cannot read the check runs of $head"
  while IFS='|' read -r rname rstatus rconc rstart rdone; do
    [[ -n $rname ]] || continue
    is_check=false
    for check_name in "${check_names[@]}"; do
      [[ $check_name != "$rname" ]] || is_check=true
    done
    $is_check || continue
    sort_key=${rstart:-9999}
    if [[ -z $run || $sort_key > $run_start ]]; then
      run="$rstatus|$rconc|$rdone"
      run_start=$sort_key
    fi
  done <<<"$runs_out"
  load_comments "$number"
  if [[ -z $run ]]; then
    age=$((now - head_epoch))
    if unavailable_hit "$name" "$since"; then
      cr_state=Unavailable cr_msg="$label posted that it is unavailable"
    elif ((age < start_s)); then
      cr_state=Pending cr_msg="no $label check on the head yet"
    else
      cr_state=NotStarted cr_msg="$label has no check on the head ${age}s after the push"
    fi
    return
  fi
  IFS='|' read -r rstatus rconc rdone <<<"$run"
  if [[ $rstatus != completed ]]; then
    if unavailable_hit "$name" "$since"; then
      cr_state=Unavailable cr_msg="$label posted that it is unavailable"
    else
      cr_state=Running cr_msg="the $label check is $rstatus"
    fi
    return
  fi
  if [[ -z $rdone ]]; then
    cr_state=Failed cr_msg="the $label check is completed ($rconc) but records no completion time"
    return
  fi
  done_epoch=$(epoch "$rdone") || exit 1
  # A cancelled or stale run can still have been followed by a review of the head, so it gets the done signal too.
  if [[ " $(rjq "$name" '(.github.done // []) | join(" ")') " == *" $rconc "* || $rconc == cancelled || $rconc == stale ]]; then
    if reviewed_head "$number" "$name" "$head"; then
      cr_state=Done
      return
    fi
    covered=$(summary_covered_commit)
    covers_head=false
    [[ -z $covered || ($head != "$covered"* && $covered != "$head"*) ]] || covers_head=true
    settled=false
    ((now < done_epoch + settle_s)) || settled=true
    if [[ $rconc == cancelled || $rconc == stale ]]; then
      if $covers_head && $settled; then
        cr_state=Done
        return
      fi
    elif [[ -n $covered ]] && ! $covers_head; then
      cr_state=Running cr_msg="$label's summary covers ${covered:0:7}, not the head ${head:0:7}"
      return
    elif $settled; then
      cr_state=Done
      return
    else
      cr_state=Running cr_msg="the $label check finished; waiting ${settle_s}s for a review that may still be coming"
      return
    fi
  fi
  if [[ " $(rjq "$name" '(.github.unavailable_conclusions // []) | join(" ")') " == *" $rconc "* ]]; then
    cr_state=Unavailable cr_msg="its check concluded $rconc"
  elif unavailable_hit "$name" "$since"; then
    cr_state=Unavailable cr_msg="$label posted that it is unavailable"
  else
    case $rconc in
    cancelled | stale)
      now=$(date +%s)
      age=$((now - done_epoch))
      ((age >= now - head_epoch)) || age=$((now - head_epoch))
      if ((age < start_s)); then
        cr_state=Pending cr_msg="the $label check was $rconc; a new run should replace it"
      else
        cr_state=Failed cr_msg="the $label check was $rconc and no new run replaced it"
      fi
      ;;
    action_required) cr_state=Failed cr_final=true cr_msg="the $label check needs owner action" ;;
    *) cr_state=Failed cr_msg="the $label check concluded $rconc" ;;
    esac
  fi
}

# A check_run reviewer's gate for one PR: waits (with --wait-review) while it is pending or running, asks once again after
# a failure, and records the problem or the note. The deadline is per reviewer, so a slow one cannot starve the next.
gate_check_run() {
  local name=$1 number=$2 label wait_s request started requested=false head
  label=$(rjq "$name" .label)
  wait_s=${MERGE_PRS_REVIEW_WAIT:-$(rjq "$name" '.github.wait_s // 1200')}
  request=$(rjq "$name" '.github.request // ""')
  started=$SECONDS
  while :; do
    head=$(gh pr view "$number" --json headRefOid --jq .headRefOid) || die "cannot read the head of #$number"
    eval_check_run "$name" "$number" "$head"
    case $cr_state in
    Pending | Running) $wait_review || break ;;
    Failed)
      if $requested; then
        :
      elif $wait_review && ! $cr_final && [[ -n $request ]] && { ! $check_only || $request_review; }; then
        echo "merge-prs: #$number's $label review failed ($cr_msg); requesting another and waiting up to ${wait_s}s" >&2
        gh pr comment "$number" --body "$request" >/dev/null || die "cannot request a $label review on #$number"
        requested=true
        started=$SECONDS
        continue
      else
        break
      fi
      ;;
    *) break ;;
    esac
    ((SECONDS - started < wait_s)) || break
    sleep "$review_poll_s"
  done
  case $cr_state in
  Done) ;;
  Unavailable | NotStarted) echo "note: #$number $cr_msg; not waiting for it" ;;
  Pending | Running)
    if $wait_review; then
      problems+=("#$number: $cr_msg after $((SECONDS - started))s; rerun with --wait-review once the $label review has finished")
    else
      problems+=("#$number: $cr_msg; wait for the $label review, or rerun with --wait-review")
    fi
    ;;
  Failed)
    if $cr_final; then
      problems+=("#$number: $cr_msg; resolve it on GitHub")
    else
      problems+=("#$number: $cr_msg; comment \"$request\" on the PR and wait for it")
    fi
    ;;
  esac
}

# A summary_comment reviewer (Codex) for one PR. Its summary comment holds a status and the reviewed commit, read by
# review_jq in the same query as the threads.
gate_summary_comment() {
  local name=$1 number=$2 info open status reviewed head waited reason rereview_why generated_skipped rerun_flags request push_time
  request=$(rjq "$name" '.github.request // "@codex review"')
  info=$(read_review "$number")
  IFS=$'\t' read -r open status reviewed head <<<"$info"
  waited=0
  if [[ $status == Running || $status == Pending ]] && $wait_review; then
    echo "merge-prs: waiting up to ${review_wait_s}s for #$number's Codex review" >&2
    poll_review "$number"
  fi
  # A summary that failed or reviewed nothing next to a usage-limit comment on this head is a reviewer that cannot run, not a failure.
  if [[ $status == Failed || $status == Unreviewed ]]; then
    load_comments "$number"
    push_time=$(head_push_time "$head") || exit 1
    if unavailable_hit "$name" "$push_time"; then
      echo "note: #$number Codex is unavailable (usage limit); not waiting for it"
      return
    fi
  fi
  if [[ $status == Failed ]] && $wait_review && { ! $check_only || $request_review; }; then
    echo "merge-prs: #$number's Codex review failed at $reviewed; requesting another and waiting up to ${review_wait_s}s" >&2
    gh pr comment "$number" --body "$request" >/dev/null || die "cannot request a Codex review on #$number"
    poll_review "$number" retry
  fi
  if [[ $status == Unreviewed ]]; then
    if $wait_review && { ! $check_only || $request_review; }; then
      echo "merge-prs: #$number has no Codex review (its summary records no commit); requesting one and waiting up to ${review_wait_s}s" >&2
      gh pr comment "$number" --body "$request" >/dev/null || die "cannot request a Codex review on #$number"
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
    rereview_reason "$reviewed" "$head"
    reason=$rereview_why
    if [[ -z $reason ]]; then
      if $generated_skipped; then
        echo "note: #$number's Codex review covers $reviewed, not the head ${head:0:7}; the later commits only fix files it reviewed or touch generated paths"
      else
        echo "note: #$number's Codex review covers $reviewed, not the head ${head:0:7}; the later commits only fix files it reviewed"
      fi
    elif $wait_review && { ! $check_only || $request_review; }; then
      echo "merge-prs: #$number changed since Codex reviewed $reviewed ($reason); requesting a review and waiting up to ${review_wait_s}s" >&2
      gh pr comment "$number" --body "$request" >/dev/null || die "cannot request a Codex review on #$number"
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
  Failed) problems+=("#$number: the Codex review failed at $reviewed; comment \"$request\" on the PR and wait for it") ;;
  none) echo "note: #$number Codex has not started on it; not waiting for it" ;;
  esac
}

# A PR that is not based on the default branch or comes from a fork would merge somewhere this script does not follow up.
# A merged fork PR is refused too: local cleanup no longer knows forks and could delete a same-named local branch.
check_targets() {
  local pr info base state cross
  for pr in "${prs[@]}"; do
    info=$(gh pr view "$pr" --json baseRefName,state,isCrossRepository \
      --jq '[.baseRefName, .state, .isCrossRepository] | @tsv') || die "cannot read PR $pr"
    IFS=$'\t' read -r base state cross <<<"$info"
    [[ $state != OPEN || $base == "$default" ]] || die "#${pr#\#} is based on $base, not $default; merge-prs only merges PRs into $default"
    [[ $cross != true ]] || die "#${pr#\#} is from a fork; merge-prs only merges PRs from this repository"
  done
}

# Checks every PR before merging any, so a run never stops halfway through the list over a review it could have seen up front.
# Unresolved threads always block; --skip-review-gate drops only the reviewers' states. The waiver is for a reviewer
# that is down or slow, not for findings it already posted. Threads are read after the
# reviewers, since findings arrive while one is waited for.
check_reviews() {
  local pr number info open status reviewed head name gated_head mark attempts
  local -a problems=()
  ! $review_gate || resolve_gates
  for pr in "${prs[@]}"; do
    number=${pr#\#}
    # The reviewers are asked one after another, so a push in between would leave one of them on an older head; every
    # reviewer is asked again on the new head, and the merge is held to the head that passed.
    attempts=0
    while :; do
      gated_head=$(gh pr view "$number" --json headRefOid --jq .headRefOid) || die "cannot read the head of #$number"
      mark=${#problems[@]}
      for name in "${gating[@]}"; do
        case $(rjq "$name" .github.signal) in
        summary_comment)
          # Only Codex's summary format is parsed; reading another reviewer's as Codex's would let it pass unread.
          if [[ $name == codex ]]; then
            gate_summary_comment "$name" "$number"
          else
            problems+=("#$number: reviewer $name signals by summary_comment, a format this script reads only for codex")
          fi
          ;;
        check_run) gate_check_run "$name" "$number" ;;
        esac
      done
      [[ $(gh pr view "$number" --json headRefOid --jq .headRefOid) == "$gated_head" ]] && break
      problems=("${problems[@]:0:mark}")
      ((++attempts < 3)) || die "#$number: the head keeps changing while the reviewers are checked; rerun when the pushes stop"
      echo "merge-prs: #$number's head moved while its reviewers were checked; checking them again on the new head" >&2
    done
    gated_heads[$number]=$gated_head
    info=$(read_review "$number")
    IFS=$'\t' read -r open status reviewed head <<<"$info"
    ((open == 0)) || problems+=("#$number: $open unresolved review thread(s); answer and resolve them")
  done
  ((${#problems[@]} == 0)) && return 0
  if $check_only; then
    die "not ready:"$'\n'"$(printf '  %s\n' "${problems[@]}")"
  fi
  if $review_gate; then
    die "not merging:"$'\n'"$(printf '  %s\n' "${problems[@]}")"$'\n'"Rerun with --skip-review-gate only if the owner waived the reviewers; unresolved threads still block."
  fi
  die "not merging:"$'\n'"$(printf '  %s\n' "${problems[@]}")"
}

tmp_root=""
rebased_oid=""
wait_s=${MERGE_PRS_WAIT:-600}
poll_s=${MERGE_PRS_POLL:-10}
known_heads=()
# Head commits this run force-pushed, by branch. GitHub can keep reporting the old head for a moment after a push, so
# merging a PR rebased earlier in the run waits for this commit instead of trusting the first head GitHub reports.
declare -A pushed_heads=()
# The head each PR had when its reviewers passed. A head this run did not push must still be that one at merge time.
declare -A gated_heads=()
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

# Rebases a PR head onto origin/$base and force-pushes it, recording the new head in rebased_oid. With require_generated,
# a rebase that drops no generated-only commit means a real conflict, which stays with the owner.
rebase_head() {
  local pr=$1 head=$2 old=$3 base=$4 require_generated=$5 before after generated_dropped=0 msg
  tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/merge-prs.XXXXXX")
  git worktree add -q --detach "$tmp_root/wt" "$old" || die "cannot create a worktree for $head"
  before=$(git rev-list --count "origin/$base..$old")
  if ! rebase_dropping_generated "$old" "$base"; then
    git -C "$tmp_root/wt" rebase --abort >/dev/null 2>&1 || true
    remove_tmp
    die "#$pr conflicts with $base; rebase $head onto origin/$base by hand, then rerun for the remaining PRs"
  fi
  after=$(git -C "$tmp_root/wt" rev-list --count "origin/$base..HEAD")
  if $require_generated && ((generated_dropped == 0)); then
    remove_tmp
    die "#$pr conflicts with $base and carries no generated-only commits to drop; resolve it by hand, then rerun for the remaining PRs"
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
  die "#$1 is $2, not MERGED, after waiting ${wait_s}s; stopping"
}

# An interrupted earlier run already merged it; finish its local cleanup. Everything here needs the PR's head commit
# locally: without it the branch cannot be shown to hold nothing the PR lacks, so it is kept.
merge_pr_already_merged() {
  local pr=$1 head=$2 head_oid=$3
  echo "#$pr already merged"
  fetch
  if ! git cat-file -e "$head_oid^{commit}" 2>/dev/null; then
    echo "kept $head: the head of #$pr ($head_oid) is not available locally, so its local commits cannot be checked"
    return 0
  fi
  known_heads+=("$head_oid")
  $keep_branch || clean_local "$pr" "$head" "$head_oid"
}

# Runs the repo's .claude/pre-merge on a detached checkout of the PR head, so build output it commits lands in the PR and
# is merged with it. Sets head_oid to the head to merge: the script's commit, pushed and seen by GitHub, if it made one.
# The gate has already run by now, so a commit made here is never held to it. Not run by --check.
run_pre_merge() {
  local pr=$1 head=$2 base=$3 hook new_oid pre_merge_oid=$head_oid
  hook=$main_dir/.claude/pre-merge
  [[ -x $hook ]] || return 0
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
  local pr=$1 info head base state head_oid
  info=$(gh pr view "$pr" --json headRefName,headRefOid,baseRefName,state \
    --jq '[.headRefName, .headRefOid, .baseRefName, .state] | @tsv') || die "cannot read PR $pr"
  IFS=$'\t' read -r head head_oid base state <<<"$info"
  if [[ $state == MERGED ]]; then
    merge_pr_already_merged "$pr" "$head" "$head_oid"
    return 0
  fi
  [[ $state == OPEN ]] || die "PR $pr is $state"
  # A retarget after check_targets (during the review wait or an earlier merge) would otherwise merge it into the new base.
  [[ $base == "$default" ]] || die "#${pr#\#} was retargeted to $base, not $default; merge-prs only merges PRs into $default"
  if [[ -z ${pushed_heads[$head]:-} && -n ${gated_heads[${pr#\#}]:-} && $head_oid != "${gated_heads[${pr#\#}]}" ]]; then
    die "PR $pr was pushed to (${head_oid:0:7}) after its reviewers passed on ${gated_heads[${pr#\#}]:0:7}; rerun to check the new head"
  fi
  head_oid=${pushed_heads[$head]:-$head_oid}

  fetch
  known_heads+=("$head_oid")
  git cat-file -e "$head_oid^{commit}" 2>/dev/null || die "PR $pr head $head_oid is not on origin/$head"

  # A stale build commit makes the PR conflict with the base's newer build; rebasing without it, then rebuilding, fixes that.
  if [[ $(await_mergeable "$pr" "$head_oid") == CONFLICTING ]]; then
    rebase_head "$pr" "$head" "$head_oid" "$base" true
    head_oid=$rebased_oid
    known_heads+=("$head_oid")
    await_mergeable "$pr" "$head_oid" >/dev/null
  fi

  run_pre_merge "$pr" "$head" "$base"

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
  [[ $state == MERGED ]] || not_merged "$pr" "$state"
  echo "$pr merged ($method)"

  fetch
  ! $keep_branch || return 0
  clean_local "$pr" "$head" "$head_oid"
}

check_targets

if $check_only; then
  check_reviews
  if $review_gate; then
    echo "ready: no unresolved review threads and no gating reviewer running or failed"
  else
    echo "ready: no unresolved review threads (reviewer states skipped)"
  fi
  exit 0
fi

check_reviews

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
