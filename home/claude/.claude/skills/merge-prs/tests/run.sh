#!/usr/bin/env bash
# Replays the merge, refusal, conflict, pre-merge and review-gate cases against merge-prs.sh with a local origin and the
# fake gh.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../merge-prs.sh}
pass=0 fail=0
check() { if eval "$2"; then
  echo "ok   $1"
  pass=$((pass + 1))
else
  echo "FAIL $1"
  fail=$((fail + 1))
fi; }
g() { git -c user.name=t -c user.email=t@t "$@"; }
show() { while IFS= read -r line; do printf '   | %s\n' "$line"; done <<<"$1"; }

setup() {
  root=$(mktemp -d)
  export ORIGIN=$root/origin.git GH_STATE=$root/state
  git init -q --bare -b main "$ORIGIN"
  g clone -q "$ORIGIN" "$root/main" 2>/dev/null
  cd "$root/main" || exit 1
  echo a >a
  g add a
  g commit -qm A
  g push -q origin main
  g switch -qc child
  echo c >c
  g add c
  g commit -qm C
  g push -q origin child
  # Main moves on after the branch was cut, so the head is behind its base.
  g switch -q main
  echo p >p
  g add p
  g commit -qm "P (rebased)"
  g push -q origin main
  g switch -q child
  printf 'head=child\nbase=main\nstate=OPEN\n' >"$GH_STATE"
}

echo "== main checkout sitting on the PR branch"
setup
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "merges" "grep -q '^7 merged (rebase)' <<<\"\$out\""
check "switches the main checkout to main" "grep -q 'switched .* to main' <<<\"\$out\""
check "deletes the local branch" "! git -C '$root/main' show-ref -q --verify refs/heads/child"
check "pulls main" "grep -q '^pulled ' <<<\"\$out\""
check "main has A, P once and C" "[[ \$(git -C '$root/main' log --format=%s main) == \$'C\nP (rebased)\nA' ]]"

echo "== already-merged PR alone: cleanup still runs"
setup
sed -i 's/^state=OPEN/state=MERGED/' "$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "says it is already merged" "grep -q '^#7 already merged' <<<\"\$out\""
check "does not merge again" "! grep -q '^7 merged' <<<\"\$out\""
check "deletes the local branch" "! git -C '$root/main' show-ref -q --verify refs/heads/child"

