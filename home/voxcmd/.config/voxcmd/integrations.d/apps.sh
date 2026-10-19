# shellcheck shell=bash disable=SC2034,SC2016
# Opens installed apps and focuses, moves, resizes or closes Hyprland windows. Format: ~/.config/voxcmd/README.md

name="Apps"
confirm=0
# The window that opens, takes focus or changes size is the feedback; moving and closing keep their toast.
silent_actions=(open open_new focus swap resize grow shrink resize_spoken_size)
# App names and window classes are short, so a fuzzy hit on scattered letters would run the wrong thing.
target_match=words
# "close the firefox window" is "close firefox"; a target of only these words ("close window", "open application")
# matches nothing and is left to the keybinds fallback. Kept in a global of its own too, for names_keybind():
# voxcmd's match_ignore_words is local to its loader and gone by the time candidates() runs.
ignored_words=(window app application program)
match_ignore_words=("${ignored_words[@]}")

# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=spoken-position.sh disable=SC2154
source "$voxcmd_share_dir/spoken-position.sh"

# Found beside this file; while it is installed, Firefox windows are not focused by the title of the tab they show.
firefox_integration="$(dirname "${BASH_SOURCE[0]}")/firefox.sh"

# Moving has no shared intent; its words are kept here for the keybind check in candidates() as well.
move_verbs="move|send|put|take|bring|shift|push|carry|relocate|place"
# "switch" moves only a window it is given ("switch firefox to workspace 5"); bare "switch to workspace 5" is a focus.
move_with_window_verbs="switch"
# The windows that mean the focused one, as in monitors.sh; moving the focused window offers nothing else.
focused_window_words='((this|the|that) )?((active|current|focused) )?window|it|this|that'

# move's target is "<window> to workspace <n>" and a resize's "<window> to 1200 by 800": one placeholder carries
# both, and candidates() splits it. A resize target that names no size ("resize left") offers nothing, which
# leaves it to the Resize submap's keybinds.
verbs=(
  "open_new  {open} (a )?new {target}"
  "open      {open} {target}"
  "swap      (swap( places)?|switch places) {target}"
  "focus     {focus} {target}"
  "move      (${move_verbs}) {target}"
  "move_with_window  (${move_with_window_verbs}) {target}"
  "close     {close} {target}"
  "resize    (resize|{set}) {target}"
  "grow      (grow|enlarge|increase|expand|extend|raise|add) {target}"
  "shrink    (shrink|decrease|reduce|lower) {target}"
  "resize_spoken_size  [0-9]+( [0-9]{3})?( (by|x) |x)[0-9]+( [0-9]{3})?( pixels?| px)?"
)

examples=(
  "open <app>"
  "open a new <app>"
  "focus <window>"
  "move <window> to workspace <number>"
  "move <window> to the third workspace"
  "move <window> to special workspace <name>"
  "move this window to workspace <number>"
  "send it to the third workspace"
  "put to special workspace <name>"
  "switch <window> to workspace <number>"
  "swap this window with <window>"
  "close <window>"
  "resize the window to <width> by <height>"
  "make it <number> pixels tall"
  "set the width to <number>"
  "make it wider by <number>"
  "increase the width by <number>"
  "decrease the height by <number>"
  "grow horizontally by <number>"
  "shrink it by <number> pixels"
  "resize <window> to <width> by <height>"
)

declare -A actions=(
  [open_new]='start_app "$id"'
  [open]='open_app "$id"'
  [focus]='focus_window "$id"'
  [move]='move_window "$id"'
  [move_with_window]='move_window "$id"'
  [swap]='swap_window "$id"'
  [close]='close_window "$id"'
  [resize]='resize_option "$id"'
  [grow]='resize_option "$id"'
  [shrink]='resize_option "$id"'
  [resize_spoken_size]='resize_active_to_spoken_size "$raw_transcript"'
)

# What a sequence's next step waits for. active_window_address and $active_before come from voxcmd. Starting an app
# returns at the fork, so opening waits until its window has focus (or, for an app whose window class is not its
# desktop id, until focus has moved off the window it started from); moving and resizing are done when they return.
declare -A step_waits=(
  [open]='app_window_focused "$id" || { [ -n "$(active_window_address)" ] && [ "$(active_window_address)" != "$active_before" ]; }'
  [open_new]='[ -n "$(active_window_address)" ] && [ "$(active_window_address)" != "$active_before" ]'
  [focus]='[ "$(active_window_address)" = "$id" ]'
  [close]='! window_exists "$id"'
)

# Only close labels read "<app> window: <title>", so only closing asks first.
confirm_labels=('^[^:]+ window(:|$)')

# Tab on these examples in Voice Help lists every installed app, and picking one opens it like "open <app>".
# Not candidates "open": its keybind checks would read the empty target as a phrase.
help_choices() {
  app_candidates | jq -c 'unique_by(.id) | sort_by(.label | ascii_downcase) | map({id, label, action: "open"})'
}

