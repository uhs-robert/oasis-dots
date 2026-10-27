#!/usr/bin/env bash
# Usage: run-local-reviews.sh <base> <outdir>; run from a clean worktree.
# Runs every reviewer whose resolved local scope is not off (see reviewers.md), in parallel, and prints one line per
# reviewer: `<name>: <review path>` or `<name>: <why there is none>`. Results are advisory, so the exit is 0 whatever the
# reviewers did; 1 means the registry did not resolve or the results could not be copied, 64 bad usage.
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
# Reviewers write here, outside the worktree: a file in the tree would make a sibling reviewer's clean-tree check fail.
# It is moved into outdir after all of them finish.
stage=$results/stage
mkdir "$stage"

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
  if [ ${#victims[@]} -gt 0 ]; then
    kill -TERM "${victims[@]}" 2>/dev/null
    # A reviewer that traps TERM gets a short grace period, then KILL.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "${victims[@]}" 2>/dev/null || break
      sleep 0.2
    done
    kill -KILL "${victims[@]}" 2>/dev/null
  fi
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
  # The reviewer owns <outdir>/<name>/ alone: clearing it drops the last run's files, which must neither pass for this
  # run's result nor (with an in-tree outdir) dirty the tree for the reviewer's own clean-tree check.
  rm -rf "${outdir:?}/$name"
  mkdir "$stage/$name"
  names+=("$name")
  REVIEW_SCOPE=$scope REVIEW_MODEL=$model bash -c '
    "$1" "$2" "$3" >"$4" 2>"$5" </dev/null
    echo $? >"$6"' _ "$command" "$base" "$stage/$name" \
    "$results/$name.out" "$stage/$name/$name.stderr.log" "$results/$name.code" &
  pids+=("$!")
done < <(jq -c '.[]' <<<"$registry")
wait
# Reaped: a later kill could hit an unrelated process that reused the pid, so drop them before anything can fail.
pids=()
cp -a "$stage"/. "$outdir"/ || {
  echo "run-local-reviews: could not copy the results to $outdir" >&2
  exit 1
}

for name in "${names[@]}"; do
  code=$(<"$results/$name.code")
  line=$(tail -n 1 "$results/$name.out")
  line=${line//"$stage"/"$outdir"}
  case $code in
  0 | 2 | 4) echo "$name: $line" ;;
  3) echo "$name: uncommitted changes; commit first" ;;
  *) echo "$name: failed (exit $code) ${line}" ;;
  esac
done
exit 0
