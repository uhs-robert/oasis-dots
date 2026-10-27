#!/usr/bin/env bash
# Usage: claude-review.sh <base> <outdir>; run from a clean worktree. Exits 0 with the review path, 2 when claude is unavailable, 3 on uncommitted changes, 4 when skipped by scope.
set -u

base=${1:?usage: claude-review.sh <base> <outdir>}
outdir=${2:?usage: claude-review.sh <base> <outdir>}
timeout_s=${REVIEW_TIMEOUT_S:-900}
# shellcheck source=review-lib.sh
. "$(dirname "$0")/review-lib.sh"

review_scope_gate claude "$outdir" off || exit 4

if ! review_tree_is_clean; then
  echo "claude-review: the worktree has uncommitted changes, which git diff <base>...HEAD cannot see; commit first" >&2
  exit 3
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "claude unavailable: claude not installed"
  exit 2
fi

mkdir -p "$outdir" || exit 2
diff_file=$outdir/claude-input.diff
out=$outdir/claude-review.md
log=$outdir/claude.stderr.log
if ! git diff "$base...HEAD" >"$diff_file" 2>"$log" || [ ! -s "$diff_file" ]; then
  echo "claude unavailable: no diff against $base"
  exit 2
fi

prompt='Review the diff on stdin for correctness bugs, regressions, missed requirements, unrelated changes, needless complexity and weak tests. The repository is the current directory; use Read, Grep and Glob to check callers and context. Report findings ranked by severity, each with file:line, a concrete failure scenario, confidence (confirmed or plausible) and a suggested fix. Do not edit anything. If you find nothing, say so.'

# No --bare: it reads only ANTHROPIC_API_KEY, so with OAuth login it prints "Not logged in" and still exits 0.
# --restricted ignores the reviewed tree's settings and hooks and confines file tools to the working dir;
# --strict-mcp-config with no --mcp-config loads no MCP servers (the tree could define some).
model_args=()
[ -z "${REVIEW_MODEL:-}" ] || model_args=(--model "$REVIEW_MODEL")
nice timeout "$timeout_s" claude -p --restricted --strict-mcp-config --tools "Read,Grep,Glob" --permission-mode dontAsk \
  --permission-prompts none --no-session-persistence "${model_args[@]}" "$prompt" \
  <"$diff_file" >"$out" 2>>"$log"
code=$?
# Only a short output counts as the login notice: a real review may quote the phrase.
not_logged_in() { [ "$(wc -l <"$out")" -le 1 ] && grep -qi 'not logged in' "$out"; }
if [ "$code" -ne 0 ] || [ ! -s "$out" ] || not_logged_in; then
  reason="exit $code"
  if [ ! -s "$out" ]; then
    reason="$reason, empty output"
  elif not_logged_in; then
    reason="$reason, not logged in"
  fi
  detail=$(tail -n 1 "$log" 2>/dev/null)
  [ -z "$detail" ] || reason="$reason: $detail"
  rm -f "$out"
  echo "claude unavailable: $reason"
  exit 2
fi
echo "$out"
