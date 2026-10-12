# shellcheck shell=bash disable=SC2034,SC2016
# Focuses, attaches or creates tmux sessions, tmuxifier layouts included. Format: ~/.config/voxcmd/README.md

name="Tmux"
confirm=0
# The session's terminal taking focus is the feedback.
silent_actions=(switch new)

# Every phrase names a session ("the X session", "session X", "attach X"), so "switch to X" stays the apps' verb.
# "new session" comes first so "open a new session X" is not read as opening a session called "new session X".
verbs=(
  "new     (start |create |open )?(a )?new (tmux )?session( called| named)? {target}"
  "switch  {focus} (the )?(tmux )?session {target}"
  "switch  {focus} (the )?{target} (tmux )?session"
  "switch  attach( to)?( the)? {target} (tmux )?session"
  "switch  attach( to)?( the)?( (tmux )?session)? {target}"
  "switch  {open} (the )?(tmux )?session {target}"
  "switch  {open} (the )?{target} (tmux )?session"
)

examples=(
  "go to the <name> session"
  "open session <name>"
  "new session <name>"
  "attach <name>"
)

declare -A actions=(
  [switch]='focus_or_attach "$id"'
  [new]='open_terminal tmux new-session -A -s "$target"'
  [not_found]='echo "no tmux session or layout matches \"$target\""; false'
)

# Tab on these examples in Voice Help lists every running session and layout, and picking one switches to it.
help_action=switch

# Without it, an unmatched "attach X" falls through to the keybinds fallback and could run an unrelated bind.
declare -A no_match_actions=(
  [switch]='not_found'
)

layout_dir="$HOME/.tmuxifier/layouts"
# The Project picker's focus-or-open logic for tmuxifier layouts, run with the layout name so it skips rofi.
layout_opener="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/rofi-tmux.sh"

open_terminal() {
  local term="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/bin/term"
  [ -x "$term" ] || term="${TERMINAL:-kitty}"
  setsid -f "$term" -e "$@" >/dev/null 2>&1
}

# The session a layout creates is the session_name it sets; layouts that don't set one are named after the file.
layout_session_name() {
  sed -nE 's/^[[:space:]]*session_name="([^"]+)".*/\1/p' "$1" | head -n 1
}

# Only "switch" has candidates; a new session's name is free text. One candidate per session: running sessions, and
# the layouts the Project picker lists. A layout whose session is running stays a layout candidate, and
# focus_or_attach treats it as that session.
candidates() {
  [ "$1" = switch ] || return 0
  local file stem session
  {
    for file in "$layout_dir"/*.session.sh; do
      [ -f "$file" ] || continue
      stem=$(basename "$file" .session.sh)
      session=$(layout_session_name "$file")
      jq -n -c --arg stem "$stem" --arg session "${session:-$stem}" \
        '{id: "layout:\($stem)", label: $session, session: $session,
          match_text: ($session + if ($stem | ascii_downcase) == ($session | ascii_downcase) then "" else " \($stem | gsub("[-_]"; " "))" end)}'
    done
    tmux list-sessions -F '#{session_name}' 2>/dev/null | jq -R -c '{id: "session:\(.)", label: ., session: .}'
  } | jq -s -c 'group_by(.session) | map(first) | map(del(.session))'
}

# A running session without a layout gets the terminal already showing it (tmux titles windows with the session
# name; matched like rofi-tmux.sh matches layout windows), else a new terminal attached to it, as the Tmux Overview
# does when no client can switch.
focus_or_attach() {
  case "$1" in
  layout:*)
    # A running layout's terminal is titled with its session name (tmux's set-titles-string is #S), which
    # rofi-tmux.sh's "Tmux <layout>" search misses, so it is found as a session instead.
    local stem="${1#layout:}" session
    session=$(layout_session_name "$layout_dir/$stem.session.sh")
    if tmux has-session -t "=${session:-$stem}" 2>/dev/null; then
      focus_or_attach "session:${session:-$stem}"
      return
    fi
    # Its terminal runs in the background; with the output captured, voxcmd would wait for that terminal to close.
    "$layout_opener" "$stem" >/dev/null 2>&1
    ;;
  session:*)
    local session="${1#session:}" address
    address=$(hyprctl clients -j | jq -r --arg session "$session" --arg term "${TERMINAL:-kitty}" '
      def norm: ascii_downcase | gsub("[^a-z0-9]"; "");
      first(.[] | select(.class | ascii_downcase | contains($term))
        | select((.title | norm) == ($session | norm) or (.title | norm) == ("tmux" + ($session | norm))) | .address) // empty')
    if [ -n "$address" ]; then
      hyprctl dispatch "hl.dsp.focus({ window = 'address:$address' })" >/dev/null
    else
      open_terminal tmux attach-session -t "=$session"
    fi
    ;;
  *)
    echo "not a session: $1"
    false
    ;;
  esac
}