echo "== already-merged PR first in the list: the rest still merges"
setup
printf 'head=gone-branch\nbase=main\nstate=MERGED\n' >"$GH_STATE.7"
mv "$GH_STATE" "$GH_STATE.8"
# Its head is gone from origin, so unpushed work on the local branch must survive.
g branch -q gone-branch main
g switch -q gone-branch
echo unpushed >unpushed
g add unpushed
g commit -qm unpushed
g switch -q child
out=$(PATH="$here:$PATH" "$script" 7 8 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "says #7 is already merged" "grep -q '^#7 already merged' <<<\"\$out\""
check "merges #8" "grep -q '^8 merged (rebase)' <<<\"\$out\""
check "deletes the local branch" "! git -C '$root/main' show-ref -q --verify refs/heads/child"
check "keeps the branch whose head is unavailable" "git -C '$root/main' show-ref -q --verify refs/heads/gone-branch"
check "says why it kept it" "grep -q 'kept gone-branch: the head of #7' <<<\"\$out\""

echo "== already-merged PR: an unrelated open PR is not reported"
setup
printf 'head=gone-branch\nbase=main\nstate=MERGED\n' >"$GH_STATE.7"
mv "$GH_STATE" "$GH_STATE.8"
g branch -q gone-branch main
g push -q origin gone-branch
g switch -q -c unrelated main
echo u >u
g add u
g commit -qm U
g push -q origin unrelated
printf 'head=unrelated\nbase=main\nstate=OPEN\n' >"$GH_STATE.9"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
show "$out"
check "no warning" "! grep -q warning <<<\"\$out\""

echo "== closed PR is still refused"
setup
sed -i 's/^state=OPEN/state=CLOSED/' "$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "names the state" "grep -q 'PR 7 is CLOSED' <<<\"\$out\""

echo "== PR based on another branch is refused"
setup
sed -i 's/^base=main/base=parent/' "$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "says the base is not main" "grep -q '#7 is based on parent, not main' <<<\"\$out\""
check "does not merge" "grep -q '^state=OPEN' '$GH_STATE'"

echo "== PR retargeted after the up-front check is refused"
setup
echo merge_base=parent >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "says it was retargeted" "grep -q '#7 was retargeted to parent, not main' <<<\"\$out\""
check "does not merge" "grep -q '^state=OPEN' '$GH_STATE'"

echo "== fork PR is refused"
setup
echo cross=true >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "says it is from a fork" "grep -q '#7 is from a fork' <<<\"\$out\""
check "does not merge" "grep -q '^state=OPEN' '$GH_STATE'"
setup
printf 'cross=true\n' >>"$GH_STATE"
sed -i 's/^state=OPEN/state=MERGED/' "$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "refuses a merged fork PR too" "[[ $code != 0 ]] && grep -q '#7 is from a fork' <<<\"\$out\""
check "keeps the local branch" "git -C '$root/main' show-ref -q --verify refs/heads/child"

echo "== main held by another worktree"
setup
g worktree add -q "$root/elsewhere" main
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "merges" "grep -q '^7 merged (rebase)' <<<\"\$out\""
check "keeps the branch with a reason" "grep -q 'kept branch child: .*could not switch' <<<\"\$out\""

echo "== conflict with main"
setup
printf 'conflicting_oid=%s\n' "$(git rev-parse child)" >>"$GH_STATE"
before=$(git -C "$ORIGIN" rev-parse child)
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "names the conflict" "grep -q 'conflicts with main' <<<\"\$out\""
check "leaves the PR branch untouched" "[[ \$(git -C '$ORIGIN' rev-parse child) == '$before' ]]"
check "keeps the PR open" "grep -q '^state=OPEN' '$GH_STATE'"

echo "== review gate: unresolved thread"
setup
echo "open_threads=2" >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "names the threads" "grep -q '#7: 2 unresolved review thread' <<<\"\$out\""
check "keeps the PR open" "grep -q '^state=OPEN' '$GH_STATE'"

echo "== review gate: Codex review failed"
setup
printf 'codex=Failed\ncodex_commit=abc1234\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "says how to rerun Codex" "grep -q '@codex review' <<<\"\$out\""

echo "== review gate: Codex review of an older commit"
setup
printf 'codex=Completed\ncodex_commit=abc1234\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "notes the unreviewed commits" "grep -q 'covers abc1234, not the head' <<<\"\$out\""

echo "== review gate: only fixes since the Codex review"
setup
printf 'codex=Completed\ncodex_commit=abc1234\nreviewed_subjects=feat: add x\nhead_subjects=feat: add x;fix(x): handle y;test: cover y\nreviewed_files=a;b\nhead_files=a;b\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "notes the fixes" "grep -q 'only fix files it reviewed' <<<\"\$out\""
check "does not request a review" "! grep -q '^commented=' '$GH_STATE'"

echo "== review gate: generated-only commit since the Codex review"
setup
mkdir -p .claude
printf '# build output\n\npublic/\nmin/\n' >.claude/generated-paths
printf 'codex=Completed\ncodex_commit=abc1234\nreviewed_subjects=feat: add x\nhead_subjects=feat: add x;build: rebuild public\nreviewed_files=a\nhead_files=a;public/x.js;min/y.js\ncommit_files_c2=public/x.js;min/y.js\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "notes the generated paths" "grep -q 'only fix files it reviewed or touch generated paths' <<<\"\$out\""

echo "== review gate: generated and other files in one commit since the Codex review"
setup
mkdir -p .claude
printf 'public/\n' >.claude/generated-paths
printf 'codex=Completed\ncodex_commit=abc1234\nreviewed_subjects=feat: add x\nhead_subjects=feat: add x;build: rebuild public\nreviewed_files=a\nhead_files=a;public/x.js;c\ncommit_files_c2=public/x.js;c\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "names the commit" "grep -q '\"build: rebuild public\" is not a fix' <<<\"\$out\""

echo "== review gate: a fix that also adds generated files"
setup
mkdir -p .claude
printf 'public/\n' >.claude/generated-paths
printf 'codex=Completed\ncodex_commit=abc1234\nreviewed_subjects=feat: add x\nhead_subjects=feat: add x;fix: y\nreviewed_files=a\nhead_files=a;public/x.js\ncommit_files_c2=a;public/x.js\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" --check 7 2>&1)
code=$?
show "$out"
check "passes" "[[ $code == 0 ]]"
check "does not note generated-only commits" "! grep -q 'touch generated paths' <<<\"\$out\""

echo "== review gate: no generated-paths file leaves a build commit gated"
setup
printf 'codex=Completed\ncodex_commit=abc1234\nreviewed_subjects=feat: add x\nhead_subjects=feat: add x;build: rebuild public\nreviewed_files=a\nhead_files=a;public/x.js\ncommit_files_c2=public/x.js\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "names the commit" "grep -q '\"build: rebuild public\" is not a fix' <<<\"\$out\""

echo "== review gate: new work since the Codex review"
setup
printf 'codex=Completed\ncodex_commit=abc1234\nreviewed_subjects=feat: add x\nhead_subjects=feat: add x;feat: add z\nreviewed_files=a\nhead_files=a\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "names the new work" "grep -q '\"feat: add z\" is not a fix' <<<\"\$out\""
check "keeps the PR open" "grep -q '^state=OPEN' '$GH_STATE'"

echo "== review gate: a fix that reaches a new file"
setup
printf 'codex=Completed\ncodex_commit=abc1234\nreviewed_subjects=feat: add x\nhead_subjects=feat: add x;fix: y\nreviewed_files=a\nhead_files=a;c\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" --check 7 2>&1)
code=$?
show "$out"
check "fails" "[[ $code != 0 ]]"
check "names the file" "grep -q 'c was not in the reviewed changes' <<<\"\$out\""
check "does not request a review under --check" "! grep -q '^commented=' '$GH_STATE'"
check "names the --check rerun that requests one" "grep -q 'rerun with --check --wait-review --request-review' <<<\"\$out\""

echo "== --wait-review: new work gets a review requested and waited for"
setup
printf 'codex=Completed\ncodex_commit=abc1234\nreviewed_subjects=feat: add x\nhead_subjects=feat: add x;feat: add z\nreviewed_files=a\nhead_files=a\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" MERGE_PRS_REVIEW_POLL=0 timeout 30 "$script" --wait-review 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "requests a review" "grep -q '^commented=1' '$GH_STATE'"
check "merges" "grep -q '^7 merged (rebase)' <<<\"\$out\""

echo "== --check --wait-review --request-review: new work gets a review requested, nothing merged"
setup
printf 'codex=Completed\ncodex_commit=abc1234\nreviewed_subjects=feat: add x\nhead_subjects=feat: add x;feat: add z\nreviewed_files=a\nhead_files=a\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" MERGE_PRS_REVIEW_POLL=0 timeout 30 "$script" --check --wait-review --request-review 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "requests a review" "grep -q '^commented=1' '$GH_STATE'"
check "does not merge" "! grep -q 'merged' <<<\"\$out\""

echo "== review gate: reviewer states skipped by the owner, threads clean"
setup
printf 'codex=Running\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" --skip-review-gate 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "merges past a running review" "grep -q '^7 merged (rebase)' <<<\"\$out\""
check "requests nothing" "! grep -q '^commented' '$GH_STATE'"

echo "== --check: clean PR"
setup
out=$(PATH="$here:$PATH" "$script" --check 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "does not merge" "grep -q '^state=OPEN' '$GH_STATE' && ! grep -q merged <<<\"\$out\""

echo "== --check: unresolved thread"
setup
echo "open_threads=2" >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" --check 7 2>&1)
code=$?
show "$out"
check "fails" "[[ $code != 0 ]]"
check "names the threads" "grep -q '#7: 2 unresolved review thread' <<<\"\$out\""
check "does not merge" "grep -q '^state=OPEN' '$GH_STATE'"

echo "== --check: Codex review running"
setup
printf 'codex=Running\ncodex_commit=abc1234\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" --check 7 2>&1)
code=$?
show "$out"
check "fails" "[[ $code != 0 ]]"
check "says the review is running" "grep -q '#7: the Codex review is still running' <<<\"\$out\""
check "does not merge" "grep -q '^state=OPEN' '$GH_STATE'"

echo "== --check: fresh PR that Codex has not started on"
setup
printf 'codex=Pending\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" --check 7 2>&1)
code=$?
show "$out"
check "fails" "[[ $code != 0 ]]"
check "says Codex has not started" "grep -q '#7: opened under 300s ago and Codex has not started on it' <<<\"\$out\""

echo "== --wait-review: Codex starts and finishes on a fresh PR"
setup
printf 'codex_pending_reads=2\ncodex_commit=abc1234\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" MERGE_PRS_REVIEW_POLL=0 "$script" --check --wait-review 7 2>&1)
code=$?
show "$out"
check "passes" "[[ $code == 0 ]]"
check "says it is waiting" "grep -q 'waiting up to' <<<\"\$out\""

echo "== --wait-review: Codex never starts on a fresh PR"
setup
printf 'codex_pending_reads=99\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" MERGE_PRS_REVIEW_POLL=0 MERGE_PRS_REVIEW_WAIT=1 timeout 30 "$script" --check --wait-review 7 2>&1)
code=$?
show "$out"
check "fails" "[[ $code != 0 ]]"
check "says no review came" "grep -q '#7: still no Codex review after' <<<\"\$out\""

echo "== --wait-review: a fresh PR in a repo without Codex passes once the window is over"
setup
printf 'codex_pending_reads=1\n' >>"$GH_STATE"
# The fake reports Completed after the pending reads; this repo has no Codex, so report none instead.
sed -i 's/^codex_pending_reads=1$/codex_pending_reads=1\nno_codex=1/' "$GH_STATE"
out=$(PATH="$here:$PATH" MERGE_PRS_REVIEW_POLL=0 "$script" --check --wait-review 7 2>&1)
code=$?
show "$out"
check "passes" "[[ $code == 0 ]]"

echo "== review_jq: Codex status with no summary comment"
# The jq the gate runs on GitHub's answer, taken from the script so the fake gh cannot stand in for it.
review_defs=$(sed -n '/^review_start_s=/,/^review_poll_s=/p' "$script")
pr_json() {
  jq -n --arg created "$1" --argjson reactions "$2" --arg body "${3:-hi}" \
    '{data: {repository: {pullRequest: {headRefOid: "abc", createdAt: $created, reviewThreads: {nodes: []},
      comments: {nodes: [{body: $body}]}, reactions: {nodes: $reactions}}}}}'
}
# shellcheck disable=SC2154 # review_jq comes from the eval of the script's definitions.
review_status() { (eval "$review_defs" && jq -r "$review_jq" | cut -f2); }
review_jq_commit() { (eval "$review_defs" && jq -r "$review_jq" | cut -f3); }
fresh=$(date -u -d '-30 sec' +%FT%TZ)
old=$(date -u -d '-1 hour' +%FT%TZ)
codex_eyes='[{"user": {"login": "chatgpt-codex-connector[bot]"}}]'
check "a fresh PR is Pending" "[[ \$(pr_json '$fresh' '[]' | review_status) == Pending ]]"
check "an old PR is none" "[[ \$(pr_json '$old' '[]' | review_status) == none ]]"
check "Codex's eyes are Running" "[[ \$(pr_json '$old' '$codex_eyes' | review_status) == Running ]]"
check "a person's eyes are not" "[[ \$(pr_json '$fresh' '[{\"user\": {\"login\": \"someone\"}}]' | review_status) == Pending ]]"
check "a reaction from a deleted account is skipped" "[[ \$(pr_json '$old' '[{\"user\": null}]' | review_status) == none ]]"
# shellcheck disable=SC2016,SC2034 # The backticks are the table's own markdown; the check strings eval the variable.
with_commit_body='codex-pull-request-review-summary | **Completed** | `abc1234` |'
check "a summary comment wins over the eyes" "[[ \$(pr_json '$fresh' '$codex_eyes' \"\$with_commit_body\" | review_status) == Completed ]]"
out=$(MERGE_PRS_REVIEW_START=5m PATH="$here:$PATH" "$script" --check 7 2>&1)
check "a window that is not seconds is refused by name" "grep -q 'MERGE_PRS_REVIEW_START must be a number of seconds' <<<\"\$out\""

