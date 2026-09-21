#!/usr/bin/env bash
# keeptabs: shared helpers for keeptabs-hook, keeptabs-pick, and keeptabs-waybar.

# Print a pid and each of its parents up to init.
ancestors() {
  local pid="$1" key value
  while [[ "$pid" -gt 1 ]]; do
    echo "$pid"
    value=1
    while read -r key value; do
      [[ "$key" == PPid: ]] && break
    done <"/proc/$pid/status" 2>/dev/null
    pid="${value:-1}"
  done
}

# True when the user is looking at this session: its terminal has focus, and its tmux pane
# and nvim terminal buffer are the active ones where they apply.
session_focused() {
  local pid="$1" socket="$2" pane="$3" nvim="$4"
  local match session active chain kitty_sock current

  if [[ -n "$pane" ]]; then
    # With focus-events on, tmux flags the client whose terminal has focus.
    read -r match session < <(tmux -S "$socket" display -p -t "$pane" \
      '#{&&:#{pane_active},#{window_active}} #{session_name}' 2>/dev/null)
    [[ "$match" == 1 ]] || return 1
    tmux -S "$socket" list-clients -t "$session" -F '#{client_flags}' 2>/dev/null |
      grep -q '\bfocused\b' || return 1
  else
    active="$(hyprctl activewindow -j 2>/dev/null | jq -r '.pid // empty')"
    chain="$(ancestors "$pid")"
    [[ -n "$active" ]] && grep -qx "$active" <<<"$chain" || return 1
    kitty_sock="${XDG_RUNTIME_DIR:-/tmp}/kitty-$active"
    if [[ -S "$kitty_sock" ]]; then
      kitten @ --to "unix:$kitty_sock" ls --match state:focused 2>/dev/null |
        jq -r '.[].tabs[].windows[] | .pid, .foreground_processes[].pid' |
        grep -qxF -f - <(printf '%s\n' "$chain") || return 1
    fi
  fi

  if [[ -S "$nvim" ]]; then
    current="$(nvim --server "$nvim" --remote-expr \
      "&buftype ==# 'terminal' ? jobpid(&channel) : 0" 2>/dev/null)"
    ancestors "$pid" | grep -qx "$current" || return 1
  fi
  return 0
}
