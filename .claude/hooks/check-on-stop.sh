#!/usr/bin/env bash
# Stop: run `just check` when tracked files have uncommitted changes or HEAD moved since the last passing run.
set -u
input=$(cat)
[[ $(jq -r '.stop_hook_active // false' <<<"$input") == true ]] && exit 0
dir=${CLAUDE_PROJECT_DIR:-$PWD}
cd "$dir" || exit 0
head=$(git rev-parse HEAD 2>/dev/null) || exit 0
ok_file=$(git rev-parse --git-path claude-check-ok)
last_ok=$(cat "$ok_file" 2>/dev/null)
dirty=$(git status --porcelain --untracked-files=no)
[[ -z $dirty && $head == "$last_ok" ]] && exit 0

if out=$(timeout 180 just check 2>&1); then
  printf '%s\n' "$head" >"$ok_file"
  exit 0
fi

base=$last_ok
git cat-file -e "${base:-none}^{commit}" 2>/dev/null || base=$(git merge-base HEAD origin/main 2>/dev/null)
changed=$({
  git diff --name-only HEAD
  [[ -n $base ]] && git diff --name-only "$base" HEAD
} | sort -u)

out=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$out" | grep -v -E '\bOK$|^sh \./lib/check\.sh$')
failing=$(grep -oE '[[:alnum:]_./-]+' <<<"$out" | sed -E 's/\.orig$//' | sort -u | while read -r p; do
  [[ -f $p ]] && git ls-files --error-unmatch -- "$p" >/dev/null 2>&1 && printf '%s\n' "$p"
done)
summary=$(sed -n '/^FAILED:/,$p' <<<"$out" | head -n 160)
[[ -n $summary ]] || summary=$(tail -n 40 <<<"$out")

if [[ -n $failing ]] && ! grep -qxF -f <(printf '%s\n' "$failing") <<<"$changed"; then
  origins=$(while read -r p; do printf '%s: last changed in %s\n' "$p" "$(git log -1 --format='%h %s' -- "$p")"; done <<<"$failing")
  jq -n --arg m "'just check' fails, but only in files this session did not change. Pre-existing failure, not blocking:
$origins" '{systemMessage: $m}'
  exit 0
fi

if [[ -z $dirty ]]; then
  reason="'just check' fails at HEAD $(git rev-parse --short HEAD), and commits since the last passing run caused it. Fix it in a follow-up commit. Output:"
else
  reason="'just check' failed with uncommitted changes to tracked files. Fix what it reports (or revert the change) before finishing. Output:"
fi
jq -n --arg r "$reason
$summary" '{decision: "block", reason: $r}'
