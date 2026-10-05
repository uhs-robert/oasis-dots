#!/usr/bin/env bash
# demo/stage-tmux.sh
# The showcase's terminal stage, rooted in this repo: `dotfiles` (Neovim's dashboard beside yazi), `agent` (Claude
# Code on Sonnet), and three single-app sessions for the layout beat: `monitor` (btop), `git` (lazygit) and
# `readme` (glow). The Demo launcher session opens a kitty on each.
#
#   stage-tmux.sh <session>   create the session if it is missing, then attach
#   stage-tmux.sh kill        end every stage session

set -euo pipefail

repo_dir=$(dirname -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")")
DEMO_AGENT_CMD=${DEMO_AGENT_CMD:-claude --model sonnet}

# Session names double as the kitty window titles (tmux.conf sets the title to '#S'), which the overview beat
# searches for; keep them unique among open windows.
ensure_dotfiles() {
  tmux has-session -t =dotfiles 2>/dev/null && return 0
  local editor_pane
  # OASIS_DEMO keeps the dashboard's recent files and projects (personal paths) off camera. Panes are addressed
  # by id because pane-base-index varies between tmux configs.
  editor_pane=$(tmux new-session -d -P -F '#{pane_id}' -s dotfiles -n editor -c "$repo_dir" "OASIS_DEMO=1 nvim")
  # yazi opens on the Stow packages rather than the repo root, which holds untracked notes.
  # A narrow yazi leaves Neovim room for the dashboard logo once the resize beat widens the window.
  tmux split-window -h -l 35% -t "$editor_pane" -c "$repo_dir/home" yazi
  tmux select-pane -t "$editor_pane"
}

ensure_agent() {
  tmux has-session -t =agent 2>/dev/null && return 0
  tmux new-session -d -s agent -n agent -c "$repo_dir" "$DEMO_AGENT_CMD"
}

# Inside tmux so `kill` closes their kitty windows without kitty's close prompt.
ensure_app() {
  local session=$1 cmd=$2
  tmux has-session -t "=$session" 2>/dev/null && return 0
  tmux new-session -d -s "$session" -n "$session" -c "$repo_dir" "$cmd"
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
monitor | git | readme)
  case $1 in
  monitor) ensure_app monitor btop ;;
  git) ensure_app git lazygit ;;
  readme) ensure_app readme "glow -p README.md" ;;
  esac
  exec tmux attach -t "=$1"
  ;;
kill)
  for session in dotfiles agent monitor git readme; do
    tmux kill-session -t "=$session" 2>/dev/null || true
  done
  ;;
*)
  echo "usage: stage-tmux.sh dotfiles|agent|monitor|git|readme|kill" >&2
  exit 2
  ;;
esac
