# shellcheck shell=bash disable=SC2034,SC2016
# Google Calendar by voice: join or open the current meeting, say what is next, show a day in the bar's clock
# popup, prefill a new event in Google's form, open the calendar. Events come from the cache calendar-sync writes.
# Format: ~/.config/voxcmd/README.md

name="Calendar"
confirm=0

# voxcmd sets voxcmd_share_dir before loading integrations.
# shellcheck source-path=SCRIPTDIR/../../../.local/share/voxcmd source=spoken-time.sh disable=SC2154
source "$voxcmd_share_dir/spoken-time.sh"

calendar_noun='(meeting|call)'
calendar_new='(new|create|schedule|add|make|set up)( me)?( a| an)?( new)?'

verbs=(
  "open_meeting  (open|join|launch|start) (my|the)( current| next)? ${calendar_noun}( now)?"
  "next          (whats|what is|when is) (my )?next ${calendar_noun}"
  "next          (whats|what is) next on (my|the) calendar"
  "day           (whats|what is)( going)? on (my|the) calendar( for| on)? {target}"
  "day_today     (whats|what is)( going)? on (my|the) calendar"
  "day           (show|open)( me)? (my|the) calendar (for|on) {target}"
  "new           ${calendar_new} (meeting|event|appointment) {target}"
  "new_blank     ${calendar_new} (meeting|event|appointment)"
  "calendar      (open|go to|take me to|show|launch) (my|the) calendar"
)

examples=(
  "join my meeting"
  "what's my next meeting"
  "what's on my calendar tomorrow"
  "new meeting tomorrow at <time> for an hour called <title> with <email>"
  "open my calendar"
)

declare -A actions=(
  [open_meeting]='open_meeting'
  [next]='next_meeting'
  [day]='show_day "$target"'
  [day_today]='show_day today'
  [new]='new_event "$target" "$raw_transcript"'
  [new_blank]='open_in_firefox "$(create_url)"'
  [calendar]='open_in_firefox https://calendar.google.com'
)
# The browser tab and the bar popup are the answer; a toast would cover them. Joining a meeting still says which.
silent_actions=(day day_today new new_blank calendar)

# A day other than today or tomorrow or a weekday prints [], leaving the phrase to the other integrations.
candidates() {
  case "$1" in
  day) parse_day "$2" >/dev/null || echo '[]' ;;
  esac
}

# ---- Browser ---------------------------------------------------------------------------------------------------

# The one place that opens a page. setsid keeps Firefox off voxcmd's output pipe, which would otherwise hold the
# notification until Firefox exits.
open_in_firefox() {
  setsid -f firefox --new-tab "$1" >/dev/null 2>&1 </dev/null
}

# ---- Events ----------------------------------------------------------------------------------------------------

# Prints the cache's timed, uncancelled events as a JSON array with start_epoch and end_epoch added. All-day events
# are left out: nobody joins one. One date -f converts every time, which also reads offsets and plain local times.
calendar_events() {
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/calendar/events.json" events starts ends
  if [ ! -r "$cache" ]; then
    echo "The calendar isn't set up yet: no events cache"
    return 1
  fi
  events=$(jq -c '[.events[]? | select(.status != "cancelled" and .all_day != true and .start != null and .end != null)]' "$cache" 2>/dev/null) || {
    echo "The calendar cache can't be read"
    return 1
  }
  starts=$(jq -r '.[].start' <<<"$events" | date -f - +%s | jq -Rsc 'split("\n") | map(select(. != "") | tonumber)')
  ends=$(jq -r '.[].end' <<<"$events" | date -f - +%s | jq -Rsc 'split("\n") | map(select(. != "") | tonumber)')
  jq -c --argjson starts "$starts" --argjson ends "$ends" '
    if length != ($starts | length) or length != ($ends | length) then error("unreadable time") else . end
    | [range(0; length) as $i | .[$i] + {start_epoch: $starts[$i], end_epoch: $ends[$i]}]' <<<"$events" 2>/dev/null || {
    echo "The calendar cache has a time that can't be read"
    return 1
  }
}

