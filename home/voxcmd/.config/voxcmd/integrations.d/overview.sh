# shellcheck shell=bash disable=SC2034,SC2016,SC2154
# Drives the Quickshell workspace overview by voice: "show workspaces" opens it, then windows are named by the numbers it
# draws on them. "two and four" marks, "move two to workspace three" moves, "close the marked windows" closes (after a count).
# The overview publishes what it shows in overview.json and takes every action through `qs-ipc call overview act`; the
# contract is in the README (Overview) and the Quickshell README.
# Format: ~/.config/voxcmd/README.md

name="Overview"
confirm=0
# Every action is visible on the overview itself; only a failure shows a toast.
silent=1
# A candidate's label says what runs ("close 3 windows"), which is also the confirm question.
action_labels=0
# The text a session turn is rewritten to, so Apps' "close {target}" and Keybinds' "go to workspace N" never hear it.
force_prefixes=(overview)
confirm_labels=('^close ')

# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=spoken-position.sh
source "$voxcmd_share_dir/spoken-position.sh"
# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=mode-phrases.sh
source "$voxcmd_share_dir/mode-phrases.sh"
# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=monitor-words.sh
source "$voxcmd_share_dir/monitor-words.sh"

overview_object='(the )?(workspace )?(overview|workspaces)'
overview_leave_phrase=$(mode_exit_phrase "$overview_object")
session_exit_phrases="(close|hide|dismiss) $overview_object|done with $overview_object|$overview_leave_phrase"
session_exit_hint="say done to close the overview"
# A longer pause than other modes: the numbers on screen are read before a command is spoken.
session_listen_no_speech_secs=20

# The ways in and out come first: the last verb takes any other phrase and keeps it only when candidates() can read it.
verbs=(
  "overview_close ((close|hide|dismiss|exit) $overview_object)"
  "overview_open  (({show}|{open}) $overview_object|workspace overview)"
  "overview_numbers ((show|display|turn on) (the )?(window )?numbers|number (the )?windows)"
  "act            {target}"
)

examples=(
  "show workspaces"
  "two and four"
  "mark one, three and five"
  "unmark two"
  "clear"
  "move two to workspace three"
  "move two and four to the left monitor"
  "move the marked windows to workspace 5"
  "move to workspace 7"
  "close them"
  "close two"
  "close the marked windows"
  "focus two"
  "focus the second window"
  "close the third one"
  "mark first and third"
  "go to workspace three"
  "go to the first workspace"
  "move workspace three to the right monitor"
  "swap workspaces two and five"
  "close overview"
)

declare -A actions=(
  [overview_open]='overview_open'
  [overview_close]='overview_close'
  [overview_numbers]='overview_numbers'
  [act]='overview_act "$id"'
)

overview_file="${XDG_RUNTIME_DIR:-/tmp}/voxcmd/overview.json"
qs_ipc="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/qs-ipc"

# Whether the overview is on screen: it says so in its file, and the bar confirms (a bar that died leaves the file behind).
# Without a bar to ask, the file is believed.
overview_is_open() {
  grep -q '"open":true' "$overview_file" 2>/dev/null || return 1
  [ ! -x "$qs_ipc" ] || [ "$(timeout 2 "$qs_ipc" call overview state 2>/dev/null)" = open ]
}

# voxcmd asks every integration with a surface_open whether its surface is up, before any verb is matched, and gives the
# phrase to that integration first. session_alive ends a mode whose surface closed.
surface_open() { overview_is_open; }

# The bar's own answer decides while it gives one: its file is rewritten a moment after the overview opens, so right after
# "open overview" it still says closed. The file is believed only when the bar cannot be asked.
session_alive() {
  local answer=""
  [ ! -x "$qs_ipc" ] || answer=$(timeout 2 "$qs_ipc" call overview state 2>/dev/null) || answer=""
  case "$answer" in
  open) return 0 ;;
  closed) return 1 ;;
  *) grep -q '"open":true' "$overview_file" 2>/dev/null ;;
  esac
}

# A turn of the session is a phrase for the overview alone.
session_rewrite() {
  printf 'overview %s' "$1"
}

# Closing the overview by voice ("done", "close overview") is how the session ends; any other end leaves it open.
session_ended() {
  [ "${1:-}" != done ] || "$qs_ipc" call overview close >/dev/null 2>&1 || true
}

