#!/usr/bin/env bash
# demo/stage-tmux.sh
# The showcase's terminal stage, rooted in this repo: `dotfiles` (Neovim's dashboard), `files` (yazi on `home/`),
# `agent` (Claude Code on Sonnet), and `monitor` (btop) and `git` (lazygit) for the layout beat. The Demo launcher
# session opens a kitty on each.
#
#   stage-tmux.sh <session>   create the session if it is missing, then attach
#   stage-tmux.sh kill        end every stage session

set -euo pipefail

repo_dir=$(dirname -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")")
DEMO_AGENT_CMD=${DEMO_AGENT_CMD:-claude --model sonnet}

# Each app gets a one-pane session so `kill` closes its kitty window without kitty's close prompt. Session names
# double as the kitty window titles (tmux.conf sets the title to '#S'), which the overview beat searches for; keep
# them unique among open windows.
ensure_app() {
  local session=$1 dir=$2 cmd=$3
  tmux has-session -t "=$session" 2>/dev/null && return 0
  tmux new-session -d -s "$session" -n "$session" -c "$dir" "$cmd"
}

case ${1:-} in
dotfiles | files | agent | monitor | git)
  case $1 in
  # OASIS_DEMO keeps the dashboard's recent files and projects (personal paths) off camera.
  dotfiles) ensure_app dotfiles "$repo_dir" "OASIS_DEMO=1 nvim" ;;
  # yazi opens on the Stow packages rather than the repo root, which holds untracked notes.
  files) ensure_app files "$repo_dir/home" yazi ;;
  agent) ensure_app agent "$repo_dir" "$DEMO_AGENT_CMD" ;;
  monitor) ensure_app monitor "$repo_dir" btop ;;
  git) ensure_app git "$repo_dir" lazygit ;;
  esac
  exec tmux attach -t "=$1"
  ;;
kill)
  for session in dotfiles files agent monitor git; do
    tmux kill-session -t "=$session" 2>/dev/null || true
  done
  ;;
*)
  echo "usage: stage-tmux.sh dotfiles|files|agent|monitor|git|kill" >&2
  exit 2
  ;;
esac
