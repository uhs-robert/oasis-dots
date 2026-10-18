#!/usr/bin/env bash
# Feeds commands to guard-tmux-socket.sh: tmux without -L/-S is denied unless read-only, and text that only
# shellcheck disable=SC2016 # the commands are fed to the hook literally, so nothing should expand
# mentions tmux passes.
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

# Own socket
expect allow 'tmux -L mine kill-server'
expect allow 'tmux -Lmine new-session -d'
expect allow 'tmux -S /tmp/s.sock send-keys -t x ls Enter'
expect allow 'tmux -S/tmp/s.sock kill-server'
expect allow 'env -u TMUX tmux -L mine kill-server'
expect allow 'tmux -2 -L mine attach'
expect allow 'tmux -f /dev/null -L mine new -d'
# Read-only without a socket
expect allow 'tmux ls'
expect allow 'tmux list-sessions'
expect allow 'tmux list-windows -a'
expect allow 'tmux list-panes'
expect allow 'tmux list-clients'
expect allow 'tmux list-keys'
expect allow 'tmux list-buffers'
expect allow 'tmux list-commands'
expect allow 'tmux has-session -t x'
expect allow 'tmux has -t x'
expect allow 'tmux display-message -p "#S"'
expect allow 'tmux display -p "#S"'
expect allow 'tmux display-message -t x -p "#S"'
expect allow 'tmux show-options -g'
expect allow 'tmux show -g'
expect allow 'tmux show-environment'
expect allow 'tmux showenv -g'
# Denied without a socket
expect deny 'tmux kill-server'
expect deny 'tmux kill-session -t x'
expect deny 'tmux new-session -d'
expect deny 'tmux new -d'
expect deny 'tmux new-window'
expect deny 'tmux send-keys -t x ls Enter'
expect deny 'tmux attach'
expect deny 'tmux capture-pane -p'
expect deny 'tmux set-option -g mouse on'
expect deny 'tmux source-file ~/.tmux.conf'
expect deny 'tmux display-message "hi"'
expect deny 'tmux'
expect deny 'tmux -2 kill-server'
expect deny 'tmux -f /dev/null kill-server'
expect deny 'tmux -u new'
expect deny '/usr/bin/tmux kill-server'
# Wrappers and prefixes
expect deny 'TMUX_TMPDIR=/tmp/x tmux kill-server'
expect deny 'env TMUX_TMPDIR=/tmp/x tmux kill-server'
expect deny 'env -u TMUX tmux kill-server'
expect deny 'env -u TMUX FOO=1 tmux new -d'
expect deny 'timeout 5 tmux kill-server'
expect deny 'timeout -s KILL 5 tmux kill-server'
expect deny 'sudo tmux kill-server'
expect deny 'sudo -u root tmux kill-server'
expect deny 'command tmux kill-server'
expect deny 'exec tmux attach'
expect deny 'nice tmux kill-server'
expect deny 'nice -n 5 tmux kill-server'
expect deny 'timeout 5 env A=1 tmux kill-server'
expect allow 'timeout 5 env -u TMUX tmux -L mine kill-server'
expect allow 'TMUX_TMPDIR=/tmp/x tmux ls'
# Chains
expect deny 'cd /tmp && tmux kill-server'
expect deny 'true || tmux kill-server'
expect deny 'echo hi; tmux kill-server'
expect deny 'echo hi | tmux load-buffer -'
expect deny 'sleep 1 & tmux kill-server'
expect deny $'echo hi\ntmux kill-server'
expect deny 'echo $(tmux kill-server)'
expect deny 'x=`tmux kill-server`'
expect deny '(tmux kill-server)'
expect deny 'if true; then tmux kill-server; fi'
expect deny 'tmux -L mine ls && tmux kill-server'
expect allow 'tmux -L a new -d && tmux -L a kill-server'
expect allow 'tmux ls && tmux has-session -t x'
expect deny 'tmux ls && tmux kill-server'
# tmux's own command separator
expect deny 'tmux list-sessions \; kill-server'
expect deny "tmux ls ';' kill-server"
expect deny 'tmux ls\; kill-server'
expect deny 'tmux ls ";" new -d'
expect allow 'tmux ls \; list-windows'
expect allow 'tmux -L mine ls \; kill-server'
# Format expansion runs shell on the server
expect deny "tmux list-panes -F '#(tmux kill-server)'"
expect deny "tmux display-message -p '#(touch /tmp/x)'"
expect allow "tmux list-panes -F '#{pane_id}'"
expect allow "tmux -L mine list-panes -F '#(echo hi)'"
# Leading redirections
expect deny '< /dev/null tmux kill-server'
expect deny '> /tmp/out tmux kill-server'
expect deny '>/tmp/out tmux kill-server'
expect deny '2>/dev/null tmux kill-server'
expect deny '2>&1 tmux kill-server'
expect deny '&>/dev/null tmux kill-server'
expect deny '>> /tmp/out tmux kill-server'
expect deny 'echo hi && <>/tmp/x tmux kill-server'
expect deny '>| /tmp/out env A=1 tmux kill-server'
expect deny 'tmux kill-server > /dev/null 2>&1'
expect allow '> /tmp/out tmux -L mine kill-server'
expect allow 'tmux ls > /tmp/out'
expect allow 'echo hi > /tmp/tmux.txt'
expect allow 'cat < /tmp/tmux.txt'
# xargs and watch wrappers
expect deny 'xargs tmux kill-server'
expect deny 'echo x | xargs -n 1 tmux kill-session -t'
expect deny 'watch tmux kill-server'
expect deny 'watch -n 1 tmux kill-server'
expect allow 'watch -n 1 tmux ls'
expect allow 'xargs -I{} tmux -L mine kill-session -t {}'
# Mentions only
expect allow 'git commit -m "fix: tmux kill-server guard"'
expect allow "git commit -m 'stop tmux kill-server'"
expect allow 'grep tmux file'
expect allow 'grep -rn "tmux kill-server" .'
expect allow 'echo "tmux kill-server"'
expect allow 'echo tmux kill-server'
expect allow 'cat ~/.tmux.conf'
expect allow 'command -v tmux'
expect allow 'which tmux'
expect allow 'echo hi # tmux kill-server'
expect allow 'pgrep -x tmux'
expect allow 'cat <<EOF
tmux is great
EOF'

echo "$pass passed, $fail failed"
((fail == 0))