echo "== review_jq: a Completed summary with no commit"
# Codex's summary for an unreviewed PR: Completed, an em dash in the Commit column.
no_commit_body='codex-pull-request-review-summary | **Completed** | — |'
check "no commit is Unreviewed" "[[ \$(pr_json '$old' '[]' '$no_commit_body' | review_status) == Unreviewed ]]"
check "a commit is still Completed" "[[ \$(pr_json '$old' '[]' \"\$with_commit_body\" | review_status) == Completed ]]"
check "a Failed summary with no commit stays Failed" "[[ \$(pr_json '$old' '[]' 'codex-pull-request-review-summary | **Failed** | — |' | review_status) == Failed ]]"

echo "== review gate: Codex completed without a commit, --check"
setup
printf 'codex=Completed\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" --check 7 2>&1)
code=$?
show "$out"
check "fails" "[[ $code != 0 ]]"
check "names the review request" "grep -q '@codex review' <<<\"\$out\""
check "posts no comment" "! grep -q '^commented=' '$GH_STATE'"
check "does not try to compare" "! grep -q 'cannot compare' <<<\"\$out\""

echo "== --wait-review: Codex completed without a commit gets a review requested"
setup
printf 'codex=Completed\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" MERGE_PRS_REVIEW_POLL=0 timeout 30 "$script" --wait-review 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "requests a review" "grep -q '^commented=1' '$GH_STATE'"
check "merges" "grep -q '^7 merged (rebase)' <<<\"\$out\""

echo "== --wait-review: the first wait runs out on a Running review that ends Unreviewed"
setup
printf 'codex_running_reads=2\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" MERGE_PRS_REVIEW_POLL=1 MERGE_PRS_REVIEW_WAIT=2 timeout 60 "$script" --wait-review 7 2>&1)
code=$?
show "$out"
check "requests a review" "grep -q '^commented=1' '$GH_STATE'"
check "waits for the requested review and merges" "[[ $code == 0 ]] && grep -q '^7 merged (rebase)' <<<\"\$out\""

