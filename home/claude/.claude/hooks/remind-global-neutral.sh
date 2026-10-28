#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit|NotebookEdit): when the target is a shared agent definition in the installed config
# directory (skills, agents, commands, hooks, status.d, settings.json, CLAUDE.md), add a project-neutrality reminder to
# the agent's context. Never blocks; prints nothing for other paths, including the directory's runtime state
# (projects, todos, ...). A project that keeps the source of these files elsewhere can point CLAUDE_CONFIG_DIR at it.
# The same entries under home/claude/.claude/ also count, so an edit in any checkout or worktree of the dotfiles that
# source them gets the reminder; the installed symlink does not reach those.
set -u
path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null) || exit 0
[[ -n $path ]] || exit 0

# -m: the file may not exist yet. Each entry is resolved on its own because an install may symlink the whole directory
# or only some entries, into a checkout anywhere on disk.
resolved=$(readlink -f -m -- "$path" 2>/dev/null) || exit 0
config_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
matched=
for entry in skills agents commands hooks status.d settings.json CLAUDE.md; do
  real_entry=$(readlink -f -m -- "$config_dir/$entry" 2>/dev/null) || continue
  if [[ $resolved == "$real_entry" || $resolved == "$real_entry"/* ||
    $resolved == */home/claude/.claude/"$entry" || $resolved == */home/claude/.claude/"$entry"/* ]]; then
    matched=1
    break
  fi
done
[[ -n $matched ]] || exit 0

reminder="This is a global agent file, loaded in every project. Each line must hold in an unrelated repository (say a Python web app or a Rust CLI). Guidance specific to one project belongs in the project's own docs/config, not here."
jq -n --arg r "$reminder" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $r}}'
