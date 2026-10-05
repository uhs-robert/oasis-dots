#!/usr/bin/env bash
# demo/stage-tmux.sh
# The showcase's terminal stage, both rooted in this repo: `dotfiles` (Neovim's dashboard beside yazi) and
# `agent` (Claude Code on Sonnet). The Demo launcher session opens a kitty on each.
#
#   stage-tmux.sh dotfiles|agent   create the session if it is missing, then attach
#   stage-tmux.sh kill             end both sessions

set -euo pipefail

repo_dir=$(dirname -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")")
DEMO_AGENT_CMD=${DEMO_AGENT_CMD:-claude --model sonnet}

# Session names double as the kitty window titles (tmux.conf sets the title to '#S'), which the overview beat
# searches for; keep them unique among open windows.
ensure_dotfiles() {
  tmux has-session -t =dotfiles 2>/dev/null && return 0
  # OASIS_DEMO keeps the dashboard's recent files and projects (personal paths) off camera.
  tmux new-session -d -s dotfiles -n editor -c "$repo_dir" "OASIS_DEMO=1 nvim"
  tmux split-window -h -t =dotfiles:editor -c "$repo_dir" yazi
  tmux select-pane -t =dotfiles:editor.0
}

ensure_agent() {
  tmux has-session -t =agent 2>/dev/null && return 0
  tmux new-session -d -s agent -n agent -c "$repo_dir" "$DEMO_AGENT_CMD"
}

case ${1:-} in
dotfiles)
  ensure_dotfiles
  exec tmux attach -t =dotfiles
  ;;
agent)
  ensure_agent
  exec tmux attach -t =agent
  ;;
kill)
  for session in dotfiles agent; do
    tmux kill-session -t "=$session" 2>/dev/null || true
  done
  ;;
*)
  echo "usage: stage-tmux.sh dotfiles|agent|kill" >&2
  exit 2
  ;;
esac
