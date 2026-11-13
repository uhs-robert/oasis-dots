#!/usr/bin/env bash
# Tests `shadow.sh player`: the fake player starts only with the shadow's env and private bus (never the owner's), is
# recorded as a session `down` sweeps, a second `start` leaves one player, and `stop` on a dead player succeeds. A
# recording stub stands in for python3 and playerctl, so no shadow or Hyprland is involved. A last case runs the real
# fake_player.py on a private dbus-daemon when dbus-daemon, playerctl and python3 with gi exist. Runs from a temp dir
# and fails if the repo's `git status` differs afterwards.
# shellcheck disable=SC2154 # the sourced script assigns runtime, base, shim_dir, logs and shadow_home
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
checkout_root=$(git -C "$here" rev-parse --show-toplevel) || exit 1
work=$(mktemp -d)
failures=0
before=$(git -C "$checkout_root" status --porcelain)

fail() {
  failures=$((failures + 1))
  echo "FAIL $*" >&2
}

# The owner's session bus, which must never reach the player.
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/owner-bus
export XDG_CACHE_HOME=$work/cache
trap 'teardown_all; rm -rf "$work"' EXIT
cd "$work" || exit 1

# shellcheck source=/dev/null # the shadow script, sourced for its functions only
source "$checkout_root/.claude/skills/shadow/shadow.sh"
set +e +o pipefail

# Per-process names, so two runs of the suite at once never share a runtime dir.
na=a${$: -6}
nb=b${$: -6}
teardown_all() { for n in "$na" "$nb"; do (set_name "$n" && teardown) >/dev/null 2>&1; done; }

# A shadow dir with a bus socket (a python listener, since only `-S` is checked) and the recording stubs.
make_shadow() {
  set_name "$1"
  mkdir -p "$runtime" "$shim_dir" "$logs"
  python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$runtime/bus"
  cat >"$shim_dir/python3" <<'STUB'
#!/bin/sh
# Records the environment and arguments the player was started with, then idles like a player.
{ env; echo "ARGS $*"; } >"$XDG_RUNTIME_DIR/player.env.$$"
exec sleep 300
STUB
  cat >"$shim_dir/playerctl" <<'STUB'
#!/bin/sh
echo shadowfake
STUB
  chmod +x "$shim_dir/python3" "$shim_dir/playerctl"
  # The stubs shadow python3 for the player only; the bus socket above used the real one.
}

players_of() { shadow_pids | while read -r pid; do tr '\0' ' ' <"/proc/$pid/cmdline" | grep -q 'sleep 300' && echo "$pid"; done; }

# Case 1: start uses the shadow's env and bus only.
make_shadow "$na"
player "$na" start --title "T one" --artist "" || fail "start exited non-zero"
[[ -f $base/player.sid ]] || fail "start wrote no player.sid"
env_file=$(compgen -G "$runtime/player.env.*" | head -1)
if [[ -z $env_file ]]; then
  fail "the player never ran"
else
  grep -qx "DBUS_SESSION_BUS_ADDRESS=unix:path=$runtime/bus" "$env_file" || fail "player bus is not the shadow's: $(grep DBUS "$env_file")"
  grep -q '/run/user/owner-bus' "$env_file" && fail "the owner's bus reached the player"
  grep -qx "XDG_RUNTIME_DIR=$runtime" "$env_file" || fail "player runtime dir is not the shadow's"
  grep -qx "HOME=$shadow_home" "$env_file" || fail "player HOME is not the shadow's"
  grep -q "^ARGS .*fake_player.py --title T one --artist $" "$env_file" || fail "player args wrong: $(grep ARGS "$env_file")"
fi

# Case 2: a second start replaces the player.
player "$na" start --title "T two"
[[ $(players_of | wc -l) == 1 ]] || fail "second start left $(players_of | wc -l) players, wanted 1"

