# shellcheck shell=bash
# Hook library of overview.toml: sourced before every hook and action of the integration.
# The contract with the bar is in the README (Overview) and the Quickshell overview README (`features/overview/README.md`).

# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=spoken-position.sh
source "$VOXCMD_SHARE_DIR/spoken-position.sh"
# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=monitor-words.sh
source "$VOXCMD_SHARE_DIR/monitor-words.sh"

overview_file="${XDG_RUNTIME_DIR:-/tmp}/voxcmd/overview.json"
qs_ipc="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/qs-ipc"

# Prints the bar's answer ("open", "closed"), or nothing when there is no qs-ipc or the bar does not answer.
overview_bar_state() {
  local answer=""
  [ ! -x "$qs_ipc" ] || answer=$(timeout 2 "$qs_ipc" call overview state 2>/dev/null) || answer=""
  echo "$answer"
}

# Whether the overview is on screen, for offering candidates: the bar must say open, which holds in the moment after it
# opens, before its file is written. A crashed bar leaves "open":true in the file, so the file counts only where there
# is no qs-ipc to ask.
overview_is_open() {
  [ -x "$qs_ipc" ] || { grep -q '"open":true' "$overview_file" 2>/dev/null; return; }
  [ "$(overview_bar_state)" = open ]
}

# The mode's `alive` hook. The bar's own answer decides while it gives one: its file is rewritten a moment after the
# overview opens, so right after "open overview" it still says closed. The file is believed only when the bar cannot be
# asked.
overview_alive() {
  case "$(overview_bar_state)" in
  open) return 0 ;;
  closed) return 1 ;;
  *) grep -q '"open":true' "$overview_file" 2>/dev/null ;;
  esac
}

# The mode's `ended` hook. Closing the overview by voice ("done", "close overview") is how the session ends; any other
# end leaves it open.
overview_ended() {
  [ "${VOXCMD_MODE_END_REASON:-}" != "done" ] || "$qs_ipc" call overview close >/dev/null 2>&1 || true
}

overview_open() {
  [ "$("$qs_ipc" call overview open 2>&1)" = ok ] || {
    echo "the bar did not open the overview"
    return 1
  }
  overview_wait_for_snapshot
}

# Gives the bar a moment to write the snapshot the numbers and later phrases are read from; the session does not depend on it.
overview_wait_for_snapshot() {
  local polls
  for ((polls = 0; polls < 20; polls++)); do
    grep -q '"open":true' "$overview_file" 2>/dev/null && return 0
    sleep "$(overview_scaled_secs 0.05)"
  done
}

# VOXCMD_TIME_SCALE shortens the waits in the suites.
overview_scaled_secs() {
  awk -v secs="$1" -v scale="${VOXCMD_TIME_SCALE:-1}" 'BEGIN { print secs * scale }'
}

overview_close() {
  "$qs_ipc" call overview close >/dev/null 2>&1 || true
}

# $1 is a candidate's id: "<verb> <arguments>" for the overview's act, or "error:<why>" for a phrase that named something
# the overview does not show. A verb that closes the overview ends the mode with it: the mode's `alive` sees the bar
# closed at the next listen, so the bar is given a moment to say so first.
overview_act() {
  local verb args result polls
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
  focus | workspace)
    for ((polls = 0; polls < 20; polls++)); do
      overview_alive || break
      sleep "$(overview_scaled_secs 0.05)"
    done
    ;;
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

# One candidate at most: what the phrase means to the overview ($1 is the action). Nothing is offered, so the phrase
# goes on to other integrations, when the overview is closed or the phrase is not about it. The candidate's match_text
# is the spoken text, so the word match keeps it.
overview_candidates() {
  local parsed
  overview_is_open || return 3
  if [ "$1" = numbers ]; then
    printf 'numbers\tshow numbers\t%s\n' "$VOXCMD_PHRASE"
    return
  fi
  parsed=$(overview_parse "$VOXCMD_ARG_TARGET")
  [ -n "$parsed" ] || return 3
  printf '%s\t%s\t%s\n' "$parsed" "$(overview_label "$parsed")" "$VOXCMD_ARG_TARGET"
}
