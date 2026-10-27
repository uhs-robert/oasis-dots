#!/usr/bin/env bash
# Usage: coderabbit-review.sh <base> <outdir>; run from a clean worktree. Exits 0 with the review path, 2 when coderabbit is unavailable, 3 on uncommitted changes, 4 when skipped by scope.
set -u

base=${1:?usage: coderabbit-review.sh <base> <outdir>}
outdir=${2:?usage: coderabbit-review.sh <base> <outdir>}
timeout_s=${REVIEW_TIMEOUT_S:-900}
# shellcheck source=review-lib.sh
. "$(dirname "$0")/review-lib.sh"

review_scope_gate coderabbit "$outdir" public || exit 4

if ! review_tree_is_clean; then
  echo "coderabbit-review: the worktree has uncommitted changes, which --committed cannot see; commit first" >&2
  exit 3
fi

if ! command -v coderabbit >/dev/null 2>&1; then
  echo "coderabbit unavailable: coderabbit not installed"
  exit 2
fi

# No --use-credits: a local review must never spend beyond the included quota.
usage=$(coderabbit usage 2>/dev/null)
if printf '%s\n' "$usage" | grep -Eq '^[[:space:]]*Remaining[[:space:]]*:[[:space:]]*0[[:space:]]+of'; then
  echo "coderabbit unavailable: no included reviews left in the current window"
  exit 2
fi

mkdir -p "$outdir" || exit 2
out=$outdir/coderabbit-review.md
log=$outdir/coderabbit.stderr.log
timeout "$timeout_s" coderabbit review --base "$base" --committed >"$out" 2>"$log" </dev/null
code=$?
if [ "$code" -ne 0 ] || [ ! -s "$out" ]; then
  reason="exit $code"
  [ -s "$out" ] || reason="$reason, empty review"
  detail=$(tail -n 1 "$log" 2>/dev/null)
  [ -z "$detail" ] || reason="$reason: $detail"
  rm -f "$out"
  echo "coderabbit unavailable: $reason"
  exit 2
fi
echo "$out"
