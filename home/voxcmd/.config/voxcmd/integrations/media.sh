# shellcheck shell=bash
# Hook library of media.toml: sourced before every hook of the integration.

# id<TAB>label per player: the full instance name, then its app name.
player_candidates() {
  playerctl --list-all 2>/dev/null | awk -F. 'NF { print $0 "\t" $1 }'
}
