#!/usr/bin/env bash
# Usage: codex-review.sh <base> <outdir>; run from the worktree.
set -u

base=${1:?usage: codex-review.sh <base> <outdir>}
outdir=${2:?usage: codex-review.sh <base> <outdir>}
max_attempts=3
poll_s=${CODEX_POLL_S:-5}
stall_s=${CODEX_STALL_S:-120}
timeout_s=${CODEX_TIMEOUT_S:-900}

pid=""

kill_group() {
  [ -n "$pid" ] || return 0
  kill -TERM -- "-$pid" 2>/dev/null
  sleep 0.2
  kill -KILL -- "-$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  pid=""
}

trap kill_group EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if ! command -v codex >/dev/null 2>&1; then
  echo "codex unavailable: codex not installed"
  exit 2
fi

mkdir -p "$outdir" || exit 2
reason=""

# Codex exits 1 for every failure; the cause is only in its event stream or stderr.
failure_message() {
  local dir=$1 msg=""
  if command -v jq >/dev/null 2>&1; then
    msg=$(jq -r 'select(.type == "turn.failed" or .type == "error") | .error.message // .message // empty' \
      "$dir/events.jsonl" 2>/dev/null | tail -n 1)
  fi
  [ -n "$msg" ] || msg=$(tail -n 1 "$dir/stderr.log" 2>/dev/null)
  printf '%s' "$msg"
}

run_attempt() {
  local dir=$1 start last_size=0 size last_growth now
  mkdir -p "$dir"
  : >"$dir/events.jsonl"
  : >"$dir/review.md"
  : >"$dir/stderr.log"
  setsid codex exec review --base "$base" --json -o "$dir/review.md" \
    >"$dir/events.jsonl" 2>"$dir/stderr.log" </dev/null &
  pid=$!
  start=$(date +%s)
  last_growth=$start
  while :; do
    sleep "$poll_s"
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid"
      local code=$?
      pid=""
      if [ "$code" -ne 0 ]; then
        reason="exit $code"
        local msg
        msg=$(failure_message "$dir")
        [ -z "$msg" ] || reason="$reason: $msg"
        return 1
      fi
      if [ ! -s "$dir/review.md" ]; then
        reason="empty review"
        return 1
      fi
      return 0
    fi
    now=$(date +%s)
    size=$(stat -c %s "$dir/events.jsonl" 2>/dev/null || echo 0)
    if [ "$size" -ne "$last_size" ]; then
      last_size=$size
      last_growth=$now
    fi
    if [ $((now - start)) -ge "$timeout_s" ]; then
      kill_group
      reason="timeout"
      return 1
    fi
    if [ $((now - last_growth)) -ge "$stall_s" ]; then
      kill_group
      reason="stalled"
      return 1
    fi
  done
}

for n in $(seq 1 "$max_attempts"); do
  dir="$outdir/attempt-$n"
  echo "codex review: attempt $n/$max_attempts started" >&2
  if run_attempt "$dir"; then
    cp "$dir/review.md" "$outdir/review.md" || exit 2
    echo "codex review: attempt $n/$max_attempts ok" >&2
    echo "$outdir/review.md"
    exit 0
  fi
  echo "codex review: attempt $n/$max_attempts failed ($reason)" >&2
  # Retrying cannot outlast a usage limit; it resets hours later.
  case $reason in *"usage limit"*) break ;; esac
done

echo "codex unavailable: $reason"
exit 2
