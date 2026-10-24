# shellcheck shell=bash
# Hook library of typing.toml: sourced before every hook and action of the integration.

# Opens with the mode: says how to finish it. The engine skips this when the mode could not open.
type_mode_hint() {
  "$VOXCMD_SELF" util notify info "voxcmd: Type mode" "Say \"cortana stop\" to type it, \"cortana cancel\" to drop it"
}

# Prints the characters of $1; the locale is set because wtype counts characters.
type_length() {
  local LC_ALL=C.UTF-8
  echo "${#1}"
}

# Replaces control characters and newlines with spaces and trims, so the text can never press Return or run a shortcut.
type_scrub() {
  local text="${1//[[:cntrl:]]/ }"
  while [[ "$text" == *"  "* ]]; do text="${text//  / }"; done
  text="${text# }"
  printf '%s' "${text% }"
}

# Prints why nothing may be typed now, nothing when typing is fine. The engine has already refused for an open picker,
# the click overlay and an ended session.
type_refusal() {
  local active_window
  if ! active_window=$(hyprctl activewindow -j 2>/dev/null); then
    echo "Hyprland cannot be reached"
  elif ! jq -e 'length > 0' >/dev/null 2>&1 <<<"$active_window"; then
    echo "no window has focus"
  fi
}

# handle_turn: types $VOXCMD_TEXT, then presses Return for the send ending. Fails (nothing typed, a toast without the
# text) when typing is refused or fails.
type_text() {
  local text refusal
  text=$(type_scrub "$VOXCMD_TEXT")
  [ -n "$text" ] || return 0
  refusal=$(type_refusal)
  if [ -n "$refusal" ]; then
    "$VOXCMD_SELF" util notify info "voxcmd: not typed" "$refusal"
    return 1
  fi
  if ! wtype -- "$text"; then
    "$VOXCMD_SELF" util notify error "voxcmd: typing failed" "could not type $(type_length "$text") characters"
    return 1
  fi
  [ "${VOXCMD_ENDING:-}" != send ] || wtype -k Return
}
