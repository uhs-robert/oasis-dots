#!/usr/bin/env bash
# PostToolUse(Write|Edit|MultiEdit): tell the agent when a .plans/ doc it just wrote has front matter that breaks
# plan-frontmatter.yaml. A steer, not a guard: the file is already written, a doc written through Bash is not seen, and
# a machine without check-jsonschema stays silent. Always exits 0.
set -u
file=$(jq -r '.tool_input.file_path // empty')
[[ $file == */.plans/*.md && -f $file ]] || exit 0
command -v check-jsonschema >/dev/null || exit 0
schema=$(dirname "$0")/plan-frontmatter.yaml

# The leading --- block, as YAML.
front=$(mktemp --suffix=.yaml)
trap 'rm -f "$front"' EXIT
if ! awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && $0 == "---" { exit } NR > 1' "$file" >"$front"; then
  errors="no front matter (a plan starts with a --- block)"
else
  errors=$(check-jsonschema --schemafile "$schema" "$front" 2>&1) && exit 0
  errors=${errors//"$front"/"$file"}
fi
msg="Front matter of $file breaks .claude/hooks/plan-frontmatter.yaml:
$errors
Fix it, or scaffold a valid doc with \`just plan-new <topic> <tracker|plan|handoff> [item]\` from the main checkout. Fields: kind, status, owner_session, updated, branch (plan and handoff), pr; no other keys."
jq -n --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
