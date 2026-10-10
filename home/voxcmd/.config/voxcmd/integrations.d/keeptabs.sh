# shellcheck shell=bash disable=SC2034,SC2016
# Jumps to coding agents tracked by keeptabs, through keeptabs-pick like the bar's popup. Format: ~/.config/voxcmd/README.md

name="Agents"
confirm=0

# The fixed phrases come before "go to agent {target}", which would otherwise take "go to the next agent".
verbs=(
  "jump_waiting  (jump|go|switch) to (the )?(waiting|blocked) agent|(jump|go|switch) to the agent that (needs|wants) (me|my attention|attention|input)"
  "jump_next     (jump to |go to |switch to )?(the )?next agent"
  "focus         (jump|go|switch) to (the )?agent {target}"
  "focus         (jump|go|switch) to (the )?{target} agent"
)

declare -A actions=(
  [jump_waiting]='focus_first_in_state waiting'
  [jump_next]='focus_first_in_state waiting done'
  [focus]='focus_agent "$id"'
  [not_found]='echo "no tracked agent matches \"$target\""; false'
)

# Without it, an unmatched "go to agent X" falls through to the keybinds fallback and could run an unrelated bind.
declare -A no_match_actions=(
  [focus]='not_found'
)

# The bar runs ~/.local/bin/keeptabs-pick by path, since it may not be on PATH; PATH wins so tests can stub it.
keeptabs_pick() {
  if command -v keeptabs-pick >/dev/null; then
    keeptabs-pick "$@"
  else
    "$HOME/.local/bin/keeptabs-pick" "$@"
  fi
}

# A session in a tmux nobody is attached to gets a terminal started in the background, which would keep voxcmd
# waiting on the captured output until that terminal closed.
focus_agent() { keeptabs_pick --focus "$1" >/dev/null 2>&1; }

agent_sessions() { keeptabs_pick --json 2>/dev/null || echo '[]'; }

agent_label() {
  agent_sessions | jq -r --arg id "$1" 'first(.[] | select(.id == $id) | "\(.title // "Untitled") (\(.project))") // empty'
}

# keeptabs-pick lists waiting sessions first, then done, oldest first within a state, so the first session in one of
# the given states is the one that has waited longest.
focus_first_in_state() {
  local id
  id=$(agent_sessions | jq -r --args 'first(.[] | select(.state | IN($ARGS.positional[])) | .id) // empty' "$@")
  if [ -z "$id" ]; then
    echo "no agent is $(printf '%s' "$*" | sed 's/ / or /g')"
    return 0
  fi
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
