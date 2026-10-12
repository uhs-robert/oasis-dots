# shellcheck shell=bash disable=SC2034,SC2016
# Opens installed apps and focuses, moves or closes Hyprland windows. Format: ~/.config/voxcmd/README.md

name="Apps"
confirm=0
# The window that opens or takes focus is the feedback; moving and closing keep their toast.
silent_actions=(open open_new focus)
# App names and window classes are short, so a fuzzy hit on scattered letters would run the wrong thing.
target_match=words
# "close the firefox window" is "close firefox"; a target of only these words ("close window", "open application")
# matches nothing and is left to the keybinds fallback. Kept in a global of its own too, for names_keybind():
# voxcmd's match_ignore_words is local to its loader and gone by the time candidates() runs.
ignored_words=(window app application program)
match_ignore_words=("${ignored_words[@]}")

# Spoken verbs per action, shared by the patterns below and by the keybind check in candidates(). -g because voxcmd
# sources this file from a function, which would make a plain declare local to it.
declare -gA action_verbs=(
  [open_new]="open new|launch new|start new"
  [open]="open|launch|start"
  [focus]="focus|switch to|go to"
  [move]="move|send|put"
  [close]="close"
)

# move's target is "<window> to workspace <n>": one placeholder carries both, and candidates() splits it.
verbs=(
  "open_new  (${action_verbs[open]}) (a )?new {target}"
  "open      (${action_verbs[open]}) {target}"
  "focus     (${action_verbs[focus]}) {target}"
  "move      (${action_verbs[move]}) {target}"
  "close     (${action_verbs[close]}) {target}"
)

examples=(
  "open <app>"
  "open a new <app>"
  "focus <window>"
  "move <window> to workspace <number>"
  "close <window>"
)

declare -A actions=(
  [open_new]='start_app "$id"'
  [open]='open_app "$id"'
  [focus]='focus_window "$id"'
  [move]='move_window "$id"'
  [close]='close_window "$id"'
)

# Only close labels read "<app> window: <title>", so only closing asks first.
confirm_labels=('^[^:]+ window(:|$)')

# Tab on these examples in Voice Help lists every installed app, and picking one opens it like "open <app>".
# Not candidates "open": its keybind checks would read the empty target as a phrase.
help_choices() {
  app_candidates | jq -c 'unique_by(.id) | sort_by(.label | ascii_downcase) | map({id, label, action: "open"})'
}

candidates() {
  local action="$1" target="$2"
  if spoken_as_keybind "$action" "$target" || names_session_or_agent "$target" || launches_keybind "$action" "$target"; then
    echo '[]'
    return
  fi
  case "$action" in
  open | open_new) app_candidates ;;
  focus | close) window_candidates "$action" ;;
  move) move_candidates "$target" ;;
  esac
}