overview_attach() {
  session_begin overview "$file" "Overview"
}

# "Show numbers" means something only while the overview is up; closed, the phrase is left unmatched.
overview_numbers() {
  overview_is_open || return 0
  overview_attach
}

overview_open() {
  [ "$("$qs_ipc" call overview open 2>&1)" = ok ] || {
    echo "the bar did not open the overview"
    return 1
  }
  overview_wait_for_snapshot
  overview_attach
}

# Gives the bar a moment to write the snapshot the numbers and later phrases are read from; the session does not depend on it.
overview_wait_for_snapshot() {
  local polls
  for ((polls = 0; polls < 20; polls++)); do
    grep -q '"open":true' "$overview_file" 2>/dev/null && return 0
    sleep "$(scaled_secs 0.05)"
  done
}

overview_close() {
  "$qs_ipc" call overview close >/dev/null 2>&1 || true
  session_leave overview 'the overview closed' 2>/dev/null || true
}

# $1 is a candidate's id: "<verb> <arguments>" for the overview's act, or "error:<why>" for a phrase that named something
# the overview does not show. A verb that closes the overview ends the mode with it.
overview_act() {
  local verb args result
  case "$1" in
  error:*)
    echo "${1#error:}"
    return 1
    ;;
  esac
  read -r verb args <<<"$1"
  result=$("$qs_ipc" call overview act "$verb" "$args" 2>&1) || true
  if [ "$result" != ok ]; then
    echo "${result#error: }"
    return 1
  fi
  case "$verb" in
  focus | workspace) session_leave overview 'the overview closed' 2>/dev/null || true ;;
  *) overview_attach ;;
  esac
}

# ---- reading the phrase ----------------------------------------------------------------------------------------------

# Prints the position the words name (digits, a number word, an ordinal: "7", "seven", "twenty five", "seventh"), or fails.
overview_number() { spoken_position "$1"; }

# Prints the numbers of a list like "two and four" or "one third and fifth", one per line; fails on any other word. A tens
# word followed by a ones or ordinal word is one number ("twenty five", "twenty first").
overview_number_list() {
  local -a words
  local index=0 word value
  read -ra words <<<"$1"
  [ "${#words[@]}" -gt 0 ] || return 1
  while [ "$index" -lt "${#words[@]}" ]; do
    word="${words[index]}"
    index=$((index + 1))
    [ "$word" != and ] || continue
    if [ "$index" -lt "${#words[@]}" ] && value=$(spoken_position "$word ${words[index]}"); then
      index=$((index + 1))
    else
      value=$(spoken_position "$word") || return 1
    fi
    echo "$value"
  done
}

# Prints the address of window number $1, or fails.
overview_window_id() {
  local id
  id=$(jq -r --argjson n "$1" 'first(.items[] | select(.kind == "window" and .n == $n) | .id) // empty' "$overview_file" 2>/dev/null)
  [ -n "$id" ] && echo "$id"
}

# Prints the reference of workspace number $1 ("3", or "sp:<name>" in special mode), or fails. A number the overview does
# not list is still a workspace to move to (Hyprland makes it) while regular workspaces are shown. Spaces and percent signs
# are percent-encoded because act splits its arguments on spaces; the overview decodes them.
overview_workspace_ref() {
  local id
  id=$(jq -r --argjson n "$1" 'first(.items[] | select(.kind == "workspace" and .n == $n) | .id) // (if .special then empty else ($n | tostring) end)' "$overview_file" 2>/dev/null)
  [ -n "$id" ] || return 1
  id="${id//%/%25}"
  echo "${id// /%20}"
}

# Prints the name of the monitor the words ("left", "top right", "monitor two", "laptop") name, or an "error:" line. The
# words are read against the monitors the overview published, by the rule voxcmd shares with its own monitor phrases.
overview_monitor() {
  monitor_named "$1" "$(jq -c '.monitors // []' "$overview_file")"
}

