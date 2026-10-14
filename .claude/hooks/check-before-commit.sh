#!/usr/bin/env bash
# PreToolUse(Bash): a `git commit` runs only once `lib/check.sh` passes on exactly the files that commit takes, so lint
# fails at the commit, not at the PR. The voxcmd suites are left to the PR and the merge, and the machine-wide check
# lock is not taken: this check is cheap and must never wait behind a long one.
set -u
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
commit_re='(^|[;&|(]|[[:space:]])git[[:space:]]+((-[^;&|]*[[:space:]])?)commit([[:space:]]|$)'
[[ $cmd =~ $commit_re ]] || exit 0
git_options=${BASH_REMATCH[2]}
after_commit=${cmd#*"${BASH_REMATCH[0]}"}

dir=$(jq -r '.cwd // empty' <<<"$input")
cd "${dir:-${CLAUDE_PROJECT_DIR:-$PWD}}" || exit 0
# A leading `cd <dir> &&` and `git -C <dir>` move where the commit happens.
cd_re='^[[:space:]]*cd[[:space:]]+([^;&|[:space:]]+)[[:space:]]*(&&|;)'
if [[ $cmd =~ $cd_re ]]; then cd "$(tr -d "\"'" <<<"${BASH_REMATCH[1]}")" 2>/dev/null || exit 0; fi
dir_re='-C[[:space:]]+("[^"]+"|'"'"'[^'"'"']+'"'"'|[^[:space:]]+)'
if [[ $git_options =~ $dir_re ]]; then cd "$(tr -d "\"'" <<<"${BASH_REMATCH[1]}")" 2>/dev/null || exit 0; fi
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0
[[ -x lib/check.sh ]] || exit 0

# Quoted text (the message) is dropped before looking for -a/--all, which takes every tracked change into the commit.
unquoted=$(sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g" <<<"$after_commit")
all_re='(^|[[:space:]])(--all|-[a-zA-Z]*a[a-zA-Z]*)([[:space:]]|$)'
add_re='git[[:space:]]+([^;&|]*[[:space:]])?add([[:space:]]|$)'
if [[ $unquoted =~ $all_re ]]; then
  paths=$(git diff --name-only --no-renames HEAD 2>/dev/null)
elif [[ $cmd =~ $add_re ]]; then
  # `git add ... && git commit` has staged nothing yet, so the staged list would be empty: take everything that could go in.
  paths=$(
    git diff --name-only --no-renames HEAD 2>/dev/null
    git ls-files -o --exclude-standard
  )
else
  paths=$(git diff --cached --name-only --no-renames)
fi
[[ -n $paths ]] || exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# Well under the hook's 150s limit. A check that cannot finish lets the commit through; the PR hook still checks.
check_limit=120
voxcmd_steps='voxcmd-phrases voxcmd-click voxcmd-calendar voxcmd-wake voxcmd-firefox'
# git-diff-check compares the whole working tree to HEAD, which is more than this commit; the commit's own diff is checked below.
out=$(printf '%s\n' "$paths" | CHECK_NO_LOCK=1 CHECK_JOBS=2 CHECK_SKIP_STEPS="$voxcmd_steps git-diff-check" timeout "$check_limit" lib/check.sh --paths-from - 2>&1)
status=$?
if ((status == 124)); then
  jq -n --arg m "The pre-commit lint did not finish within ${check_limit}s, so the commit went ahead unchecked. Run 'lib/check.sh --changed HEAD' before the PR." '{systemMessage: $m}'
  exit 0
fi
if ((status != 0)); then
  summary=$(sed -E $'s/\e\\[[0-9;]*m//g' <<<"$out" | sed -n '/^FAILED:/,$p' | head -n 400)
  [[ -n $summary ]] || summary=$(tail -n 40 <<<"$out")
  deny "The lint of the files in this commit fails, so it was not made. Fix what it reports, stage the fixes and commit again. Output:
$summary"
fi
if [[ $unquoted =~ $all_re ]]; then diff_check=$(git diff --check HEAD 2>&1); else diff_check=$(git diff --cached --check 2>&1); fi
[[ -z $diff_check ]] || deny "git diff --check fails on this commit's changes, so it was not made. Output:
$diff_check"
exit 0
