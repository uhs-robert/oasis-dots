#!/usr/bin/env bash
# Usage: run-local-reviews.sh <base> <outdir>; run from a clean worktree.
# Runs every reviewer whose resolved local scope is not off (see reviewers.md), in parallel, and prints one line per
# reviewer: `<name>: <review path>` or `<name>: <why there is none>`. Results are advisory, so the exit is 0 whatever the
# reviewers did; 1 means the registry did not resolve, 64 bad usage.
set -u

[ $# -eq 2 ] || {
  echo "usage: run-local-reviews.sh <base> <outdir>" >&2
  exit 64
}
base=$1
outdir=$2
here=$(cd "$(dirname "$0")" && pwd)

registry=$("$here/reviewers.sh" list) || {
  echo "run-local-reviews: reviewers.sh list failed" >&2
  exit 1
}
mkdir -p "$outdir" || exit 1
results=$(mktemp -d)

# `timeout` moves its child into a process group of its own, so a group kill misses it: walk the process tree instead.
pids=()
# shellcheck disable=SC2329 # Both functions run from the EXIT trap.
descendants() {
  local child
  for child in $(pgrep -P "$1" 2>/dev/null); do
    descendants "$child"
    echo "$child"
  done
}
# shellcheck disable=SC2329
cleanup() {
  local pid found victims=()
  for pid in "${pids[@]}"; do
    mapfile -t found < <(descendants "$pid")
    victims+=("${found[@]}" "$pid")
  done
  [ ${#victims[@]} -eq 0 ] || kill -TERM "${victims[@]}" 2>/dev/null
  rm -rf "$results"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# jq is a hard dependency (reviewers.sh needs it too). Fields are read one jq call each, never split on a delimiter.
names=()
while IFS= read -r entry; do
  name=$(jq -r '.name' <<<"$entry")
  scope=$(jq -r '.local.scope' <<<"$entry")
  command=$(jq -r '.local.command // ""' <<<"$entry")
  model=$(jq -r '.local.model // ""' <<<"$entry")
  # Only enabled reviewers are worth a warning.
  [ "$scope" != off ] || continue
  [[ $name =~ ^[a-z0-9][a-z0-9_-]*$ ]] || {
    echo "run-local-reviews: skipping reviewer with unsafe name '$name'" >&2
    echo "$name: skipped, the name is not usable in a file name"
    continue
  }
  [ -n "$command" ] || {
    echo "$name: no local command configured"
    continue
  }
  case $command in /*) ;; *) command=$here/$command ;; esac
  # A stale file from an earlier run must not pass for this run's result.
  rm -f "$outdir/$name-review.md" "$outdir/$name-skipped.txt"
  names+=("$name")
  REVIEW_SCOPE=$scope REVIEW_MODEL=$model bash -c '
    "$1" "$2" "$3" >"$4" 2>"$5" </dev/null
    echo $? >"$6"' _ "$command" "$base" "$outdir" \
    "$results/$name.out" "$outdir/$name.stderr.log" "$results/$name.code" &
  pids+=("$!")
done < <(jq -c '.[]' <<<"$registry")
wait
# Reaped: a later kill could hit an unrelated process that reused the pid.
pids=()

for name in "${names[@]}"; do
  code=$(<"$results/$name.code")
  line=$(tail -n 1 "$results/$name.out")
  case $code in
  0 | 2 | 4) echo "$name: $line" ;;
  3) echo "$name: uncommitted changes; commit first" ;;
  *) echo "$name: failed (exit $code) ${line}" ;;
  esac
done
exit 0
