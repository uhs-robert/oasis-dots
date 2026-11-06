#!/usr/bin/env bash
# Runs cursor_drag.lua, the lifecycle check for keyboard drag and drop. It builds a sandbox of stub ydotool, ydotoold,
# wlrctl, hyprctl, notify-send and wl-kbptr script on a PATH that holds nothing else, so the real tools (and the live
# desktop) are never reached, and drives the real shell scripts cursor.lua generates. Needs lua and python3.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel) || exit 1
work=$(mktemp -d)
trap 'pkill -f "$work" 2>/dev/null; rm -rf "$work"' EXIT

stub="$work/stub"
mkdir -p "$stub/bin" "$work/run" "$work/home/.config/hypr/scripts"
# The only real tools the stubs and generated scripts use.
for tool in sh sleep rm cat env python3 mkdir touch basename; do
  ln -s "$(command -v "$tool")" "$stub/bin/$tool" || exit 1
done

for tool in ydotool wlrctl notify-send; do
  cat >"$stub/$tool" <<'STUB'
#!/bin/sh
. "$STUB_DIR/mode" 2>/dev/null
echo "$(basename "$0") $*" >>"$STUB_DIR/log"
[ "$(basename "$0")" = ydotool ] && [ "$1" = click ] && [ "$2" = 0x40 ] && [ -n "$FAIL_PRESS" ] && exit 1
exit 0
STUB
done
cat >"$stub/hyprctl" <<'STUB'
#!/bin/sh
case $1 in
  eval) echo "$2" >>"$STUB_DIR/cb.queue" ;;
  *) echo "hyprctl $*" >>"$STUB_DIR/log" ;;
esac
STUB
cat >"$stub/ydotoold" <<'STUB'
#!/bin/sh
. "$STUB_DIR/mode" 2>/dev/null
for arg; do case $arg in --socket-path=*) sock=${arg#*=} ;; esac; done
echo "ydotoold start" >>"$STUB_DIR/log"
case $DAEMON in
  exit) exit 1 ;;
  nosocket)
    trap 'echo "ydotoold stop" >>"$STUB_DIR/log"; exit 0' TERM
    while :; do sleep 0.05; done ;;
esac
exec python3 -I -c '
import signal, socket, sys
s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])
def stop(*_):
    open(sys.argv[2], "a").write("ydotoold stop\n"); sys.exit(0)
signal.signal(signal.SIGTERM, stop); signal.pause()' "$sock" "$STUB_DIR/log"
STUB
cat >"$work/home/.config/hypr/scripts/kbptr.sh" <<'STUB'
#!/bin/sh
. "$STUB_DIR/mode" 2>/dev/null
echo "kbptr $*" >>"$STUB_DIR/log"
[ "$PICK" = dismiss ] && exit 1
echo "$PICK" >"$STUB_DIR/pointer"
exit 0
STUB
chmod +x "$stub"/* "$work/home/.config/hypr/scripts/kbptr.sh" 2>/dev/null

export DRAG_TEST_DIR="$work" XDG_RUNTIME_DIR="$work/run" HOME="$work/home"
status=0
before=$(git -C "$repo" status --porcelain)
lua "$here/cursor_drag.lua" || status=1
if [[ $(git -C "$repo" status --porcelain) != "$before" ]]; then
  echo "FAIL the test changed the repo" >&2
  status=1
fi
exit "$status"
