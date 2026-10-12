# shellcheck shell=bash disable=SC2034,SC2016
# Timers and reminders as transient systemd user timers. Format: ~/.config/voxcmd/README.md

name="Timers"
confirm=0

# voxcmd sets voxcmd_share_dir before loading integrations.
# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=spoken-time.sh disable=SC2154
source "$voxcmd_share_dir/spoken-time.sh"

# "stop" is left out of the cancel verbs: Media's "stop {target}" would claim "stop the timer" as a player name.
# "{target} timer" breaks the README's put-it-last advice safely: voxcmd still finds the group by counting "(".
verbs=(
  "list        ((list|show|check)( me)?|what are)( all)?( the| my)? (active |running )?(timers|reminders)( and (timers|reminders))?"
  "list        what (timers|reminders)( and (timers|reminders))?( do i have| are (there|running|set|active)| are there)?"
  "list        (are there |do i have )?any (timers|reminders)( running| set)?|(how much )?time( is)? left( on (the|my) timer)?"
  "cancel_all  (cancel|delete|remove|clear)( all)?( of)?( the| my)? (timers|reminders)( and (timers|reminders))?"
  "cancel      (cancel|delete|remove|dismiss)( the| my| that)? (timer|reminder)( (about|for|to|called|named) {target})?"
  "cancel      (cancel|delete|remove|dismiss)( the| my| that)? {target} (timer|reminder)"
  "timer       ((set|start|make|create|add)( me)? )?(a |an |the )?(new )?timer( for)? {target}"
  "timer       (set|start|make|create|add)( me)? (a |an )?{target} timer"
  "remind      remind me {target}"
  "remind      ((set|add|create|make)( me)? )?(a |an )?(new )?reminder {target}"
)

examples=(
  "set a timer for <minutes> minutes"
  "remind me in <minutes> minutes to <text>"
  "list my timers"
  "what timers do i have"
  "cancel the <name> timer"
)

declare -A actions=(
  [timer]='start_timer "$target"'
  [remind]='start_reminder "$target"'
  [list]='list_timers'
  [cancel]='cancel_timer "$id" "$target"'
  [cancel_all]='cancel_all_timers'
  [cancel_unmatched]='cancel_unmatched "$target"'
)

declare -A no_match_actions=(
  [cancel]='cancel_unmatched'
)

unit_prefix="voxcmd-timer-"

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

# Prints nothing when no timer runs, so "cancel the timer" reaches cancel_timer with no id and can say so,
# instead of ending as "no match".
candidates() {
  case "$1" in
  # A timer that names no time prints [], leaving the phrase to other integrations: "start a timer for acme" is
  # a time tracker's client.
  timer) split_duration "$2" >/dev/null || parse_when "$2" >/dev/null || echo '[]' ;;
  cancel)
    local timers
    timers=$(running_timers)
    [ "$(jq length <<<"$timers")" != 0 ] || return 0
    while IFS=$'\t' read -r unit description next; do
      jq -n -c --arg id "$unit" --arg description "$description" --arg label "$(describe_scheduled "$description" "$((next / 1000000))")" \
        '{id: $id, label: $label, match_text: ($description | sub("^[A-Za-z]+: "; ""))}'
    done < <(jq -r '.[] | [.unit, .description, .next] | @tsv' <<<"$timers") | jq -s -c .
    ;;
  esac
}

# ---- Scheduling ------------------------------------------------------------------------------------------------

# Every timer is due at a wall-clock time, timers included: --on-active counts on the monotonic clock, which stops
# while the machine sleeps, so a 20 minute timer across a suspend would ring late. A calendar time already past on
# resume fires at once.
# The unit runs voxcmd-alarm (a critical notification and the style's alarm sound) by absolute path, resolved
# here, so the user manager's PATH does not matter. Without it (voxcmd not restowed) the notification still
# shows, silently.
schedule() {
  local kind="$1" text="$2" due="$3" path unit ringer=()
  if path=$(command -v voxcmd-alarm); then
    ringer=("$path")
  elif path=$(command -v notify-send); then
    ringer=("$path" --urgency=critical --app-name=voxcmd)
  else
    echo "notify-send is not installed"
    return 1
  fi
  unit="$unit_prefix$(date +%s%N | cut -c1-13)"
  systemd-run --user --quiet --collect --unit="$unit" --description="$kind: $text" \
    --on-calendar="$(date -d "@$due" '+%Y-%m-%d %H:%M:%S')" --timer-property=AccuracySec=1s \
    -- "${ringer[@]}" "$kind" "$text"
}

