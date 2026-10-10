# shellcheck shell=bash disable=SC2034,SC2016
# Media playback (playerctl) and output volume (pamixer). Format: ~/.config/voxcmd/README.md

name="Media"
confirm=0

# Tried in order against the normalized transcript, so the specific forms come before the {target} catch-alls.
verbs=(
  "toggle       play pause|toggle (the )?(music|media|playback)"
  "play         (play|resume|unpause)( (the )?(music|song|track|media|playback))?"
  "pause        (pause|stop)( (the )?(music|song|track|media|playback))?"
  "next         (play )?(the )?next( (song|track))?|skip( (this|the))?( (song|track))?"
  "previous     (play )?(the )?(previous|last)( (song|track))?|go back( (a|one) (song|track))?"
  "volume_up    (turn )?(the )?(volume|sound) up( by {number}( percent)?)?|louder|turn it up"
  "volume_down  (turn )?(the )?(volume|sound) down( by {number}( percent)?)?|quieter|turn it down"
  "volume_set   (set )?(the )?(volume|sound)( to| at)? {number}( percent)?"
  "toggle_mute  toggle mute"
  "mute         mute( (the )?(sound|audio|volume))?"
  "unmute       unmute( (the )?(sound|audio|volume))?"
  "play_on      (play|resume) {target}"
  "pause_on     (pause|stop) {target}"
)

declare -A actions=(
  [toggle]='playerctl play-pause'
  [play]='playerctl play'
  [pause]='playerctl pause'
  [next]='playerctl next'
  [previous]='playerctl previous'
  [volume_up]='pamixer --increase "${target:-5}"'
  [volume_down]='pamixer --decrease "${target:-5}"'
  [volume_set]='pamixer --set-volume "$target"'
  [toggle_mute]='pamixer --toggle-mute'
  [mute]='pamixer --mute'
  [unmute]='pamixer --unmute'
  [play_on]='playerctl --player="$id" play'
  [pause_on]='playerctl --player="$id" pause'
)

# Players for "play spotify" / "pause firefox": the full instance name is the id, its app name the label.
candidates() {
  case "$1" in
  play_on | pause_on)
    playerctl --list-all 2>/dev/null | jq -R -s -c 'split("\n") | map(select(. != "") | {id: ., label: (split(".")[0])})'
    ;;
  esac
}
