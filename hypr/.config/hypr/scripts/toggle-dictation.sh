#!/bin/bash

# Set up environment for proper audio/session access
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export PULSE_SERVER="unix:${XDG_RUNTIME_DIR}/pulse/native"
export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export PATH="$HOME/.local/bin:$PATH"
#
# Check if nerd-dictation is already in 'begin' mode
if pgrep -f "nerd-dictation" >/dev/null; then
  nerd-dictation end
  notify-send "Dictation" "Stopped" -t 2000 2>/dev/null || true
else
  # Start nerd-dictation with proper environment
  nerd-dictation begin --simulate-input-tool DOTOOL >/tmp/nd.log 2>&1 &
  disown
  notify-send "Dictation" "Started" -t 2000 2>/dev/null || true
fi
