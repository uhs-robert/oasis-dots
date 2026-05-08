#!/bin/bash
# Wrapper for VoxtType that auto-pauses/resumes media

STATE_FILE="$XDG_RUNTIME_DIR/voxtype/state"
MEDIA_PAUSED_FLAG="/tmp/voxtype-paused-media"

# Check current VoxtType state
if [ -f "$STATE_FILE" ]; then
  current_state=$(cat "$STATE_FILE")
else
  current_state="idle"
fi

# Starting recording - pause media if playing
if [ "$current_state" = "idle" ]; then
  if playerctl status 2>/dev/null | grep -q "Playing"; then
    playerctl pause
    touch "$MEDIA_PAUSED_FLAG"
  fi
fi

# Toggle VoxtType
voxtype record toggle

# Stopping recording - resume media if we paused it
if [ "$current_state" != "idle" ]; then
  sleep 0.3  # Brief delay for transcription
  if [ -f "$MEDIA_PAUSED_FLAG" ]; then
    playerctl play
    rm "$MEDIA_PAUSED_FLAG"
  fi
fi
