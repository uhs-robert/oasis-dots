#!/usr/bin/env bash
# Stop: run `lib/check.sh --changed <base>` when tracked files have uncommitted changes or HEAD's tree has not passed in any worktree.
# Skips a tree it already ran on without blocking, so a pre-existing failure doesn't rerun the suite every turn.
set -u
input=$(cat)
[[ $(jq -r '.stop_hook_active // false' <<<"$input") == true ]] && exit 0
dir=${CLAUDE_PROJECT_DIR:-$PWD}
cd "$dir" || exit 0
head=$(git rev-parse HEAD 2>/dev/null) || exit 0
ok_file=$(git rev-parse --git-path claude-check-ok)
last_ok=$(cat "$ok_file" 2>/dev/null)
# lib/check-passed.sh keys passes on tree, shared across worktrees, so merging or pulling commits that already passed
# in their own worktree does not rerun the suite just because a rebase merge gave them new hashes.
check_passed=lib/check-passed.sh
dirty=$(git status --porcelain --untracked-files=no)
[[ -z $dirty && -x $check_passed ]] && "$check_passed" is-passed && exit 0
seen_file=$(git rev-parse --git-path claude-check-seen)
tree_state="$head $(git diff HEAD | sha1sum | cut -d' ' -f1)"
[[ $(cat "$seen_file" 2>/dev/null) == "$tree_state" ]] && exit 0

base=$last_ok
git cat-file -e "${base:-none}^{commit}" 2>/dev/null || base=$(git merge-base HEAD origin/main 2>/dev/null)

# Under the hook's own 330s limit, so a slow run is reported here instead of the hook being killed mid-output.
check_limit=300
if [[ -n $base ]]; then
  out=$(timeout "$check_limit" lib/check.sh --changed "$base" 2>&1)
else
  out=$(timeout "$check_limit" lib/check.sh 2>&1)
fi
status=$?
if ((status == 124)); then
  jq -n --arg m "'lib/check.sh' did not finish within ${check_limit}s, so it was stopped. That is not a test failure: run it by hand." \
    '{systemMessage: $m}'
  exit 0
fi
if ((status == 0)); then
  printf '%s\n' "$head" >"$ok_file"
  # Only a full run on a clean tree vouches for HEAD's tree; a scoped run checked just what changed.
  [[ -z $dirty && -z $base && -x $check_passed ]] && "$check_passed" record
  printf '%s\n' "$tree_state" >"$seen_file"
  exit 0
fi

changed=$({
  git diff --name-only HEAD
  [[ -n $base ]] && git diff --name-only "$base" HEAD
} | sort -u)

# sed, not ${out//$'\e['*([0-9;])m/}: bash's extglob substitution is superlinear and spun for minutes on 14 KB.
out=$(sed -E $'s/\e\\[[0-9;]*m//g' <<<"$out" | grep -v -E '\bOK$|^sh \./lib/check\.sh$')
failing=$(grep -oE '[[:alnum:]_./-]+' <<<"$out" | sed -E 's/\.orig$//' | sort -u | while read -r p; do
  [[ -f $p ]] && git ls-files --error-unmatch -- "$p" >/dev/null 2>&1 && printf '%s\n' "$p"
done)
summary=$(sed -n '/^FAILED:/,$p' <<<"$out" | head -n 400)
[[ -n $summary ]] || summary=$(tail -n 40 <<<"$out")

if [[ -n $failing ]] && ! grep -qxF -f <(printf '%s\n' "$failing") <<<"$changed"; then
  origins=$(while read -r p; do printf '%s: last changed in %s\n' "$p" "$(git log -1 --format='%h %s' -- "$p")"; done <<<"$failing")
  jq -n --arg m "'lib/check.sh' fails, but only in files this session did not change. Pre-existing failure, not blocking:
$origins" '{systemMessage: $m}'
  printf '%s\n' "$tree_state" >"$seen_file"
  exit 0
fi

if [[ -z $dirty ]]; then
  reason="'lib/check.sh' fails at HEAD $(git rev-parse --short HEAD), and commits since the last passing run caused it. Fix it in a follow-up commit. Output:"
else
  reason="'lib/check.sh' failed with uncommitted changes to tracked files. Fix what it reports (or revert the change) before finishing. Output:"
fi
jq -n --arg r "$reason
$summary" '{decision: "block", reason: $r}'
