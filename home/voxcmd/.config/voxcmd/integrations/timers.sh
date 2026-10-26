# shellcheck shell=bash disable=SC2154
# Hook library of timers.toml: sourced before every hook and action of the integration.

# VOXCMD_SHARE_DIR is set by voxcmd for every hook and action.
# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=spoken-time.sh
source "$VOXCMD_SHARE_DIR/spoken-time.sh"

unit_prefix="voxcmd-timer-"

# Prints "<seconds> <label>" from the longest leading run of words that reads as a duration; whatever follows is the
# timer's name. Fails when none does, or the duration is zero. The Rust splitter, so the hook and the action agree.
split_duration() {
  "$VOXCMD_SELF" util speech split-duration "$1" 2>/dev/null
}

# Running timers as {unit, description, next}: next is the realtime due time in microseconds. list-timers has the
# due time and list-units the Description, which holds the label ("Timer: 5 minutes", "Reminder: Call the bank").
# A timer that has rung but is not yet collected has no next time and is left out.
running_timers() {
  local due descriptions
  due=$(systemctl --user list-timers --all --output=json "$unit_prefix*" 2>/dev/null) || due='[]'
  descriptions=$(systemctl --user list-units --all --output=json "$unit_prefix*.timer" 2>/dev/null) || descriptions='[]'
  jq -c --argjson descriptions "$descriptions" '
    map(.unit as $unit | select(.next != null and .next > 0)
      | {unit: $unit, next, description: (first($descriptions[] | select(.unit == $unit) | .description) // $unit)})
    | sort_by(.next)' <<<"$due" 2>/dev/null || echo '[]'
}

# One row, the target itself, when it names a time; none otherwise, leaving the phrase to other integrations
# ("start a timer for acme" is a time tracker's client).
timer_candidates() {
  local target="${VOXCMD_ARG_TARGET-}"
  split_duration "$target" >/dev/null || parse_when "$target" >/dev/null || return 0
  printf '%s\t%s\t%s\n' "$target" "$target" "$target"
}

# Running timers as unit, label, match_text. With none running, one placeholder row with id "none" and the spoken target
# as its match_text, so it always passes the word match and "cancel the timer" reaches cancel_timer, which says so.
# The label is the spoken target, else the noun said ("cancel the reminder"), as the toast title, not the message
# cancel_timer prints.
cancel_candidates() {
  local timers unit description next
  timers=$(running_timers)
  if [ "$(jq length <<<"$timers")" = 0 ]; then
    local noun=timer
    [[ " ${VOXCMD_PHRASE-} " == *" reminder "* ]] && noun=reminder
    printf 'none\t%s\t%s\n' "${VOXCMD_ARG_TARGET:-$noun}" "${VOXCMD_ARG_TARGET-}"
    return 0
  fi
  while IFS=$'\t' read -r unit description next; do
    printf '%s\t%s\t%s\n' "$unit" "$(describe_scheduled "$description" "$((next / 1000000))")" "${description#*: }"
  done < <(jq -r '.[] | [.unit, .description, .next] | @tsv' <<<"$timers")
}

# ---- Scheduling ------------------------------------------------------------------------------------------------

# Every timer is due at a wall-clock time, timers included: --on-active counts on the monotonic clock, which stops
# while the machine sleeps, so a 20 minute timer across a suspend would ring late. A calendar time already past on
# resume fires at once.
# The unit rings through `timer ring` of the voxcmd running this hook (a critical notification and the style's alarm
# sound), by absolute path, so the user manager's PATH does not matter.
schedule() {
  local kind="$1" text="$2" due="$3" unit
  unit="$unit_prefix$(date +%s%N | cut -c1-13)"
  systemd-run --user --quiet --collect --unit="$unit" --description="$kind: $text" \
    --on-calendar="$(date -d "@$due" '+%Y-%m-%d %H:%M:%S')" --timer-property=AccuracySec=1s \
    -- "$VOXCMD_SELF" timer ring "$kind" "$text"
}

# A duration ("5 minutes for the pasta", "in 5 minutes"), or else a clock time ("3 pm", "noon tomorrow") to ring at.
start_timer() {
  local split seconds label
  if ! split=$(split_duration "${1#in }"); then
    start_clock_timer "$1"
    return
  fi
  read -r seconds label <<<"$split"
  label=$(sed -E 's/^(for|called|named|labell?ed) //; s/^the //' <<<"$label")
  label="${label^}"
  local length due
  length=$(format_length "$seconds")
  due=$(($(date +%s) + seconds))
  schedule Timer "${label:+$label, }$length" "$due" || return 1
  echo "Timer set: ${label:+$label, }$length, rings $(format_at "$due")"
}

# The Description holds the time of day alone ("Timer: 3:00pm"): the day it would carry goes stale overnight, and
# describe_scheduled adds the current one from the due time.
start_clock_timer() {
  local due when time_of_day
  if ! due=$(parse_when "$1"); then
    echo "no duration or time in \"$1\""
    return 1
  fi
  if [ "$due" -le "$(date +%s)" ]; then
    echo "\"$1\" is in the past"
    return 1
  fi
  when=$(format_due "$due")
  time_of_day="${when##* }"
  schedule Timer "$time_of_day" "$due" || return 1
  echo "Timer set for $when"
}

# "in 20 minutes to call the bank", "at 3 pm to stretch", "to stretch at 3 pm", "about the oven in 5 minutes".
start_reminder() {
  local -a words
  read -ra words <<<"$1"
  local count=${#words[@]} split due="" text=""
  # The time first, then "to ..." for the text.
  for ((split = 1; split < count; split++)); do
    [ "${words[split]}" = to ] || continue
    due=$(parse_when "${words[*]:0:split}") && {
      text="${words[*]:split+1}"
      break
    }
    due=""
  done
  # The text first, then the time from an "in", "at", "tomorrow" or "tonight" on.
  if [ -z "$due" ]; then
    local -a rest=("${words[@]}")
    [[ "${rest[0]-}" =~ ^(to|about|that)$ ]] && rest=("${rest[@]:1}")
    for ((split = 0; split < ${#rest[@]}; split++)); do
      [[ "${rest[split]}" =~ ^(in|at|for|tomorrow|tonight|today)$ ]] || continue
      due=$(parse_when "${rest[*]:split}") && {
        text="${rest[*]:0:split}"
        break
      }
      due=""
    done
  fi
  if [ -z "$due" ]; then
    echo "no time in \"$1\""
    return 1
  fi
  text="${text:-time is up}"
  text="${text^}"
  if [ "$due" -le "$(date +%s)" ]; then
    echo "\"$1\" is in the past"
    return 1
  fi
  schedule Reminder "$text" "$due" || return 1
  describe_scheduled "Reminder: $text" "$due"
}

# ---- Listing and cancelling ------------------------------------------------------------------------------------

list_timers() {
  local timers
  timers=$(running_timers)
  if [ "$(jq length <<<"$timers")" = 0 ]; then
    echo "No timers or reminders"
    return
  fi
  # One line, since only the last line of output reaches the notification.
  jq -r '.[] | [.description, .next] | @tsv' <<<"$timers" | while IFS=$'\t' read -r description next; do
    local due=$((next / 1000000))
    case "$description" in
    Timer:*) echo "$(describe_scheduled "$description" "$due"), $(format_left "$due")" ;;
    *) describe_scheduled "$description" "$due" ;;
    esac
  done | paste -sd ';' | sed 's/;/; /g'
}

cancel_timer() {
  local unit="$1"
  # The placeholder cancel_candidates offers when nothing runs.
  if [ "$unit" = none ]; then
    echo "No timers or reminders are running"
    return
  fi
  if ! [[ "$unit" =~ ^voxcmd-timer-[0-9]+\.timer$ ]]; then
    echo "not a voxcmd timer: $unit"
    return 1
  fi
  systemctl --user stop "$unit" || return 1
  echo "Cancelled"
}

cancel_unmatched() {
  echo "No timer or reminder matches \"$1\""
  return 1
}

cancel_all_timers() {
  local -a units
  mapfile -t units < <(running_timers | jq -r '.[].unit')
  if [ "${#units[@]}" = 0 ]; then
    echo "No timers or reminders are running"
    return
  fi
  systemctl --user stop "${units[@]}" || return 1
  echo "Cancelled ${#units[@]} timer$([ "${#units[@]}" = 1 ] || echo s)"
}

# ---- Parsing ---------------------------------------------------------------------------------------------------
# Clock times, durations (parse_duration) and number words come from spoken-time.sh, sourced at the top.

# Prints the epoch "in 20 minutes", "at 3 pm", "for 3 pm", "tomorrow at 9" or a bare "20 minutes" names.
parse_when() {
  local when="$1" seconds
  case "$when" in
  in\ *) seconds=$(parse_duration "${when#in }") || return 1 ;;
  at\ * | today\ * | tomorrow\ * | tonight\ *) parse_clock "$when" && return || return 1 ;;
  *)
    when="${when#for }"
    seconds=$(parse_duration "$when") || {
      parse_clock "$when" && return || return 1
    }
    ;;
  esac
  echo $(($(date +%s) + seconds))
}

# ---- Formatting ------------------------------------------------------------------------------------------------
# format_length, format_due and format_at come from spoken-time.sh.

# "5 minutes left" for a timer due at the epoch $1, to the minute once there is more than one.
format_left() {
  local left=$(($1 - $(date +%s)))
  [ "$left" -gt 60 ] && left=$((left / 60 * 60))
  [ "$left" -gt 0 ] || left=1
  echo "$(format_length "$left") left"
}

# A timer or reminder as the list, the cancel picker and a reminder's confirmation show it, from its unit's
# Description ("Timer: 5 minutes", "Timer: 3:00pm", "Reminder: Call the bank"): "Timer: 5 minutes, rings at
# 3:47pm", "Timer at 3:00pm", "Reminder at 3:00pm: Call the bank".
describe_scheduled() {
  local description="$1" due="$2" text="${1#*: }"
  case "$description" in
  # A clock timer's text is a bare time; a duration timer's always ends in its length's unit.
  Timer:\ [0-9]*:[0-9][0-9] | Timer:\ [0-9]*:[0-9][0-9][ap]m) echo "Timer $(format_at "$due")" ;;
  Timer:*) echo "Timer: $text, rings $(format_at "$due")" ;;
  Reminder:*) echo "Reminder $(format_at "$due"): $text" ;;
  *) echo "$description, $(format_at "$due")" ;;
  esac
}
