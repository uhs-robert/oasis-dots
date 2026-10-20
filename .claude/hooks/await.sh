#!/usr/bin/env bash
# Usage: await.sh <log> [secs]
# Waits up to secs (default 100, inside the Bash call's default 120 s timeout; a larger secs needs a matching Bash
# timeout, max 600000 ms) for a non-empty "<log>.exit", which the backgrounded run writes last.
# Finished: prints the log's tail and exits with the recorded code. Still running: exits 75, and the caller calls
# again. A reused log path returns the previous run's result, so always take a fresh private directory
# (dir=$(mktemp -d); log=$dir/log), which also keeps another process from planting a symlink at the path.
# Lives beside check-in-background.sh, whose forced backgrounding it pairs with.
set -u
log=${1:?usage: await.sh <log> [secs]}
secs=${2:-100}
tail_lines=40
still_running=75

waited=0
while [[ ! -s $log.exit ]]; do
  if ((waited >= secs)); then
    printf 'still running after %ss: %s\n' "$waited" "$(tail -n 1 "$log" 2>/dev/null)"
    exit "$still_running"
  fi
  sleep 2
  waited=$((waited + 2))
done

tail -n "$tail_lines" "$log" 2>/dev/null
code=$(<"$log.exit")
[[ $code =~ ^[0-9]+$ ]] || code=1
exit "$code"
