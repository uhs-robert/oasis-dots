#!/usr/bin/env bash
# Sourced by spawn-successor.sh and rename-window.sh: the orchestrator window names `orch-<N>[-next|-prev|-done]`.
# N comes from one global counter, not a per-repo or per-session one, so two windows never share a number.

counter_dir=${XDG_STATE_HOME:-$HOME/.local/state}/claude

# Prints the next number. flock keeps two concurrent spawns from reading the same value.
next_window_number() {
  mkdir -p "$counter_dir"
  (
    flock 9
    n=$(cat "$counter_dir/orchestrator-window-counter" 2>/dev/null || echo 0)
    [[ $n =~ ^[0-9]+$ ]] || n=0
    n=$((n + 1))
    echo "$n" >"$counter_dir/orchestrator-window-counter"
    echo "$n"
  ) 9>"$counter_dir/orchestrator-window-counter.lock"
}

# The caller's own window id, from $TMUX_PANE: the active window may be a different one.
own_window_id() {
  tmux display-message -p -t "${TMUX_PANE:?}" '#{window_id}'
}

# Prints the number in a window name, or nothing when it is not an orch-<N> name.
window_number_of() {
  local name
  name=$(tmux display-message -p -t "$1" '#{window_name}')
  [[ $name =~ ^orch-([0-9]+)(-next|-prev|-done)?$ ]] && echo "${BASH_REMATCH[1]}"
  return 0
}
