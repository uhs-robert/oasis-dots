# shellcheck shell=bash disable=SC2034,SC2016
# Launches the auto-launcher sessions by name, as picking one in the Session Launcher does. Format: ~/.config/voxcmd/README.md

name="Sessions"
confirm=0
# The session's windows appearing is the feedback.
silent_actions=(open)

# "open the session launcher" never ends in "session" after a target, so it stays with the keybinds. The "skip" verb
# matches first and offers nothing, so "open the work tmux session" falls through to Tmux instead of naming a session
# called "work tmux".
verbs=(
  "skip  {open} (.* )?tmux {target}"
  "open  {open} (the )?{target} session"
)

# A target of these words alone names no session, and word matching then offers nothing at all, not even "no session
# called", so "open a session" and "open a new session" are left to the Session Launcher bind; "open a work session"
# still names "work".
target_match=words
match_ignore_words=(a an any some new)

examples=(
  "open the <name> session"
)

declare -A actions=(
  [open]='launch_session "$id"'
  [not_found]='echo "no session called \"$target\""; false'
)

# Tab on the example in Voice Help lists every session, and picking one launches it.
help_action=open

# An unknown name must not fall through to the keybinds fallback and open a picker.
declare -A no_match_actions=(
  [open]='not_found'
)

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

candidates() {
  case "$1" in
  skip) echo '[]' ;;
  open) session_names | jq -c 'map({id: ., label: .})' 2>/dev/null ;;
  esac
}

# The name goes to Lua as a JSON string, which Lua reads the same for anything but \u escapes jq only writes for control
# characters.
launch_session() {
  hyprctl_eval "$launcher_module.launch($(jq -n -c --arg name "$1" '$name'))"
}
