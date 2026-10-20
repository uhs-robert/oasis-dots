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
pr_create_re='gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'
[[ $cmd =~ $pr_create_re ]] || exit 0
dir=$(jq -r '.cwd // empty' <<<"$input")
cd "${dir:-${CLAUDE_PROJECT_DIR:-$PWD}}" || exit 0
# The PR is opened from where the command runs, which an agent in another worktree reaches with a `cd` before it.
enter_command_cd "$cmd" "$pr_create_re" || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0
[[ -x lib/check/passed.sh ]] || exit 0
base=$(git merge-base HEAD origin/main 2>/dev/null) || exit 0

lib/check/passed.sh passed-since "$base" HEAD && exit 0
reason="No recorded pass of 'lib/check.sh --changed $base' for HEAD's tree, so the PR was not opened. Commit everything (a pass is recorded only for a tree with nothing uncommitted or untracked), run that command in the background, and open the PR again once it passes; steps that already passed for the same files are skipped."
# A check chained into this very command cannot have been recorded yet, which the message above does not say.
# Only a check at command position counts: a mention inside a quoted --body or a longer word (`just checkfoo`) does not.
nl=$'\n'
chained_re="(^|[;&|(]|$nl)[[:space:]]*(([^][:space:];&|(]*/)?lib/check\\.sh|just[[:space:]]+check)([[:space:];&]|\$)"
if [[ $cmd =~ $chained_re ]]; then
  reason+=" This command is judged before it runs, so a check inside it cannot count: run the check as its own earlier call, then gh pr create in a separate one."
fi
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