echo "== --wait-review: Codex keeps answering without a commit"
setup
printf 'codex=Completed\ncodex_never_reviews=1\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" MERGE_PRS_REVIEW_POLL=0 MERGE_PRS_REVIEW_WAIT=1 timeout 30 "$script" --check --wait-review --request-review 7 2>&1)
code=$?
show "$out"
check "fails" "[[ $code != 0 && $code != 124 ]]"
check "says Codex has not reviewed" "grep -q 'Codex has not reviewed the head .* after [0-9]*s' <<<\"\$out\""
check "comments exactly once" "[[ \$(grep -c '@codex review' <<<\"\$out\") -le 1 ]] && grep -q '^commented=1' '$GH_STATE'"

echo "== --wait-review: Codex review finishes while waiting"
setup
printf 'codex_running_reads=2\ncodex_commit=abc1234\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" MERGE_PRS_REVIEW_POLL=0 "$script" --check --wait-review 7 2>&1)
code=$?
show "$out"
check "passes" "[[ $code == 0 ]]"
check "says it is waiting" "grep -q 'waiting up to' <<<\"\$out\""

echo "== --wait-review: Codex review outlasts the wait"
setup
printf 'codex_running_reads=99\ncodex_commit=abc1234\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" MERGE_PRS_REVIEW_POLL=0 MERGE_PRS_REVIEW_WAIT=1 timeout 30 "$script" --check --wait-review 7 2>&1)
code=$?
show "$out"
check "fails" "[[ $code != 0 ]]"
check "stops at the limit even with a zero poll interval" "[[ $code != 124 ]] && grep -q 'still running after [0-9]*s' <<<\"\$out\""

# Installs .claude/pre-merge in the main checkout from the given body; each run logs its environment to $root/env.
# shellcheck disable=SC2016 # The single-quoted text is the hook script's own source.
pre_merge_hook() {
  mkdir -p .claude
  {
    printf '#!/usr/bin/env bash\nset -e\n'
    printf 'echo "$MERGE_PRS_PR $MERGE_PRS_BRANCH $MERGE_PRS_BASE $MERGE_PRS_REPO_ROOT $PWD" >>"%s/env"\n' "$root"
    printf 'echo hook ran\n%s\n' "$1"
  } >.claude/pre-merge
  chmod +x .claude/pre-merge
}
# shellcheck disable=SC2016
commit_build='echo built >"built-$MERGE_PRS_BRANCH"; git add .; git -c user.name=t -c user.email=t@t commit -qm "build: $MERGE_PRS_BRANCH"'

echo "== pre-merge: no script"
setup
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "does not mention pre-merge" "! grep -q pre-merge <<<\"\$out\""

echo "== pre-merge: script that commits"
setup
pre_merge_hook "$commit_build"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "announces the step and streams the output" "grep -q '^merge-prs: pre-merge #7' <<<\"\$out\" && grep -q '^hook ran' <<<\"\$out\""
check "gives the script its environment" "[[ \$(cut -d' ' -f1-4 '$root/env') == '7 child main $root/main' ]] && [[ \$(cut -d' ' -f5 '$root/env') != '$root/main' ]]"
check "merges" "grep -q '^7 merged (rebase)' <<<\"\$out\""
check "merged the pre-merge commit" "[[ \$(git -C '$ORIGIN' log --format=%s main | head -n 1) == 'build: child' ]]"
check "removes the temporary worktree" "[[ \$(git worktree list | wc -l) == 1 ]]"

echo "== pre-merge: script that changes nothing"
setup
pre_merge_hook "true"
before=$(git -C "$ORIGIN" rev-parse child)
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "runs the script" "grep -q '^hook ran' <<<\"\$out\""
check "merges" "grep -q '^7 merged (rebase)' <<<\"\$out\""
check "adds no commit" "! grep -q 'pre-merge committed' <<<\"\$out\" && [[ \$(git -C '$ORIGIN' log --format=%s main | head -n 1) == C ]]"

echo "== pre-merge: script that fails"
setup
pre_merge_hook "echo boom; exit 3"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "names the PR" "grep -q 'pre-merge step failed on #7' <<<\"\$out\""
check "shows the output" "grep -q '^boom' <<<\"\$out\""
check "does not merge" "grep -q '^state=OPEN' '$GH_STATE'"
check "removes the temporary worktree" "[[ \$(git worktree list | wc -l) == 1 ]]"

echo "== pre-merge: --check never runs it"
setup
pre_merge_hook "$commit_build"
out=$(PATH="$here:$PATH" "$script" --check 7 2>&1)
code=$?
show "$out"
check "passes" "[[ $code == 0 ]]"
check "does not run the script" "[[ ! -e '$root/env' ]]"

# A repo whose src the pre-merge step minifies into out/src.min, a generated path. Source lines 2 and 7 are far enough
# apart for two PRs to edit them without a source conflict, while both rebuild the one line of out/src.min.
# shellcheck disable=SC2016
minify='mkdir -p out; tr "\n" " " <src >out/src.min; git add -A out; git diff --cached --quiet || git -c user.name=t -c user.email=t@t commit -qm "build: minify"'
init_build_repo() {
  root=$(mktemp -d)
  export ORIGIN=$root/origin.git GH_STATE=$root/state
  git init -q --bare -b main "$ORIGIN"
  g clone -q "$ORIGIN" "$root/main" 2>/dev/null
  cd "$root/main" || exit 1
  printf '1\n2\n3\n4\n5\n6\n7\n8\n' >src
  mkdir out
  tr '\n' ' ' <src >out/src.min
  g add -A
  g commit -qm A
  g push -q origin main
  : >"$GH_STATE"
  printf '.claude\n' >>.git/info/exclude
  mkdir -p .claude
  printf 'out/\n' >.claude/generated-paths
  pre_merge_hook "$minify"
}
edit_src() {
  sed -i "s/^$1\$/$2/" src
  g commit -qam "$3"
}

