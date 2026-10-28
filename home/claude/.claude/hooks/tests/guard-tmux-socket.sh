#!/usr/bin/env bash
# Feeds commands to guard-tmux-socket.sh: a tmux call without -L/-S is denied unless read-only; mentions pass.
set -uo pipefail
hook=$(cd "$(dirname "$0")" && pwd)/../guard-tmux-socket.sh
pass=0 fail=0

# expect <allow|deny> <command>
expect() {
  local out got=allow
  out=$(jq -n --arg c "$2" '{tool_input: {command: $c}}' | "$hook" | jq -r '.hookSpecificOutput.permissionDecision // empty')
  [[ $out == deny ]] && got=deny
  if [[ $got == "$1" ]]; then
    echo "ok   $1: $2"
    pass=$((pass + 1))
  else
    echo "FAIL $1: $2 (got $got)"
    fail=$((fail + 1))
  fi
}

expect deny 'tmux kill-server'
expect deny 'cd x && tmux new -d'
expect deny 'echo hi | tmux load-buffer -'
expect deny 'tmux ls; tmux kill-server'
expect allow 'tmux -L x new -d'
expect allow 'env -u TMUX tmux -L x kill-server'
expect allow 'tmux ls'
expect allow 'tmux display-message -p "#S"'
expect allow 'grep tmux file'
expect allow 'git commit -m "fix: tmux kill-server guard"'

echo "$pass passed, $fail failed"
((fail == 0))
