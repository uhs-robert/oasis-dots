# shellcheck shell=bash
# Hook library of screenshot.toml: sourced before every hook of the integration.

screenshot_tool="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/screenshot.sh"

# screenshot.sh waits for the selector or the capture to finish; detached, voxcmd does not.
capture() {
  if [ ! -x "$screenshot_tool" ]; then
    echo "$screenshot_tool is missing"
    return 1
  fi
  setsid -f "$screenshot_tool" "$@" >/dev/null 2>&1 </dev/null
}
