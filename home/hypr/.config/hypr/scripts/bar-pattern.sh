# shellcheck shell=bash disable=SC2034 # bar_pattern is read by the scripts that source this
# hypr/.config/hypr/scripts/bar-pattern.sh
# Sourced by restart-bar.sh and ship-batch.sh: the pgrep/pkill -f pattern for the owner's live bar.
# The owner's bar is `qs -n` (bare or with an absolute path), or a bare `quickshell`: Quickshell's crash handler relaunches
# the bar as plain `quickshell`, dropping `-n`. Test bars (`qs -p ...`), shadow bars (`qs-shadow`) and the greeter
# (`quickshell` with arguments) never match.
bar_pattern='^(/[^ ]*/)?(qs -n( |$)|quickshell$)'
