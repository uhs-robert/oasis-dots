# shellcheck shell=bash
# Hook library of keeptabs.toml: sourced before every hook and action of the integration.

# The bar runs ~/.local/bin/keeptabs-pick by path, since it may not be on PATH; PATH wins so tests can stub it.
keeptabs_pick_path() { command -v keeptabs-pick || echo "$HOME/.local/bin/keeptabs-pick"; }

keeptabs_pick() { "$(keeptabs_pick_path)" "$@"; }

# A session in a tmux nobody is attached to gets a terminal started in the background, which would keep voxcmd
# waiting on the captured output until that terminal closed.
focus_agent() { keeptabs_pick --focus "$1" >/dev/null 2>&1; }

agent_sessions() { keeptabs_pick --json 2>/dev/null || echo '[]'; }

agent_label() {
  agent_sessions | jq -r --arg id "$1" 'first(.[] | select(.id == $id) | "\(.title // "Untitled") (\(.project))") // empty'
}

# keeptabs-pick lists waiting sessions first, then done, running and idle, oldest first within a state, so the first
# session in one of the given states is the one that has waited longest.
first_agent_in_state() {
  agent_sessions | jq -r --args 'first(.[] | select(.state | IN($ARGS.positional[])) | .id) // empty' "$@"
}

focus_first_in_state() {
  local id
  id=$(first_agent_in_state "$@")
  if [ -z "$id" ]; then
    echo "no agent is $(printf '%s' "$*" | sed 's/ / or /g')"
    return 0
  fi
  focus_agent "$id" && agent_label "$id"
}

# keeptabs-pick --focus marks a done session seen, dropping it to idle, so saying it again reaches the next done one.
focus_oldest_done() {
  local id
  id=$(first_agent_in_state "done")
  if [ -z "$id" ]; then
    # A silent action's output is dropped, and this is the answer, not a failure.
    notify-send --transient --app-name=voxcmd "no agent is done"
    return 0
  fi
  focus_agent "$id"
}

# Steps $1 (1 or -1) through keeptabs-pick's order from the focused agent, wrapping around. With none focused, "next"
# starts at the first agent and "previous" at the last.
# keeptabs' own session_focused decides which agents are focused, the test keeptabs-hook uses to mark a finished
# session seen, so voxcmd agrees with keeptabs about where the user is. More than one can be: an agent started from
# inside another's pane (codex run from a Claude session) shares its tmux pane. Those are stepped over, since
# jumping to one would leave the screen as it was.
focus_cycled_agent() {
  local step="$1" sessions count index current="" lib pid socket pane nvim
  local -a focused=()
  sessions=$(agent_sessions)
  count=$(jq length <<<"$sessions")
  if [ "$count" = 0 ]; then
    echo "no agents are tracked"
    return 0
  fi
  lib="$(dirname "$(readlink -f "$(keeptabs_pick_path)")")/../share/keeptabs/lib.sh"
  # shellcheck source=/dev/null
  if [ -r "$lib" ] && source "$lib"; then
    index=0
    # \x1f separates the fields so an empty tmux pane or nvim socket survives read, as in keeptabs-pick.
    while IFS=$'\x1f' read -r pid socket pane nvim; do
      if session_focused "$pid" "$socket" "$pane" "$nvim" </dev/null; then
        focused[index]=1
        current="${current:-$index}"
      fi
      index=$((index + 1))
    done < <(jq -r '.[] | [.pid, .tmux_socket, .tmux_pane, .nvim] | map(. // "" | tostring) | join("\u001f")' <<<"$sessions")
  fi
  if [ -z "$current" ]; then
    [ "$step" -gt 0 ] && index=0 || index=$((count - 1))
  else
    index="$current"
    local tries
    for ((tries = 0; tries < count; tries++)); do
      index=$(((index + step + count) % count))
      [ -n "${focused[index]-}" ] || break
    done
    if [ -n "${focused[index]-}" ]; then
      echo "no other agent to go to"
      return 0
    fi
  fi
  local id
  id=$(jq -r --argjson i "$index" '.[$i].id' <<<"$sessions")
  focus_agent "$id" && agent_label "$id"
}

# id<TAB>label<TAB>match_text rows; tabs and newlines in a title are blanked so they cannot split a row.
focus_candidates() {
  agent_sessions | jq -r '.[] | [.id,
    "\(.title // "Untitled") (\(.project), \(.state))",
    "\(.title // "") \(.project) \(.agent // "claude")"]
    | map(gsub("[\t\n\r]"; " ")) | join("\t")'
}
