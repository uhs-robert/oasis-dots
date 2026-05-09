#!/usr/bin/env bash
# hypr/.config/hypr/scripts/go-to-or-open.sh

set -euo pipefail

# Print usage and exit with error
usage() {
  cat <<EOF
Focus an existing Hyprland window or launch the program if no matching window is found.

Usage: go-to-or-open.sh <program> [options]

Options:
  -c, --class <window-class>    Window class to match (default: <program>)
  -t, --title <title>           Window title to match (exact or prefix)
  -x, --exclude-title <prefix>  Skip windows whose title starts with <prefix>
  -e, --cmd <launch-cmd>        Command to launch if no window found (default: <program>)
  -h, --help                    Show this help message
EOF
  exit 1
}

# Populate globals: PROGRAM, CLASS, TITLE, EXCLUDE_TITLE, CMD
parse_args() {
  [[ $# -lt 1 ]] && usage
  [[ "$1" == "--help" || "$1" == "-h" ]] && usage
  PROGRAM="$1"
  CLASS="$PROGRAM"
  TITLE=""
  EXCLUDE_TITLE=""
  CMD=""
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -c | --class)
      CLASS="$2"
      shift 2
      ;;
    -t | --title)
      TITLE="$2"
      shift 2
      ;;
    -x | --exclude-title)
      EXCLUDE_TITLE="$2"
      shift 2
      ;;
    -e | --cmd)
      CMD="$2"
      shift 2
      ;;
    *) usage ;;
    esac
  done
}

# Query hyprctl for the first matching window address; prints empty string if none
# $class/$title/$exclude are jq --arg variables, not shell expansions, shellcheck disabled for each
find_window() {
  local jq_args=(--arg class "$CLASS")
  # shellcheck disable=SC2016
  local jq_filter='.[] | select(.class == $class)'

  if [[ -n "$TITLE" ]]; then
    jq_args+=(--arg title "$TITLE")
    # shellcheck disable=SC2016
    jq_filter+=' | select(.title == $title or (.title | startswith($title + " ")))'
  fi

  if [[ -n "$EXCLUDE_TITLE" ]]; then
    jq_args+=(--arg exclude "$EXCLUDE_TITLE")
    # shellcheck disable=SC2016
    jq_filter+=' | select((.title | startswith($exclude)) | not)'
  fi

  hyprctl clients -j | jq -r "${jq_args[@]}" "$jq_filter | .address" | head -n 1
}

# Focus an existing window by its hyprctl address
focus_window() {
  hyprctl dispatch focuswindow "address:$1"
}

# Launch the program; uses CMD if set, otherwise runs PROGRAM directly
launch_program() {
  if [[ -n "$CMD" ]]; then
    eval "$CMD" &
  else
    "$PROGRAM" &
  fi
}

main() {
  parse_args "$@"

  local address
  address="$(find_window)"
  if [[ -n "$address" ]]; then
    focus_window "$address"
  else
    launch_program
  fi
}

main "$@"