echo "== pre-merge: a head behind its base is rebased before the build"
init_build_repo
g switch -qc a main
edit_src 2 2a "feat: a"
g push -q origin a
g switch -qc c main
edit_src 7 7c "feat: c"
g push -q origin c
g switch -q main
printf 'head=a\nbase=main\nstate=OPEN\nreal_merge=1\n' >"$GH_STATE.7"
printf 'head=c\nbase=main\nstate=OPEN\nreal_merge=1\n' >"$GH_STATE.8"
out=$(PATH="$here:$PATH" "$script" 7 8 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "rebases #8 onto the merged #7" "grep -q '^#8 rebased onto main' <<<\"\$out\""
check "merges both" "grep -q '^7 merged (rebase)' <<<\"\$out\" && grep -q '^8 merged (rebase)' <<<\"\$out\""
check "main has both builds and both edits" "[[ \$(git -C '$ORIGIN' log --format=%s main) == \$'build: minify\nfeat: c\nbuild: minify\nfeat: a\nA' ]]"
check "the output matches the merged source" "[[ \$(git -C '$ORIGIN' show main:out/src.min) == \$(git -C '$ORIGIN' show main:src | tr '\n' ' ') ]]"

echo "== pre-merge: a branch carrying an outdated build commit is recovered"
init_build_repo
g switch -qc c main
edit_src 7 7c "feat: c"
eval "$minify"
g push -q origin c
g switch -q main
edit_src 2 2a "feat: a"
eval "$minify"
g push -q origin main
printf 'head=c\nbase=main\nstate=OPEN\nreal_merge=1\n' >"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "drops the generated-only commit" "grep -q 'dropping 1 generated-only commit(s) the pre-merge step rebuilds' <<<\"\$out\""
check "the output matches the merged source" "[[ \$(git -C '$ORIGIN' show main:out/src.min) == \$(git -C '$ORIGIN' show main:src | tr '\n' ' ') ]]"

echo "== pre-merge: GitHub still reporting the old head is not taken for a settled state"
setup
pre_merge_hook "$commit_build"
printf 'lag_reads=99\nstale_oid=%s\n' "$(git rev-parse child)" >>"$GH_STATE"
out=$(PATH="$here:$PATH" MERGE_PRS_MERGEABLE_WAIT=1 timeout 60 "$script" 7 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ $code != 0 && $code != 124 ]]"
check "says GitHub has not caught up" "grep -q 'GitHub has not caught up' <<<\"\$out\""
check "does not merge" "grep -q '^state=OPEN' '$GH_STATE'"

echo "== --check: refuses merge options"
setup
out=$(PATH="$here:$PATH" "$script" --check --keep-branch 7 2>&1)
code=$?
show "$out"
check "fails" "[[ $code != 0 ]]"
check "says why" "grep -q 'cannot be combined' <<<\"\$out\""

# ---- The reviewer gate: which reviewers are waited for, and each one's state.
# The registry is the built-in one only; a test that needs a repo layer writes .claude/reviewers.json in the main checkout.
iso() { date -u -d "$1" +%FT%TZ; }
head_of() { git -C "$ORIGIN" rev-parse child; }
# Gate tests start from setup; history_logins=none leaves CodeRabbit the only reviewer inferred unless a test says more.
gate_setup() {
  setup
  printf 'history_logins=none\n' >>"$GH_STATE"
}
# A CodeRabbit repo whose head was pushed $1 ago.
cr_setup() {
  gate_setup
  printf 'suites=coderabbitai\nhead_date=%s\n' "$(iso "-$1")" >>"$GH_STATE"
}
# The head's CodeRabbit check run: status, conclusion, started and completed (minutes ago, empty for none).
cr_run() {
  printf 'cr_run=CodeRabbit|%s|%s|%s|%s\n' "$1" "$2" "$(iso "-$3")" "$([[ -z $4 ]] || iso "-$4")" >>"$GH_STATE"
}
cr_reviewed_head() { printf 'cr_reviews=coderabbitai[bot]|%s\n' "$(head_of)" >>"$GH_STATE"; }
comment() { printf '{"login":"%s","created_at":"%s","body":"%s"}\n' "$1" "$(iso "$2")" "$3" >>"$GH_STATE.comments"; }
gate() {
  out=$(PATH="$here:$PATH" MERGE_PRS_REVIEW_POLL=0 MERGE_PRS_REVIEW_WAIT=${WAIT:-1} timeout 60 "$script" "$@" 2>&1)
  code=$?
  show "$out"
}

echo "== gate: both reviewers Done merges"
cr_setup "30 min"
printf 'history_logins=chatgpt-codex-connector\ncodex=Completed\ncodex_commit=%s\n' "$(head_of | cut -c1-7)" >>"$GH_STATE"
cr_run completed success "25 min" "20 min"
cr_reviewed_head
gate 7
check "merges" "[[ $code == 0 ]] && grep -q '^7 merged (rebase)' <<<\"\$out\""

echo "== gate: CodeRabbit running blocks"
cr_setup "30 min"
cr_run in_progress "" "25 min" ""
gate --check 7
check "fails naming CodeRabbit" "[[ $code != 0 ]] && grep -q '#7: the CodeRabbit check is in_progress' <<<\"\$out\""

echo "== gate: --wait-review passes once CodeRabbit finishes"
cr_setup "30 min"
cr_run completed success "25 min" "20 min"
cr_reviewed_head
printf 'cr_running_reads=2\ncr_run_running=CodeRabbit|in_progress||%s|\n' "$(iso '-25 min')" >>"$GH_STATE"
# A wait that cannot run out under load: the reads, not the clock, end it.
WAIT=600 gate --check --wait-review 7
check "passes" "[[ $code == 0 ]] && grep -q '^ready:' <<<\"\$out\""
check "polled, since the first reads were running" "grep -q '^cr_running_reads=0' '$GH_STATE'"

echo "== gate: CodeRabbit rate-limited, no check run"
cr_setup "30 min"
comment 'coderabbitai[bot]' '-5 min' 'Rate limit exceeded, please try again later'
gate 7
check "notes it and merges" "[[ $code == 0 ]] && grep -q 'note: #7 CodeRabbit posted that it is unavailable' <<<\"\$out\" && grep -q '^7 merged' <<<\"\$out\""

echo "== gate: CodeRabbit check conclusions that are unavailable or failed"
cr_setup "30 min"
cr_run completed skipped "25 min" "20 min"
gate --check 7
check "skipped is unavailable, a note" "[[ $code == 0 ]] && grep -q 'its check concluded skipped' <<<\"\$out\""
for failed_conclusion in failure timed_out; do
  cr_setup "30 min"
  cr_run completed $failed_conclusion "25 min" "20 min"
  gate --check 7
  check "$failed_conclusion blocks as failed" "[[ $code != 0 ]] && grep -q 'concluded $failed_conclusion' <<<\"\$out\""
done

