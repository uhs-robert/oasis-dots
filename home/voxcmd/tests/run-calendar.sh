#!/usr/bin/env bash
# Runs the calendar phrases for real inside the sandbox, against an events cache built around the current time, and
# checks what reached the stubs: the browser, the bar's IPC and the notification. Also checks the spoken-time.sh
# day words the calendar uses. The cache holds placeholder data only.
#
#   home/voxcmd/tests/run-calendar.sh
set -euo pipefail

tests_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ -z "${SANDBOX_DIR:-}" ]; then
  exec "$tests_dir/sandbox.sh" "$0" "$@"
fi

export TZ=UTC
cache_file="$XDG_CACHE_HOME/calendar/events.json"
share_dir="$(dirname "$tests_dir")/.local/share/voxcmd"
failures=0
total=0

# A non-UTC offset, as the sync writes them.
iso() { TZ=America/New_York date -d "@$1" +%Y-%m-%dT%H:%M:%S%:z; }

# event <uid> <title> <start offset secs> <end offset secs> <meet_url|null> <event_url|null> [status]
event() {
  local now
  now=$(date +%s)
  jq -n -c --arg uid "$1" --arg title "$2" --arg start "$(iso $((now + $3)))" --arg end "$(iso $((now + $4)))" \
    --arg meet "$5" --arg url "$6" --arg status "${7:-confirmed}" \
    '{uid: $uid, title: $title, start: $start, end: $end, all_day: false,
      meet_url: (if $meet == "null" then null else $meet end), event_url: (if $url == "null" then null else $url end),
      status: $status, organizer: "", attendees: [], location: ""}'
}

write_cache() {
  mkdir -p "$(dirname "$cache_file")"
  printf '%s\n' "$@" | jq -s -c '{updated: "now", source: "ical", events: .}' >"$cache_file"
}

# say <phrase>: runs it and leaves the stub calls in $calls.
say() {
  : >"$SANDBOX_DIR/calls.log"
  voxcmd "$1" >/dev/null 2>&1 || true
  calls=$(cat "$SANDBOX_DIR/calls.log")
}

expect() {
  local description="$1" needle="$2"
  total=$((total + 1))
  if [[ "$calls" != *"$needle"* ]]; then
    printf '%s: expected "%s" in:\n%s\n' "$description" "$needle" "$calls"
    failures=$((failures + 1))
  fi
}

expect_absent() {
  local description="$1" needle="$2"
  total=$((total + 1))
  if [[ "$calls" == *"$needle"* ]]; then
    printf '%s: did not expect "%s" in:\n%s\n' "$description" "$needle" "$calls"
    failures=$((failures + 1))
  fi
}

# A countdown crossing midnight reads "tomorrow", so those checks stand down in the last minutes of the day.
same_day_in_20_minutes() { [ "$(date +%F)" = "$(date -d '+20 minutes' +%F)" ]; }

# ---- Open the meeting ------------------------------------------------------------------------------------------

write_cache \
  "$(event a "Cancelled sync" -600 600 https://meet.example.com/cancelled null cancelled)" \
  "$(event b "Standup" -600 600 https://meet.example.com/standup https://calendar.example.com/standup)" \
  "$(event c "Review" -600 600 null https://calendar.example.com/review)"
say "join my meeting"
expect "in-progress meeting with a Meet link" "firefox --new-tab https://meet.example.com/standup"
expect_absent "cancelled meeting" "cancelled"
expect "says which meeting" "Joining Standup"

write_cache "$(event c "Review" -600 600 null https://calendar.example.com/review)"
say "open my meeting"
expect "event page when there is no Meet link" "firefox --new-tab https://calendar.example.com/review"

write_cache "$(event d "Old" -7200 -3600 https://meet.example.com/old null)" \
  "$(event e "Cancelled" 300 900 https://meet.example.com/cancelled null cancelled)"
say "join my meeting"
expect "nothing left today" "No more meetings today"
expect_absent "nothing left today" "firefox"

if same_day_in_20_minutes; then
  write_cache "$(event f "Planning" 600 1800 https://meet.example.com/planning null)"
  say "open my meeting"
  expect "next meeting today" "firefox --new-tab https://meet.example.com/planning"
fi

rm -f "$cache_file"
say "join my meeting"
expect "no cache" "isn't set up"
expect_absent "no cache" "firefox"

