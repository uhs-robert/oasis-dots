#!/usr/bin/env bash
# Replays the stale-stack, real-conflict and review-gate cases against merge-prs.sh with a local origin and the fake gh,
# then restacks a local stack with restack.sh.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../merge-prs.sh}
restack=$here/../restack.sh
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
  g switch -qc parent
  echo p >p
  g add p
  g commit -qm P
  g push -q origin parent
  g switch -qc child
  echo c >c
  g add c
  g commit -qm C
  g push -q origin child
  # The parent lands on main by rebase outside the run: same change, new commit id.
  g switch -q main
  g cherry-pick "$(git rev-parse parent)" >/dev/null
  g commit -q --amend -m "P (rebased)"
  g push -q origin main
  g push -q origin --delete parent
  g branch -q -D parent
  g switch -q child
  printf 'head=child\nbase=main\nstate=OPEN\nconflicting_oid=%s\n' "$(git rev-parse child)" >"$GH_STATE"
}

echo "== stale stack, main checkout sitting on the PR branch"
setup
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "rebases and drops the merged parent commit" "grep -q 'rebased onto main, dropping 1 commit' <<<\"\$out\""
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

echo "== already-merged parent: its child is reported, not rebased"
setup
parent_oid=$(git rev-parse child~1)
g push -q origin "$parent_oid:refs/heads/parent"
printf 'head=parent\nbase=main\nstate=MERGED\n' >"$GH_STATE.7"
mv "$GH_STATE" "$GH_STATE.8"
printf 'head=child\nbase=main\nstate=OPEN\n' >"$GH_STATE.8"
child_before=$(git -C "$ORIGIN" rev-parse child)
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "warns about the child carrying the parent commit" "grep -q 'warning: #8 (child) is stacked on the merged #7' <<<\"\$out\""
check "prints the manual rebase" "grep -q 'git rebase --onto origin/main $parent_oid $child_before' <<<\"\$out\""
check "pushes nothing" "[[ \$(git -C '$ORIGIN' rev-parse child) == '$child_before' ]]"

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

echo "== main held by another worktree"
setup
g worktree add -q "$root/elsewhere" main
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "merges" "grep -q '^7 merged (rebase)' <<<\"\$out\""
check "keeps the branch with a reason" "grep -q 'kept branch child: .*could not switch' <<<\"\$out\""

echo "== real conflict"
setup
echo other >c
g add c
g commit -qm "C2"
g switch -q main
echo clash >c
g add c
g commit -qm "clash"
g push -q origin main
g switch -q child
g push -q origin child
# Drop P from the child so nothing in it is already merged, leaving only the clashing change.
g rebase -q --onto "$(git rev-parse HEAD~3)" HEAD~2 child 2>/dev/null || true
g push -q -f origin child
printf 'head=child\nbase=main\nstate=OPEN\nconflicting_oid=%s\n' "$(git rev-parse child)" >"$GH_STATE"
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

echo "== review gate: skipped by the owner"
setup
echo "open_threads=1" >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" --skip-review-gate 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "merges" "grep -q '^7 merged (rebase)' <<<\"\$out\""

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
check "stops at the limit even with a zero poll interval" "[[ $code != 124 ]] && grep -q 'still running after 1s' <<<\"\$out\""

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

echo "== pre-merge: fork PR is skipped"
setup
# The fake merge cherry-picks the branch, so give the fork a branch that does not repeat what setup landed on main.
g switch -q main
g switch -qc fork-head
echo f >f
g add f
g commit -qm F
g push -q origin fork-head
pre_merge_hook "$commit_build"
printf 'head=fork-head\nbase=main\nstate=OPEN\ncross=true\n' >"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "warns" "grep -q 'warning: #7 is from a fork, so the pre-merge step was skipped' <<<\"\$out\""
check "does not run the script" "[[ ! -e '$root/env' ]]"
check "merges" "grep -q '^7 merged (rebase)' <<<\"\$out\""

echo "== pre-merge: --check never runs it"
setup
pre_merge_hook "$commit_build"
out=$(PATH="$here:$PATH" "$script" --check 7 2>&1)
code=$?
show "$out"
check "passes" "[[ $code == 0 ]]"
check "does not run the script" "[[ ! -e '$root/env' ]]"

