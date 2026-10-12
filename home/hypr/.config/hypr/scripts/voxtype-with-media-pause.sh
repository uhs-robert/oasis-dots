#!/bin/bash
# Speech to Text: dictate with voxtype, pausing media while it records.
# While voxtype records, every voice key only stops it, so this also ends a voxcmd recording and leaves its
# transcript to voxcmd. Media resumes when the recording this script started ends, whichever key (or voxtype's
# max duration) ends it.

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/voxtype/state"

voxtype_state() { cat "$STATE_FILE" 2>/dev/null || echo idle; }

# Polled every 0.2s: 5s for the recording to show up, 10 minutes for it to end.
resume_media_when_recording_ends() {
  local polls recording_seen=0
  for ((polls = 0; polls < 3000; polls++)); do
    if [ "$(voxtype_state)" = recording ]; then
      recording_seen=1
    elif [ "$recording_seen" = 1 ] || [ "$polls" -gt 25 ]; then
      break
    fi
    sleep 0.2
  done
  playerctl play
}

if [ "${1:-}" = --resume-media-when-recording-ends ]; then
  resume_media_when_recording_ends
  exit
fi

case "$(voxtype_state)" in
recording) exec voxtype record stop ;;
idle) ;;
# Transcribing: the text is already on its way.
*) exit 0 ;;
esac

media_paused=0
if playerctl status 2>/dev/null | grep -q "Playing"; then
  playerctl pause && media_paused=1
fi
if ! voxtype record start; then
  [ "$media_paused" = 0 ] || playerctl play
  exit 1
fi
if [ "$media_paused" = 1 ]; then
  setsid "$0" --resume-media-when-recording-ends </dev/null >/dev/null 2>&1 &
fi
