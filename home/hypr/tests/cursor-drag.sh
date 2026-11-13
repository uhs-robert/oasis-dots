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
mkdir -p "$stub/bin" "$stub/cb.d" "$work/run" "$work/home/.config/hypr/scripts"
# The only real tools the stubs and generated scripts use.
for tool in sh sleep rm mv cat env python3 mkdir touch basename grep jq date; do
  ln -s "$(command -v "$tool")" "$stub/bin/$tool" || exit 1
done

# The daemon stub runs python under this name: the scripts only kill a pid whose /proc comm is ydotoold.
mkdir -p "$stub/py" && ln -s "$(command -v python3)" "$stub/py/ydotoold" || exit 1
for tool in ydotool wlrctl notify-send; do
  cat >"$stub/$tool" <<'STUB'
#!/bin/sh
. "$STUB_DIR/mode" 2>/dev/null
echo "$(basename "$0") $*" >>"$STUB_DIR/log"
# ydotool's default socket ($XDG_RUNTIME_DIR/.ydotool_socket) may be a stale one from a manual run; no call may use it.
case $(basename "$0"):$YDOTOOL_SOCKET in ydotool:*/hypr-cursor-drag/*/sock) ;; ydotool:*) echo "ydotool default socket" >>"$STUB_DIR/log" ;; esac
[ "$(basename "$0")" = ydotool ] && [ "$1" = click ] && [ "$2" = 0x40 ] && [ -n "$FAIL_PRESS" ] && exit 1
exit 0
STUB
done
cat >"$stub/hyprctl" <<'STUB'
#!/bin/sh
case $1 in
  # One file per callback, written under a dot name and then renamed, so the pump never reads a half-written one and
  # never races an append. The timestamp name keeps the callbacks in order.
  eval)
    tmp="$STUB_DIR/cb.d/.tmp.$$"
    echo "$2" >"$tmp"
    mv "$tmp" "$STUB_DIR/cb.d/$(date +%s%N).$$" ;;
  # The daemon's mouse is listed once its device file exists. As on Hyprland, its keyboard takes the plain name and its
  # mouse gets a -N suffix and its own address, both changing with each start. REUSE_NAME keeps the suffix and
  # REUSE_ADDRESS the address of the first start, as a freed device can come back under both. PREEXISTING_MOUSE adds
  # another daemon's mouse, listed throughout.
  devices)
    . "$STUB_DIR/mode" 2>/dev/null
    mice='{"address":"0x1","name":"keyd-virtual-pointer"},{"address":"0x3","name":null}'
    keyboards=''
    [ -n "$PREEXISTING_MOUSE" ] && mice="$mice"',{"address":"0x4","name":"ydotoold-virtual-device-90"}'
    if [ -f "$STUB_DIR/device" ]; then
      serial=$(cat "$STUB_DIR/device")
      suffix=$serial; [ -n "$REUSE_NAME" ] && suffix=1
      address=$(printf '0x%x' $((0x1000 + serial))); [ -n "$REUSE_ADDRESS" ] && address=0x2
      mice="$mice"',{"address":"'"$address"'","name":"ydotoold-virtual-device-'"$suffix"'"}'
      keyboards='{"address":"0x5","name":"ydotoold-virtual-device"}'
    fi
    echo "{\"mice\":[$mice],\"keyboards\":[$keyboards]}" ;;
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
# The virtual mouse shows up in `hyprctl devices` some time after the socket, or never (NO_DEVICE).
serial=$(( $(cat "$STUB_DIR/serial" 2>/dev/null || echo 0) + 1 )); echo $serial >"$STUB_DIR/serial"
[ -z "$NO_DEVICE" ] && (sleep "${DEVICE_DELAY:-0}"; kill -0 $$ 2>/dev/null && echo $serial >"$STUB_DIR/device") &
export DEVICE_LINGER
exec "$STUB_DIR/py/ydotoold" -I -c '
import os, signal, socket, sys
s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])
def stop(*_):
    open(sys.argv[2], "a").write("ydotoold stop\n")
    device = os.path.join(os.path.dirname(sys.argv[2]), "device")
    if os.environ.get("DEVICE_LINGER"):
        # Hyprland lists the mouse of a dead daemon for a moment longer.
        # It removes the file only while it still names this daemon, not a later one.
        try: serial = open(device).read().strip()
        except OSError: serial = ""
        os.spawnlp(os.P_NOWAIT, "sh", "sh", "-c", "sleep $1; [ x$(cat $2) = x$3 ] && rm -f $2", "sh", os.environ["DEVICE_LINGER"], device, serial)
    else:
        try: os.remove(device)
        except OSError: pass
    sys.exit(0)
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
