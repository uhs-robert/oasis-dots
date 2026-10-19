# shellcheck shell=bash disable=SC2034,SC2016,SC2154
# Rapid mode: a voice session where every turn is routed as a normal command, so a run of commands needs no key press
# between them. "click mode" and "type mode" open inside it and return to it. Format: ~/.config/voxcmd/README.md

name="Rapid"
confirm=0
silent_actions=(rapid_mode stop_rapid rapid_leave_hint)

# The ways out, as a command and as a turn inside the mode. Outside a session the command forms name the mode, so a bare
# "stop" there still pauses the music; inside, bare done and exit words are not exits (default exits are off), so only
# "cortana ..." leaves.
# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=mode-phrases.sh
source "$voxcmd_share_dir/mode-phrases.sh"
rapid_exit_object='(the )?(rapid|rapid mode|rapid fire mode)'
rapid_exit_phrase=$(mode_exit_phrase "$rapid_exit_object")
session_exit_phrases="done with $rapid_exit_object|$rapid_exit_phrase|exit|quit"
session_exit_hint="say cortana done to stop"
session_default_exits=0
# A bare done or exit word is a missed turn that answers with the hint, since only "cortana ..." leaves.
session_miss_actions=(rapid_leave_hint)
rapid_leave_words='done|im done|thats all|exit|quit|done with (the )?(rapid|rapid mode|rapid fire mode)'
rapid_leave_hint_text="say cortana done to leave"
mode_actions=(rapid_mode stop_rapid)

# Inside the session the mode-naming forms are a missed turn, not an exit: only "cortana ..." leaves. The verbs stay so
# that outside a session they still run before Media's and System's. A bare done or exit word becomes the hint's own
# phrase, so it routes to rapid_leave_hint per step; an empty rewrite would be the generic "Not understood" for the turn.
session_rewrite() {
  if [[ "$1" =~ ^($rapid_exit_phrase)$ ]]; then return; fi
  if [[ "$1" =~ ^($rapid_leave_words)$ ]]; then printf '%s' "$rapid_leave_hint_text"; return; fi
  printf '%s' "$1"
}

# "stop rapid mode" is here because Media's "stop {target}" would otherwise hear it.
verbs=(
  "rapid_mode ((start|enter|begin) )?rapid( fire)? mode"
  "stop_rapid $rapid_exit_phrase"
  "rapid_leave_hint $rapid_leave_hint_text"
)

examples=(
  "rapid mode"
  "cortana done"
)

declare -A actions=(
  [rapid_mode]='session_begin rapid "$file" "Rapid mode"'
  [stop_rapid]='session_leave rapid done || true'
  # Spelled out, not $rapid_leave_hint_text: actions run where this file's variables are not set.
  [rapid_leave_hint]='notify info "voxcmd: Rapid mode" "say cortana done to leave"'
)