# Prints the addresses a window reference names, one per line: numbers ("two and four", "window three") or the marked
# windows ("the marked windows"), which print nothing and succeed so the overview uses its marks. Fails with an
# "error:" line for a number the overview does not show.
overview_windows() {
  local text="$1" numbers number address
  text="${text#the }"
  if [[ "$text" =~ ^(marked|selected|checked|ticked)( windows| ones| window| items)?$ || "$text" =~ ^(them|these|those|it|this|that)$ ]]; then
    echo "marked"
    return 0
  fi
  text="${text#window }" text="${text#windows }" text="${text#number }" text="${text#numbers }"
  # "the second window", "the third one"; after a cardinal "one" is a number ("twenty one").
  text="${text% windows}" text="${text% window}"
  if [[ "$text" =~ ^(.*\ )?([a-z0-9]+)\ ones?$ ]] && spoken_ordinal "${BASH_REMATCH[2]}" >/dev/null; then
    text="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  fi
  numbers=$(overview_number_list "$text") || return 1
  while IFS= read -r number; do
    address=$(overview_window_id "$number") || {
      echo "error:no window $number"
      return 0
    }
    echo "$address"
  done <<<"$numbers"
}

# Prints the verb and its arguments for a phrase as one line, "error:<why>" for a phrase that is overview talk about
# something not shown, and nothing for a phrase that is not for the overview.
overview_parse() {
  local text="$1" rest ref ws ws2 addresses monitor
  text="${text#please }"
  text="${text% please}"
  # Whisper's habits: "work space 7", "workspace number 7".
  text="${text//work space/workspace}"
  text="${text//workspace number /workspace }"
  text="${text//desktop number /desktop }"
  # "swap the second and fifth workspaces" names the noun once, after the pair.
  if [[ "$text" =~ ^swap\ (the\ )?(.+)\ (and|with)\ (.+)\ (workspaces|desktops)$ ]]; then
    text="swap workspace ${BASH_REMATCH[2]} and ${BASH_REMATCH[4]}"
  fi
  if [[ "$text" =~ ^(unmark|deselect|uncheck|remove)\ (all|everything)$ || "$text" =~ ^(clear|clear (the )?(marks|marked|selection|all marks))$ ]]; then
    echo "clear"
  elif [[ "$text" =~ ^(unmark|deselect|uncheck|remove)\ (.+)$ ]]; then
    addresses=$(overview_windows "${BASH_REMATCH[2]}") || return 0
    overview_emit unmark "$addresses"
  elif [[ "$text" =~ ^(mark|select|check|tick|add)\ (.+)$ ]]; then
    addresses=$(overview_windows "${BASH_REMATCH[2]}") || return 0
    overview_emit mark "$addresses"
  elif [[ "$text" =~ ^(move|send|put|carry)\ (the )?(workspace|desktop)\ (.+)\ (to|onto|on)\ (the )?(.+)$ ]]; then
    ws=$(overview_number "${BASH_REMATCH[4]}") || return 0
    ref=$(overview_workspace_ref "$ws") || {
      echo "error:no workspace $ws"
      return 0
    }
    monitor=$(overview_monitor "${BASH_REMATCH[7]}")
    [[ "$monitor" != error:* ]] || {
      echo "$monitor"
      return 0
    }
    [[ "$ref" =~ ^[0-9]+$ ]] || {
      echo "error:special workspaces stay where they are"
      return 0
    }
    echo "workspace_to_monitor $ref $monitor"
  elif [[ "$text" =~ ^(move|send|put|carry)(\ (.+))?\ (to|onto|on)\ (the )?(workspace|desktop)\ ([a-z0-9\ ]+)$ ]]; then
    # Without windows named ("move to workspace 7"), the marks go.
    addresses=$(overview_windows "${BASH_REMATCH[3]:-marked}") || return 0
    ws=$(overview_number_list "${BASH_REMATCH[7]}") || return 0
    [ "$(wc -l <<<"$ws")" = 1 ] || return 0
    ref=$(overview_workspace_ref "$ws") || {
      echo "error:no workspace $ws"
      return 0
    }
    overview_emit move "$addresses" "$ref"
  elif [[ "$text" =~ ^(move|send|put|carry)(\ (.+))?\ (to|onto|on)\ (the )?(.+\ (monitor|screen|display)|(monitor|screen|display)\ .+)$ ]]; then
    addresses=$(overview_windows "${BASH_REMATCH[3]:-marked}") || return 0
    monitor=$(overview_monitor "${BASH_REMATCH[6]}")
    [[ "$monitor" != error:* ]] || {
      echo "$monitor"
      return 0
    }
    overview_emit send "$addresses" "$monitor"
  elif [[ "$text" =~ ^(close|kill|quit)\ (.+)$ ]]; then
    addresses=$(overview_windows "${BASH_REMATCH[2]}") || return 0
    overview_emit close "$addresses"
  elif [[ "$text" =~ ^swap\ (the )?(workspaces|workspace|desktops|desktop)\ (number )?(.+)\ (and|with)\ (number )?(.+)$ ]]; then
    ws=$(overview_number "${BASH_REMATCH[4]}") || return 0
    ws2=$(overview_number "${BASH_REMATCH[7]}") || return 0
    ref=$(overview_workspace_ref "$ws") || {
      echo "error:no workspace $ws"
      return 0
    }
    rest=$(overview_workspace_ref "$ws2") || {
      echo "error:no workspace $ws2"
      return 0
    }
    echo "swap_workspaces $ref $rest"
  elif [[ "$text" =~ ^(focus|go to|switch to|jump to|take me to|open|show)\ (the )?(workspace|desktop)\ (.+)$ || "$text" =~ ^(the )?(workspace|desktop)\ (.+)$ ]]; then
    ws=$(overview_number "${BASH_REMATCH[$((${#BASH_REMATCH[@]} - 1))]}") || return 0
    ref=$(overview_workspace_ref "$ws") || {
      echo "error:no workspace $ws"
      return 0
    }
    echo "workspace $ref"
  elif [[ "$text" =~ ^(focus|go to|switch to|jump to|take me to|open)\ (window |number )?(.+)$ ]]; then
    addresses=$(overview_windows "${BASH_REMATCH[3]}") || return 0
    [ "$addresses" != marked ] || {
      echo "error:say which window"
      return 0
    }
    [ "$(wc -l <<<"$addresses")" = 1 ] || {
      echo "error:focus takes one window"
      return 0
    }
    overview_emit focus "$addresses"
  else
    addresses=$(overview_windows "$text") || return 0
    [ "$addresses" != marked ] || return 0
    overview_emit mark "$addresses"
  fi
}

