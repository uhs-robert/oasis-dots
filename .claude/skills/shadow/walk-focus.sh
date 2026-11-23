#!/bin/bash
# Manual repro for popup keyboard focus lost after a fast Ctrl+H/L walk.
# usage: walk-focus.sh <running shadow name> [runs=10] [start popup=start]
# Each run opens a popup, sends 12 Ctrl+L/H presses (3:1) at 0.15 s, then Escape; it passes when the popup closes.
# Do not call `popup focus` before Escape: it re-grabs the keyboard and hides the failure.
S="$(dirname "$(readlink -f "$0")")/shadow.sh"
n=${1:?usage: walk-focus.sh <shadow> [runs] [popup]}
runs=${2:-10}
start=${3:-start}
pass=0
for r in $(seq "$runs"); do
  $S ipc "$n" popup close >/dev/null
  sleep 0.6
  $S ipc "$n" popup open "$start" >/dev/null
  sleep 1
  for k in l l l h l l l h l l l h; do
    $S keys "$n" -M ctrl -k $k -m ctrl >/dev/null
    sleep 0.15
  done
  sleep 1
  st=$($S ipc "$n" popup state)
  $S keys "$n" -k Escape >/dev/null
  sleep 0.8
  after=$($S ipc "$n" popup state)
  ok=FAIL
  [ "$after" = closed ] && {
    ok=ok
    pass=$((pass + 1))
  }
  echo "run $r: state=[$st] after_esc=[$after] $ok"
done
echo "pass $pass/$runs"
[ "$pass" = "$runs" ]