# Case 3: a refused start (no bus) and a bad option start nothing.
(player "$na" start --bogus) 2>/dev/null && fail "unknown option accepted"
(player "$na") 2>/dev/null && fail "missing action accepted"

# Case 4: stop ends it, and stop again (dead player) and stop with no sid file both succeed.
player "$na" stop || fail "stop exited non-zero"
[[ $(players_of | wc -l) == 0 ]] || fail "stop left a player running"
player "$na" stop || fail "stop on a dead player failed"
echo 99999999 >"$base/player.sid"
player "$na" stop || fail "stop with a stale sid failed"
[[ ! -e $base/player.sid ]] || fail "stale player.sid not removed"

# Case 5: teardown (what down runs) sweeps a running player.
player "$na" start
[[ $(players_of | wc -l) == 1 ]] || fail "restart after stop did not start a player"
teardown >/dev/null 2>&1 || fail "teardown failed with a player running"
[[ $(players_of | wc -l) == 0 ]] || fail "down left a player running"
[[ ! -d $runtime ]] || fail "down left the runtime dir"

# Case 6: no bus socket, no start.
set_name "$nb"
mkdir -p "$runtime" "$logs"
(player "$nb" start) 2>/dev/null && fail "start without a bus succeeded"
[[ ! -e $base/player.sid ]] || fail "start without a bus left a player.sid"
teardown >/dev/null 2>&1

# Case 7: the real script on a private bus.
if command -v dbus-daemon >/dev/null && command -v playerctl >/dev/null && python3 -c 'import gi; gi.require_version("Gio", "2.0")' 2>/dev/null; then
  live=$work/live
  mkdir -p "$live"
  dbus-daemon --session --nofork --address="unix:path=$live/bus" >/dev/null 2>&1 &
  bus_pid=$!
  wait_for 100 test -S "$live/bus"
  run_player() { env -i PATH="$PATH" XDG_RUNTIME_DIR="$live" DBUS_SESSION_BUS_ADDRESS="unix:path=$live/bus" "$@"; }
  run_player python3 "$checkout_root/.claude/skills/shadow/fake_player.py" --title "Live T" --artist "" >"$live/player.log" 2>&1 &
  player_pid=$!
  ok=0
  for _ in $(seq 100); do
    run_player playerctl -p shadowfake metadata title 2>/dev/null | grep -qx "Live T" && ok=1 && break
    sleep 0.05
  done
  ((ok)) || fail "playerctl did not see the fake player: $(<"$live/player.log")"
  [[ $(run_player playerctl -p shadowfake status) == Playing ]] || fail "status is not Playing"
  [[ -z $(run_player playerctl -p shadowfake metadata artist 2>/dev/null) ]] || fail "an empty artist printed one"
  run_player playerctl -p shadowfake pause
  [[ $(run_player playerctl -p shadowfake status) == Paused ]] || fail "pause did not pause"
  # A second instance cannot take the name, so it must exit on its own.
  run_player python3 "$checkout_root/.claude/skills/shadow/fake_player.py" >/dev/null 2>&1 &
  second=$!
  for _ in $(seq 100); do
    kill -0 "$second" 2>/dev/null || break
    sleep 0.05
  done
  kill -0 "$second" 2>/dev/null && {
    fail "a second player kept running"
    kill "$second"
  }
  # The script refuses the owner's runtime dir.
  env -i PATH="$PATH" XDG_RUNTIME_DIR=/run/user/1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1/bus python3 "$checkout_root/.claude/skills/shadow/fake_player.py" >/dev/null 2>&1 && fail "the player accepted the owner's bus"
  kill "$player_pid" "$bus_pid" 2>/dev/null
  wait "$player_pid" "$bus_pid" 2>/dev/null
else
  echo "shadow-player: skipped the live-bus case (needs dbus-daemon, playerctl, python3 gi)"
fi

[[ $(git -C "$checkout_root" status --porcelain) == "$before" ]] || fail "the test changed the repo"
((failures == 0)) || exit 1
echo "shadow-player: ok"
