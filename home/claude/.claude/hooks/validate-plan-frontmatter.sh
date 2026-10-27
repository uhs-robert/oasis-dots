#!/usr/bin/env bash
# PostToolUse(Write|Edit|MultiEdit): tell the agent when a .plans/ doc it just wrote has front matter that breaks
# specs/schema/plan.yaml. A steer, not a guard: the file is already written, a doc written through Bash is not seen, and
# a machine without check-jsonschema stays silent. Always exits 0.
set -u
file=$(jq -r '.tool_input.file_path // empty')
[[ $file == */.plans/*.md && -f $file ]] || exit 0
command -v check-jsonschema >/dev/null || exit 0
# .plans/ lives in the main checkout, so the repo is the path's prefix before it.
root=${file%%/.plans/*}
checker=$root/lib/check/steps/specs.py
[[ -f $checker ]] || exit 0

errors=$(cd "$root" && python3 -B "$checker" --file "$file" 2>&1) && exit 0
msg="Front matter of $file breaks specs/schema/plan.yaml:
$errors
Fix it, or scaffold a valid doc with \`just plan-new <topic> <tracker|plan|handoff> [item]\` from the main checkout. Fields: kind, status, owner_session, updated, specs, branch (plan and handoff), pr; no other keys."
jq -n --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
