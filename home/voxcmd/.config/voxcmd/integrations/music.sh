# shellcheck shell=bash
# Hook library of music.toml: sourced before every action of the integration.

qs_ipc="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/qs-ipc"

# `music set` is the bar's setter, so a repeated "music mode on" stays on instead of flipping it.
music_mode_set() {
  "$qs_ipc" call music set "$1"
}
