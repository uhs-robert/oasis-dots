#!/usr/bin/env bash
# PreToolUse(Bash): `gh pr create` runs only once `lib/check.sh --changed <merge-base with origin/main>` passes, so a PR
# goes up checked. This and ship-batch's check of each branch before it merges are the only automatic check runs:
# while working, an agent runs the tests that cover what it changed.
set -u
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ $cmd =~ gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$) ]] || exit 0
dir=$(jq -r '.cwd // empty' <<<"$input")
cd "${dir:-${CLAUDE_PROJECT_DIR:-$PWD}}" || exit 0
[[ -x lib/check.sh ]] || exit 0
base=$(git merge-base HEAD origin/main 2>/dev/null) || exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# Under the hook's own 900s limit, which also covers waiting for another session's check to finish.
check_limit=870
# The lock wait gives up before the hook does, so a long wait is reported as one, naming who holds the lock.
out=$(CHECK_LOCK_WAIT_SECS=$((check_limit - 60)) timeout "$check_limit" lib/check.sh --changed "$base" 2>&1)
status=$?
((status == 0)) && exit 0
((status == 124)) && deny "'lib/check.sh --changed $base' did not finish within ${check_limit}s (it may have waited for another session's check). Rerun it, then open the PR once it passes."
summary=$(sed -E $'s/\e\\[[0-9;]*m//g' <<<"$out" | sed -n '/^FAILED:/,$p' | head -n 400)
[[ -n $summary ]] || summary=$(tail -n 40 <<<"$out")
deny "'lib/check.sh --changed $base' fails, so the PR was not opened. Fix what it reports, commit, and open it again. Output:
$summary"
