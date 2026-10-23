#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit|NotebookEdit): when the target is a global agent file (skills, agents, commands,
# hooks, or anything else under a checkout's home/claude/.claude/), add a project-neutrality reminder to the agent's
# context. Never blocks and prints nothing for other paths.
set -u
path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null) || exit 0
[[ -n $path ]] || exit 0

# -m: the file may not exist yet. Resolving symlinks maps ~/.claude/... onto the checkout it links to.
resolved=$(realpath -m -- "$path" 2>/dev/null) || exit 0
global_home=$(realpath -m -- "$HOME/.claude" 2>/dev/null) || exit 0
case $resolved in
*/home/claude/.claude/*) ;;
"$global_home"/skills/* | "$global_home"/agents/* | "$global_home"/commands/* | "$global_home"/hooks/*) ;;
*) exit 0 ;;
esac

reminder="This is a global agent file, loaded in every project. Each line must hold in an unrelated repository (say a Python web app or a Rust CLI). Guidance specific to one project belongs in that project's AGENTS.md or its .claude/skills/, not here."
jq -n --arg r "$reminder" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $r}}'
