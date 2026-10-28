#!/usr/bin/env bash
# shellcheck disable=SC2016 # the commands are fed to the hook literally, so nothing should expand
# Feeds commands to guard-tmux-socket.sh. The rule fails closed: any `tmux` word is denied unless every one carries a
# provably separate -L/-S socket, or the whole command is one plain read-only tmux call. Wrappers and shells need no
# entry of their own, and so do text that merely mentions tmux (they are denied too; see the hook).
set -uo pipefail
hook=$(cd "$(dirname "$0")" && pwd)/../guard-tmux-socket.sh
pass=0 fail=0

# expect <allow|deny> <command> [the hook's own $TMUX]
expect() {
  local out got=allow
  out=$(jq -n --arg c "$2" '{tool_input: {command: $c}}' | TMUX=${3:-/run/owner/sock,123,0} "$hook" | jq -r '.hookSpecificOutput.permissionDecision // empty')
  [[ $out == deny ]] && got=deny
  if [[ $got == "$1" ]]; then
    echo "ok   $1: $2"
    pass=$((pass + 1))
  else
    echo "FAIL $1: $2 (got $got)"
    fail=$((fail + 1))
  fi
}

# No tmux word: untouched
expect allow 'ls -la'
expect allow 'echo mux'
# Own socket
expect allow 'tmux -L mine kill-server'
expect allow 'tmux -Lmine new-session -d'
expect allow 'tmux -S /tmp/s.sock send-keys -t x ls Enter'
expect allow 'env -u TMUX tmux -L mine kill-server'
expect allow 'tmux -2 -L mine attach'
expect allow 'tmux -L a new -d && tmux -L a kill-server'
# Read-only single calls
expect allow 'tmux ls'
expect allow 'tmux list-windows -a'
expect allow 'tmux has-session -t x'
expect allow 'tmux display-message -p "#S"'
expect allow 'tmux show-options -g'
# Owner socket reachable
expect deny 'tmux kill-server'
expect deny 'tmux new-session -d'
expect deny 'tmux send-keys -t x ls Enter'
expect deny 'tmux display-message "hi"'
expect deny 'TMUX_TMPDIR=/tmp/x tmux kill-server'
expect deny 'env -u TMUX tmux kill-server'
expect deny '/usr/bin/tmux kill-server'
expect deny 'cd /tmp && tmux kill-server'
expect deny 'echo $(tmux kill-server)'
# Read-only prefix does not cover a chained or ;-joined second command
expect deny 'tmux ls && tmux kill-server'
expect deny 'tmux ls; tmux kill-server'
expect deny 'tmux list-sessions \; kill-server'
expect deny "tmux list-panes -F '#(tmux kill-server)'"
expect deny 'tmux -L mine ls && tmux kill-server'
# Sockets that are not provably separate
expect deny 'tmux -L default kill-server'
expect deny 'tmux -L "$X" kill-server'
expect deny 'tmux -S ~/s.sock kill-server'
expect deny 'tmux -S /tmp/tmux-1000/default kill-server'
expect deny 'tmux -S /run/owner/sock kill-server'
expect deny 'tmux -S sock kill-server'
expect deny 'tmux -L work kill-server' "/tmp/tmux-$(id -u)/work,1,0"
# Fail closed on wrappers and shells the rule has no entry for
expect deny 'setsid tmux kill-server'
expect deny 'stdbuf -o0 tmux kill-server'
expect deny "bash -c 'tmux kill-server'"
expect deny "watch 'tmux kill-server'"
expect deny $'cat <<END\nbody\ntmux kill-server'
expect deny 'tm\
ux kill-server'
# Mentions are denied too: the cost of failing closed
expect deny 'grep tmux file'

echo "$pass passed, $fail failed"
((fail == 0))