echo "== gate: Codex failed next to a usage-limit comment"
cr_setup "30 min"
printf 'history_logins=chatgpt-codex-connector\ncodex=Failed\ncodex_commit=abc1234\n' >>"$GH_STATE"
cr_run completed success "25 min" "20 min"
cr_reviewed_head
comment 'chatgpt-codex-connector[bot]' '-5 min' 'You have reached your Codex usage limits for code reviews.'
gate 7
check "Codex is skipped with a note and the PR merges" "[[ $code == 0 ]] && grep -q 'note: #7 Codex is unavailable' <<<\"\$out\" && grep -q '^7 merged' <<<\"\$out\""

echo "== gate: Codex failed alone"
gate_setup
printf 'history_logins=chatgpt-codex-connector\ncodex=Failed\ncodex_commit=abc1234\n' >>"$GH_STATE"
gate 7
check "blocks" "[[ $code != 0 ]] && grep -q 'the Codex review failed' <<<\"\$out\""

echo "== gate: a usage-limit comment older than the head is ignored"
gate_setup
printf 'history_logins=chatgpt-codex-connector\ncodex=Failed\ncodex_commit=abc1234\nhead_date=%s\n' "$(iso '-1 min')" >>"$GH_STATE"
comment 'chatgpt-codex-connector[bot]' '-30 min' 'You have reached your Codex usage limits for code reviews.'
gate 7
check "still blocks" "[[ $code != 0 ]] && grep -q 'the Codex review failed' <<<\"\$out\""

echo "== gate: Codex failed gets one re-request under --wait-review"
gate_setup
printf 'history_logins=chatgpt-codex-connector\ncodex=Failed\ncodex_commit=abc1234\n' >>"$GH_STATE"
gate --wait-review 7
check "comments @codex review and then merges" "[[ $code == 0 ]] && grep -q '^commented=1' '$GH_STATE' && grep -q '^7 merged' <<<\"\$out\""

echo "== gate: a reviewer that never started"
cr_setup "30 min"
gate --check 7
check "past start_s it is a note" "[[ $code == 0 ]] && grep -q 'note: #7 CodeRabbit has no check on the head' <<<\"\$out\""
cr_setup "30 sec"
gate --check 7
check "within start_s it is pending" "[[ $code != 0 ]] && grep -q '#7: no CodeRabbit check on the head yet' <<<\"\$out\""
gate_setup
printf 'history_logins=chatgpt-codex-connector\ncodex=none\n' >>"$GH_STATE"
gate --check 7
check "Codex past its window is a note" "[[ $code == 0 ]] && grep -q 'note: #7 Codex has not started' <<<\"\$out\""

echo "== gate: unresolved threads block when the reviewer states are skipped or unavailable"
gate_setup
echo "open_threads=2" >>"$GH_STATE"
gate --skip-review-gate 7
check "--skip-review-gate still stops on threads" "[[ $code != 0 ]] && grep -q '#7: 2 unresolved review thread' <<<\"\$out\""
check "and leaves the PR open" "grep -q '^state=OPEN' '$GH_STATE'"
cr_setup "30 min"
comment 'coderabbitai[bot]' '-5 min' 'Review skipped: rate limit'
echo "open_threads=1" >>"$GH_STATE"
gate --check 7
check "an unavailable reviewer does not excuse threads" "[[ $code != 0 ]] && grep -q '#7: 1 unresolved review thread' <<<\"\$out\" && grep -q 'unavailable' <<<\"\$out\""

echo "== gate: --check --skip-review-gate is allowed"
gate_setup
printf 'codex=Running\n' >>"$GH_STATE"
gate --check --skip-review-gate 7
check "passes without reading reviewers" "[[ $code == 0 ]] && grep -q 'reviewer states skipped' <<<\"\$out\""
gate --check --keep-branch 7
check "--keep-branch is still refused" "[[ $code != 0 ]] && grep -q 'cannot be combined' <<<\"\$out\""

echo "== gate inference: which reviewers are waited for"
cr_setup "30 sec"
gate --check 7
check "an app with a check suite gates" "[[ $code != 0 ]] && grep -q 'CodeRabbit' <<<\"\$out\""
gate_setup
gate --check 7
check "no suite: not waited for" "[[ $code == 0 ]]"
gate_setup
printf 'history_logins=chatgpt-codex-connector\ncodex=Running\n' >>"$GH_STATE"
gate --check 7
check "a comment-only bot seen in recent PRs gates" "[[ $code != 0 ]] && grep -q 'the Codex review is still running' <<<\"\$out\""
gate_setup
printf 'codex=Running\n' >>"$GH_STATE"
gate --check 7
check "a comment-only bot not seen is not waited for" "[[ $code == 0 ]]"
gate_setup
printf 'history_logins=someone;chatgpt-codex-connector[bot]\ncodex=Running\n' >>"$GH_STATE"
gate --check 7
check "a [bot] author name still matches" "[[ $code != 0 ]]"
cr_setup "30 sec"
mkdir -p "$root/main/.claude"
echo '{"reviewers":[{"name":"coderabbit","gate":"never"}]}' >"$root/main/.claude/reviewers.json"
gate --check 7
check "never skips it even with the suite" "[[ $code == 0 ]]"
gate_setup
printf 'head_date=%s\n' "$(iso '-30 sec')" >>"$GH_STATE"
mkdir -p "$root/main/.claude"
echo '{"reviewers":[{"name":"coderabbit","gate":"always"}]}' >"$root/main/.claude/reviewers.json"
gate --check 7
check "always waits though nothing shows it installed" "[[ $code != 0 ]] && grep -q 'no CodeRabbit check on the head yet' <<<\"\$out\""
gate_setup
printf 'suites=claude;vercel\ncodex=Running\n' >>"$GH_STATE"
gate --check 7
check "the claude and vercel suites do not gate" "[[ $code == 0 ]]"
cr_setup "30 sec"
printf 'suites=%s;coderabbitai\n' "$(seq -f 'app%g' 1 34 | paste -sd ';')" >>"$GH_STATE"
gate --check 7
check "a suite on the second page is found" "[[ $code != 0 ]] && grep -q 'CodeRabbit' <<<\"\$out\""

