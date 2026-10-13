#!/usr/bin/env bash
# Runs the calendar phrases for real inside the sandbox, against an events cache built around the current time, and
# checks what reached the stubs: the browser, the bar's IPC and the notification. Also checks the spoken-time.sh
# day words the calendar uses. The cache holds placeholder data only.
#
#   home/voxcmd/tests/run-calendar.sh
set -euo pipefail

tests_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ -z "${SANDBOX_DIR:-}" ]; then
  unset VOXCMD_EXTRA_INTEGRATIONS
  # Installed apps come from the fixture alone: an installed Calendar app must not turn "open my calendar" into a picker.
  export XDG_DATA_HOME="$tests_dir/fixtures" XDG_DATA_DIRS="$tests_dir/fixtures"
  exec "$tests_dir/sandbox.sh" "$0" "$@"
fi

export TZ=UTC
cache_file="$XDG_CACHE_HOME/calendar/events.json"
share_dir="$(dirname "$tests_dir")/.local/share/voxcmd"
failures=0
total=0

# A non-UTC offset, as the sync writes them.
iso() { TZ=America/New_York date -d "@$1" +%Y-%m-%dT%H:%M:%S%:z; }

# event <uid> <title> <start offset secs> <end offset secs> <join_url|null> <event_url|null> [status]
event() {
  local now
  now=$(date +%s)
  jq -n -c --arg uid "$1" --arg title "$2" --arg start "$(iso $((now + $3)))" --arg end "$(iso $((now + $4)))" \
    --arg meet "$5" --arg url "$6" --arg status "${7:-confirmed}" \
    '{uid: $uid, title: $title, start: $start, end: $end, all_day: false,
      join_url: (if $meet == "null" then null else $meet end), event_url: (if $url == "null" then null else $url end),
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
expect "in-progress meeting with a join link" "xdg-open https://meet.example.com/standup"
expect_absent "cancelled meeting" "cancelled"
expect "says which meeting" "Joining Standup"

# An in-progress and an upcoming meeting: "current" and "next" each take only their own.
if same_day_in_20_minutes; then
  write_cache \
    "$(event q "Running" -300 600 https://meet.example.com/running null)" \
    "$(event r "Upcoming" 900 1800 https://meet.example.com/upcoming null)"
  say "join my current meeting"
  expect "current joins the one in progress" "xdg-open https://meet.example.com/running"
  say "join my next meeting"
  expect "next joins the upcoming one" "xdg-open https://meet.example.com/upcoming"
  expect_absent "next skips the one in progress" "meet.example.com/running"
  say "join my meeting"
  expect "no qualifier keeps the ranking" "xdg-open https://meet.example.com/running"

  write_cache "$(event s "Running" -300 600 https://meet.example.com/running null)"
  say "join my next meeting"
  expect "next with none" "No more meetings today"
  expect_absent "next never falls back to the one in progress" "xdg-open"
  write_cache "$(event t2 "Upcoming" 900 1800 https://meet.example.com/upcoming null)"
  say "join my current meeting"
  expect "current with none" "No meeting in progress"
  expect_absent "current never falls back to a future one" "xdg-open"
fi

# Focus (9:00-12:00, no Meet) overlapping Standup (10:00-10:15, Meet) at 10:05; every event has an event_url, as
# calendar-sync writes them.
write_cache \
  "$(event i "Focus" -3900 6900 null https://calendar.example.com/focus)" \
  "$(event j "Standup" -300 600 https://meet.example.com/standup https://calendar.example.com/standup)"
say "join my meeting"
expect "overlap joins the meeting with a join link" "xdg-open https://meet.example.com/standup"
expect_absent "overlap skips the long event" "calendar.example.com/focus"

write_cache \
  "$(event k "Focus" -3900 6900 null https://calendar.example.com/focus)" \
  "$(event l "Planning" 240 1800 https://meet.example.com/planning https://calendar.example.com/planning)"
say "join my meeting"
expect "join-link meeting starting within 5 minutes beats one without" "xdg-open https://meet.example.com/planning"

write_cache "$(event t "Teams sync" -300 600 https://teams.microsoft.com/l/meetup-join/placeholder https://calendar.example.com/teams)"
say "join my meeting"
expect "Teams join link" "xdg-open https://teams.microsoft.com/l/meetup-join/placeholder"
expect "Teams says joining" "Joining Teams sync"

write_cache "$(event m 'Sync <img src="https://example.com/x.png"> & plan' -300 600 https://meet.example.com/markup null)"
say "join my meeting"
expect "title markup is escaped" 'Joining Sync &lt;img src="https://example.com/x.png"&gt; &amp; plan'
expect_absent "raw markup" "<img"
write_cache "$(event n 'Sync <b>x</b>' -3600 -1800 null null)" "$(event o 'Sync <b>x</b>' 300 900 null null)"
say "what's my next meeting"
expect "next meeting title is escaped" "Sync &lt;b&gt;x&lt;/b&gt;"
write_cache "$(event p 'Sync <b>x</b>' -300 600 null null)"
say "join my meeting"
expect "no-link message is escaped" "Sync &lt;b&gt;x&lt;/b&gt; has no meeting link"

write_cache "$(event c "Review" -600 600 null https://calendar.example.com/review)"
say "open my meeting"
expect "event page when there is no Meet link" "xdg-open https://calendar.example.com/review"

write_cache "$(event d "Old" -7200 -3600 https://meet.example.com/old null)" \
  "$(event e "Cancelled" 300 900 https://meet.example.com/cancelled null cancelled)"
say "join my meeting"
expect "nothing left today" "No more meetings today"
expect_absent "nothing left today" "xdg-open"

if same_day_in_20_minutes; then
  write_cache "$(event f "Planning" 600 1800 https://meet.example.com/planning null)"
  say "open my meeting"
  expect "next meeting today" "xdg-open https://meet.example.com/planning"
fi

rm -f "$cache_file"
say "join my meeting"
expect "no cache" "isn't set up"
expect_absent "no cache" "xdg-open"

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
expect "new meeting" "xdg-open https://calendar.google.com/calendar/render?action=TEMPLATE&text=Design%20review&dates=${tomorrow}T150000/${tomorrow}T160000&ctz=UTC&add=alice%40example.com"
say "new meeting tomorrow at 3 pm for 30 minutes called Lunch with Bob"
expect "title keeps 'with' and its casing" "&text=Lunch%20with%20Bob&dates=${tomorrow}T150000/${tomorrow}T153000&ctz=UTC"
expect_absent "no guests" "&add="
say "new meeting tomorrow at 3 pm for an hour called Design review with alice@example.com and bob@example.com"
expect "two guests, title cut at the first with" "&text=Design%20review&dates=${tomorrow}T150000/${tomorrow}T160000&ctz=UTC&add=alice%40example.com%2Cbob%40example.com"
say "new meeting friday at 3 called Sync"
expect "bare 3 is the afternoon" "&text=Sync&dates=$(date -d friday +%Y%m%d)T150000/$(date -d friday +%Y%m%d)T160000"
say "new meeting tomorrow at 9 called Sync"
expect "bare 9 is the morning" "&dates=${tomorrow}T090000/${tomorrow}T100000"
say "new meeting tomorrow at 12 called Sync"
expect "bare 12 is noon" "&dates=${tomorrow}T120000/${tomorrow}T130000"
say "new meeting tomorrow at 9 am for 2 hours long called Sync"
expect "for N hours long" "&dates=${tomorrow}T090000/${tomorrow}T110000"
say "new meeting tomorrow at 9 am 2 hours long called Sync"
expect "N hours long" "&dates=${tomorrow}T090000/${tomorrow}T110000"
say "new meeting for 3 pm tomorrow called Sync"
expect "for before a clock time" "&dates=${tomorrow}T150000/${tomorrow}T160000"
say "new meeting tomorrow at 3 pm"
expect "no title" "render?action=TEMPLATE&dates=${tomorrow}T150000/${tomorrow}T160000&ctz=UTC"
say "new meeting friday called Offsite"
expect "day only is all day" "&text=Offsite&dates=$(date -d friday +%Y%m%d)/$(date -d 'friday +1 day' +%Y%m%d)"
say "new meeting"
expect "blank form" "xdg-open https://calendar.google.com/calendar/render?action=TEMPLATE"
say "open my calendar"
expect "calendar" "xdg-open https://calendar.google.com"
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
expect_value "parse_day next weekday" "$(date -d "next friday" +%F)" "$(parse_day "next friday")"
expect_value "parse_day tomorrow" "$(date -d tomorrow +%F)" "$(parse_day tomorrow)"
expect_value "parse_day rejects words" "fail" "$(parse_day banana || echo fail)"
expect_value "parse_clock weekday" "$(date -d "friday 09:00" +%s)" "$(parse_clock "friday at 9 am")"
expect_value "parse_clock next weekday" "$(date -d "next friday 15:00" +%s)" "$(parse_clock "next friday at 3 pm")"
# The same weekday is a week out once its time has passed, and today before it.
today_name=$(date +%A)
today_name=${today_name,,}
past=$(date -d '-1 hour' '+%-I %M %P')
if [ "$(date +%F)" = "$(date -d '-1 hour' +%F)" ]; then
  expect_value "parse_clock same weekday, time passed" "$(date -d "$today_name +7 days $(date -d '-1 hour' +%H:%M)" +%s)" \
    "$(parse_clock "$today_name $past")"
fi
# "next <today's weekday>" is a week out, whichever weekday the test runs on.
expect_value "next today's weekday" "$(date -d "$today_name +7 days" +%F)" "$(parse_day "next $today_name")"
expect_value "parse_clock next today's weekday" "$(date -d "$today_name +7 days 15:00" +%s)" "$(parse_clock "next $today_name 3 pm")"
expect_value "next elsewhere is not a day word" "fail" "$(parse_clock "9 am next in tokyo" || echo fail)"
expect_value "parse_clock rejects day clash" "fail" "$(parse_clock "tomorrow friday at 3" || echo fail)"
expect_value "parse_duration" "5400" "$(parse_duration "an hour and a half")"

if [ "$failures" != 0 ]; then
  printf '%s of %s calendar checks failed\n' "$failures" "$total"
  exit 1
fi
printf '%s calendar checks passed\n' "$total"
