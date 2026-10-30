# shellcheck shell=bash
# Hook library of tmux.toml: sourced before every hook and action of the integration.

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

# One candidate per session: running sessions, and the layouts the Project picker lists. A layout whose session is
# running stays a layout candidate, and focus_or_attach treats it as that session. The JSON is turned into
# id<TAB>label<TAB>match_text rows at the end; a name holding a tab or newline splits its row, as it never did in JSON.
switch_candidates() {
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
  } | jq -s -r 'group_by(.session) | map(first) | .[] | [.id, .label, (.match_text // "")] | join("\t")'
}

# A running session without a layout gets the terminal already showing it (tmux titles windows "<session> <program>",
# or "Tmux <session> <program>" for a layout; matched by that prefix, longest session name first), else a new terminal attached to it, as the Tmux Overview
# does when no client can switch.
focus_or_attach() {
  case "$1" in
  layout:*)
    # A running layout's terminal is titled with its session name and program, which
    # rofi-tmux.sh's "Tmux <layout>" search can miss, so it is found as a session instead.
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
    local session="${1#session:}" address others
    others=$(tmux list-sessions -F '#S' 2>/dev/null | jq -R . | jq -sc .)
    # A longer session name that also fits the title owns the window ("Dev tools nvim" is not session "Dev").
    address=$(hyprctl clients -j | jq -r --arg session "$session" --arg term "${TERMINAL:-kitty}" --argjson others "${others:-[]}" '
      def fits($t; $s): ($t | ascii_downcase) as $l | ($s | ascii_downcase) as $n
        | $l == $n or ($l | startswith($n + " ")) or $l == "tmux " + $n or ($l | startswith("tmux " + $n + " "));
      first(.[] | select(.class | ascii_downcase | contains($term)) | select(.title as $t
        | fits($t; $session) and ($others | map(select(length > ($session | length) and fits($t; .))) | length == 0))
        | .address) // empty')
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