# Opening or going to "my calendar" or "the calendar" is left to calendar.sh, which opens Google Calendar; an installed
# Calendar app would otherwise turn "open my calendar" into a picker. "open calendar" still opens the app, and closing
# "the calendar" still closes its window, since calendar.sh has nothing to close.
candidates() {
  local action="$1" target="$2"
  case "$action" in
  resize | grow | shrink)
    resize_candidates "$action" "$target"
    return
    ;;
  esac
  case "$action" in
  move | move_with_window)
    # Before the keybind check below: "move window to workspace 5" names the "Move to Workspace 5" bind once the
    # ignored word is dropped, and that bind would swallow the focused-window move.
    if focused_move_candidates "$action" "$target"; then
      return
    fi
    ;;
  esac
  if spoken_as_keybind "$action" "$target" || names_session_or_agent "$target" || launches_keybind "$action" "$target" ||
    { [[ "$action" =~ ^(open|open_new|focus)$ ]] && [[ "$target" =~ ^(my|the)\ calendar$ ]]; } ||
    opens_in_browser "$action" "$target"; then
    echo '[]'
    return
  fi
  case "$action" in
  open | open_new) app_candidates ;;
  focus | close) window_candidates "$action" ;;
  move | move_with_window) move_candidates "$target" ;;
  swap) swap_candidates "$target" ;;
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

# The spoken verbs of an action, one per line, as its pattern above accepts them.
action_verbs() {
  case "$1" in
  open_new) intent_forms open | sed 's/$/ new/' ;;
  move) tr '|' '\n' <<<"$move_verbs" ;;
  move_with_window) tr '|' '\n' <<<"$move_with_window_verbs" ;;
  swap) echo swap ;;
  open | focus | close) intent_forms "$1" ;;
  esac
}

# True when "<verb> <target>" names a described keybind ("close browsers", "focus left", "go to workspace 2", "start
# menu"): those belong to the keybinds fallback, which only gets a turn when this integration offers nothing.
spoken_as_keybind() {
  local action="$1" target="$2" verb phrases=()
  while IFS= read -r verb; do phrases+=("$verb $target"); done < <(action_verbs "$action")
  names_keybind "${phrases[@]}"
}

# "switch to the X session", "go to the X agent": a session or agent integration owns those, and a window whose
# name X happens to match would otherwise share a picker with it, or take the phrase when X matches no session.
names_session_or_agent() {
  [[ " $1 " =~ \ (session|sessions|agent|agents)\  ]]
}

# "open example in firefox" opens a site, which firefox.sh does; the "firefox" in it is not this app.
opens_in_browser() {
  [[ "$1" == open && -f "$firefox_integration" && "$2" =~ \ (in|on|with)\ (firefox|the\ browser|a\ new\ tab|new\ tab)$ ]]
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
  clients=$(timeout 2 hyprctl clients -j 2>/dev/null) || return 0
  jq -r --argjson app "$1" '
    ($app.id | sub("\\.desktop$"; "")) as $id
    | ([$app.wm_class, $id, ($id | split(".") | last)] | map(select(. != "") | ascii_downcase)) as $classes
    | map(select(.mapped and ((.class, .initialClass) | ascii_downcase | IN($classes[]))))
    | sort_by(.focusHistoryID | if . < 0 then infinite else . end) | first | .address // empty' <<<"$clients"
}

# Whether the app's most recently focused window is the active one.
app_window_focused() {
  local entry address
  entry=$(desktop_entry "$1" 2>/dev/null) || return 1
  address=$(app_window "$entry")
  [ -n "$address" ] && [ "$address" = "$(active_window_address)" ]
}

# Bounded like voxcmd's active_window_address, since the close step's wait polls it.
window_exists() {
  timeout 2 hyprctl clients -j 2>/dev/null | jq -e --arg address "$1" 'any(.[]; .address == $address)' >/dev/null
}

# Started like the Quickshell apps picker starts them: the Exec line with its field codes dropped, in Path when set,
# and Terminal=true apps inside the Hyprland config's terminal wrapper. setsid keeps the app off voxcmd's output
# pipe, which would otherwise hold the notification until the app exits. setsid -f succeeds once it forks, so the
# directory and program are checked before detaching to report a stale entry.
start_entry() {
  local entry="$1" command directory terminal="" app_name
  command=$(jq -r .exec <<<"$entry" | sed -E 's/%[fFuUdDnNickvm]//g; s/%%/%/g')
  directory=$(jq -r .path <<<"$entry")
  app_name=$(jq -r .name <<<"$entry")
  if [ "$(jq -r .terminal <<<"$entry")" = true ]; then
    terminal="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/bin/term"
    [ -x "$terminal" ] || terminal="${TERMINAL:-kitty}"
  fi
  sh -c '
    [ -z "$1" ] || cd "$1" || exit
    if [ -n "$2" ]; then
      command -v "$2" || exit
      exec setsid -f "$2" -e sh -c "$3"
    fi
    eval "set -- $3"
    command -v "$1" || exit
    exec setsid -f "$@"' sh "$directory" "$terminal" "$command" </dev/null >/dev/null 2>&1 || {
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
        title: (if (.title | length) > 60 then .title[:57] + "..." else .title end),
        firefox: (.class | ascii_downcase | contains("firefox"))})' <<<"$clients" 2>/dev/null || echo '[]'
}

