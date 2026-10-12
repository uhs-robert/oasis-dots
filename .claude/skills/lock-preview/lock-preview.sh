#!/usr/bin/env bash
# Preview a lock-screen skin in a shadow bar (invisible nested Hyprland), screenshot it, and drive it with keys.
set -euo pipefail

shadow="$(dirname "$0")/../shadow/shadow.sh"
state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/shadow"
layer=quickshell-lock-preview
# Whether the frames are seeded is fixed when a shadow starts, so each variant gets its own.
framed=lockprev
bare=lockbare
usage="usage: lock-preview.sh {show <skin> [--no-frames]|shot|keys <wtype args>|close|down}"

die() {
  echo "lock-preview: $*" >&2
  exit 1
}

# Reads the whole status first: grep -q exiting early would fail the pipeline under pipefail.
is_up() {
  local status
  status=$("$shadow" status "$1")
  [[ $status == "$1: up"* ]]
}

# The variant `show` used last, so keys, shot and close follow the preview that is open.
current() {
  local name=$framed
  [[ -f $state_dir/lock-preview-current ]] && name=$(<"$state_dir/lock-preview-current")
  echo "$name"
}

wait_for_layer() {
  local name=$1
  for _ in $(seq 100); do
    "$shadow" hyprctl "$name" layers -j | jq -e --arg ns "$layer" 'any(.[].levels[][]; .namespace == $ns)' >/dev/null && return 0
    sleep 0.1
  done
  return 1
}

show() {
  local skin=${1:?$usage} name=$framed
  [[ ${2:-} == --no-frames ]] && name=$bare
  if ! is_up "$name"; then
    if [[ $name == "$framed" ]]; then SHADOW_GOLDENEYE_FRAMES=1 "$shadow" up "$name" >&2; else "$shadow" up "$name" >&2; fi
  fi
  mkdir -p "$state_dir"
  echo "$name" >"$state_dir/lock-preview-current"
  local reply
  reply=$("$shadow" ipc "$name" lock preview "$skin")
  # Anything but "ok" (e.g. "unknown" for a misspelled skin) would otherwise shoot whatever preview is still open.
  [[ $reply == ok ]] || die "lock preview '$skin' failed: ${reply:-no reply}"
  wait_for_layer "$name" || die "no $layer layer after 10 s; see $state_dir/$name/logs/qs.log"
  # Shaders and live data need a moment after the layer maps.
  sleep 1
  "$shadow" shot "$name" "$layer"
}

case ${1:-} in
show)
  shift
  show "$@"
  ;;
shot) "$shadow" shot "$(current)" "$layer" ;;
keys)
  shift
  "$shadow" keys "$(current)" "$@"
  ;;
close) "$shadow" ipc "$(current)" lock preview_close ;;
down)
  for name in "$framed" "$bare"; do
    is_up "$name" && "$shadow" down "$name"
  done
  rm -f "$state_dir/lock-preview-current"
  ;;
*) die "$usage" ;;
esac