# Prints "<seconds> <label>" from the longest leading run of words that reads as a duration; whatever follows is
# the timer's name. Fails when none does, or the duration is zero.
split_duration() {
  local -a words
  read -ra words <<<"$1"
  local count seconds
  for ((count = ${#words[@]}; count > 0; count--)); do
    seconds=$(parse_duration "${words[*]:0:count}") && break
  done
  [ "$count" -gt 0 ] && [ "$seconds" -gt 0 ] || return 1
  echo "$seconds ${words[*]:count}"
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
  local unit="$1" spoken="$2"
  # With no candidates printed, voxcmd hands over the spoken text as the id.
  if [ -z "$unit" ] || [ "$unit" = "$spoken" ]; then
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
# Clock times and number words come from spoken-time.sh, sourced at the top.

# Prints the seconds a whole phrase names: "5 minutes", "90 seconds", "an hour and a half", "1 hour 30",
# "two and a half minutes", "half an hour", "1 5 hours". Fails on anything left over.
parse_duration() {
  local -a parse_words
  read -ra parse_words <<<"$1"
  local parse_at=0 amount_milli total_milli=0 last_unit="" unit
  [ "${#parse_words[@]}" -gt 0 ] || return 1
  while [ "$parse_at" -lt "${#parse_words[@]}" ]; do
    if [ "${parse_words[parse_at]}" = and ] && [ -n "$last_unit" ]; then
      parse_at=$((parse_at + 1))
      # "an hour and a half": half of the unit just named
      if [ "${parse_words[parse_at]-}" = a ] && [ "${parse_words[parse_at + 1]-}" = half ] && [ -z "${parse_words[parse_at + 2]-}" ]; then
        total_milli=$((total_milli + last_unit * 500))
        parse_at=$((parse_at + 2))
        continue
      fi
    fi
    read_amount || return 1
    if unit=$(unit_seconds "${parse_words[parse_at]-}"); then
      parse_at=$((parse_at + 1))
    elif [ -n "$last_unit" ] && [ "$last_unit" -gt 1 ] && [ -z "${parse_words[parse_at]-}" ]; then
      # A bare number after a unit counts in the next one down: "1 hour 30", "2 minutes 15".
      unit=$((last_unit / 60))
    else
      return 1
    fi
    total_milli=$((total_milli + amount_milli * unit))
    last_unit="$unit"
  done
  echo $(((total_milli + 500) / 1000))
}

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

format_length() {
  local seconds="$1" parts=() hours minutes
  hours=$((seconds / 3600)) minutes=$((seconds % 3600 / 60)) seconds=$((seconds % 60))
  [ "$hours" = 0 ] || parts+=("$hours hour$([ "$hours" = 1 ] || echo s)")
  [ "$minutes" = 0 ] || parts+=("$minutes minute$([ "$minutes" = 1 ] || echo s)")
  [ "$seconds" = 0 ] || parts+=("$seconds second$([ "$seconds" = 1 ] || echo s)")
  echo "${parts[*]}"
}

# "3:47pm", "tomorrow 9:00am", "Thu 9:00am" within the week, else "Oct 20 9:00am", in the bar's Settings > Clock
# time format.
format_due() {
  local due="$1" format day=""
  format=$(clock_time_format)
  local due_day today
  due_day=$(date -d "@$due" +%F) today=$(date +%F)
  if [ "$due_day" = "$today" ]; then
    day=""
  elif [ "$due_day" = "$(date -d "$today +1 day" +%F)" ]; then
    day="tomorrow "
  elif [[ "$due_day" < "$(date -d "$today +7 days" +%F)" ]]; then
    day="$(date -d "@$due" +%a) "
  else
    day="$(date -d "@$due" '+%b %-d') "
  fi
  echo "$day$(date -d "@$due" "+$format")"
}

# "at 3:47pm" today, "tomorrow 9:00am" otherwise: a day reads wrong after "at".
format_at() {
  local when
  when=$(format_due "$1")
  [[ "$when" == [0-9]* ]] && when="at $when"
  echo "$when"
}

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
