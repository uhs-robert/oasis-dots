# shellcheck shell=bash
# Hook library of keys.toml: sourced before every hook of the integration.

qs_ipc="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/qs-ipc"

# Whether a bar popup that takes the keyboard (the pickers included) or either overview is up. They are layer-shell surfaces
# that hold the keyboard without a focused client, so Hyprland's activewindow is empty while they are open. Hyprland does not
# report which layer has the keyboard, so the bar's own state stands for it. A hands-off popup leaves it to the window below.
bar_surface_open() {
  [ -x "$qs_ipc" ] || return 1
  [ "$(timeout 2 "$qs_ipc" call popup keyboard 2>/dev/null)" = yes ] ||
    [ "$(timeout 2 "$qs_ipc" call overview state 2>/dev/null)" = open ] ||
    [ "$(timeout 2 "$qs_ipc" call tmux_overview state 2>/dev/null)" = open ]
}

# Prints why no key may be pressed now, nothing when pressing is fine (the same checks as type mode's, except that a
# bar surface counts as focus: typing into one would put text where it is not wanted, a key press drives it).
keys_refusal() {
  if "$VOXCMD_SELF" util pending-pick >/dev/null; then
    echo "a voxcmd picker or card is open"
  elif [ -x "$qs_ipc" ] && [ "$(timeout 2 "$qs_ipc" call clickhints state 2>/dev/null)" = open ]; then
    echo "the click overlay is open"
  elif ! hyprctl activewindow -j 2>/dev/null | jq -e 'length > 0' >/dev/null 2>&1 && ! bar_surface_open; then
    echo "no window or bar surface has focus"
  fi
}

# A runaway count (a misheard "20 times") stops here.
max_key_presses=20

# Prints how many presses the spoken count ("", "twice", "3 times", "ten") asks for; fails when it is none.
key_press_count() {
  local words="${1% times}"
  words="${words% time}"
  case "$words" in
  "" | once | one | 1) echo 1 ;;
  twice | two | 2) echo 2 ;;
  three) echo 3 ;;
  four) echo 4 ;;
  five) echo 5 ;;
  six) echo 6 ;;
  seven) echo 7 ;;
  eight) echo 8 ;;
  nine) echo 9 ;;
  ten) echo 10 ;;
  *)
    [[ "$words" =~ ^[0-9]+$ ]] || return 1
    # Too many digits for bash arithmetic would wrap; any such count is over the cap anyway.
    if [ "${#words}" -gt 4 ]; then echo "$max_key_presses"; else echo "$((10#$words))"; fi
    ;;
  esac
}

# press_key <keysym, or Shift+Tab> [spoken count]
press_key() {
  local keysym="$1" count refusal index
  local -a keys=()
  if ! count=$(key_press_count "${2:-}") || [ "$count" -lt 1 ]; then
    "$VOXCMD_SELF" util notify info "voxcmd" "Not a key count: ${2:-}"
    return 0
  fi
  [ "$count" -le "$max_key_presses" ] || count=$max_key_presses
  refusal=$(keys_refusal)
  if [ -n "$refusal" ]; then
    "$VOXCMD_SELF" util notify info "voxcmd: no key pressed" "$refusal"
    return 0
  fi
  for ((index = 0; index < count; index++)); do
    if [ "$keysym" = Shift+Tab ]; then keys+=(-M shift -k Tab -m shift); else keys+=(-k "$keysym"); fi
  done
  wtype "${keys[@]}"
}