# Join links (Meet or Teams) decide which meeting to join, not event_url: calendar-sync fills that for every event.
# The in-progress event with a join link and the latest start wins; an in-progress event without one gives way to a
# joinable meeting starting within five minutes. Failing both, the next event that starts today.
open_meeting() {
  local events now end_of_day event link title
  events=$(calendar_events) || {
    echo "$events"
    return 1
  }
  now=$(date +%s)
  end_of_day=$(date -d 'tomorrow 00:00' +%s)
  event=$(jq -c --argjson now "$now" --argjson end_of_day "$end_of_day" '
    def has_join_link: (.join_url // "") != "";
    (map(select(.start_epoch <= $now and .end_epoch > $now)) | sort_by([(has_join_link | not), -.start_epoch])) as $current
    | (map(select(.start_epoch > $now and .start_epoch <= $now + 300 and has_join_link)) | sort_by(.start_epoch)) as $starting_soon
    | (if ($current | first | . != null and has_join_link) then $current[0] else ($starting_soon[0] // $current[0]) end)
    // (map(select(.start_epoch > $now and .start_epoch < $end_of_day)) | sort_by(.start_epoch) | first)
    // empty' <<<"$events")
  if [ -z "$event" ]; then
    echo "No more meetings today"
    return
  fi
  title=$(jq -r '.title // "Untitled"' <<<"$event")
  link=$(jq -r '.join_url // .event_url // empty' <<<"$event")
  if [ -z "$link" ]; then
    echo "$title has no meeting link"
    return
  fi
  open_in_firefox "$link"
  if [ -n "$(jq -r '.join_url // empty' <<<"$event")" ]; then
    echo "Joining $title"
  else
    echo "Opening $title"
  fi
}

# "Standup at 3:00pm, in 12 minutes"; on a later day the time reads "tomorrow 9:00am" and no countdown follows.
next_meeting() {
  local events now event title start_epoch minutes message
  events=$(calendar_events) || {
    echo "$events"
    return 1
  }
  now=$(date +%s)
  event=$(jq -c --argjson now "$now" 'map(select(.start_epoch > $now)) | sort_by(.start_epoch) | first // empty' <<<"$events")
  if [ -z "$event" ]; then
    echo "No upcoming meetings"
    return
  fi
  title=$(jq -r '.title // "Untitled"' <<<"$event")
  start_epoch=$(jq -r .start_epoch <<<"$event")
  message="$title $(format_at "$start_epoch")"
  if [ "$(date -d "@$start_epoch" +%F)" = "$(date +%F)" ]; then
    minutes=$(((start_epoch - now + 30) / 60))
    [ "$minutes" -ge 1 ] || minutes=1
    message+=", in $(format_length $((minutes * 60)))"
  fi
  echo "$message"
}

# The clock popup shows the day's agenda itself.
show_day() {
  local date qs_ipc="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/qs-ipc"
  date=$(parse_day "$1") || {
    echo "no day in \"$1\""
    return 1
  }
  if [ ! -x "$qs_ipc" ]; then
    echo "no Quickshell bar: $qs_ipc is missing"
    return 1
  fi
  "$qs_ipc" call calendar open_day "$date"
}

# ---- New event -------------------------------------------------------------------------------------------------

url_encode() {
  jq -rn --arg value "$1" '$value | @uri'
}

# The IANA zone Google reads the local dates in.
local_zone() {
  local zone="${TZ:-}"
  [ -n "$zone" ] || zone=$(readlink -f /etc/localtime 2>/dev/null)
  zone="${zone#*/zoneinfo/}"
  echo "${zone#:}"
}

# create_url [title] [start] [end] [emails]: Google's prefilled new-event form. Start and end are YYYYMMDDTHHMMSS in
# the local zone, or YYYYMMDD for an all-day event, whose end day is exclusive. Fields left empty are left out.
create_url() {
  local title="${1:-}" start="${2:-}" end="${3:-}" emails="${4:-}" url
  url="https://calendar.google.com/calendar/render?action=TEMPLATE"
  [ -z "$title" ] || url+="&text=$(url_encode "$title")"
  if [ -n "$start" ]; then
    url+="&dates=$(url_encode "$start")/$(url_encode "$end")"
    [[ "$start" != *T* ]] || url+="&ctz=$(url_encode "$(local_zone)")"
  fi
  [ -z "$emails" ] || url+="&add=$(url_encode "$emails")"
  echo "$url"
}

# A bare hour with no am or pm, read as a meeting time: 1 to 7 is the afternoon, 8 to 11 the morning, 12 noon.
# Prints the meridiem to add; fails when the time says its own or is not a plain hour. Timers keep parse_clock's
# "sooner of the two" reading, which suits a reminder but not a booking.
working_hours_meridiem() {
  local -a parse_words kept=()
  local word parse_at=0 amount_milli
  read -ra parse_words <<<"$1"
  for word in "${parse_words[@]}"; do
    case "$word" in
    today | tomorrow | monday | tuesday | wednesday | thursday | friday | saturday | sunday | next | on | at | the | this | o | oh | oclock | clock) ;;
    am | pm | a | p | m | noon | midday | midnight | morning | afternoon | evening | tonight | *[0-9]am | *[0-9]pm) return 1 ;;
    *) kept+=("$word") ;;
    esac
  done
  parse_words=("${kept[@]}")
  read_amount && [ $((amount_milli % 1000)) = 0 ] || return 1
  case $((amount_milli / 1000)) in
  [1-7] | 12) echo pm ;;
  8 | 9 | 10 | 11) echo am ;;
  *) return 1 ;;
  esac
}

