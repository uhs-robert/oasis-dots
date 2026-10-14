# shellcheck shell=bash disable=SC2034,SC2016,SC2154
# Type mode: dictation into the focused window, in chunks, with voice commands that start with the wake word. A pause
# ends a chunk, which is typed as it is transcribed; silence is thinking time and never ends the mode. Format:
# ~/.config/voxcmd/README.md

name="Type"
confirm=0
silent_actions=(type_mode stop_typing)

# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=mode-phrases.sh
source "$voxcmd_share_dir/mode-phrases.sh"
# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=voice-env.sh
source "$voxcmd_share_dir/voice-env.sh"
type_exit_object='(the )?(typing|typing mode|type mode|dictation|dictation mode)'
type_exit_phrase=$(mode_exit_phrase "$type_exit_object")
# "start typing" is a search placeholder somewhere, so entering needs the word "mode".
verbs=(
  "type_mode   ((start|enter|begin) )?(type|typing|dictation) mode"
  "stop_typing $type_exit_phrase|(im )?done (typing|with $type_exit_object)"
)

examples=(
  "type mode"
  "jarvis stop typing"
)

declare -A actions=(
  [type_mode]='session_begin type "$file" "Type mode"'
  [stop_typing]='session_leave type done || true'
)

# Session settings voxcmd reads for this mode (load_mode_settings).
mode_actions=(type_mode stop_typing)
# What is said is text: only the wake word gives a command, so "done" or "stop typing" are typed.
session_default_exits=0
session_exit_phrases="$type_exit_phrase|(im )?done typing|done with $type_exit_object"
session_exit_hint="say jarvis stop typing"
session_control_phrases='scratch that|new line|new paragraph'
# A chunk may end with a command ("...the plan. Jarvis, stop typing.").
session_wake_at_end=1
# Dictation is private: no text in the debug log, a toast or the session file.
session_private=1
# Long and silent by design. The mode has its own bounds instead of the session's turn and time caps.
session_open_ended=1
session_mode_idle_secs="${VOXCMD_TYPE_IDLE_SECS:-120}"
session_mode_max_secs="${VOXCMD_TYPE_MAX_SECS:-1800}"
# A pause this long ends a chunk, and speech this long is cut into one (inside Whisper's 30 s window). The silent listen
# is shorter than the idle bound only so the recording is never open for the whole of it.
session_listen_silence_secs="$(voice_env_value VOXCMD_TYPE_CHUNK_PAUSE_SECS || echo 2.5)"
session_listen_max_secs="${VOXCMD_TYPE_CHUNK_MAX_SECS:-25}"
session_listen_no_speech_secs=30

# {frame, resumes, held, prev_held, last_len, typed, window}: the mode it belongs to (its frame_id; state of any other mode, such
# as one a killed listener left, reads as empty), how many times the mode had become current again (a click or rapid
# detour may have moved the cursor, so a count that has moved on forgets last_len), the final sentence mark of the last chunk (typed with the next one, or when the
# mode ends), the mark held before that chunk (for "scratch that"), the characters the last chunk typed, and whether
# anything was typed since the mode (or a new line) began, and the address of the window it was typed into (focus that
# has moved on means the cursor is in other text, so the rest is forgotten). Lengths and marks only, never the text.
type_state_file="${XDG_RUNTIME_DIR:-/tmp}/voxcmd/type-state"

# Words Whisper capitalizes only because a chunk began there. A chunk that continues a sentence gets its first letter
# lowercased when it is one of these; any other capital (a name, "I") is left alone.
type_lowercased_words=" the a an and but or so then that this these those it its there their to of in on for with as at by if when because which who what where how is are was were be been have has had do does did not no can could would should will just also very really maybe well now still too our my your his her them us me we they he she you "

# Prints the address of the focused window, nothing when none has focus.
type_focused_window() {
  hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty' 2>/dev/null || true
}

# type_read_state [frame id]: the state of the mode on top, or of the popped mode with that id (session_ended). Sets
# type_window to the focused window; state typed into another one reads as empty.
type_read_state() {
  type_held="" type_prev_held="" type_last_len=0 type_typed=false type_resumes=0
  local state session stored_resumes stored_window
  type_window=$(type_focused_window)
  type_frame="${1:-}"
  if session=$(session_state); then
    [ -n "$type_frame" ] || type_frame=$(jq -r '.frame_id // empty' <<<"$session")
    type_resumes=$(jq -r '.resumes // 0' <<<"$session")
  fi
  state=$(cat "$type_state_file" 2>/dev/null) || return 0
  [ -n "$type_frame" ] && [ "$(jq -r '.frame // empty' <<<"$state" 2>/dev/null)" = "$type_frame" ] || return 0
  IFS=$'\t' read -r type_held type_prev_held type_last_len type_typed stored_resumes stored_window < <(
    jq -r '[.held, .prev_held, .last_len, .typed, (.resumes // 0), (.window // "")] | @tsv' <<<"$state" 2>/dev/null || true
  )
  [ "$stored_resumes" = "$type_resumes" ] || type_last_len=0
  # An empty field would shift the others, so type_write_state stores an empty mark as "-".
  [ "$type_held" != - ] || type_held=""
  [ "$type_prev_held" != - ] || type_prev_held=""
  [ -n "$type_typed" ] || type_typed=false
  if [ -z "$type_window" ] || [ "$stored_window" != "$type_window" ]; then
    type_held="" type_prev_held="" type_last_len=0 type_typed=false
  fi
}

type_write_state() {
  mkdir -p "$(dirname "$type_state_file")"
  jq -n -c --arg frame "$type_frame" --arg window "$type_window" --argjson resumes "$type_resumes" --arg held "${1:--}" --arg prev_held "${2:--}" --argjson last_len "$3" --argjson typed "$4" \
    '{frame: $frame, resumes: $resumes, held: $held, prev_held: $prev_held, last_len: $last_len, typed: $typed, window: $window}' >"$type_state_file"
}