# A window matches by its app name ("focus firefox") and by its title ("focus tmux config"); several matching
# windows open the picker, where the label shows each title. A Firefox window's title is its selected tab's, and
# firefox.sh focuses any tab by its title, so with it installed "go to <tab>" is left to it: matching the window here
# too would offer the same tab twice, and only the one selected. "go to firefox" still focuses the window.
window_candidates() {
  local tabs_elsewhere=false
  [ "$1" != focus ] || [ ! -f "$firefox_integration" ] || tabs_elsewhere=true
  windows | jq -c --arg action "$1" --argjson tabs_elsewhere "$tabs_elsewhere" '
    def plain: ascii_downcase | [splits("[^a-z0-9]+") | select(. != "")] | join(" ");
    map((if $action == "close" then "\(.app) window" else .app end) as $app_part
      | (if .title == "" then $app_part else "\($app_part): \(.title)" end) as $label
      | {id: .address, label: $label, match_text: .app},
        (select(.title != "" and (.title | plain) != (.app | plain) and ($tabs_elsewhere and .firefox | not))
          | {id: .address, label: $label, match_text: .title}))'
}

# Splits a move target into move_window_part (the words before the destination, possibly none), move_workspace (a
# number, or "special:<name>"), move_label_to and move_workspace_words (the destination as spoken, with its leading
# space, which word matching reads after the window part). Fails when the target names no workspace.
split_move_target() {
  local spoken=" $1"
  if [[ "$spoken" =~ ^(.*)(\ to\ (the\ )?special\ workspace\ ([a-z0-9]+(\ [a-z0-9]+)*))$ ]]; then
    move_workspace="special:$(special_workspace_name "${BASH_REMATCH[4]}")"
    move_label_to="to special workspace ${move_workspace#special:}"
  elif [[ "$spoken" =~ ^(.*)(\ (to|onto|on)\ (the\ )?(workspace|desktop)\ ([a-z0-9]+(\ [a-z0-9]+)?))$ ]]; then
    move_workspace=$(workspace_number "${BASH_REMATCH[6]}")
    move_label_to="to workspace $move_workspace"
  else
    return 1
  fi
  move_window_part="${BASH_REMATCH[1]# }"
  move_workspace_words="${BASH_REMATCH[2]}"
  [ -n "$move_workspace" ]
}

# "move this window to workspace 5", "send it to the third workspace", "put to special workspace notes": no window
# or a deictic one means the focused window, offered alone with the whole target as its match_text so it is an exact
# match and runs without a picker. Never lists other windows for it. Prints the candidates and succeeds when the
# target is one of those moves; fails for a named window, which move_candidates() handles. With no focused window
# it offers nothing, which leaves the phrase to the keybinds fallback. "switch" moves only a window it is given, so
# its bare form ("switch to workspace 5") is left to the focus keybinds. "take me to workspace 5" is a focus.
focused_move_candidates() {
  local action="$1" target="$2" active label encoded
  local move_window_part move_workspace move_label_to move_workspace_words
  split_move_target "$target" || return 1
  if [[ "$move_window_part" =~ ^(me|us)$ ]]; then
    echo '[]'
    return 0
  fi
  if [ -n "$move_window_part" ] && ! [[ "$move_window_part" =~ ^($focused_window_words)$ ]]; then
    return 1
  fi
  if [ -z "$move_window_part" ] && [ "$action" = move_with_window ]; then
    echo '[]'
    return 0
  fi
  active=$(timeout 2 hyprctl activewindow -j 2>/dev/null | jq -c 'select(.address // "" != "") | {address, class, title}')
  if [ -z "$active" ]; then
    echo '[]'
    return 0
  fi
  if [[ "$move_workspace" =~ ^[0-9]+$ ]] && move_bind_candidate "$move_workspace" "$target"; then
    return 0
  fi
  encoded="${move_workspace//%/%25}"
  encoded="${encoded// /%20}"
  jq -c --arg workspace "$encoded" --arg label_to "$move_label_to" --arg match_text "$target" '
    [{id: "\(.address) \($workspace)",
      label: (if .title == "" then "\(.class) \($label_to)" else "\(.class): \(.title) \($label_to)" end),
      match_text: $match_text}]' <<<"$active"
}

# The "Move to Workspace <n>" keybind as the one candidate, when the binds cover n. The Lua config owns what moving to
# workspace n means (the n-th workspace of the current monitor with persistent workspaces, and whether focus follows),
# so the focused window is moved by running that bind, not by an absolute workspace id. Fails when no such bind exists
# (a number above the bind range), which leaves the move to move_window()'s absolute id.
move_bind_candidate() {
  local number="$1" target="$2"
  timeout 2 hyprctl binds -j 2>/dev/null | jq -ce --arg description "Move to Workspace $number" --arg match_text "$target" '
    [.[] | select(.has_description and .dispatcher == "__lua" and (.mouse | not)
        and (.description | ascii_downcase) == ($description | ascii_downcase))]
    | sort_by(.submap != "") | first | select(. != null)
    | [{id: "bind:\(.arg)", label: .description, match_text: $match_text}]'
}

