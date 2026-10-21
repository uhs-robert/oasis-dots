#!/usr/bin/env bash
# PreToolUse(Bash): route PR merges through ship-batch, which also cleans up and leaves a running test bar alone.
set -u
cmd=$(jq -r '.tool_input.command // empty')

# Drop heredoc bodies and quoted -m/--message/--body/--title values, so a commit or PR message that mentions a merge
# is no call. An unterminated quote does not match and stays in the text, so doubt still denies.
cmd=$(awk '
  skip { t = $0; sub(/^\t+/, "", t); if (t == tag) { skip = 0; print } ; next }
  { print }
  match($0, /(^|[^<])<<-?[ ]*[\047"\\]?[A-Za-z_][A-Za-z0-9_]*/) { tag = substr($0, RSTART, RLENGTH); sub(/^.*<<-?[ ]*[\047"\\]?/, "", tag); skip = 1 }
' <<<"$cmd")
message_arg="(-m|--message|--body|--title)[[:space:]=]*('[^']*'|\"([^\"\\\\]|\\\\.)*\")"
while [[ $cmd =~ $message_arg ]]; do cmd=${cmd/"${BASH_REMATCH[0]}"/}; done

# merge-prs.sh is the merge engine ship-batch calls itself (a subprocess this hook never sees), so a direct run that
# merges skips ship-batch's per-PR check, restows and post-merge check. Only a command word counts, not a mention
# (`grep merge-prs.sh x`); `--check` and `--help` merge nothing.
nl=$'\n'
# Wrappers that still run the script as the command word: timeout <dur>, env and VAR=val, sh/bash, exec, nohup, command, time, !.
# The arguments are the last capture group, whatever the number of prefix groups.
prefix='((timeout[[:space:]]+[^[:space:]]+|env|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|bash|sh|exec|nohup|command|time|!)[[:space:]]+)*'
invocation="(^|[;&|(\`$nl])[[:space:]]*${prefix}([^[:space:]]*/)?merge-prs\.sh([^;&|)\`$nl]*)"
merges_directly() {
  local rest=$cmd args
  while [[ $rest =~ $invocation ]]; do
    args=${BASH_REMATCH[${#BASH_REMATCH[@]} - 1]}
    rest=${rest#*"${BASH_REMATCH[0]}"}
    [[ $args =~ ^[[:space:]]*$ || $args =~ [[:space:]](--check|--help|-h)([[:space:]=]|$) ]] || return 0
  done
  return 1
}

# Global flags (`gh -R x pr merge`) and pr flags (`gh pr -R x merge`) may precede the subcommand.
gh_flags='(-[^[:space:]]+[[:space:]]+([^-[:space:]][^[:space:]]*[[:space:]]+)?)*'
gh_merge="gh[[:space:]]+${gh_flags}pr[[:space:]]+${gh_flags}merge([[:space:]]|\$)"
[[ $cmd =~ $gh_merge ]] || merges_directly || exit 0

reason="Blocked: merge PRs with \`.claude/skills/ship-batch/ship-batch.sh <pr>...\` (in merge order), not \`gh pr merge\` or a direct \`merge-prs.sh <pr>\`; \`merge-prs.sh --check\` is still fine. ship-batch checks each PR, rebase-merges, rebases stacked PRs, removes merged worktrees and branches, pulls main, restows packages that gained files, syncs the greeter, restarts the bar (skipped while a test bar is running) and checks main. After a PR was merged on GitHub by hand, run \`ship-batch.sh\` with no arguments for the post-merge steps. Load the ship-batch skill for details."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
