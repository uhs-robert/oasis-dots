#!/usr/bin/env bash
# PreToolUse(Bash): refuse to kill Quickshell while it is showing the lock screen.
set -u
cmd=$(jq -r '.tool_input.command // empty')
[[ -n $cmd ]] || exit 0

kills_qs='(^|[;&|[:space:]])(pkill|killall)[^;&|]*[[:space:]](-x[[:space:]]+)?(qs|quickshell)([[:space:];&|]|$)'
kills_pid='(^|[;&|[:space:]])kill[^;&|]*\$\(pgrep[^)]*(qs|quickshell)'
[[ $cmd =~ $kills_qs || $cmd =~ $kills_pid ]] || exit 0

pgrep -x qs >/dev/null || pgrep -x quickshell >/dev/null || exit 0

state=$(timeout 3 "${QS_IPC:-$HOME/.config/hypr/scripts/qs-ipc}" call lock state 2>/dev/null)
[[ $state == unlocked ]] && exit 0

reason="Blocked: this command kills Quickshell, and Quickshell also runs the lock screen. The lock state is '${state:-unknown (qs-ipc did not answer)}', so killing it now could drop the lock or the password prompt while the owner is locked out. Wait until '~/.config/hypr/scripts/qs-ipc call lock state' prints 'unlocked', then retry. Restart the bar with: pkill -x qs; hyprctl dispatch \"hl.dsp.exec_cmd('qs -n')\" (never launch qs from this shell, it would inherit TMUX)."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
