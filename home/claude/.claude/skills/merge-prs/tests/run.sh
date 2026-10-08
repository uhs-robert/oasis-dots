#!/usr/bin/env bash
# Replays the stale-stack, real-conflict and review-gate cases against merge-prs.sh with a local origin and the fake gh.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script=${1:-$here/../merge-prs.sh}
pass=0 fail=0
check() { if eval "$2"; then echo "ok   $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
g() { git -c user.name=t -c user.email=t@t "$@"; }
show() { while IFS= read -r line; do printf '   | %s\n' "$line"; done <<<"$1"; }

setup() {
  root=$(mktemp -d); export ORIGIN=$root/origin.git GH_STATE=$root/state
  git init -q --bare -b main "$ORIGIN"
  g clone -q "$ORIGIN" "$root/main" 2>/dev/null; cd "$root/main" || exit 1
  echo a > a; g add a; g commit -qm A; g push -q origin main
  g switch -qc parent; echo p > p; g add p; g commit -qm P; g push -q origin parent
  g switch -qc child; echo c > c; g add c; g commit -qm C; g push -q origin child
  # The parent lands on main by rebase outside the run: same change, new commit id.
  g switch -q main; g cherry-pick "$(git rev-parse parent)" >/dev/null; g commit -q --amend -m "P (rebased)" ; g push -q origin main
  g push -q origin --delete parent; g branch -q -D parent
  g switch -q child
  printf 'head=child\nbase=main\nstate=OPEN\nconflicting_oid=%s\n' "$(git rev-parse child)" > "$GH_STATE"
}

echo "== stale stack, main checkout sitting on the PR branch"
setup
out=$(PATH="$here:$PATH" "$script" 7 2>&1); code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "rebases and drops the merged parent commit" "grep -q 'rebased onto main, dropping 1 commit' <<<\"\$out\""
check "merges" "grep -q '^7 merged (rebase)' <<<\"\$out\""
check "switches the main checkout to main" "grep -q 'switched .* to main' <<<\"\$out\""
check "deletes the local branch" "! git -C '$root/main' show-ref -q --verify refs/heads/child"
check "pulls main" "grep -q '^pulled ' <<<\"\$out\""
check "main has A, P once and C" "[[ \$(git -C '$root/main' log --format=%s main) == \$'C\nP (rebased)\nA' ]]"

echo "== main held by another worktree"
setup
g worktree add -q "$root/elsewhere" main
out=$(PATH="$here:$PATH" "$script" 7 2>&1); code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "merges" "grep -q '^7 merged (rebase)' <<<\"\$out\""
check "keeps the branch with a reason" "grep -q 'kept branch child: .*could not switch' <<<\"\$out\""

echo "== real conflict"
setup
echo other > c; g add c; g commit -qm "C2"; 
g switch -q main; echo clash > c; g add c; g commit -qm "clash"; g push -q origin main; g switch -q child; g push -q origin child
# Drop P from the child so nothing in it is already merged, leaving only the clashing change.
g rebase -q --onto "$(git rev-parse HEAD~3)" HEAD~2 child 2>/dev/null || true
g push -q -f origin child
printf 'head=child\nbase=main\nstate=OPEN\nconflicting_oid=%s\n' "$(git rev-parse child)" > "$GH_STATE"
before=$(git -C "$ORIGIN" rev-parse child)
out=$(PATH="$here:$PATH" "$script" 7 2>&1); code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "names the conflict" "grep -q 'conflicts with main' <<<\"\$out\""
check "leaves the PR branch untouched" "[[ \$(git -C '$ORIGIN' rev-parse child) == '$before' ]]"
check "keeps the PR open" "grep -q '^state=OPEN' '$GH_STATE'"

echo "== review gate: unresolved thread"
setup
echo "open_threads=2" >> "$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1); code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "names the threads" "grep -q '#7: 2 unresolved review thread' <<<\"\$out\""
check "keeps the PR open" "grep -q '^state=OPEN' '$GH_STATE'"

echo "== review gate: Codex review failed"
setup
printf 'codex=Failed\ncodex_commit=abc1234\n' >> "$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1); code=$?
show "$out"
check "stops with an error" "[[ $code != 0 ]]"
check "says how to rerun Codex" "grep -q '@codex review' <<<\"\$out\""

echo "== review gate: Codex review of an older commit"
setup
printf 'codex=Completed\ncodex_commit=abc1234\n' >> "$GH_STATE"
out=$(PATH="$here:$PATH" "$script" 7 2>&1); code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "notes the unreviewed commits" "grep -q 'covers abc1234, not the head' <<<\"\$out\""

echo "== review gate: skipped by the owner"
setup
echo "open_threads=1" >> "$GH_STATE"
out=$(PATH="$here:$PATH" "$script" --skip-review-gate 7 2>&1); code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "merges" "grep -q '^7 merged (rebase)' <<<\"\$out\""

echo "== stack merged in one run, GitHub slow to report the rebased child"
root=$(mktemp -d); export ORIGIN=$root/origin.git GH_STATE=$root/state
git init -q --bare -b main "$ORIGIN"
g clone -q "$ORIGIN" "$root/main" 2>/dev/null; cd "$root/main" || exit 1
echo a > a; g add a; g commit -qm A; g push -q origin main
g switch -qc parent; echo p > p; g add p; g commit -qm P; g push -q origin parent
g switch -qc child; echo c > c; g add c; g commit -qm C; g push -q origin child
g switch -q main
: > "$GH_STATE"
printf 'head=parent\nbase=main\nstate=OPEN\n' > "$GH_STATE.7"
printf 'head=child\nbase=parent\nstate=OPEN\nstale_oid=%s\nlag_reads=3\n' "$(git rev-parse child)" > "$GH_STATE.8"
out=$(PATH="$here:$PATH" "$script" 7 8 2>&1); code=$?
show "$out"
check "exits 0" "[[ $code == 0 ]]"
check "rebases the child" "grep -q '^8 rebased onto main' <<<\"\$out\""
check "merges the child" "grep -q '^8 merged (rebase)' <<<\"\$out\""
check "main has A, P and C" "[[ \$(git -C '$ORIGIN' log --format=%s main) == \$'C\nP\nA' ]]"

echo "$pass passed, $fail failed"
((fail == 0))
