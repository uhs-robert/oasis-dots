#!/usr/bin/env bash
# hypr/.config/hypr/scripts/focus-topgrade.sh
# Focus the running topgrade window (selecting its tmux pane), or open the updates popup when none runs.

pid=$(pgrep -xo topgrade) || exec "$HOME/.config/hypr/scripts/qs-ipc" call popup open updates

ancestors=" "
p=$pid
while [ -n "$p" ] && [ "$p" -gt 1 ]; do
  ancestors+="$p "
  p=$(ps -o ppid= -p "$p" | tr -d ' ')
done

title=""
pane=$(tmux list-panes -a -F '#{pane_pid} #{pane_id}' 2>/dev/null |
  while read -r pane_pid pane_id; do
    [[ "$ancestors" == *" $pane_pid "* ]] && echo "$pane_id" && break
  done)
if [ -n "$pane" ]; then
  tmux select-window -t "$pane" \; select-pane -t "$pane"
  title=$(tmux display -p -t "$pane" '#{T:set-titles-string}')
fi

addr=$(hyprctl clients -j | jq -r --arg t "$title" '
  [.[] | select(($t != "" and .title == $t) or .class == "quickshell-upgrade" or (.class | endswith("-topgrade")))]
  | first | .address // empty')

if [ -n "$addr" ]; then
  hyprctl dispatch "hl.dsp.focus({ window = 'address:$addr' })"
else
  exec "$HOME/.config/hypr/scripts/qs-ipc" call popup open updates
fi
