#!/usr/bin/env bash
# PreToolUse(Bash): CHECK_FULL=1 on lib/check.sh reruns every step, ~4 minutes, even when the scoped run reported "skipped
# (passed for these inputs)". If the tree already has a recorded pass for the merge-base the run is denied, unless the
# same command sets CHECK_FULL_REASON="<why>": that is allowed, echoed into the transcript and appended to a log the
# orchestrator reads to judge each reason. Runs on every Bash call, so it leaves at once unless CHECK_FULL is named.
set -u
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ $cmd == *CHECK_FULL* ]] || exit 0

full_re='CHECK_FULL=(1|"1"|'"'1'"')([^[:alnum:]_]|$)'
check_re='lib/check\.sh|just[[:space:]]+check([[:space:]]|$)'
[[ $cmd =~ $full_re && $cmd =~ $check_re ]] || exit 0

# shellcheck source=command-dir.sh
source "$(dirname "${BASH_SOURCE[0]}")/command-dir.sh"
dir=$(jq -r '.cwd // empty' <<<"$input")
cd "${dir:-${CLAUDE_PROJECT_DIR:-$PWD}}" || exit 0
enter_command_cd "$cmd" "$check_re" || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0

reason_re='CHECK_FULL_REASON=("([^"]+)"|'"'([^']+)'"'|([^[:space:]"'"'"';&|]+))'
reason=
if [[ $cmd =~ $reason_re ]]; then
  reason=${BASH_REMATCH[2]:-${BASH_REMATCH[3]:-${BASH_REMATCH[4]}}}
fi

if [[ -n $reason ]]; then
  log=${CHECK_FULL_REASONS_LOG:-$HOME/.cache/dotfiles/check-full-reasons.log}
  branch=$(git branch --show-current 2>/dev/null)
  head=$(git rev-parse --short HEAD 2>/dev/null)
  mkdir -p "$(dirname "$log")" 2>/dev/null &&
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$root" "${branch:-detached}" "$head" "${reason//$'\n'/ }" >>"$log"
  note="CHECK_FULL allowed with reason (logged for the orchestrator): $reason"
  jq -n --arg n "$note" '{systemMessage: $n, hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $n}}'
  exit 0
fi

# Only a clean tree can match a record: with edits or new untracked files (the runner reads both), the run checks
# inputs nobody has passed.
[[ -x lib/check/passed.sh ]] || exit 0
[[ -z $(git status --porcelain --untracked-files=normal 2>/dev/null) ]] || exit 0
base=$(git merge-base HEAD origin/main 2>/dev/null) || exit 0
lib/check/passed.sh passed-since "$base" HEAD >/dev/null 2>&1 || exit 0

deny="This tree already has a recorded pass: the scoped 'lib/check.sh --changed $base' counts for these inputs, and 'skipped (passed for these inputs)' means those steps need no rerun. CHECK_FULL=1 is only for a reason the scoped run cannot cover. If you have one, rerun the same command with CHECK_FULL_REASON=\"<why>\" set; the reason is logged for the orchestrator."
jq -n --arg r "$deny" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
