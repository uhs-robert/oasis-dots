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
cd "$work" || exit 1

# shellcheck source=/dev/null # the shadow script, sourced for its functions only
source "$checkout_root/.claude/skills/shadow/shadow.sh"
set +e +o pipefail

# Per-run names, so two runs of the suite at once never share a runtime dir (at most 8 characters).
run_id=$(((RANDOM << 15 | RANDOM) % 1000000))
na=a$run_id
nb=b$run_id
live_pids=()
# The real shadow_pids reads every /proc/*/environ (seconds on a busy machine). Here the sessions in the .sid files
# are what the test proves `teardown` sweeps, so the stray scan finds nothing.
shadow_pids() { :; }
cleanup() {
  local n
  for n in "$na" "$nb"; do
    set_name "$n"
    kill_session player
    rm -rf "$runtime"
  done
  ((${#live_pids[@]} == 0)) || kill "${live_pids[@]}" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

# A shadow dir with a bus socket (a python listener, since only `-S` is checked) and the recording stubs.
make_shadow() {
  set_name "$1"
  mkdir -p "$runtime" "$shim_dir" "$logs"
  python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$runtime/bus"
  cat >"$shim_dir/python3" <<'STUB'
#!/bin/bash
# Records the environment and arguments the player was started with, marks itself ready, then idles like a player.
# The argv0 marker lets the test count players with pgrep instead of scanning /proc environments.
{ env; echo "ARGS $*"; } >"$XDG_RUNTIME_DIR/player.env.$$"
touch "$XDG_RUNTIME_DIR/ready.$$"
exec -a "fakeplayer-test:$XDG_RUNTIME_DIR" sleep 300
STUB
  # Lists shadowfake only once a live stub has written its record, like the real bus name appearing after startup.
  cat >"$shim_dir/playerctl" <<'STUB'
#!/bin/sh
for f in "$XDG_RUNTIME_DIR"/ready.*; do
  [ -e "$f" ] && kill -0 "${f##*.}" 2>/dev/null && echo shadowfake && exit 0
done
exit 1
STUB
  chmod +x "$shim_dir/python3" "$shim_dir/playerctl"
  # The stubs shadow python3 for the player only; the bus socket above used the real one.
}

# Players running for the current shadow, by their argv0 marker.
players_of() { pgrep -f "^fakeplayer-test:$runtime "; }

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

# Case 3: a bad option and a missing action start nothing.
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
rm -rf "$runtime"

# Case 7: the real script on a private bus.
if command -v dbus-daemon >/dev/null && command -v playerctl >/dev/null && python3 -c 'import gi; gi.require_version("Gio", "2.0")' 2>/dev/null; then
  live=$work/live
  mkdir -p "$live"
  dbus-daemon --session --nofork --address="unix:path=$live/bus" >/dev/null 2>&1 &
  bus_pid=$!
  live_pids+=("$bus_pid")
  wait_for 100 test -S "$live/bus"
  run_player() { env -i PATH="$PATH" XDG_RUNTIME_DIR="$live" DBUS_SESSION_BUS_ADDRESS="unix:path=$live/bus" "$@"; }
  run_player python3 "$checkout_root/.claude/skills/shadow/fake_player.py" --title "Live T" --artist "" >"$live/player.log" 2>&1 &
  player_pid=$!
  live_pids+=("$player_pid")
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
  live_pids+=("$second")
  for _ in $(seq 100); do
    kill -0 "$second" 2>/dev/null || break
    sleep 0.05
  done
  kill -0 "$second" 2>/dev/null && {
    fail "a second player kept running"
    kill "$second"
  }
  # The script refuses the owner's runtime dir, an unset runtime dir, and a bus that is not <runtime>/bus.
  fake=$checkout_root/.claude/skills/shadow/fake_player.py
  refused=$(env -i PATH="$PATH" XDG_RUNTIME_DIR=/run/user/1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1/bus python3 "$fake" 2>&1)
  grep -q refusing <<<"$refused" || fail "the player accepted the owner's bus"
  refused=$(env -i PATH="$PATH" DBUS_SESSION_BUS_ADDRESS="unix:path=$live/bus" timeout 5 python3 "$fake" 2>&1)
  grep -q refusing <<<"$refused" || fail "the player accepted an empty runtime dir"
  refused=$(env -i PATH="$PATH" XDG_RUNTIME_DIR="$live" DBUS_SESSION_BUS_ADDRESS="unix:path=$live/other" timeout 5 python3 "$fake" 2>&1)
  grep -q refusing <<<"$refused" || fail "the player accepted a bus outside <runtime>/bus"
  kill "$player_pid" "$bus_pid" 2>/dev/null
  wait "$player_pid" "$bus_pid" 2>/dev/null
else
  echo "shadow-player: skipped the live-bus case (needs dbus-daemon, playerctl, python3 gi)"
fi

[[ $(git -C "$checkout_root" status --porcelain) == "$before" ]] || fail "the test changed the repo"
((failures == 0)) || exit 1
echo "shadow-player: ok"
