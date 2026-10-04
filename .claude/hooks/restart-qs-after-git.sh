#!/usr/bin/env bash
# PostToolUse(Bash): after a git command moves the live checkout, restart the stowed Quickshell if its files changed.
set -u
cmd=$(jq -r '.tool_input.command // empty')
[[ $cmd =~ (^|[;&|[:space:]])git[[:space:]].*(switch|checkout|merge|pull|rebase|reset|restore|stash)([[:space:]]|$) ]] || exit 0

live=$(readlink -f "$HOME/.config/quickshell" 2>/dev/null) || exit 0
repo=$(git -C "$live" rev-parse --show-toplevel 2>/dev/null) || exit 0
moved_at=$(git -C "$repo" log -g -1 --format=%ct HEAD 2>/dev/null) || exit 0
((moved_at >= $(date +%s) - 120)) || exit 0
git -C "$repo" diff --quiet 'HEAD@{1}' HEAD -- home/quickshell 2>/dev/null && exit 0

say() { jq -n --arg c "$1" '{systemMessage: $c, hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'; }

if pgrep -af '^qs .*-p ' >/dev/null; then
  say "Quickshell files changed in the live checkout ($repo), but a worktree test bar is running (qs -p ...), so the stowed bar was not restarted. Restore it with the test-bar skill when testing is done."
  exit 0
fi
state=$(timeout 3 "${QS_IPC:-$HOME/.config/hypr/scripts/qs-ipc}" call lock state 2>/dev/null)
if [[ $state != unlocked ]] && pgrep -x qs >/dev/null; then
  say "Quickshell files changed in the live checkout, but the lock state is '${state:-unknown}', so the bar was not restarted (killing it could drop the lock). Restart it once the owner is unlocked: pkill -x qs; hyprctl dispatch \"hl.dsp.exec_cmd('qs -n')\"."
  exit 0
fi

pkill -x qs
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x qs >/dev/null || break; sleep 0.2; done
hyprctl dispatch "hl.dsp.exec_cmd('qs -n')" >/dev/null 2>&1
sleep 3
if pgrep -x qs >/dev/null; then
  say "Quickshell files changed in the live checkout ($repo), so the stowed bar was restarted: hot-reload can keep stale code after a git checkout or merge. Check 'qs log' for load errors before telling the owner it is live."
else
  say "Quickshell files changed and the bar was restarted, but qs is not running now: it probably failed to load. Read 'qs log' for the error and relaunch with hyprctl dispatch \"hl.dsp.exec_cmd('qs -n')\"."
fi