# For "move firefox to workspace 3" every window is offered as "<app> to workspace 3" (and by title), so word
# matching compares the window part while the workspace rides along in the id as "<address> <workspace>". A target
# without the workspace part offers nothing. "to special workspace <name>" works the same, with the special workspace
# that special_workspace_name() resolves the spoken name to. An existing special workspace's name may hold spaces, so
# the workspace travels percent-encoded, as the overview's references do.
move_candidates() {
  local move_window_part move_workspace move_label_to move_workspace_words
  split_move_target "$1" && [ -n "$move_window_part" ] || {
    echo '[]'
    return
  }
  local workspace_words="$move_workspace_words" workspace="$move_workspace" label_to="$move_label_to"
  windows | jq -c --arg suffix "$workspace_words" --arg workspace "$workspace" --arg label_to "$label_to" '
    def plain: ascii_downcase | [splits("[^a-z0-9]+") | select(. != "")] | join(" ");
    ($workspace | gsub("%"; "%25") | gsub(" "; "%20")) as $workspace
    | map("\(.app): \(.title) \($label_to)" as $label
      | {id: "\(.address) \($workspace)", label: $label, match_text: (.app + $suffix)},
        (select(.title != "" and (.title | plain) != (.app | plain))
          | {id: "\(.address) \($workspace)", label: $label, match_text: (.title + $suffix)}))'
}

