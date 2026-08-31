#!/bin/sh
# Stops the recording, waits for voxtype to go idle again, pastes the transcript into tmux.

set -eu

if [ "$#" -ne 4 ]; then
  printf 'usage: %s TRANSCRIPT_FILE PREFIX submit|prefill TMUX_TARGET\n' "$0" >&2
  exit 2
fi

transcript_file="$1"
prefix="$2"
mode="$3"
tmux_target="$4"

timeout_seconds=90

notify() {
  notify-send "AI" "$1" 2>/dev/null || true
}

fail() {
  notify "$1"
  printf '%s\n' "$1" >&2
  exit 1
}

case "$mode" in
  submit | prefill) ;;
  *) fail "invalid mode: $mode" ;;
esac

fifo=$(mktemp -u "${XDG_RUNTIME_DIR:-/tmp}/ai-voice-status.XXXXXX")
mkfifo "$fifo"
cleanup() { rm -f "$fifo"; }
trap cleanup EXIT

timeout "$timeout_seconds" voxtype status --follow --format json >"$fifo" 2>/dev/null &
watcher_pid=$!

# attach before stop, so first line is "recording" not a stale "idle"
exec 3<"$fifo"

voxtype record stop

found_idle=0
while IFS= read -r line <&3; do
  case "$line" in
    *'"alt": "idle"'*)
      found_idle=1
      break
      ;;
  esac
done

exec 3<&-
kill "$watcher_pid" 2>/dev/null || true
wait "$watcher_pid" 2>/dev/null || true

[ "$found_idle" -eq 1 ] || fail "voxtype transcription timed out"

transcript=$(cat "$transcript_file" 2>/dev/null || true)
rm -f "$transcript_file"

[ -n "$transcript" ] || { notify "Empty transcript, nothing sent"; exit 0; }

printf '%s %s' "$prefix" "$transcript" | tmux load-buffer -b ai-voice -
tmux paste-buffer -p -d -b ai-voice -t "$tmux_target"

if [ "$mode" = "submit" ]; then
  tmux send-keys -t "$tmux_target" Enter
fi
