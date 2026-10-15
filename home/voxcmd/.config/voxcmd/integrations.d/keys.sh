# shellcheck shell=bash disable=SC2034,SC2016,SC2154
# Bare key presses in the focused window: "press enter", "hit escape", "press down three times". Format:
# ~/.config/voxcmd/README.md

name="Keys"
confirm=0
# The key press is its own feedback.
silent_actions=(enter escape tab shift_tab up down left right page_up page_down home end backspace delete space)

# Prints why no key may be pressed now, nothing when pressing is fine (the same checks as type mode's).
keys_refusal() {
  if pending_pick >/dev/null; then
    echo "a voxcmd picker or card is open"
  elif [ -x "$qs_ipc" ] && [ "$(timeout 2 "$qs_ipc" call clickhints state 2>/dev/null)" = open ]; then
    echo "the click overlay is open"
  elif ! hyprctl activewindow -j 2>/dev/null | jq -e 'length > 0' >/dev/null 2>&1; then
    echo "no window has focus"
  fi
}

# "press" and "hit" always come first and there is no bare "enter" or "send": a misheard Enter can submit a form or run
# a shell line, and "send firefox to workspace 3" belongs to Apps. {target} holds the count ("three times").
verbs=(
  "enter      send it|send (the )?message|(press|hit) (enter|return)( {target})?"
  "escape     (press|hit) escape( {target})?"
  "shift_tab  (press|hit) shift tab( {target})?"
  "tab        (press|hit) tab( {target})?"
  "up         (press|hit) up( arrow)?( {target})?"
  "down       (press|hit) down( arrow)?( {target})?"
  "left       (press|hit) left( arrow)?( {target})?"
  "right      (press|hit) right( arrow)?( {target})?"
  "page_up    (press|hit) page up( {target})?"
  "page_down  (press|hit) page down( {target})?"
  "home       (press|hit) home( key)?( {target})?"
  "end        (press|hit) end( key)?( {target})?"
  "backspace  (press|hit) backspace( {target})?"
  "delete     (press|hit) delete( key)?( {target})?"
  "space      (press|hit) (the )?space( ?bar)?( {target})?"
)

examples=(
  "press enter"
  "send it"
  "press down three times"
  "hit escape"
  "press shift tab"
  "press y"
)

declare -A actions=(
  [enter]='press_key Return "$target"'
  [escape]='press_key Escape "$target"'
  [tab]='press_key Tab "$target"'
  [shift_tab]='press_key Shift+Tab "$target"'
  [up]='press_key Up "$target"'
  [down]='press_key Down "$target"'
  [left]='press_key Left "$target"'
  [right]='press_key Right "$target"'
  [page_up]='press_key Prior "$target"'
  [page_down]='press_key Next "$target"'
  [home]='press_key Home "$target"'
  [end]='press_key End "$target"'
  [backspace]='press_key BackSpace "$target"'
  [delete]='press_key Delete "$target"'
  [space]='press_key space "$target"'
)

# A verb captures only the count as {target}, so each letter is a verb of its own, with the letter in its action name.
# Letters take no count: "a" is also an article, and with a count "press a button" would be a press of "a" with a
# count it cannot read, refused instead of going on to the keybinds. Whisper hears a spoken "y" as "why".
for letter in {a..z}; do
  alternatives="$letter"
  [ "$letter" != y ] || alternatives="y|why"
  verbs+=("letter_$letter  (press|hit) (the )?(letter )?($alternatives)( key)?")
  actions[letter_$letter]="press_key $letter"
  silent_actions+=("letter_$letter")
done

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
    notify info "voxcmd" "Not a key count: ${2:-}"
    return 0
  fi
  [ "$count" -le "$max_key_presses" ] || count=$max_key_presses
  refusal=$(keys_refusal)
  if [ -n "$refusal" ]; then
    notify info "voxcmd: no key pressed" "$refusal"
    return 0
  fi
  for ((index = 0; index < count; index++)); do
    if [ "$keysym" = Shift+Tab ]; then keys+=(-M shift -k Tab -m shift); else keys+=(-k "$keysym"); fi
  done
  wtype "${keys[@]}"
}
