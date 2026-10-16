# shellcheck shell=bash disable=SC2034,SC2016,SC2154
# Type mode: one dictation into the focused window. It is one voxtype recording, typed once it ends: on "cortana stop"
# and the other endings below, the voice key or Stop Voice, at voxtype's recording limit, or after 10 s of quiet once
# something was said. "cortana cancel", or 10 s with nothing said at all, ends it typing nothing. Format: ~/.config/voxcmd/README.md

name="Type"
confirm=0
silent_actions=(type_mode type_start stop_typing)

# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=mode-phrases.sh
source "$voxcmd_share_dir/mode-phrases.sh"
type_exit_object='(the )?(typing|typing mode|type mode|dictation|dictation mode)'
type_exit_phrase=$(mode_exit_phrase "$type_exit_object")
# "start typing" is not in mode_actions: inside click mode it stays a click target (a search box may be labelled
# "Start typing"), and only "cortana start typing" switches from there. It still enters a mode, so it is listed in
# mode_entry_actions and a sequence may only end with it.
verbs=(
  "type_mode   ((start|enter|begin) )?(type|typing|dictation) mode"
  "type_start  (start|begin) typing"
  "stop_typing $type_exit_phrase|(im )?done (typing|with $type_exit_object)"
)

examples=(
  "type mode"
  "cortana stop typing"
)

declare -A actions=(
  [type_mode]='type_mode_begin'
  [type_start]='type_mode_begin'
  [stop_typing]='session_leave type done || true'
)

# Session settings voxcmd reads for this mode (load_mode_settings).
mode_actions=(type_mode stop_typing)
mode_entry_actions=(type_start)
# What is said is text: only the wake word gives a command, so "done" or "stop typing" are typed.
session_default_exits=0
session_exit_hint="say cortana stop, or cortana cancel"
# Dictation is private: no text in the debug log, a toast or the session file.
session_private=1
# Long by design, and bounded by its recording instead of the session's turn and time caps.
session_open_ended=1
session_one_recording=1
# voxcmd-wake keeps listening through the recording, for the wake word and an ending.
session_wake_listens=1
# How the recording ends, after the wake word: "<action> <regex>" rows, the first whose regex matches the whole of the
# words wins. discard and end_session are voxcmd's (see voxcmd's one-recording modes); session_handle_turn gets the
# others. Whisper writes "never mind" both ways.
session_endings=(
  "type        stop|stop typing|stop recording|done|im done|thats all|$type_exit_phrase|(im )?done typing|done with $type_exit_object"
  "send        send|send it|send (the |a )?message|press enter"
  "discard     cancel|never ?mind"
  "end_session stop listening|stop everything|end session|end the session"
)
# The idle bound: 10 s of quiet after speech stop the recording and type it, as "cortana stop" would, and 10 s with no
# speech at all end the mode. The cap stops it before voxtype's max_duration_secs (300), whose own cut would lose the transcript's end.
session_listen_no_speech_secs="${VOXCMD_TYPE_IDLE_SECS:-10}"
session_listen_silence_secs="${VOXCMD_TYPE_IDLE_SECS:-10}"
session_listen_max_secs="${VOXCMD_TYPE_MAX_SECS:-295}"

# Opens the mode and says how to finish it: by the wake word while voxcmd-wake runs, else by the voice key.
type_mode_begin() {
  local session wake_pid
  session_begin type "$file" "Type mode"
  session=$(session_state) && [ "$(jq -r .kind <<<"$session")" = type ] || return 0
  wake_pid=$(jq -r '.pid // empty' "$runtime_dir/wake.json" 2>/dev/null || true)
  if [ -n "$wake_pid" ] && kill -0 "$wake_pid" 2>/dev/null; then
    notify info "voxcmd: Type mode" "Say \"cortana stop\" to type it, \"cortana cancel\" to drop it"
  else
    notify info "voxcmd: Type mode" "Press the voice key to type it: the Cortana listener is off"
  fi
}

# Prints why nothing may be typed now, nothing when typing is fine.
type_refusal() {
  local active_window
  if pending_pick >/dev/null; then
    echo "a voxcmd picker or card is open"
  elif [ -x "$qs_ipc" ] && [ "$(timeout 2 "$qs_ipc" call clickhints state 2>/dev/null)" = open ]; then
    echo "the click overlay is open"
  elif ! active_window=$(hyprctl activewindow -j 2>/dev/null); then
    echo "Hyprland cannot be reached"
  elif ! jq -e 'length > 0' >/dev/null 2>&1 <<<"$active_window"; then
    echo "no window has focus"
  fi
}

# Checked straight before typing: Stop Voice or another end may have landed since the recording ended, and type mode
# may have been left meanwhile.
type_still_wanted() {
  local session
  [ ! -e "$(discard_flag_of $$)" ] && session=$(session_state) || return 1
  [ -z "$heard_mode" ] || [ "$heard_mode" = "$(session_mode_token "$session")" ]
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

# session_handle_turn <text> <ending action>: types the dictation, then presses Return for send. Fails (nothing typed, a
# toast without the text) when typing is refused or fails.
session_handle_turn() {
  local text refusal
  text=$(type_scrub "$1")
  [ -n "$text" ] || return 0
  refusal=$(type_refusal)
  if [ -n "$refusal" ]; then
    notify info "voxcmd: not typed" "$refusal"
    return 1
  fi
  if ! type_still_wanted; then
    debug "type: not typed, the session ended or was stopped"
    return 1
  fi
  if ! wtype -- "$text"; then
    notify error "voxcmd: typing failed" "could not type $(type_length "$text") characters"
    return 1
  fi
  debug "type: typed $(type_length "$text") characters"
  [ "${2:-}" != send ] || wtype -k Return
}
