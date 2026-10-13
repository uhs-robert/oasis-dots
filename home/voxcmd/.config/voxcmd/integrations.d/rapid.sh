# shellcheck shell=bash disable=SC2034,SC2016,SC2154
# Rapid mode: a voice session where every turn is routed as a normal command, so a run of commands needs no key press
# between them. "click mode" and "type mode" open inside it and return to it. Format: ~/.config/voxcmd/README.md

name="Rapid"
confirm=0
silent_actions=(rapid_mode stop_rapid)

# The ways out, as a command and as a turn inside the mode. Each names the mode: a bare "stop" or "cancel" is a command.
# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=mode-phrases.sh
source "$voxcmd_share_dir/mode-phrases.sh"
rapid_exit_object='(the )?(rapid|rapid mode|rapid fire mode)'
rapid_exit_phrase=$(mode_exit_phrase "$rapid_exit_object")
session_exit_phrases="done with $rapid_exit_object|$rapid_exit_phrase"
session_exit_hint="say done to stop"
mode_actions=(rapid_mode stop_rapid)

# "stop rapid mode" is here because Media's "stop {target}" would otherwise hear it.
verbs=(
  "rapid_mode ((start|enter|begin) )?rapid( fire)? mode"
  "stop_rapid $rapid_exit_phrase"
)

examples=(
  "rapid mode"
  "done"
)

declare -A actions=(
  [rapid_mode]='session_begin rapid "$file" "Rapid mode"'
  [stop_rapid]='session_leave rapid done || true'
)
