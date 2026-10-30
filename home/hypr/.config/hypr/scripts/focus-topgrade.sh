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
  title=$(tmux display -p -t "$pane" '#{session_name}')
fi

others=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | jq -R . | jq -sc .)
# A longer session name that also fits a title owns that window ("Config tools zsh" is not session "Config"), as in
# voxcmd's tmux.sh.
addr=$(hyprctl clients -j | jq -r --arg t "$title" --argjson others "${others:-[]}" '
  def fits($w; $s): $w == $s or ($w | startswith($s + " ")) or $w == "Tmux " + $s or ($w | startswith("Tmux " + $s + " "));
  [.[] | select((.title as $w | $t != "" and fits($w; $t) and ($others | map(select(length > ($t | length) and fits($w; .))) | length == 0))
    or .class == "quickshell-upgrade" or (.class | endswith("-topgrade")))]
  | first | .address // empty')

if [ -n "$addr" ]; then
  hyprctl dispatch "hl.dsp.focus({ window = 'address:$addr' })"
else
  exec "$HOME/.config/hypr/scripts/qs-ipc" call popup open updates
fi
