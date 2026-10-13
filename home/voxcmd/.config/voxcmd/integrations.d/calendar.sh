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

# The event in progress (one with a link first), else the next one that starts today.
open_meeting() {
  local events now end_of_day event link title
  events=$(calendar_events) || {
    echo "$events"
    return 1
  }
  now=$(date +%s)
  end_of_day=$(date -d 'tomorrow 00:00' +%s)
  event=$(jq -c --argjson now "$now" --argjson end_of_day "$end_of_day" '
    def by_link_then_start: sort_by([((.meet_url // .event_url) == null), .start_epoch]);
    (map(select(.start_epoch <= $now and .end_epoch > $now)) | by_link_then_start | first)
    // (map(select(.start_epoch > $now and .start_epoch < $end_of_day)) | sort_by(.start_epoch) | first)
    // empty' <<<"$events")
  if [ -z "$event" ]; then
    echo "No more meetings today"
    return
  fi
  title=$(jq -r '.title // "Untitled"' <<<"$event")
  link=$(jq -r '.meet_url // .event_url // empty' <<<"$event")
  if [ -z "$link" ]; then
    echo "$title has no meeting link"
    return
  fi
  open_in_firefox "$link"
  if [ -n "$(jq -r '.meet_url // empty' <<<"$event")" ]; then
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
  schedule="${schedule#for }"
  read -ra words <<<"$schedule"
  local split duration day
  for ((split = 0; split < ${#words[@]}; split++)); do
    [ "${words[split]}" = for ] || continue
    duration=$(parse_duration "${words[*]:split+1}") || continue
    seconds="$duration" when="${words[*]:0:split}"
    break
  done
  [ -n "$when" ] || when="$schedule"
  when="${when% long}"

  shopt -s nocasematch
  if [[ "$raw" =~ (^|[[:space:]])(called|named|titled)[[:space:]]+(.+)$ ]]; then
    title="${BASH_REMATCH[3]}"
    # Strip the guest list only when it holds an address, so "Lunch with Bob" keeps its title.
    if [[ "$title" =~ ^(.*[^[:space:]])[[:space:]]+(with|and|inviting|invite)[[:space:]]+[^[:space:]]+@ ]]; then
      title="${BASH_REMATCH[1]}"
    fi
    title=$(sed -E 's/[[:space:].!?,]+$//' <<<"$title")
  fi
  shopt -u nocasematch
  emails=$(grep -oE '[[:alnum:]._%+-]+@[[:alnum:].-]*[[:alnum:]]\.[[:alpha:]]+' <<<"$raw" | paste -sd ',')

  local start="" end="" start_epoch
  if [ -n "$when" ]; then
    if start_epoch=$(parse_clock "$when"); then
      start=$(date -d "@$start_epoch" +%Y%m%dT%H%M%S)
      end=$(date -d "@$((start_epoch + seconds))" +%Y%m%dT%H%M%S)
    elif day=$(parse_day "$when"); then
      start=$(date -d "$day" +%Y%m%d)
      end=$(date -d "$day +1 day" +%Y%m%d)
    else
      echo "no day or time in \"$when\""
      return 1
    fi
  fi
  open_in_firefox "$(create_url "$title" "$start" "$end" "$emails")"
}
