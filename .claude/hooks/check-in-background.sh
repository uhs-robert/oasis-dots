#!/usr/bin/env bash
# PreToolUse(Bash): a command that runs the check, a voxcmd suite or ship-batch always runs in the background. Each may
# wait up to CHECK_LOCK_WAIT_SECS for the machine-wide lock, longer than a foreground call lives, and a killed wait tells
# the agent nothing; in the background it waits as long as the lock needs and the agent is notified when it ends.
# Only the input changes: no permission decision is returned, so the call still goes through the normal permission flow.
set -u
input=$(cat)
[[ $(jq -r '.tool_input.run_in_background // false' <<<"$input") == true ]] && exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ $cmd == *--plan* ]] && exit 0

# Matches where a command starts (line start or after ; & | ( ), past env assignments and timeout/env/sh/bash wrappers,
# so a path that is only an argument (shellcheck lib/check.sh, git diff lib/check.sh) does not count.
start='(^|[;&|(]|\n)[[:space:]]*'
wrappers='(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|env|timeout[[:space:]]+[^[:space:]]+|(ba)?sh)[[:space:]]+)*'
target='([^[:space:];&|]*/)?(lib/check\.sh|\.claude/skills/ship-batch/ship-batch\.sh|home/voxcmd/tests/(sandbox\.sh[[:space:]]+([^[:space:];&|]*/)?)?run[^/[:space:];&|]*\.sh)([[:space:]]|$)'
just_check="${start}just[[:space:]]+check([[:space:]]|$)"
[[ $cmd =~ ${start}${wrappers}${target} || $cmd =~ $just_check ]] || exit 0

jq -c '{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: (.tool_input + {run_in_background: true})}}' <<<"$input"
