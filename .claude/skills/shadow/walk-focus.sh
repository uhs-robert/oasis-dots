#!/usr/bin/env bash
# Repro for popup keyboard focus lost after a fast Ctrl+H/L walk, on a running shadow bar.
# Each run opens a popup, sends 12 Ctrl+L/H presses (3:1) at 0.15 s, then Escape; it passes when the popup closes.
# Usage: walk-focus.sh <shadow> [runs=10] [start popup=start]   (exits non-zero when any run fails)
# Do not call `popup focus` before Escape: it re-grabs the keyboard and hides the failure.
set -euo pipefail

shadow="$(dirname "$(readlink -f "$0")")/shadow.sh"
name=${1:?usage: walk-focus.sh <shadow> [runs] [popup]}
runs=${2:-10}
start_popup=${3:-start}
passed=0

for run in $(seq "$runs"); do
  "$shadow" ipc "$name" popup close >/dev/null
  sleep 0.6
  "$shadow" ipc "$name" popup open "$start_popup" >/dev/null
  sleep 1
  for key in l l l h l l l h l l l h; do
    "$shadow" keys "$name" -M ctrl -k "$key" -m ctrl >/dev/null
    sleep 0.15
  done
  sleep 1
  state_before=$("$shadow" ipc "$name" popup state)
  "$shadow" keys "$name" -k Escape >/dev/null
  sleep 0.8
  state_after=$("$shadow" ipc "$name" popup state)
  verdict=FAIL
  if [[ $state_after == closed ]]; then
    verdict=ok
    passed=$((passed + 1))
  fi
  echo "run $run: state=[$state_before] after_esc=[$state_after] $verdict"
done
echo "pass $passed/$runs"
[[ $passed == "$runs" ]]
