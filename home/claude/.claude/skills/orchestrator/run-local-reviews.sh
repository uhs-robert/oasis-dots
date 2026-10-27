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
trap 'rm -rf "$results"' EXIT

names=()
while IFS='|' read -r name scope command model; do
  [ "$scope" != off ] || continue
  [ -n "$command" ] || {
    echo "$name: no local command configured"
    continue
  }
  case $command in /*) ;; *) command=$here/$command ;; esac
  names+=("$name")
  (
    REVIEW_SCOPE=$scope REVIEW_MODEL=$model "$command" "$base" "$outdir" \
      >"$results/$name.out" 2>"$outdir/$name.stderr.log" </dev/null
    echo $? >"$results/$name.code"
  ) &
done < <(jq -r '.[] | [.name, .local.scope, (.local.command // ""), (.local.model // "")] | join("|")' <<<"$registry")
wait

for name in "${names[@]}"; do
  code=$(<"$results/$name.code")
  line=$(tail -n 1 "$results/$name.out")
  case $code in
  0) echo "$name: $line" ;;
  2 | 4) echo "$name: $line" ;;
  3) echo "$name: uncommitted changes; commit first" ;;
  *) echo "$name: failed (exit $code) ${line}" ;;
  esac
done
exit 0
