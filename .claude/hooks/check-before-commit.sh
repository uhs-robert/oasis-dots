#!/usr/bin/env bash
# PreToolUse(Bash): a `git commit` runs only once `lib/check.sh` passes on exactly the files that commit takes, so lint
# fails at the commit, not at the PR. The voxcmd suites are left to the PR and the merge, and CHECK_NO_LOCK keeps any
# heavy step from waiting for a slot: this check is cheap and must never wait behind a long one.
set -u
# shellcheck source=command-dir.sh
source "$(dirname "${BASH_SOURCE[0]}")/command-dir.sh"
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
commit_re='(^|[;&|(]|[[:space:]])git[[:space:]]+((-[^;&|]*[[:space:]])?)commit([[:space:]]|$)'
[[ $cmd =~ $commit_re ]] || exit 0
git_options=${BASH_REMATCH[2]}
after_commit=${cmd#*"${BASH_REMATCH[0]}"}

dir=$(jq -r '.cwd // empty' <<<"$input")
cd "${dir:-${CLAUDE_PROJECT_DIR:-$PWD}}" || exit 0
# A leading `cd <dir> &&` and `git -C <dir>` move where the commit happens.
enter_leading_cd "$cmd" || exit 0
dir_re='-C[[:space:]]+("[^"]+"|'"'"'[^'"'"']+'"'"'|[^[:space:]]+)'
if [[ $git_options =~ $dir_re ]]; then cd "$(tr -d "\"'" <<<"${BASH_REMATCH[1]}")" 2>/dev/null || exit 0; fi
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0
[[ -x lib/check.sh ]] || exit 0

# Quoted text (the message) is dropped before looking for -a/--all, which takes every tracked change into the commit.
unquoted=$(sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g" <<<"$after_commit")
all_re='(^|[[:space:]])(--all|-[a-zA-Z]*a[a-zA-Z]*)([[:space:]]|$)'
add_re='git[[:space:]]+([^;&|]*[[:space:]])?add([[:space:]]|$)'
# A commit that takes working-tree content itself (`--only`, `-- <path>`, `--pathspec-from-file`, `-p`, `--interactive`)
# can commit files the index does not have yet, so it is linted like -a; bare paths without `--` are not detected.
worktree_re='(^|[[:space:]])(--only|-o|--|--pathspec-from-file(=[^[:space:]]*)?|-p|--patch|--interactive)([[:space:]]|$)'
# `--include` commits what is staged plus the named working-tree files.
include_re='(^|[[:space:]])(--include|-i)([[:space:]]|$)'
diff_check_target=--cached check_partial=1
if [[ $unquoted =~ $all_re || $unquoted =~ $worktree_re ]]; then
  paths=$(git diff --name-only --no-renames HEAD 2>/dev/null)
  diff_check_target=HEAD check_partial=''
elif [[ $unquoted =~ $include_re ]]; then
  paths=$(
    git diff --cached --name-only --no-renames
    git diff --name-only --no-renames
  )
  diff_check_target=HEAD
elif [[ $cmd =~ $add_re ]]; then
  # `git add ... && git commit` has staged nothing yet, so the staged list would be empty: take everything that could go in.
  paths=$(
    git diff --name-only --no-renames HEAD 2>/dev/null
    git ls-files -o --exclude-standard
  )
  diff_check_target=HEAD check_partial=''
else
  paths=$(git diff --cached --name-only --no-renames)
fi
[[ -n $paths ]] || exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# The linters read the working tree, so a staged file with further unstaged edits would be linted as something other
# than what is committed.
if [[ -n $check_partial ]]; then
  partly_staged=$(comm -12 <(git diff --cached --name-only | sort) <(git diff --name-only | sort))
  [[ -z $partly_staged ]] || deny "These files have staged and unstaged changes, so the lint cannot check what the commit takes. Stage or stash the rest, then commit:
$partly_staged"
fi

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
diff_check=$(git diff --check "$diff_check_target" 2>&1)
# `git add ... && git commit` may also take new files, which no diff against HEAD shows yet.
if [[ $cmd =~ $add_re ]]; then
  while IFS= read -r new_file; do
    diff_check+=$(git diff --no-index --check /dev/null "$new_file" 2>&1)
  done < <(git ls-files -o --exclude-standard)
fi
[[ -z $diff_check ]] || deny "git diff --check fails on this commit's changes, so it was not made. Output:
$diff_check"
exit 0
