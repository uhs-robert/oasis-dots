#!/usr/bin/env bash
# PreToolUse(Bash): `gh pr create` goes through only when HEAD's tree is recorded as passing `lib/check.sh --changed
# <merge-base with origin/main>` (or the full check), so a PR goes up checked. It only looks the pass up: running the
# check here would hold the agent for as long as the check takes, so a missing pass is denied at once with the command
# to run in the background.
set -u
# shellcheck source=command-dir.sh
source "$(dirname "${BASH_SOURCE[0]}")/command-dir.sh"
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ $cmd =~ gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$) ]] || exit 0
dir=$(jq -r '.cwd // empty' <<<"$input")
cd "${dir:-${CLAUDE_PROJECT_DIR:-$PWD}}" || exit 0
# The PR is opened from where the command runs, which an agent in another worktree reaches with a leading `cd`.
enter_leading_cd "$cmd" || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0
[[ -x lib/check-passed.sh ]] || exit 0
base=$(git merge-base HEAD origin/main 2>/dev/null) || exit 0

lib/check-passed.sh passed-since "$base" HEAD && exit 0
reason="No recorded pass of 'lib/check.sh --changed $base' for HEAD's tree, so the PR was not opened. Commit everything (a pass is recorded only for a tree with nothing uncommitted or untracked), run that command in the background, and open the PR again once it passes; steps that already passed for the same files are skipped."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
