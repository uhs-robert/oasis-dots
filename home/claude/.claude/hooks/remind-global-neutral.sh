#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit|NotebookEdit): when the target is a shared agent definition (skills, agents, commands,
# hooks, settings, status.d, CLAUDE.md), add a project-neutrality reminder to the agent's context. Never blocks;
# prints nothing for other paths, including the config directory's runtime state (projects, todos, ...).
set -u
path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null) || exit 0
[[ -n $path ]] || exit 0

# -m: the file may not exist yet. Resolving symlinks maps the config directory onto the tracked source it links to.
resolved=$(realpath -m -- "$path" 2>/dev/null) || exit 0
config_dir=$(realpath -m -- "$HOME/.claude" 2>/dev/null) || exit 0
case $resolved in
*/home/claude/.claude/*) relative=${resolved##*/home/claude/.claude/} ;;
"$config_dir"/*) relative=${resolved#"$config_dir"/} ;;
*) exit 0 ;;
esac
case $relative in
skills/* | agents/* | commands/* | hooks/* | status.d/* | settings.json | CLAUDE.md) ;;
*) exit 0 ;;
esac

reminder="This is a global agent file, loaded in every project. Each line must hold in an unrelated repository (say a Python web app or a Rust CLI). Guidance specific to one project belongs in the project's own docs/config, not here."
jq -n --arg r "$reminder" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $r}}'
