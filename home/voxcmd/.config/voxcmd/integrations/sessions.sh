# shellcheck shell=bash
# Hook library of sessions.toml: sourced before every hook and action of the integration.

launcher_module="require('extensions.auto_launcher.launcher')"

hyprctl_eval() {
  local output
  output=$(hyprctl eval "$1" 2>&1) || {
    echo "$output"
    return 1
  }
}

# Prints the launcher's session names as a JSON array. `hyprctl eval` prints nothing back, so Hyprland's Lua writes
# them to a file, one per call since phrases are routed in parallel. Prints nothing when Hyprland cannot answer, which
# leaves the phrase to the action to report.
session_names() {
  local dir="${XDG_RUNTIME_DIR:-/tmp}/voxcmd" file
  mkdir -p "$dir"
  file=$(mktemp "$dir/launcher-sessions.XXXXXX") || return 0
  hyprctl eval "$launcher_module.write_names('$file')" >/dev/null 2>&1 && cat "$file" 2>/dev/null
  rm -f "$file"
  return 0
}

# id<TAB>label per session, both the name. A name holding a tab or newline splits the row, as it never did in JSON.
# When the names cannot be read (Hyprland down, or a reply that is not a JSON list) bash had no hook answer and
# launched the spoken target as the name, so the target is offered as the one session, and the action reports the failure.
session_candidates() {
  local names rows
  names=$(session_names)
  if [ -n "$names" ] && rows=$(jq -r '.[] | [., .] | join("\t")' <<<"$names" 2>/dev/null); then
    [ -z "$rows" ] || printf '%s\n' "$rows"
  elif [ -n "${VOXCMD_ARG_TARGET:-}" ]; then
    printf '%s\t%s\n' "$VOXCMD_ARG_TARGET" "$VOXCMD_ARG_TARGET"
  fi
}

# The name goes to Lua as a JSON string, which Lua reads the same for anything but \u escapes jq only writes for control
# characters.
launch_session() {
  hyprctl_eval "$launcher_module.launch($(jq -n -c --arg name "$1" '$name'))"
}
