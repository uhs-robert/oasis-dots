#!/usr/bin/env bash
# Open a lock-skin preview on eDP-1, optionally with the GoldenEye footage frames hidden, and restore them.
set -euo pipefail

ipc="$HOME/.config/hypr/scripts/qs-ipc"
frames="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/goldeneye-frames"

die() {
  echo "lock-preview: $*" >&2
  exit 1
}

case ${1:-} in
  show)
    skin=${2:?usage: lock-preview.sh show <skin> [--no-frames]}
    if [[ ${3:-} == --no-frames ]]; then
      [[ -e $frames ]] || die "no frames at $frames"
      mv "$frames" "$frames.off"
      echo "lock-preview: GoldenEye frames hidden; run 'lock-preview.sh restore-frames' afterwards"
    fi
    hyprctl eval "hl.dispatch(hl.dsp.focus({ monitor = 'eDP-1' }))" >/dev/null
    sleep 0.3
    "$ipc" call lock preview "$skin"
    ;;
  close)
    "$ipc" call lock preview_close
    ;;
  restore-frames)
    [[ -e $frames.off ]] || die "nothing to restore at $frames.off"
    [[ -e $frames ]] && die "$frames already exists; refusing to overwrite it"
    mv "$frames.off" "$frames"
    echo "lock-preview: GoldenEye frames restored"
    ;;
  *)
    die "usage: lock-preview.sh {show <skin> [--no-frames]|close|restore-frames}"
    ;;
esac