# Prints "<verb> <addresses...> [<extra>]" from the newline-separated addresses $2 (or "marked", which names none), or
# the first "error:" line among them. The extra argument ($3, a workspace or monitor) goes first for the verbs that take
# one, as act reads it.
overview_emit() {
  local verb="$1" addresses="$2" extra="${3:-}" line list=""
  while IFS= read -r line; do
    case "$line" in
    error:*)
      echo "$line"
      return
      ;;
    marked) ;;
    *) list+=" $line" ;;
    esac
  done <<<"$addresses"
  echo "$verb${extra:+ $extra}$list"
}

# A readable name for the toast and the confirm question: the verb with how many windows it touches.
overview_label() {
  local verb args count
  read -r verb args <<<"$1"
  case "$verb" in
  error:*) echo "$1" ;;
  *)
    count=$(wc -w <<<"$args")
    case "$verb" in
    move | send) count=$((count - 1)) ;;
    esac
    case "$verb" in
    close | mark | unmark | move | send)
      if [ "$count" -le 0 ]; then
        # No numbers said: the marks, or the selected window when nothing is marked, as the keys do.
        count=$(jq '.marks | length | if . == 0 then 1 else . end' "$overview_file" 2>/dev/null || echo 1)
      fi
      echo "$verb $count window$([ "$count" = 1 ] || echo s)"
      ;;
    *) echo "${verb//_/ }" ;;
    esac
    ;;
  esac
}

# Always at most one candidate: what the phrase means to the overview, or none when the overview is closed or the
# phrase is not about it. The candidate's match_text is the spoken text, so voxcmd's fuzzy match keeps it.
candidates() {
  local parsed
  overview_is_open || {
    echo '[]'
    return
  }
  parsed=$(overview_parse "$2")
  [ -n "$parsed" ] || {
    echo '[]'
    return
  }
  jq -n -c --arg id "$parsed" --arg label "$(overview_label "$parsed")" --arg match_text "$2" '[{id: $id, label: $label, match_text: $match_text}]'
}