# The title ends where the guest list starts: the first "with", "inviting" or "invite" that is followed by an
# address, so "Lunch with Bob with alice@example.com" keeps "Lunch with Bob".
title_before_guests() {
  local -a words
  local at
  read -ra words <<<"$1"
  for ((at = 0; at < ${#words[@]} - 1; at++)); do
    if [[ "${words[at]}" =~ ^(with|inviting|invite)$ && "${words[at + 1]}" == *@* ]]; then
      echo "${words[*]:0:at}"
      return
    fi
  done
  echo "$1"
}

# "tomorrow at 3 pm for an hour called Design review with alice@example.com". The words before "called" give the
# time and length from the normalized target; the title and addresses come from the raw transcript, which still
# has its casing and "@".
new_event() {
  local target="$1" raw="$2" schedule="" title="" emails="" when="" seconds=3600
  local -a words
  schedule=" $target"
  schedule="${schedule%% called *}"
  schedule="${schedule%% named *}"
  schedule="${schedule%% titled *}"
  schedule="${schedule%% with *}"
  schedule="${schedule# }"
  # "2 hours long" and "for 2 hours long": the length may follow its time with or without "for".
  local had_long=0 split start duration day
  [[ "$schedule" != *\ long ]] || had_long=1
  schedule="${schedule% long}"
  read -ra words <<<"$schedule"
  for ((split = 0; split < ${#words[@]}; split++)); do
    start="$split"
    if [ "${words[split]}" = for ]; then
      start=$((split + 1))
    elif [ "$had_long" = 0 ]; then
      continue
    fi
    duration=$(parse_duration "${words[*]:start}") || continue
    seconds="$duration" when="${words[*]:0:split}"
    break
  done
  [ -n "$when" ] || [ "${duration:-}" ] || when="$schedule"
  when=" $when "
  when="${when// for / }"
  when="${when# }"
  when="${when% }"

  shopt -s nocasematch
  if [[ "$raw" =~ (^|[[:space:]])(called|named|titled)[[:space:]]+(.+)$ ]]; then
    title=$(title_before_guests "${BASH_REMATCH[3]}")
    title=$(sed -E 's/[[:space:].!?,]+$//' <<<"$title")
  fi
  shopt -u nocasematch
  emails=$(grep -oE '[[:alnum:]._%+-]+@[[:alnum:].-]*[[:alnum:]]\.[[:alpha:]]+' <<<"$raw" | paste -sd ',')

  local start_time="" end_time="" start_epoch meridiem
  if [ -n "$when" ]; then
    meridiem=$(working_hours_meridiem "$when") && when="$when $meridiem"
    if start_epoch=$(parse_clock "$when"); then
      start_time=$(date -d "@$start_epoch" +%Y%m%dT%H%M%S)
      end_time=$(date -d "@$((start_epoch + seconds))" +%Y%m%dT%H%M%S)
    elif day=$(parse_day "$when"); then
      start_time=$(date -d "$day" +%Y%m%d)
      end_time=$(date -d "$day +1 day" +%Y%m%d)
    else
      echo "no day or time in \"$when\""
      return 1
    fi
  fi
  open_in_firefox "$(create_url "$title" "$start_time" "$end_time" "$emails")"
}