# Prints the name of the special workspace the spoken words mean, without its "special:" prefix. An existing special
# workspace wins when its name, spaces and hyphens dropped and in any case, is the words with spaces dropped ("scratch
# pad" is scratchpad, Scratchpad or "scratch pad"); otherwise the words are joined with hyphens.
special_workspace_name() {
  local spoken="${1,,}" existing
  existing=$(timeout 2 hyprctl workspaces -j 2>/dev/null | jq -r --arg squashed "${spoken// /}" '
    first(.[] | .name | select(startswith("special:")) | ltrimstr("special:") | select(gsub("[- ]"; "") | ascii_downcase == $squashed))')
  echo "${existing:-${spoken// /-}}"
}

# "swap this window with firefox": the focused window is always one side, so only "with <window>" is offered, and
# every window but the focused one. The words before "with" stay in match_text so word matching sees the same text
# as the target. A pair of named windows ("swap firefox and slack") and the overview's "swap workspaces ..." have no
# leading "with" and offer nothing. The id is "<target> <focused>": the window focused now is the source even if a
# picker or a spoken reply lets focus move before the swap runs.
swap_candidates() {
  local target="$1" prefix active_address
  [[ "$target" =~ ^((this\ |the\ |that\ )?(window|it)\ )?with\ .+$ ]] || {
    echo '[]'
    return
  }
  prefix="${BASH_REMATCH[1]}with "
  active_address=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')
  [ -n "$active_address" ] || {
    echo '[]'
    return
  }
  windows | jq -c --arg active "$active_address" --arg prefix "$prefix" '
    def plain: ascii_downcase | [splits("[^a-z0-9]+") | select(. != "")] | join(" ");
    map(select(.address != $active)
      | "swap with \(.app): \(.title)" as $label
      | {id: "\(.address) \($active)", label: $label, match_text: ($prefix + .app)},
        (select(.title != "" and (.title | plain) != (.app | plain))
          | {id: "\(.address) \($active)", label: $label, match_text: ($prefix + .title)}))'
}

# Prints the workspace the words name ("3", "three", "twenty five", "third"), or nothing for a number below 1.
workspace_number() {
  local number
  number=$(spoken_position "$1") && [ "$number" -ge 1 ] && echo "$number"
  return 0
}

focus_window() {
  window_address "$1" || return 1
  hypr_dispatch "hl.dsp.focus({ window = 'address:$1' })"
}

# A named window stays put on the current workspace's side: moving a window out of the way should not drag focus along.
move_window() {
  if [[ "$1" == bind:* ]]; then
    local bind_id="${1#bind:}" output
    [[ "$bind_id" =~ ^[0-9]+$ ]] || {
      echo "not a keybind: $bind_id"
      return 1
    }
    output=$(hyprctl eval "debug.getregistry()[$bind_id]()") || {
      echo "$output"
      return 1
    }
    return
  fi
  local address="${1%% *}" workspace="${1#* }" lua_workspace
  window_address "$address" || return 1
  workspace="${workspace//%20/ }"
  workspace="${workspace//%25/%}"
  # Quotes and backslashes would end the Lua string.
  if [[ "$workspace" =~ ^special:[^\'\\]+$ ]]; then
    lua_workspace="'$workspace'"
  elif [[ "$workspace" =~ ^[0-9]+$ ]]; then
    lua_workspace="$workspace"
  else
    echo "not a workspace: $workspace"
    return 1
  fi
  hypr_dispatch "hl.dsp.window.move({ window = 'address:$address', workspace = $lua_workspace, follow = false })"
}

# Hyprland does swap across workspaces and with a floating window, but then leaves focus on a window that is no
# longer on the shown workspace and swaps floating geometry into tiled slots; refused instead.
swap_window() {
  local address="${1% *}" active_address="${1#* }" pair
  window_address "$address" || return 1
  pair=$(hyprctl clients -j 2>/dev/null | jq -r --arg a "$active_address" --arg b "$address" '
    [.[] | select(.address == $a or .address == $b)] as $both
    | if ($both | length) != 2 then "missing"
      elif any($both[]; .floating) then "floating"
      elif $both[0].workspace.id != $both[1].workspace.id then "workspace"
      else "ok" end')
  case "$pair" in
  ok)
    hypr_dispatch "hl.dsp.window.swap({ window = 'address:$active_address', target = 'address:$address' })"
    return
    ;;
  floating) echo "cannot swap with a floating window" ;;
  workspace) echo "cannot swap with a window on another workspace" ;;
  *) echo "that window is gone" ;;
  esac
  return 1
}

close_window() {
  window_address "$1" || return 1
  hypr_dispatch "hl.dsp.window.close({ window = 'address:$1' })"
}

# ---- Resizing --------------------------------------------------------------------------------------------------

# Sizes are logical pixels, the ones hyprctl reports and the resize dispatcher takes, so on a monitor scaled 1.6 a
# window "400 high" covers 640 device pixels.

# No size goes below this or past the window's monitor: a window resized to 1x1 or far wider than any screen can
# crash its app (kitty does), and none of it could be seen anyway.
min_window_size=100

# Words that point at the active window rather than name one: "make it 400 tall", "resize the window to ...".
active_window_words="the|a|this|that|current|active|focused|selected|window|windows|it|its|my"

# Splits text into size_words, one word each, with "400px" read as "400 px" and "1200x800" as "1200 x 800".
split_size_words() {
  local word
  size_words=()
  for word in $1; do
    if [[ "$word" =~ ^([0-9]+)(px)$ || "$word" =~ ^([0-9]+)(x)([0-9]+)$ ]]; then
      size_words+=("${BASH_REMATCH[@]:1}")
    else
      size_words+=("$word")
    fi
  done
}

# Advances size_at past the word there when it is one of the alternatives in $1, an ERE alternation.
skip_size_word() {
  [[ "${size_words[size_at]-}" =~ ^($1)$ ]] && size_at=$((size_at + 1))
  return 0
}

# Reads an amount at size_words[size_at] into pixels, with an optional "pixels" after it. Amounts come as digits,
# and normalizing turned "1,200" into "1 200", which reads as 1200.
read_pixels() {
  local word="${size_words[size_at]-}" next="${size_words[size_at + 1]-}"
  [[ "$word" =~ ^[0-9]+$ ]] || return 1
  pixels=$((10#$word))
  size_at=$((size_at + 1))
  if [[ "$word" =~ ^[0-9]{1,3}$ && "$next" =~ ^[0-9]{3}$ ]]; then
    pixels=$((pixels * 1000 + 10#$next))
    size_at=$((size_at + 1))
  fi
  skip_size_word 'pixels?|px'
}

# "to 1200 by 800", "800 wide", "400 pixels high"; a dimension left unnamed is "-", keeping the window's own.
read_exact_size() {
  skip_size_word 'to|at|of'
  read_pixels || return 1
  local first="$pixels" word="${size_words[size_at]-}"
  size_at=$((size_at + 1))
  case "$word" in
  by | x | times)
    read_pixels || return 1
    size_width="$first" size_height="$pixels"
    ;;
  high | tall) size_width=- size_height="$first" ;;
  wide) size_width="$first" size_height=- ;;
  *) return 1 ;;
  esac
  size_kind=exact
}

# "height to 400", "width of 800", "size to 1200 by 800".
read_named_dimension() {
  local dimension="${size_words[size_at]-}"
  size_at=$((size_at + 1))
  skip_size_word 'is'
  skip_size_word 'to|at|of'
  case "$dimension" in
  height | width)
    read_pixels || return 1
    if [ "$dimension" = height ]; then size_width=- size_height="$pixels"; else size_width="$pixels" size_height=-; fi
    ;;
  size | dimensions)
    read_pixels || return 1
    local first="$pixels"
    [[ "${size_words[size_at]-}" =~ ^(by|x|times)$ ]] || return 1
    size_at=$((size_at + 1))
    read_pixels || return 1
    size_width="$first" size_height="$pixels"
    ;;
  *) return 1 ;;
  esac
  size_kind=exact
}