echo "== gate: CodeRabbit done signal"
cr_setup "30 min"
cr_run completed success "25 min" "30 sec"
comment 'coderabbitai[bot]' '-1 min' "<!-- final_review_risk_coverage {\\\"coveredCommitId\\\":\\\"$(head_of)\\\"} -->"
gate --check 7
check "success inside the settle window is not done" "[[ $code != 0 ]] && grep -q 'waiting 180s for a review' <<<\"\$out\""
cr_setup "30 min"
cr_run completed success "25 min" "10 min"
comment 'coderabbitai[bot]' '-9 min' "<!-- final_review_risk_coverage {\\\"coveredCommitId\\\":\\\"$(head_of)\\\"} -->"
gate --check 7
check "after the settle window it is done" "[[ $code == 0 ]]"
cr_setup "30 min"
cr_run completed success "25 min" "5 sec"
cr_reviewed_head
gate --check 7
check "a review of the head ends the wait at once" "[[ $code == 0 ]]"
cr_setup "30 min"
cr_run completed success "25 min" "5 sec"
cr_reviewed_head
echo "open_threads=3" >>"$GH_STATE"
gate --check 7
check "findings that arrive as threads still block" "[[ $code != 0 ]] && grep -q '#7: 3 unresolved review thread' <<<\"\$out\""
cr_setup "30 min"
cr_run completed success "25 min" "10 min"
comment 'coderabbitai[bot]' '-9 min' "<!-- final_review_risk_coverage {\\\"coveredCommitId\\\":\\\"1111111111111111111111111111111111111111\\\"} -->"
gate --check 7
check "a marker covering an older commit blocks" "[[ $code != 0 ]] && grep -q 'summary covers 1111111, not the head' <<<\"\$out\""
cr_setup "30 min"
cr_run completed success "25 min" "10 min"
gate --check 7
check "no marker at all falls back to check plus settle" "[[ $code == 0 ]]"
cr_setup "30 min"
cr_run completed success "25 min" "30 sec"
gate --check 7
check "and inside the settle window it waits" "[[ $code != 0 ]]"

echo "== gate: unclassified CodeRabbit conclusions"
cr_setup "3 min"
cr_run completed cancelled "2 min" "1 min"
gate --check 7
check "a cancelled run is pending while a new one may replace it" "[[ $code != 0 ]] && grep -q 'was cancelled; a new run should replace it' <<<\"\$out\""
cr_setup "30 min"
cr_run completed cancelled "25 min" "20 min"
gate --check 7
check "after start_s it has failed" "[[ $code != 0 ]] && grep -q 'was cancelled and no new run replaced it' <<<\"\$out\""
cr_setup "30 min"
cr_run completed cancelled "25 min" "20 min"
printf 'cr_after=CodeRabbit|completed|success|%s|%s\n' "$(iso '-15 min')" "$(iso '-10 min')" >>"$GH_STATE"
gate --wait-review 7
check "--wait-review asks once and then passes" "[[ $code == 0 ]] && grep -q '^commented_cr=1' '$GH_STATE' && grep -q '^7 merged' <<<\"\$out\""
cr_setup "30 min"
cr_run completed cancelled "25 min" "20 min"
gate --check --wait-review 7
check "--check never comments without --request-review" "[[ $code != 0 ]] && ! grep -q '^commented_cr' '$GH_STATE'"
cr_setup "30 min"
cr_run completed action_required "25 min" "20 min"
gate --wait-review 7
check "action_required needs the owner and is never re-requested" "[[ $code != 0 ]] && grep -q 'needs owner action' <<<\"\$out\" && ! grep -q '^commented_cr' '$GH_STATE'"
cr_setup "30 min"
cr_run completed startup_failure "25 min" "20 min"
gate --check 7
check "an unknown conclusion fails with its value" "[[ $code != 0 ]] && grep -q 'concluded startup_failure' <<<\"\$out\""

echo "== gate: a cancelled run that the done signal covers"
cr_setup "30 min"
cr_run completed cancelled "25 min" "20 min"
cr_reviewed_head
gate --check 7
check "a review of the head makes cancelled Done" "[[ $code == 0 ]]"
cr_setup "30 min"
cr_run completed cancelled "25 min" "20 min"
comment 'coderabbitai[bot]' '-19 min' "<!-- final_review_risk_coverage {\\\"coveredCommitId\\\":\\\"$(head_of)\\\"} -->"
gate --check 7
check "a head-covering marker past settle_s makes cancelled Done" "[[ $code == 0 ]]"
cr_setup "30 min"
cr_run completed cancelled "25 min" "20 min"
gate --check 7
check "cancelled with no done signal still fails" "[[ $code != 0 ]] && grep -q 'was cancelled and no new run replaced it' <<<\"\$out\""

echo "== gate: a completed run with no completion time"
cr_setup "30 min"
cr_run completed success "25 min" ""
gate --check 7
check "fails with a message, not a midnight timestamp" "[[ $code != 0 ]] && grep -q 'records no completion time' <<<\"\$out\""

echo "== gate: a push while the reviewers are checked"
cr_setup "30 min"
printf 'history_logins=chatgpt-codex-connector\ncodex=Completed\ncodex_commit=%s\nreviewed_subjects=feat: c\nhead_subjects=feat: late push\nreviewed_files=c\nhead_files=c;late\npush_on_cr_read=1\n' "$(head_of | cut -c1-7)" >>"$GH_STATE"
cr_run completed success "25 min" "20 min"
cr_reviewed_head
gate 7
check "Codex is asked again on the new head and blocks it" "[[ $code != 0 ]] && grep -q 'need their own review' <<<\"\$out\" && ! grep -q '^7 merged' <<<\"\$out\""

echo "== gate: a push between the reviewers passing and the merge"
gate_setup
echo 'push_on_merge_read=1' >>"$GH_STATE"
gate 7
check "the merge is refused for the unreviewed head" "[[ $code != 0 ]] && grep -q 'after its reviewers passed' <<<\"\$out\" && ! grep -q '^7 merged' <<<\"\$out\""

echo "== gate: a failed check-runs call"
cr_setup "30 min"
echo 'cr_api_fail=1' >>"$GH_STATE"
gate 7
check "stops rather than reading it as no runs" "[[ $code != 0 ]] && grep -q 'cannot read the check runs' <<<\"\$out\" && ! grep -q '^7 merged' <<<\"\$out\""

