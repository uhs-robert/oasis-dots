# shellcheck shell=bash disable=SC2034,SC2016
# Jumps to coding agents tracked by keeptabs, through keeptabs-pick like the bar's popup. Format: ~/.config/voxcmd/README.md

name="Agents"
confirm=0
# The focused agent is the feedback. The jumps keep their toast: "no agent is waiting" is their only reply when
# nothing moves, and silent would drop it.
silent_actions=(focus)

# The fixed phrases come before "go to the {target} agent", which would otherwise take "go to the next agent".
verbs=(
  "jump_waiting  (jump|go|switch) to (the )?(waiting|blocked) agent|(jump|go|switch) to the agent that (needs|wants) (me|my attention|attention|input)"
  "jump_next     (jump to |go to |switch to )?(the )?next agent"
  "jump_previous (jump to |go to |switch to )?(the )?(previous|prior) agent"
  "focus         (jump|go|switch) to (the )?agent {target}"
  "focus         (jump|go|switch) to (the )?{target} agent"
)

examples=(
  "jump to the waiting agent"
  "go to the agent that needs me"
  "next agent"
  "go to the previous agent"
  "go to the <name> agent"
)

declare -A actions=(
  [jump_waiting]='focus_first_in_state waiting'
  [jump_next]='focus_cycled_agent 1'
  [jump_previous]='focus_cycled_agent -1'
  [focus]='focus_agent "$id"'
  [not_found]='echo "no tracked agent matches \"$target\""; false'
)

# Tab on these examples in Voice Help lists every tracked agent, and picking one jumps to it.
help_action=focus

# Without it, an unmatched "go to agent X" falls through to the keybinds fallback and could run an unrelated bind.
declare -A no_match_actions=(
  [focus]='not_found'
)

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
focus_first_in_state() {
  local id
  id=$(agent_sessions | jq -r --args 'first(.[] | select(.state | IN($ARGS.positional[])) | .id) // empty' "$@")
  if [ -z "$id" ]; then
    echo "no agent is $(printf '%s' "$*" | sed 's/ / or /g')"
    return 0
  fi
  focus_agent "$id" && agent_label "$id"
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

candidates() {
  case "$1" in
  focus)
    agent_sessions | jq -c 'map({id, label: "\(.title // "Untitled") (\(.project), \(.state))",
      match_text: "\(.title // "") \(.project) \(.agent // "claude")"})'
    ;;
  esac
}