# Sets change_width and change_height to the sign a word gives each dimension ("narrower" is -1 0), and advances
# past it. A comparative carries its direction; a dimension named without one ("width", "in height", "vertically")
# grows unless a word after it says otherwise ("horizontally decreased"), and grow and shrink override both.
read_change_word() {
  local word="${size_words[size_at]-}" next="${size_words[size_at + 1]-}"
  size_at=$((size_at + 1))
  case "$word" in
  taller | higher) change_width=0 change_height=1 ;;
  shorter) change_width=0 change_height=-1 ;;
  wider | broader) change_width=1 change_height=0 ;;
  narrower | thinner) change_width=-1 change_height=0 ;;
  bigger | larger) change_width=1 change_height=1 ;;
  smaller) change_width=-1 change_height=-1 ;;
  height | vertically) change_width=0 change_height=1 ;;
  width | horizontally) change_width=1 change_height=0 ;;
  in)
    size_at=$((size_at + 1))
    case "$next" in
    height) change_width=0 change_height=1 ;;
    width) change_width=1 change_height=0 ;;
    *) return 1 ;;
    esac
    ;;
  *) return 1 ;;
  esac
  case "${size_words[size_at]-}" in
  increase | increased | grow | grown | more)
    size_at=$((size_at + 1))
    change_width="${change_width#-}" change_height="${change_height#-}"
    ;;
  decrease | decreased | reduce | reduced | shrink | shrunk | less)
    size_at=$((size_at + 1))
    change_width=$((-${change_width#-})) change_height=$((-${change_height#-}))
    ;;
  esac
}

# "200 more pixels wide": with "more", "wide", "tall" and "high" name a change rather than an exact size.
read_more_word() {
  case "${size_words[size_at]-}" in
  wide) change_width=1 change_height=0 ;;
  tall | high) change_width=0 change_height=1 ;;
  *) return 1 ;;
  esac
  size_at=$((size_at + 1))
}

