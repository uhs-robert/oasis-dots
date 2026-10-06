#!/usr/bin/env bash
# PreToolUse(Bash): route PR merges through ship-batch, which also cleans up and leaves a running test bar alone.
set -u
cmd=$(jq -r '.tool_input.command // empty')
[[ $cmd =~ gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$) ]] || exit 0

reason="Blocked: merge PRs with \`.claude/skills/ship-batch/ship-batch.sh <pr>...\` (in merge order), not \`gh pr merge\`. It rebase-merges, rebases stacked PRs, removes merged worktrees and branches, pulls main, runs \`just check\`, and skips the bar restart while a test bar is running. Load the ship-batch skill for details."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