# Words compared the way voxcmd's word matching compares them, as a set: filler and ignored_words dropped, number
# words as digits, plurals singular, so "close the browser" names "Close Browsers". Prefix of a jq program that
# defines `words`; the program needs `--argjson ignored`.
word_set_jq='
  {"one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10"} as $digits
  | (["the", "a", "an", "my", "this", "that", "please", "to", "of", "on", "in", "for", "it"] + $ignored) as $ignored
  | def singular: if length > 3 and endswith("s") and (endswith("ss") | not) then .[:-1] else . end;
    def words: ascii_downcase | gsub("\u0027"; "") | [splits("[^a-z0-9]+") | select(. != "") | ($digits[.] // .) | singular]
      | map(select(IN($ignored[]) | not)) | unique;'

ignored_words_json() {
  printf '%s\n' "${ignored_words[@]}" | jq -R -s -c 'split("\n") | map(select(. != ""))'
}

# True when one of the phrases is a described Hyprland keybind.
names_keybind() {
  hyprctl binds -j 2>/dev/null | jq -e --argjson ignored "$(ignored_words_json)" --args "$word_set_jq"'
    ($ARGS.positional | map(words)) as $phrases
    | any(.[] | select(.has_description) | .description | words; . as $bind | any($phrases[]; . == $bind))
  ' "$@" >/dev/null
}

# True when "<verb> <target>" names a described keybind ("close browsers", "focus left", "go to workspace 2", "start
# menu"): those belong to the keybinds fallback, which only gets a turn when this integration offers nothing.
spoken_as_keybind() {
  local action="$1" target="$2" verb phrases=()
  local -a spoken_verbs
  IFS='|' read -ra spoken_verbs <<<"${action_verbs[$action]}"
  for verb in "${spoken_verbs[@]}"; do phrases+=("$verb $target"); done
  names_keybind "${phrases[@]}"
}

# "switch to the X session", "go to the X agent": a session or agent integration owns those, and a window whose
# name X happens to match would otherwise share a picker with it, or take the phrase when X matches no session.
names_session_or_agent() {
  [[ " $1 " =~ \ (session|sessions|agent|agents)\  ]]
}

# True for "open files" or "open the browser" when a keybind is described by the target alone ("Files", "Browser")
# and no app is named by it: the bind launches what the desktop means by it, where a weak word match would offer
# File Roller or qutebrowser. An app the target names exactly ("open firefox" with a "Firefox" bind) stays here, so
# a running window is focused instead of a second one started.
launches_keybind() {
  local action="$1" target="$2"
  [[ "$action" == open || "$action" == open_new ]] || return 1
  names_keybind "$target" || return 1
  ! app_candidates | jq -e --argjson ignored "$(ignored_words_json)" --arg target "$target" "$word_set_jq"'
    ($target | words) as $spoken | any(.[]; (.match_text | words) == $spoken)' >/dev/null
}

# ---- Apps ------------------------------------------------------------------------------------------------------

# Desktop files by id (the path under applications/, "/" turned to "-"), the first data dir holding an id winning
# as the XDG spec says, so a Hidden=true copy in ~/.local/share masks the system one.
desktop_files() {
  local data_dirs="${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" dir
  local IFS=:
  for dir in $data_dirs; do
    [ -d "$dir/applications" ] || continue
    find -L "$dir/applications" -name '*.desktop' -printf '%P\t%p\n' 2>/dev/null
  done | awk -F'\t' '{ id = $1; gsub("/", "-", id) } !seen[id]++ { print id "\t" $2 }'
}

# Launchable apps as [{id, name, terminal, wm_class, exec, path}]: Type=Application entries that are not
# NoDisplay or Hidden and are shown on the current desktop, read from the [Desktop Entry] group only (the
# [Desktop Action ...] groups have their own Name and Exec).
desktop_entries() {
  desktop_files | awk -F'\t' -v desktops="${XDG_CURRENT_DESKTOP:-Hyprland}" '
    function on_this_desktop(list,   names, count, i) {
      count = split(desktops, names, ":")
      for (i = 1; i <= count; i++) if (index(";" list ";", ";" names[i] ";")) return 1
      return 0
    }
    {
      file = $2; group = ""; split("", entry)
      while ((getline line < file) > 0) {
        if (line ~ /^\[/) { group = line; continue }
        if (group != "[Desktop Entry]" || !(eq = index(line, "="))) continue
        key = substr(line, 1, eq - 1); sub(/[ \t]+$/, "", key)
        value = substr(line, eq + 1); sub(/^[ \t]+/, "", value)
        if (!(key in entry)) entry[key] = value
      }
      close(file)
      if (entry["Type"] != "Application" || entry["NoDisplay"] == "true" || entry["Hidden"] == "true") next
      if (entry["Name"] == "" || entry["Exec"] == "") next
      if (entry["OnlyShowIn"] != "" && !on_this_desktop(entry["OnlyShowIn"])) next
      if (entry["NotShowIn"] != "" && on_this_desktop(entry["NotShowIn"])) next
      print $1 "\t" entry["Name"] "\t" (entry["Terminal"] == "true") "\t" entry["StartupWMClass"] "\t" entry["Exec"] "\t" entry["Path"]
    }' | jq -R -s -c 'split("\n") | map(select(. != "") | split("\t")
      | {id: .[0], name: .[1], terminal: (.[2] == "1"), wm_class: .[3], exec: .[4], path: .[5]})'
}

# Each app matches by its Name and, when that says something else, by its id's last part ("Files" is also
# "nautilus", "Visual Studio Code" also "code").
app_candidates() {
  desktop_entries | jq -c '
    def plain: ascii_downcase | [splits("[^a-z0-9]+") | select(. != "")] | join(" ");
    map((.id | sub("\\.desktop$"; "") | split(".") | last) as $short
      | {id, label: .name, match_text: .name},
        (select(($short | plain) != (.name | plain)) | {id, label: .name, match_text: $short}))'
}

# An app that already has a window is focused rather than started again ("open firefox" twice gives one window);
# "open new firefox" always starts one.
open_app() {
  local entry address
  entry=$(desktop_entry "$1") || return 1
  address=$(app_window "$entry")
  if [ -n "$address" ]; then
    focus_window "$address" && echo "already running, focused it"
  else
    start_entry "$entry"
  fi
}

start_app() {
  local entry
  entry=$(desktop_entry "$1") || return 1
  start_entry "$entry"
}

desktop_entry() {
  local entry
  entry=$(desktop_entries | jq -c --arg id "$1" 'first(.[] | select(.id == $id)) // empty')
  if [ -z "$entry" ]; then
    echo "no installed app $1"
    return 1
  fi
  printf '%s\n' "$entry"
}

# The app's most recently focused window: its class (or initial class) is the entry's StartupWMClass, its id, or
# the last part of its id, ignoring case. A window outside the focus history has a negative ID and ranks last.
app_window() {
  local clients
  clients=$(hyprctl clients -j 2>/dev/null) || return 0
  jq -r --argjson app "$1" '
    ($app.id | sub("\\.desktop$"; "")) as $id
    | ([$app.wm_class, $id, ($id | split(".") | last)] | map(select(. != "") | ascii_downcase)) as $classes
    | map(select(.mapped and ((.class, .initialClass) | ascii_downcase | IN($classes[]))))
    | sort_by(.focusHistoryID | if . < 0 then infinite else . end) | first | .address // empty' <<<"$clients"
}

# Started like the Quickshell apps picker starts them: the Exec line with its field codes dropped, in Path when set,
# and Terminal=true apps inside the Hyprland config's terminal wrapper. setsid keeps the app off voxcmd's output
# pipe, which would otherwise hold the notification until the app exits.
start_entry() {
  local entry="$1" command directory terminal="" app_name
  command=$(jq -r .exec <<<"$entry" | sed -E 's/%[fFuUdDnNickvm]//g; s/%%/%/g')
  directory=$(jq -r .path <<<"$entry")
  app_name=$(jq -r .name <<<"$entry")
  if [ "$(jq -r .terminal <<<"$entry")" = true ]; then
    terminal="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/bin/term"
    [ -x "$terminal" ] || terminal="${TERMINAL:-kitty}"
  fi
  setsid -f sh -c '
    [ -z "$1" ] || cd "$1" || exit
    if [ -n "$2" ]; then exec "$2" -e sh -c "$3"; fi
    eval "exec $3"' sh "$directory" "$terminal" "$command" </dev/null >/dev/null 2>&1 || {
    echo "could not start $app_name"
    return 1
  }
  echo "started $app_name"
}

# ---- Windows ---------------------------------------------------------------------------------------------------

# Mapped windows, most recently focused first, each named by its app: the Name of the desktop entry whose
# StartupWMClass or id is its class, else the class's last part ("kitty-tmux-config"). Printed as
# [{address, app, title}] with long titles cut.
windows() {
  local clients
  clients=$(hyprctl clients -j 2>/dev/null) || clients='[]'
  jq -c --argjson apps "$(desktop_entries)" '
    # wm_class keys come last so they win over an id that happens to equal another app class.
    ($apps | map((.id | sub("\\.desktop$"; "")) as $id
        | {key: ($id | ascii_downcase), value: .name}, {key: ($id | split(".") | last | ascii_downcase), value: .name})
      + ($apps | map(select(.wm_class != "") | {key: (.wm_class | ascii_downcase), value: .name}))
      | from_entries) as $app_names
    | map(select(.mapped and .class != ""))
    | sort_by(.focusHistoryID | if . < 0 then infinite else . end)
    | map({address, app: ($app_names[.class | ascii_downcase] // (.class | split(".") | last)),
        title: (if (.title | length) > 60 then .title[:57] + "..." else .title end)})' <<<"$clients" 2>/dev/null || echo '[]'
}

# A window matches by its app name ("focus firefox") and by its title ("focus tmux config"); several matching
# windows open the picker, where the label shows each title.
window_candidates() {
  windows | jq -c --arg action "$1" '
    def plain: ascii_downcase | [splits("[^a-z0-9]+") | select(. != "")] | join(" ");
    map((if $action == "close" then "\(.app) window" else .app end) as $app_part
      | (if .title == "" then $app_part else "\($app_part): \(.title)" end) as $label
      | {id: .address, label: $label, match_text: .app},
        (select(.title != "" and (.title | plain) != (.app | plain)) | {id: .address, label: $label, match_text: .title}))'
}

# For "move firefox to workspace 3" every window is offered as "<app> to workspace 3" (and by title), so word
# matching compares the window part while the workspace rides along in the id as "<address> <workspace>". A target
# without the workspace part offers nothing.
move_candidates() {
  local target="$1" workspace_words workspace
  [[ "$target" =~ ^(.+)(\ (to|onto|on)\ (the\ )?(workspace|desktop)\ ([a-z0-9]+))$ ]] || {
    echo '[]'
    return
  }
  workspace_words="${BASH_REMATCH[2]}"
  workspace=$(workspace_number "${BASH_REMATCH[6]}")
  if [ -z "$workspace" ]; then
    echo '[]'
    return
  fi
  windows | jq -c --arg suffix "$workspace_words" --arg workspace "$workspace" '
    def plain: ascii_downcase | [splits("[^a-z0-9]+") | select(. != "")] | join(" ");
    map("\(.app): \(.title) to workspace \($workspace)" as $label
      | {id: "\(.address) \($workspace)", label: $label, match_text: (.app + $suffix)},
        (select(.title != "" and (.title | plain) != (.app | plain))
          | {id: "\(.address) \($workspace)", label: $label, match_text: (.title + $suffix)}))'
}

workspace_number() {
  case "$1" in
  one) echo 1 ;; two) echo 2 ;; three) echo 3 ;; four) echo 4 ;; five) echo 5 ;;
  six) echo 6 ;; seven) echo 7 ;; eight) echo 8 ;; nine) echo 9 ;; ten) echo 10 ;;
  eleven) echo 11 ;; twelve) echo 12 ;; thirteen) echo 13 ;; fourteen) echo 14 ;; fifteen) echo 15 ;;
  sixteen) echo 16 ;; seventeen) echo 17 ;; eighteen) echo 18 ;; nineteen) echo 19 ;; twenty) echo 20 ;;
  *) if [[ "$1" =~ ^[0-9]+$ ]] && [ "$((10#$1))" -ge 1 ]; then echo "$((10#$1))"; fi ;;
  esac
}

focus_window() {
  window_address "$1" || return 1
  hypr_dispatch "hl.dsp.focus({ window = 'address:$1' })"
}

# The window stays put on the current workspace's side: moving a window out of the way should not drag focus along.
move_window() {
  local address="${1% *}" workspace="${1##* }"
  window_address "$address" || return 1
  [[ "$workspace" =~ ^[0-9]+$ ]] || {
    echo "not a workspace: $workspace"
    return 1
  }
  hypr_dispatch "hl.dsp.window.move({ window = 'address:$address', workspace = $workspace, follow = false })"
}

close_window() {
  window_address "$1" || return 1
  hypr_dispatch "hl.dsp.window.close({ window = 'address:$1' })"
}

# The id goes into a Lua string, so only a real address is let through.
window_address() {
  [[ "$1" =~ ^0x[0-9a-f]+$ ]] && return
  echo "not a window: $1"
  return 1
}

# hyprctl prints "ok" on success and an error message otherwise, exiting 0 either way.
hypr_dispatch() {
  local output
  output=$(hyprctl dispatch "$1" 2>&1) || {
    echo "$output"
    return 1
  }
  [ "$output" = ok ] || [ -z "$output" ] || {
    echo "$output"
    return 1
  }
}