# "taller by 100", "width by 400", "horizontally by 300", "100 pixels wider", "200 more pixels wide", "200 to the
# width", and after grow or shrink also "by 50" alone, which changes both dimensions. Grow and shrink set the
# direction themselves, so "shrink it 100 narrower" and "shrink it 100 wider" agree.
read_size_change() {
  local verb="$1" amount start="$size_at"
  change_width="" change_height=""
  if read_change_word; then
    [ "${size_words[size_at]-}" = by ] || return 1
    size_at=$((size_at + 1))
    read_pixels || return 1
  else
    size_at="$start"
    local said_by=0
    [ "${size_words[size_at]-}" = by ] && said_by=1 && size_at=$((size_at + 1))
    read_pixels || return 1
    if [ "${size_words[size_at]-}" = more ]; then
      size_at=$((size_at + 1))
      skip_size_word 'pixels?|px'
      read_more_word || read_change_word || return 1
    elif [ "${size_words[size_at]-}" = to ]; then
      size_at=$((size_at + 1))
      skip_size_word 'the|its'
      [[ "${size_words[size_at]-}" =~ ^(width|height)$ ]] || return 1
      read_change_word || return 1
    elif [ "$size_at" -lt "${#size_words[@]}" ]; then
      read_change_word || return 1
    elif [ "$verb" = resize ]; then
      return 1
    elif [ "$said_by" = 1 ] || [[ "${size_words[size_at - 1]}" =~ ^(pixels?|px)$ ]]; then
      # A bare number needs its "by" or "pixels": "add slack to workspace 2" is no resize by 2.
      change_width=1 change_height=1
    else
      return 1
    fi
  fi
  amount="$pixels"
  case "$verb" in
  grow) change_width="${change_width#-}" change_height="${change_height#-}" ;;
  shrink) change_width=$((-${change_width#-})) change_height=$((-${change_height#-})) ;;
  esac
  size_kind=delta size_width=$((change_width * amount)) size_height=$((change_height * amount))
}

# True when size_words from size_at to the end are a size the verb ("resize", "grow" or "shrink") can take. After
# grow or shrink an exact size needs its "to" ("increase the height to 600", "shrink it to 800 wide"), since "grow it
# 200 wide" means by 200.
read_size() {
  local verb="$1" start="$size_at"
  size_kind="" size_width="" size_height=""
  if [ "$verb" = resize ] || [ "${size_words[size_at]-}" = to ]; then
    { read_exact_size && [ "$size_at" = "${#size_words[@]}" ]; } && return
    size_at="$start"
  fi
  { read_named_dimension && [ "$size_at" = "${#size_words[@]}" ]; } && return
  size_at="$start"
  read_size_change "$verb" && [ "$size_at" = "${#size_words[@]}" ]
}

# Splits a spoken resize target into the window it names (size_window, empty for the active window) and the size
# after it, read into size_kind, size_width and size_height. The size starts at the earliest word it can, so the
# "to" in "firefox to 1200 by 800" goes with the size.
parse_resize_target() {
  local verb="$1" target="$2" start
  split_size_words "$target"
  for ((start = 0; start < ${#size_words[@]}; start++)); do
    size_at="$start"
    read_size "$verb" || continue
    size_window="${size_words[*]:0:start}"
    [[ " $size_window " =~ ^(\ ($active_window_words))*\ $ ]] && size_window=""
    return 0
  done
  return 1
}

# "resize horizontally and increase", "make it bigger": a resize of the active window that says which way but not how
# much, answered with a hint rather than a silent "no match". Every word must be one a resize uses, so "lower the
# volume", "make the font bigger" and "resize left" (a keybind) are left alone.
names_size_without_amount() {
  local word names_dimension=1
  for word in $1; do
    [[ "$word" =~ ^(width|height|size|horizontally|vertically|taller|shorter|higher|wider|narrower|broader|thinner|bigger|larger|smaller)$ ]] && names_dimension=0 && continue
    [[ "$word" =~ ^($active_window_words|and|by|in|to|pixels?|px|more|less|increase|increased|decrease|decreased)$ ]] || return 1
  done
  return "$names_dimension"
}

# The size part of a resize option's id, "<kind> <width> <height>", which resize_window() reads back.
size_id() {
  printf '%s %s %s' "$size_kind" "$size_width" "$size_height"
}

# How a resize option's label states the size: "to 1200x800", "100 taller".
size_description() {
  if [ "$size_kind" = exact ]; then
    if [ "$size_width" = - ]; then
      echo "to $size_height high"
    elif [ "$size_height" = - ]; then
      echo "to $size_width wide"
    else
      echo "to ${size_width}x$size_height"
    fi
    return
  fi
  local width="${size_width#-}" height="${size_height#-}"
  if [ "$width" != 0 ] && [ "$height" != 0 ]; then
    [ "$size_width" -gt 0 ] && echo "$width bigger" || echo "$width smaller"
  elif [ "$width" != 0 ]; then
    [ "$size_width" -gt 0 ] && echo "$width wider" || echo "$width narrower"
  else
    [ "$size_height" -gt 0 ] && echo "$height taller" || echo "$height shorter"
  fi
}

# A size spoken without a window ("make it 400 tall") is the active window's: one candidate, matched by the
# target itself. A named one ("resize firefox to 1200 by 800") offers every window as "<app> <size words>", so
# word matching compares the window part while the size rides along in the id, as move_candidates() does.
resize_candidates() {
  local verb="$1" target="$2" size description spoken_size active_address
  if ! parse_resize_target "$verb" "$target"; then
    if names_size_without_amount "$target"; then
      jq -n -c --arg target "$target" '[{id: "how-much", label: "how much?", match_text: $target}]'
    else
      echo '[]'
    fi
    return
  fi
  size=$(size_id)
  description=$(size_description)
  if [ -z "$size_window" ]; then
    active_address=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')
    windows | jq -c --arg address "$active_address" --arg size "$size" --arg description "$description" --arg target "$target" '
      map(select(.address == $address) | {id: "\(.address) \($size)", label: "\(.app): \(.title) \($description)", match_text: $target})'
    return
  fi
  # The window words are the target's first words, which split_size_words leaves alone, so what follows them is
  # the size as spoken. A window named by no word at all (a title of "~") is left out: its match text would be the
  # size alone, which any spoken name plus the size holds.
  spoken_size="${target#"$size_window "}"
  windows | jq -c --arg size "$size" --arg description "$description" --arg suffix " $spoken_size" '
    def plain: ascii_downcase | [splits("[^a-z0-9]+") | select(. != "")] | join(" ");
    map("\(.app): \(.title) \($description)" as $label
      | (select((.app | plain) != "") | {id: "\(.address) \($size)", label: $label, match_text: (.app + $suffix)}),
        (select((.title | plain) != "" and (.title | plain) != (.app | plain))
          | {id: "\(.address) \($size)", label: $label, match_text: (.title + $suffix)}))'
}

# "1200 by 800" said alone resizes the active window. The verb has no target to carry the size, so it is read from
# the transcript.
resize_active_to_spoken_size() {
  local spoken address
  spoken=$(tr '[:upper:]' '[:lower:]' <<<"$1" | tr -c 'a-z0-9\n' ' ')
  split_size_words "$spoken"
  size_at=0
  if ! read_size resize || [ "$size_kind" != exact ]; then
    echo "not a size: $1"
    return 1
  fi
  address=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')
  [ -n "$address" ] || {
    echo "no active window"
    return 1
  }
  resize_window "$address $(size_id)"
}

# Runs a resize option: a size, or the "how-much" hint names_size_without_amount() offers.
resize_option() {
  if [ "$1" = how-much ]; then
    notify-send --transient --app-name=voxcmd "Say how much, e.g. \"increase width by 200\""
    return 0
  fi
  resize_window "$1"
}

# Prints "<width> <height> <floating> <monitor width> <monitor height>" for a window, the monitor's size in
# logical pixels like the window's.
window_geometry() {
  {
    hyprctl clients -j 2>/dev/null
    hyprctl monitors -j 2>/dev/null
  } | jq -r -s --arg address "$1" '
    .[1] as $monitors
    | first(.[0][] | select(.address == $address)) as $window
    | first($monitors[] | select(.id == $window.monitor)) as $monitor
    | ([$monitor.width, $monitor.height] | map(. / $monitor.scale | floor)) as $logical
    | (if $monitor.transform % 2 == 1 then $logical | reverse else $logical end) as $monitor_size
    | "\($window.size[0]) \($window.size[1]) \($window.floating) \($monitor_size[0]) \($monitor_size[1])"
  ' 2>/dev/null
}

window_size() {
  hyprctl clients -j 2>/dev/null | jq -r --arg address "$1" 'first(.[] | select(.address == $address)) | "\(.size[0]) \(.size[1])"'
}

clamp_size() {
  local size="$1" most="$2"
  [ "$size" -lt "$min_window_size" ] && size="$min_window_size"
  [ "$size" -gt "$most" ] && size="$most"
  echo "$size"
}

# Resizes to the id's size, "<address> exact <width> <height>" (a "-" keeps that dimension) or "<address> delta
# <dx> <dy>". A tiled window's size is the layout's: the resize moves its split, and a dimension with no split along
# it, or none left to give, does not change. That is reported rather than floating the window to force it, and as
# information, since the layout limiting a size is no failure; only a missing window, a bad size or a dispatch error
# fails. Success sends nothing.
resize_window() {
  local address kind width height
  read -r address kind width height <<<"$1"
  window_address "$address" || return 1
  [[ "$kind" =~ ^(exact|delta)$ && "$width" =~ ^(-|-?[0-9]+)$ && "$height" =~ ^(-|-?[0-9]+)$ ]] || {
    echo "not a size: ${1#* }"
    return 1
  }
  local geometry start_width start_height floating monitor_width monitor_height
  geometry=$(window_geometry "$address")
  [ -n "$geometry" ] || {
    echo "no window $address"
    return 1
  }
  read -r start_width start_height floating monitor_width monitor_height <<<"$geometry"

  local asked_width="$start_width" asked_height="$start_height"
  if [ "$kind" = exact ]; then
    [ "$width" = - ] || asked_width="$width"
    [ "$height" = - ] || asked_height="$height"
  else
    asked_width=$((start_width + width)) asked_height=$((start_height + height))
  fi
  local target_width="$start_width" target_height="$start_height"
  [ "$asked_width" = "$start_width" ] || target_width=$(clamp_size "$asked_width" "$monitor_width")
  [ "$asked_height" = "$start_height" ] || target_height=$(clamp_size "$asked_height" "$monitor_height")

  resize_axis "$address" x $((target_width - start_width)) || return 1
  resize_axis "$address" y $((target_height - start_height)) || return 1

  local final_width final_height limit notes=()
  read -r final_width final_height <<<"$(window_size "$address")"
  [ "$floating" = true ] && limit="the monitor or the app limits it" || limit="the tiled layout limits it"
  [ "$asked_width" = "$start_width" ] || size_note width "$start_width" "$final_width" "$asked_width"
  [ "$asked_height" = "$start_height" ] || size_note height "$start_height" "$final_height" "$asked_height"
  [ "${#notes[@]}" = 0 ] && return 0
  local app message
  app=$(window_app "$address")
  message="${app:-The window}: $(printf '%s, ' "${notes[@]}")"
  # Silent on success and not a failure either, so the action says it by itself, as recording.sh does.
  notify-send --transient --app-name=voxcmd "${message%, } ($limit)"
}

# Adds to resize_window's notes when a dimension did not end where it was asked: "height stayed 686".
size_note() {
  local dimension="$1" start="$2" final="$3" asked="$4"
  if [ "$final" = "$start" ]; then
    notes+=("$dimension stayed $final")
  elif [ "$(abs $((final - asked)))" -gt 1 ]; then
    notes+=("$dimension is $final, not $asked")
  fi
}

# Changes one dimension ("x" or "y") of a window by delta pixels, as far as it goes. A tiled window's resize moves
# the edge it shares with its split, so one on the right or bottom of a split shrinks on a positive delta, an exact
# size included. Whether this edge is such one shows only in the result: a resize that went the wrong way is undone
# and sent the other way, and one that did nothing (the wrong way was blocked, say at the layout's minimum) is tried
# the other way too, then undone if that went the wrong way as well.
resize_axis() {
  local address="$1" axis="$2" delta="$3" before after change remaining
  [ "$delta" = 0 ] && return 0
  before=$(window_dimension "$address" "$axis")
  resize_by "$address" "$axis" "$delta" || return 1
  after=$(window_dimension "$address" "$axis")
  change=$((after - before))
  if [ "$change" = 0 ]; then
    resize_by "$address" "$axis" $((-delta)) || return 1
    change=$(($(window_dimension "$address" "$axis") - before))
    # Sending -delta moved it by -delta's sign: an edge that resizes as asked, and the way wanted was blocked.
    if [ "$change" != 0 ] && [ "$((change > 0))" = "$((-delta > 0))" ]; then
      resize_by "$address" "$axis" $((-change)) || return 1
    fi
  elif [ "$((change > 0))" != "$((delta > 0))" ]; then
    # This edge resizes inverted, so sending -n changes the size by n.
    remaining=$((delta - change))
    resize_by "$address" "$axis" $((-remaining)) || return 1
  fi
}

resize_by() {
  local address="$1" axis="$2" pixels="$3" dx=0 dy=0
  [ "$axis" = x ] && dx="$pixels" || dy="$pixels"
  hypr_dispatch "hl.dsp.window.resize({ window = 'address:$address', x = $dx, y = $dy, relative = true })"
}

window_dimension() {
  local width height
  read -r width height <<<"$(window_size "$1")"
  [ "$2" = x ] && echo "$width" || echo "$height"
}

# The window's app name as the picker shows it.
window_app() {
  windows | jq -r --arg address "$1" 'first(.[] | select(.address == $address) | .app) // empty'
}

abs() {
  echo "${1#-}"
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