# ---- What is next ----------------------------------------------------------------------------------------------

if same_day_in_20_minutes; then
  write_cache "$(event g "Standup" 719 1800 null null)"
  say "what's my next meeting"
  expect "next meeting with a countdown" "Standup"
  expect "next meeting with a countdown" ", in 12 minutes"
  say "what's next on my calendar"
  expect "other phrasing" ", in 12 minutes"
fi

write_cache "$(event h "Past" -7200 -3600 null null)"
say "what's my next meeting"
expect "no next meeting" "No upcoming meetings"

# ---- A day, a new event, the calendar --------------------------------------------------------------------------

say "what's on my calendar tomorrow"
expect "tomorrow in the bar" "qs-ipc call calendar open_day $(date -d tomorrow +%F)"
expect_absent "day is silent" "notify-send"
say "what's on my calendar"
expect "today by default" "qs-ipc call calendar open_day $(date +%F)"
say "what's on my calendar friday"
expect "weekday" "qs-ipc call calendar open_day $(date -d friday +%F)"

tomorrow=$(date -d tomorrow +%Y%m%d)
say "new meeting tomorrow at 3 pm for an hour called Design review with alice@example.com"
expect "new meeting" "firefox --new-tab https://calendar.google.com/calendar/render?action=TEMPLATE&text=Design%20review&dates=${tomorrow}T150000/${tomorrow}T160000&ctz=UTC&add=alice%40example.com"
say "new meeting tomorrow at 3 pm for 30 minutes called Lunch with Bob"
expect "title keeps 'with' and its casing" "&text=Lunch%20with%20Bob&dates=${tomorrow}T150000/${tomorrow}T153000&ctz=UTC"
expect_absent "no guests" "&add="
say "new meeting tomorrow at 3 pm"
expect "no title" "render?action=TEMPLATE&dates=${tomorrow}T150000/${tomorrow}T160000&ctz=UTC"
say "new meeting friday called Offsite"
expect "day only is all day" "&text=Offsite&dates=$(date -d friday +%Y%m%d)/$(date -d 'friday +1 day' +%Y%m%d)"
say "new meeting"
expect "blank form" "firefox --new-tab https://calendar.google.com/calendar/render?action=TEMPLATE"
say "open my calendar"
expect "calendar" "firefox --new-tab https://calendar.google.com"
expect_absent "calendar is silent" "notify-send"

# ---- spoken-time.sh day words ----------------------------------------------------------------------------------

# shellcheck disable=SC1091
source "$share_dir/spoken-time.sh"

expect_value() {
  local description="$1" expected="$2" actual="$3"
  total=$((total + 1))
  if [ "$expected" != "$actual" ]; then
    printf '%s: expected "%s", got "%s"\n' "$description" "$expected" "$actual"
    failures=$((failures + 1))
  fi
}

expect_value "parse_day weekday" "$(date -d friday +%F)" "$(parse_day friday)"
expect_value "parse_day next weekday" "$(date -d friday +%F)" "$(parse_day "next friday")"
expect_value "parse_day tomorrow" "$(date -d tomorrow +%F)" "$(parse_day tomorrow)"
expect_value "parse_day rejects words" "fail" "$(parse_day banana || echo fail)"
expect_value "parse_clock weekday" "$(date -d "friday 09:00" +%s)" "$(parse_clock "friday at 9 am")"
expect_value "parse_clock next weekday" "$(date -d "friday 15:00" +%s)" "$(parse_clock "next friday at 3 pm")"
# The same weekday is a week out once its time has passed, and today before it.
today_name=$(date +%A)
today_name=${today_name,,}
past=$(date -d '-1 hour' '+%-I %M %P')
if [ "$(date +%F)" = "$(date -d '-1 hour' +%F)" ]; then
  expect_value "parse_clock same weekday, time passed" "$(date -d "$today_name +7 days $(date -d '-1 hour' +%H:%M)" +%s)" \
    "$(parse_clock "$today_name $past")"
fi
expect_value "parse_clock rejects day clash" "fail" "$(parse_clock "tomorrow friday at 3" || echo fail)"
expect_value "parse_duration" "5400" "$(parse_duration "an hour and a half")"

if [ "$failures" != 0 ]; then
  printf '%s of %s calendar checks failed\n' "$failures" "$total"
  exit 1
fi
printf '%s calendar checks passed\n' "$total"