echo "== gate: the start window counts from the push, not the commit date"
cr_setup "30 min"
printf 'push_date=%s\n' "$(iso '-30 sec')" >>"$GH_STATE"
gate --check 7
check "an old commit pushed just now is still pending" "[[ $code != 0 ]] && grep -q 'no CodeRabbit check on the head yet' <<<\"\$out\""
cr_setup "30 min"
gate --check 7
check "with no suite it falls back to the commit date" "[[ $code == 0 ]] && grep -q 'has no check on the head 18' <<<\"\$out\""

echo "== gate: a re-requested CodeRabbit review gets its own wait"
cr_setup "30 min"
cr_run completed failure "25 min" "20 min"
printf 'cr_running_reads=4\ncr_run_running=CodeRabbit|in_progress||%s|\ncr_after=CodeRabbit|completed|success|%s|%s\ncr_after_running_reads=4\n' \
  "$(iso '-25 min')" "$(iso '-1 min')" "$(iso '-10 min')" >>"$GH_STATE"
cr_reviewed_head
out=$(PATH="$here:$PATH" MERGE_PRS_REVIEW_POLL=1 MERGE_PRS_REVIEW_WAIT=6 timeout 60 "$script" --check --wait-review --request-review 7 2>&1)
code=$?
show "$out"
check "the wait restarts at the request" "[[ $code == 0 ]] && grep -q '^ready:' <<<\"\$out\""

echo "== gate: a summary_comment reviewer that is not Codex"
gate_setup
mkdir -p "$root/main/.claude"
echo '{"reviewers":[{"name":"other","label":"Other","gate":"always","github":{"signal":"summary_comment"}}]}' >"$root/main/.claude/reviewers.json"
gate --check 7
check "blocks as a format it cannot read" "[[ $code != 0 ]] && grep -q '#7: reviewer other signals by summary_comment' <<<\"\$out\""

echo "== gate: check names are matched whole"
gate_setup
printf 'head_date=%s\ncr_run=Merge|completed|success|%s|%s\n' "$(iso '-30 sec')" "$(iso '-25 min')" "$(iso '-20 min')" >>"$GH_STATE"
mkdir -p "$root/main/.claude"
echo '{"reviewers":[{"name":"qodo","label":"Qodo","gate":"always","github":{"signal":"check_run","check_names":["Qodo Merge"]}}]}' >"$root/main/.claude/reviewers.json"
gate --check 7
check "a check named after one word of Qodo Merge is not its run" "[[ $code != 0 ]] && grep -q 'no Qodo check on the head yet' <<<\"\$out\""

echo "== gate: a Codex quota comment older than the push"
gate_setup
printf 'history_logins=chatgpt-codex-connector\ncodex=Failed\ncodex_commit=abc1234\nhead_date=%s\npush_date=%s\n' "$(iso '-30 min')" "$(iso '-1 min')" >>"$GH_STATE"
comment 'chatgpt-codex-connector[bot]' '-5 min' 'You have reached your Codex usage limits for code reviews.'
gate 7
check "does not excuse a head pushed after it" "[[ $code != 0 ]] && grep -q 'the Codex review failed' <<<\"\$out\""

echo "== gate: a failed commit-date read"
gate_setup
printf 'history_logins=chatgpt-codex-connector\ncodex=Failed\ncodex_commit=abc1234\nhead_date_fail=1\n' >>"$GH_STATE"
comment 'chatgpt-codex-connector[bot]' '-30 min' 'You have reached your Codex usage limits for code reviews.'
gate 7
check "Codex path stops instead of excusing the review" "[[ $code != 0 ]] && grep -q 'cannot read the commit' <<<\"\$out\" && ! grep -q 'is unavailable' <<<\"\$out\""
cr_setup "30 min"
echo 'head_date_fail=1' >>"$GH_STATE"
gate 7
check "check-run path stops rather than reading a bogus time" "[[ $code != 0 ]] && grep -q 'cannot read the commit' <<<\"\$out\" && ! grep -q '^7 merged' <<<\"\$out\""

echo "== gate: an unreadable completion time"
cr_setup "30 min"
printf 'cr_run=CodeRabbit|completed|success|%s|garbage\n' "$(iso '-25 min')" >>"$GH_STATE"
gate 7
check "stops rather than reading it as settled" "[[ $code != 0 ]] && grep -q 'cannot read the time garbage' <<<\"\$out\" && ! grep -q '^7 merged' <<<\"\$out\""

echo "== gate: gate always on a reviewer merge-prs cannot read"
gate_setup
mkdir -p "$root/main/.claude"
echo '{"reviewers":[{"name":"codex","gate":"always","github":{"signal":"bogus"}}]}' >"$root/main/.claude/reviewers.json"
gate --check 7
check "blocks rather than dropping it" "[[ $code != 0 ]] && grep -q 'reviewer codex has gate always but its signal \"bogus\"' <<<\"\$out\""

echo "== review_jq: Codex's machine-readable state"
codex_state_body() { printf 'codex-pull-request-review-summary\n<!-- codex-review-state:v1 {"code_review":{"commit_sha":"%s","status":"%s"},"security_review":{"status":"completed"}} -->\n%s' "$1" "$2" "$3"; }
check "the JSON status is read" "[[ \$(pr_json '$old' '[]' \"\$(codex_state_body abc1234def running '')\" | review_status) == Running ]]"
check "the JSON commit is read" "[[ \$(pr_json '$old' '[]' \"\$(codex_state_body abc1234def completed '')\" | review_jq_commit) == abc1234def ]]"
check "the JSON wins over a stale table" "[[ \$(pr_json '$old' '[]' \"\$(codex_state_body abc1234def failed '| **Completed** | \`1111111\` |')\" | review_status) == Failed ]]"
check "a null commit is Unreviewed" "[[ \$(pr_json '$old' '[]' 'codex-pull-request-review-summary <!-- codex-review-state:v1 {\"code_review\":{\"commit_sha\":null,\"status\":\"completed\"}} -->' | review_status) == Unreviewed ]]"
# shellcheck disable=SC2016,SC2034 # Markdown backticks; used by the eval in the check below.
broken_marker_body='codex-pull-request-review-summary <!-- codex-review-state:v1 {oops} --> | **Completed** | `abc1234` |'
check "a broken marker falls back to the table" "[[ \$(pr_json '$old' '[]' \"\$broken_marker_body\" | review_status) == Completed ]]"

echo "== resolve-thread.sh"
bash "$here/resolve-thread.sh" || fail=$((fail + 1))

echo "$pass passed, $fail failed"
((fail == 0))
