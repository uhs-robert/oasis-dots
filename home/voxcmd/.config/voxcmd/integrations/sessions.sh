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
# The hook runner kills a hook that outlives its 3 s limit with SIGKILL, which no trap catches. So hyprctl gets a shorter
# limit of its own, with a KILL after 0.5 s for a hyprctl that ignores TERM, and the rm below always runs.
session_names() {
  local dir="${XDG_RUNTIME_DIR:-/tmp}/voxcmd" file
  mkdir -p "$dir"
  file=$(mktemp "$dir/launcher-sessions.XXXXXX") || return 0
  timeout --kill-after=0.5 2 hyprctl eval "$launcher_module.write_names('$file')" >/dev/null 2>&1 && cat "$file" 2>/dev/null
  rm -f "$file"
  return 0
}

# id<TAB>label per session, both the name. Names holding a tab or newline, and empty names, are skipped: such a name
# would split its row, and the launch looks the name up exactly, so a changed name would launch nothing.
# Prints nothing when the names cannot be read (Hyprland down, or a reply that is not a JSON list).
session_candidates() {
  local names
  names=$(session_names)
  [ -n "$names" ] || return 0
  jq -r '.[] | select(. != "" and (test("[\t\n]") | not)) | [., .] | join("\t")' <<<"$names" 2>/dev/null || true
}

# The name goes to Lua as a JSON string, which Lua reads the same for anything but \u escapes jq only writes for control
# characters.
launch_session() {
  hyprctl_eval "$launcher_module.launch($(jq -n -c --arg name "$1" '$name'))"
}
