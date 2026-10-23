#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit|NotebookEdit): the global neutrality reminder, for edits to this repo's source of the
# global agent files in any checkout or worktree. The global hook only knows the installed ~/.claude, and a path in
# another worktree is not behind that symlink. It supplies the reminder text; this hook only names the source tree.
set -u
input=$(cat)
path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input" 2>/dev/null) || exit 0
[[ -n $path ]] || exit 0

resolved=$(readlink -f -m -- "$path" 2>/dev/null) || exit 0
case $resolved in
*/home/claude/.claude/*) ;;
*) exit 0 ;;
esac
source_root=${resolved%%/home/claude/.claude/*}/home/claude/.claude

# Edits through the installed symlink already got the global hook's reminder.
installed=$(readlink -f -m -- "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" 2>/dev/null) || exit 0
[[ $source_root == "$installed" ]] && exit 0

CLAUDE_CONFIG_DIR=$source_root bash "$(dirname "$0")/../../home/claude/.claude/hooks/remind-global-neutral.sh" <<<"$input"