echo "== pre-merge: stack where both PRs get a commit"
root=$(mktemp -d)
export ORIGIN=$root/origin.git GH_STATE=$root/state
git init -q --bare -b main "$ORIGIN"
g clone -q "$ORIGIN" "$root/main" 2>/dev/null
cd "$root/main" || exit 1
echo a >a
g add a
g commit -qm A
g push -q origin main
g switch -qc parent
echo p >p
g add p
g commit -qm P
g push -q origin parent
g switch -qc child
echo c >c
g add c
g commit -qm C
g push -q origin child
g switch -q main
: >"$GH_STATE"
printf 'head=parent\nbase=main\nstate=OPEN\n' >"$GH_STATE.7"
printf 'head=child\nbase=parent\nstate=OPEN\n' >"$GH_STATE.8"
pre_merge_hook "$commit_build"
out=$(PATH="$here:$PATH" "$script" 7 8 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "runs the script for both" "[[ \$(cut -d' ' -f1-3 '$root/env' | tr '\n' ',') == '7 parent main,8 child main,' ]]"
check "rebases the child past the parent's pre-merge commit" "grep -q '^8 rebased onto main' <<<\"\$out\""
check "merges both" "grep -q '^7 merged (rebase)' <<<\"\$out\" && grep -q '^8 merged (rebase)' <<<\"\$out\""
check "main has each commit once, the child built on the merged parent" "[[ \$(git -C '$ORIGIN' log --format=%s main) == \$'build: child\nC\nbuild: parent\nP\nA' ]]"

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

echo "== pre-merge: a failing step leaves the children where they were"
setup
# The setup PR becomes the parent of a second PR on a copy of its branch.
git -C "$ORIGIN" branch -q grandchild child
mv "$GH_STATE" "$GH_STATE.7"
printf 'head=grandchild\nbase=child\nstate=OPEN\n' >"$GH_STATE.8"
pre_merge_hook "exit 1"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "names the step" "grep -q 'pre-merge step failed on #7' <<<\"\$out\""
check "does not retarget the child" "grep -q '^base=child' '$GH_STATE.8'"

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

echo "== review gate: generated-only commit on a fork PR still needs a review"
setup
mkdir -p .claude
printf 'public/\n' >.claude/generated-paths
printf 'cross=true\ncodex=Completed\ncodex_commit=abc1234\nreviewed_subjects=feat: add x\nhead_subjects=feat: add x;build: rebuild public\nreviewed_files=a\nhead_files=a;public/x.js\ncommit_files_c2=public/x.js\n' >>"$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "names the commit" "grep -q '\"build: rebuild public\" is not a fix' <<<\"\$out\""

echo "== --check: refuses merge options"
setup
out=$(PATH="$here:$PATH" "$script" --check --keep-branch 7 2>&1)
code=$?
show "$out"
check "fails" "[[ $code != 0 ]]"
check "says why" "grep -q 'cannot be combined' <<<\"\$out\""

echo "== stack merged in one run, GitHub slow to report the rebased child"
root=$(mktemp -d)
export ORIGIN=$root/origin.git GH_STATE=$root/state
git init -q --bare -b main "$ORIGIN"
g clone -q "$ORIGIN" "$root/main" 2>/dev/null
cd "$root/main" || exit 1
echo a >a
g add a
g commit -qm A
g push -q origin main
g switch -qc parent
echo p >p
g add p
g commit -qm P
g push -q origin parent
g switch -qc child
echo c >c
g add c
g commit -qm C
g push -q origin child
g switch -q main
: >"$GH_STATE"
printf 'head=parent\nbase=main\nstate=OPEN\n' >"$GH_STATE.7"
printf 'head=child\nbase=parent\nstate=OPEN\nstale_oid=%s\nlag_reads=3\n' "$(git rev-parse child)" >"$GH_STATE.8"
out=$(PATH="$here:$PATH" "$script" 7 8 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "rebases the child" "grep -q '^8 rebased onto main' <<<\"\$out\""
check "merges the child" "grep -q '^8 merged (rebase)' <<<\"\$out\""
check "main has A, P and C" "[[ \$(git -C '$ORIGIN' log --format=%s main) == \$'C\nP\nA' ]]"

# Stack a <- b <- c on main, all pushed, b in its own worktree and c in none; the main checkout is left on a.
stack_setup() {
  root=$(mktemp -d)
  ORIGIN=$root/origin.git
  git init -q --bare -b main "$ORIGIN"
  g clone -q "$ORIGIN" "$root/main" 2>/dev/null
  cd "$root/main" || exit 1
  echo m >m
  g add m
  g commit -qm A
  g push -q origin main
  local branch
  for branch in a b c; do
    g switch -qc "$branch"
    echo "$branch" >"f$branch"
    g add "f$branch"
    g commit -qm "${branch}1"
    g push -q origin "$branch"
  done
  g switch -q a
  g worktree add -q "$root/wt-b" b
}
subjects() { git -C "$root/main" log --format=%s "$1" | paste -sd ' '; }

echo "== restack: the bottom gets a new commit"
stack_setup
echo more >fa2
g add fa2
g commit -qm a2
out=$("$restack" a b c 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "uses origin/a as a's old tip" "grep -q '(origin/a)' <<<\"\$out\""
check "c carries the whole stack once" "[[ \$(subjects c) == 'c1 b1 a2 a1 A' ]]"
check "b's worktree follows its branch" "[[ \$(git -C '$root/wt-b' rev-parse HEAD) == \$(git rev-parse b) ]]"
check "pushes b and c" "[[ \$(git -C '$ORIGIN' rev-parse b c) == \$(git rev-parse b c) ]]"
check "removes the temporary worktree for c" "[[ \$(git worktree list | wc -l) == 2 ]]"

echo "== restack: the bottom was amended and pushed"
stack_setup
g commit -q --amend -m "a1 amended"
g push -q -f origin a
out=$("$restack" --no-push a b c 2>&1)
code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "uses the reflog as a's old tip" "grep -q '(a@{1})' <<<\"\$out\""
check "drops the replaced a1" "[[ \$(subjects c) == 'c1 b1 a1 amended A' ]]"
check "--no-push leaves origin alone" "[[ \$(git -C '$ORIGIN' rev-parse c) != \$(git rev-parse c) ]]"

echo "== restack: conflict"
stack_setup
echo clash >fb
g add fb
g commit -qm "a2 clash"
before_b=$(git rev-parse b)
before_c=$(git rev-parse c)
out=$("$restack" a b c 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "names the file" "grep -q 'conflicts rebasing onto a in fb' <<<\"\$out\""
check "prints how to finish" "grep -q 'git add fb && git rebase --continue' <<<\"\$out\" && grep -q 'restack.sh b c' <<<\"\$out\""
check "leaves origin/b and c alone" "[[ \$(git -C '$ORIGIN' rev-parse b) == '$before_b' && \$(git rev-parse c) == '$before_c' ]]"

echo "== restack: check fails"
stack_setup
echo more >fa2
g add fa2
g commit -qm a2
before_c=$(git rev-parse c)
out=$("$restack" --check 'echo checking; echo boom >&2; exit 3' a b c 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "shows the check's output" "grep -q '^boom' <<<\"\$out\""
check "names the branch" "grep -q 'check failed on b' <<<\"\$out\""
check "does not push b" "[[ \$(git -C '$ORIGIN' rev-parse b) != \$(git rev-parse b) ]]"
check "does not touch c" "[[ \$(git rev-parse c) == '$before_c' ]]"

echo "== restack: the remote moves after the rebase starts"
stack_setup
echo more >fa2
g add fa2
g commit -qm a2
moved=$(git rev-parse main)
out=$("$restack" --check "git --git-dir='$ORIGIN' update-ref refs/heads/b $moved" a b c 2>&1)
code=$?
show "$out"
check "stops with an error" "[[ \$code != 0 ]]"
check "names the branch it could not push" "grep -q 'cannot push b' <<<\"\$out\""
check "leaves the other push in place" "[[ \$(git -C '$ORIGIN' rev-parse b) == '$moved' ]]"

echo "$pass passed, $fail failed"
((fail == 0))