# Prints why nothing may be typed now, nothing when typing is fine.
type_refusal() {
  if pending_pick >/dev/null; then
    echo "a voxcmd picker or card is open"
  elif [ -x "$qs_ipc" ] && [ "$(timeout 2 "$qs_ipc" call clickhints state 2>/dev/null)" = open ]; then
    echo "the click overlay is open"
  elif ! hyprctl activewindow -j 2>/dev/null | jq -e 'length > 0' >/dev/null 2>&1; then
    echo "no window has focus"
  fi
}

# Checked straight before typing: Stop Voice or another end may have landed since the turn began, and type mode may have
# been left (for the mode under it, or for another over it) while the chunk was handled.
type_still_wanted() {
  local session
  [ ! -e "$(discard_flag_of $$)" ] && session=$(session_state) || return 1
  [ -z "$heard_mode" ] || [ "$heard_mode" = "$(session_mode_token "$session")" ]
}

# Prints the characters of $1; the locale is set because wtype and the BackSpaces that undo it count characters.
type_length() {
  local LC_ALL=C.UTF-8
  echo "${#1}"
}

# Types $1 and fails with a toast that holds no text.
type_out() {
  if ! type_still_wanted; then
    debug "type: not typed, the session ended or was stopped"
    return 1
  fi
  if ! wtype -- "$1"; then
    notify error "voxcmd: typing failed" "could not type $(type_length "$1") characters"
    return 1
  fi
}

# Replaces control characters and newlines with spaces and trims, so a chunk can never press Return or run a shortcut.
type_scrub() {
  local text="${1//[[:cntrl:]]/ }"
  while [[ "$text" == *"  "* ]]; do text="${text//  / }"; done
  text="${text# }"
  printf '%s' "${text% }"
}

# The boundary between chunks. A mark held back from the last chunk is typed ahead of this one when this one starts a
# sentence (anything but a lowercase letter) and dropped when it continues one. With no mark held, a capital that is
# only the chunk's start is lowercased if it is a common word. Prints the text to type.
type_with_boundary() {
  local core="$1" first first_word
  first="${core:0:1}"
  if [ "$type_typed" != true ]; then
    printf '%s' "$core"
  elif [ -n "$type_held" ]; then
    if [[ "$first" == [[:lower:]] ]]; then printf ' %s' "$core"; else printf '%s %s' "$type_held" "$core"; fi
  else
    first_word="${core%% *}"
    first_word="${first_word,,}"
    if [[ "$first" == [[:upper:]] && "$type_lowercased_words" == *" ${first_word//[^[:alnum:]]/} "* ]]; then core="${first,}${core:1}"; fi
    printf ' %s' "$core"
  fi
}

# A transcript chunk in. Fails (nothing typed, a toast) when typing is refused or fails.
session_handle_turn() {
  local text core held="" refusal out
  text=$(type_scrub "$1")
  core="$text"
  # Final sentence marks wait for the next chunk to say whether the sentence goes on.
  while [[ "$core" == *[.!?] ]]; do
    held="${core: -1}$held"
    core="${core%?}"
  done
  core="${core% }"
  [ -n "$core" ] || return 0
  refusal=$(type_refusal)
  if [ -n "$refusal" ]; then
    notify info "voxcmd: not typed" "$refusal"
    return 1
  fi
  type_read_state
  out=$(type_with_boundary "$core")
  type_out "$out" || return 1
  type_write_state "$held" "$type_held" "$(type_length "$out")" true
  debug "type: typed a chunk of $(type_length "$out") characters"
}

# A control command from the wake word: scratch that, new line, new paragraph. Succeeds when it was one.
session_control() {
  local refusal line_count index
  local -a keys=()
  refusal=$(type_refusal)
  if [ -n "$refusal" ]; then
    notify info "voxcmd: not typed" "$refusal"
    return 0
  fi
  type_read_state
  case "$1" in
  "scratch that")
    if [ "$type_last_len" -le 0 ]; then
      notify info "voxcmd" "Nothing to scratch"
      return 0
    fi
    for ((index = 0; index < type_last_len; index++)); do keys+=(-k BackSpace); done
    type_still_wanted && wtype "${keys[@]}" || return 0
    type_write_state "$type_prev_held" "" 0 "$type_typed"
    ;;
  "new line" | "new paragraph")
    line_count=1
    [ "$1" != "new paragraph" ] || line_count=2
    [ -z "$type_held" ] || type_out "$type_held" || return 0
    for ((index = 0; index < line_count; index++)); do keys+=(-k Return); done
    type_still_wanted && wtype "${keys[@]}" || return 0
    type_write_state "" "" 0 false
    ;;
  esac
  return 0
}

# Leaving the mode on purpose types the mark it was holding, so the last sentence is closed. Stop Voice, the idle bound
# and the caps type nothing: by then focus may be in another window, and Stop must never type. This runs in the
# background, so Stop may land after the mode was left: when the session went on in the mode underneath ($3 is 1) and is
# gone by now, nothing is typed. The state file is removed only if it is still this mode's: a new type mode may have
# written its own since.
session_ended() {
  type_read_state "${2:-}"
  if [ "${1:-}" = done ] && [ -n "$type_held" ] && [ -z "$(type_refusal)" ] &&
    { [ "${3:-0}" != 1 ] || session_state >/dev/null; }; then
    wtype -- "$type_held" || true
  fi
  if [ "$(jq -r '.frame // empty' "$type_state_file" 2>/dev/null)" = "${2:-}" ]; then rm -f "$type_state_file"; fi
}
