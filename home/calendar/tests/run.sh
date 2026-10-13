#!/usr/bin/env bash
# Runs calendar-sync against the synthetic fixture. rbw and qs-ipc are stubs on
# PATH, so nothing touches a real vault, feed or bar.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
sync_bin="$here/../.local/bin/calendar-sync"
fixture="$here/fixtures/sample.ics"
fixed_now="2026-10-12T09:00:00+00:00"
secret="SECRETTOKEN123"

real_home=$HOME
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stubs="$work/stubs"
mkdir -p "$stubs"

# RBW_STATE is "locked" or "unlocked". Without RBW_STORE_DIR, rbw get prints the
# file named by FEED_URL_FILE. RBW_FAIL=add|edit makes that call fail without
# touching the store, and RBW_AMBIGUOUS=1 makes get report duplicate names.
cat >"$stubs/rbw" <<'STUB'
#!/usr/bin/env bash
echo "rbw $*" >>"$STUB_LOG"
entry="${*: -1}"
case "$1" in
unlocked) [ "$RBW_STATE" = unlocked ] ;;
get)
  if [ -z "${RBW_STORE_DIR:-}" ]; then
    cat "$FEED_URL_FILE"
  elif [ "${RBW_AMBIGUOUS:-0}" = 1 ]; then
    echo "rbw get: multiple entries found" >&2
    exit 1
  elif [ ! -e "$RBW_STORE_DIR/$entry" ]; then
    echo "rbw get: no entry found" >&2
    exit 1
  elif [ "$2" = --field ]; then
    cat "$RBW_STORE_DIR/$entry.notes" 2>/dev/null || true
  else
    head -n 1 "$RBW_STORE_DIR/$entry"
  fi
  ;;
add | edit)
  [ "${RBW_FAIL:-}" = "$1" ] && exit 1
  IFS= read -r first
  printf '%s\n' "$first" >"$RBW_STORE_DIR/$entry"
  cat >"$RBW_STORE_DIR/$entry.notes"
  ;;
remove) rm -f "$RBW_STORE_DIR/$entry" ;;
esac
STUB
# KEYRING_MODE is up (default), locked, or down (no Secret Service on the bus).
cat >"$stubs/busctl" <<'STUB'
#!/usr/bin/env bash
echo "busctl $*" >>"$STUB_LOG"
case "${KEYRING_MODE:-up}" in
up) echo "b false" ;;
locked) echo "b true" ;;
*) exit 1 ;;
esac
STUB
# gdbus is the fallback query, so it must answer the same way busctl does.
cat >"$stubs/gdbus" <<'STUB'
#!/usr/bin/env bash
echo "gdbus $*" >>"$STUB_LOG"
case "${KEYRING_MODE:-up}" in
up) echo "(<false>,)" ;;
locked) echo "(<true>,)" ;;
*) exit 1 ;;
esac
STUB
cat >"$stubs/secret-tool" <<'STUB'
#!/usr/bin/env bash
echo "secret-tool $*" >>"$STUB_LOG"
case "$1" in
store) cat >"$KEYRING_FILE" ;;
lookup) cat "$KEYRING_FILE" ;;
esac
STUB
for name in systemctl xdg-open; do
  # shellcheck disable=SC2016 # $* and $STUB_LOG expand when the stub runs
  printf '#!/usr/bin/env bash\necho "%s $*" >>"$STUB_LOG"\n' "$name" >"$stubs/$name"
done
cat >"$stubs/qs-ipc" <<'STUB'
#!/usr/bin/env bash
echo "qs-ipc $*" >>"$STUB_LOG"
STUB
chmod +x "$stubs"/*

export PATH="$stubs:$PATH"
export STUB_LOG="$work/stub.log"
export FEED_URL_FILE="$work/feed_url"
export RBW_STATE=unlocked
export CALENDAR_SYNC_ALLOW_FILE_URL=1
export XDG_CONFIG_HOME="$work/config"
export TZ=UTC
: >"$STUB_LOG"

failures=0
check() {
  local label=$1
  shift
  if "$@"; then
    echo "ok: $label"
  else
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

# --- fixture through --ics -------------------------------------------------
export XDG_CACHE_HOME="$work/cache_ics"
"$sync_bin" --ics "$fixture" --at "$fixed_now"
check "ics sync pokes the bar" grep -qx 'qs-ipc call calendar refresh' "$STUB_LOG"
check "ics sync never reads the vault" test "$(grep -c '^rbw' "$STUB_LOG")" -eq 0

assert_events() {
  python3 -I - "$XDG_CACHE_HOME/calendar/events.json" <<'PY'
import base64, datetime, json, sys

data = json.load(open(sys.argv[1]))
assert data["source"] == "ical" and data["updated"].startswith("2026-10-12T09:00:00")
assert data["window_start"] == "2026-09-12T00:00:00+00:00", data["window_start"]
assert data["window_end"] == "2027-10-13T00:00:00+00:00", data["window_end"]
events = data["events"]
by_title = {}
for event in events:
    by_title.setdefault(event["title"], []).append(event)

expected_keys = {"uid", "title", "start", "end", "all_day", "location", "join_url",
                 "event_url", "status", "organizer", "attendees"}
assert all(set(event) == expected_keys for event in events)

titles = [event["title"] for event in events]
assert "Too old" not in titles and "Too far ahead" not in titles, "window"
assert "Recent past" in titles and "Far ahead" in titles, "default window is 30 days back, 365 ahead"
starts = [datetime.datetime.fromisoformat(e["start"]) for e in events]
assert starts == sorted(starts), "sorted by instant"

def eid(url):
    raw = url.split("eid=")[1]
    return base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)).decode()

review = by_title["Design review"][0]
assert review["start"].startswith("2026-10-13T14:00:00"), review["start"]
assert review["end"].startswith("2026-10-13T15:00:00")
assert not review["all_day"]
assert review["location"] == "Room 4, second floor"
assert review["join_url"] == "https://meet.google.com/abc-defg-hij"
assert review["organizer"] == "alice@example.com"
assert review["attendees"] == ["alice@example.com", "bob@example.com"]
assert eid(review["event_url"]) == "review1 alice@example.com"

teams = by_title["Vendor sync"][0]
assert teams["join_url"] == "https://teams.microsoft.com/l/meetup-join/19%3ameeting_EXAMPLE%40thread.v2/0?context=%7b%22Tid%22%3a%22example%22%7d", teams["join_url"]

assert by_title["Description only"][0]["join_url"] == "https://teams.microsoft.com/l/meetup-join/example2/0"

insecure = by_title["Insecure link"][0]
assert insecure["join_url"] is None, "http links are not accepted"

offsite = by_title["Team offsite"][0]
assert offsite["all_day"] and offsite["start"].startswith("2026-10-14T00:00:00")
assert offsite["end"].startswith("2026-10-15T00:00:00")
assert offsite["join_url"] is None

old_sync = by_title["Old sync"][0]
assert old_sync["status"] == "cancelled"

planning = by_title["Planning"][0]
assert planning["status"] == "tentative"
assert planning["join_url"] == "https://meet.google.com/lmn-opqr-stu"
assert planning["event_url"] == "https://calendar.google.com/calendar/r/day/2026/10/16", "day view fallback"

standups = by_title["Standup"]
standup_days = [e["start"][:10] for e in standups]
assert standup_days == ["2026-10-07", "2026-10-28", "2026-11-04", "2026-11-11"], standup_days
assert "2026-10-14" not in standup_days, "EXDATE"
assert all(e["join_url"] == "https://meet.google.com/xyz-wxyz-uvw" for e in standups)
assert len({e["uid"] for e in events}) == len(events), "uids unique"
assert eid(standups[1]["event_url"]) == "standup1_20261028T093000Z alice@example.com"

workshop = by_title["Long workshop"][0]
assert workshop["start"].startswith("2026-10-04"), "event spanning the window start is kept"

quick_call = by_title["Quick call"][0]
assert quick_call["end"].startswith("2026-10-13T17:45:00"), "DURATION without DTEND"

retros = {e["start"][:10]: e for e in by_title["Retro"]}
assert sorted(retros) == ["2026-10-08", "2026-10-15", "2026-10-22"]
assert retros["2026-10-15"]["status"] == "cancelled", "cancelled override"
assert retros["2026-10-08"]["status"] == "confirmed" and retros["2026-10-22"]["status"] == "confirmed"

focus_days = [e["start"][:10] for e in by_title["Focus day"]]
assert focus_days == ["2026-10-19", "2026-11-02"], focus_days
assert all(e["all_day"] for e in by_title["Focus day"]), "recurring all-day with EXDATE"
assert eid(by_title["Focus day"][0]["event_url"]) == "focus1_20261019 alice@example.com"

planning = [(e["start"], e["title"]) for e in events if e["title"].startswith("Weekly planning")]
assert planning == [
    ("2026-10-26T13:00:00+00:00", "Weekly planning"),
    ("2026-11-03T20:00:00+00:00", "Weekly planning (moved)"),
    ("2026-11-09T14:00:00+00:00", "Weekly planning"),
], planning
moved_planning = by_title["Weekly planning (moved)"][0]
assert eid(moved_planning["event_url"]) == "planning1_20261102T140000Z alice@example.com", "override id uses the original start across DST"

moved = by_title["Standup (moved)"][0]
assert moved["start"].startswith("2026-10-21T14:00:00")
assert eid(moved["event_url"]) == "standup1_20261021T093000Z alice@example.com", "override keeps original id"
PY
}
check "fixture normalizes as the plan says" assert_events

# --- time zones: same instants, local offsets -------------------------------
export XDG_CACHE_HOME="$work/cache_ny"
TZ=America/New_York "$sync_bin" --ics "$fixture" --at "$fixed_now"
assert_local_offset() {
  python3 -I - "$XDG_CACHE_HOME/calendar/events.json" <<'PY'
import json, sys

events = {}
for event in json.load(open(sys.argv[1]))["events"]:
    events.setdefault(event["title"], event)
assert events["Design review"]["start"] == "2026-10-13T10:00:00-04:00"
assert events["Team offsite"]["start"] == "2026-10-14T00:00:00-04:00"
assert events["Weekly planning"]["start"] == "2026-10-26T09:00:00-04:00"
assert events["Weekly planning (moved)"]["start"] == "2026-11-03T15:00:00-05:00"
# 01:45-04:00 is earlier than 01:15-05:00, though the strings sort the other way.
order = [e["title"] for e in json.load(open(sys.argv[1]))["events"]]
assert order.index("Early bird") < order.index("Late bird"), order
PY
}
check "times are written in the local zone" assert_local_offset

# --- the window: defaults, configured, and bad values -------------------------
window_run() {
  export XDG_CACHE_HOME="$work/cache_window"
  rm -rf "$XDG_CACHE_HOME"
  window_status=0
  "$sync_bin" --ics "$fixture" --at "$fixed_now" >"$work/window.out" 2>&1 || window_status=$?
}
write_window_config() {
  rm -rf "$work/window_config"
  mkdir -p "$work/window_config/calendar-sync"
  printf '%s\n' "$@" >"$work/window_config/calendar-sync/config"
  export XDG_CONFIG_HOME="$work/window_config"
}

assert_window() {
  python3 -I - "$XDG_CACHE_HOME/calendar/events.json" "$@" <<'PY'
import json, sys

path, start, end, present, absent = sys.argv[1:6]
data = json.load(open(path))
titles = {event["title"] for event in data["events"]}
assert data["window_start"] == start and data["window_end"] == end, (data["window_start"], data["window_end"])
for title in present.split(",") if present else []:
    assert title in titles, title
for title in absent.split(",") if absent else []:
    assert title not in titles, title
PY
}

write_window_config "# only the url_command is set" "url_command = echo unused"
window_run
check "no window keys means 30 back, 365 ahead" assert_window "2026-09-12T00:00:00+00:00" "2027-10-13T00:00:00+00:00" "Recent past,Far ahead" "Too old,Too far ahead"

write_window_config "days_back = 7" "days_ahead = 60"
window_run
check "a configured window narrows expansion" assert_window "2026-10-05T00:00:00+00:00" "2026-12-12T00:00:00+00:00" "Standup,Design review" "Recent past,Far ahead,Too old"

write_window_config "days_back = 0" "days_ahead = 0"
window_run
check "a zero window is today only" assert_window "2026-10-12T00:00:00+00:00" "2026-10-13T00:00:00+00:00" "" "Standup,Design review,Recent past"

write_window_config "days_ahead = 3650"
window_run
check "the maximum is accepted" test "$window_status" -eq 0

for bad in "days_ahead = abc" "days_ahead = -1" "days_ahead = 3651" "days_back = 1.5" "days_back = 1e3"; do
  write_window_config "$bad"
  window_run
  check "bad value '$bad' exits 1" test "$window_status" -eq 1
  check "bad value '$bad' gives a fixed message" grep -q 'whole numbers from 0 to 3650' "$XDG_CACHE_HOME/calendar/error.json"
  check "bad value '$bad' writes no events" test ! -e "$XDG_CACHE_HOME/calendar/events.json"
done
export XDG_CONFIG_HOME="$work/config"

# --- vault path: locked, then unlocked ---------------------------------------
export XDG_CACHE_HOME="$work/cache_rbw"
printf 'file://%s/%s/%s\n' "$work" "$secret" "feed.ics" >"$FEED_URL_FILE"
mkdir -p "$work/$secret"
cp "$fixture" "$work/$secret/feed.ics"

: >"$STUB_LOG"
RBW_STATE=locked "$sync_bin" >"$work/locked.out" 2>&1
check "locked vault exits quietly" test ! -s "$work/locked.out"
check "locked vault is not asked for the entry" test "$(grep -c '^rbw get' "$STUB_LOG")" -eq 0
check "locked vault writes nothing" test ! -e "$XDG_CACHE_HOME/calendar/events.json"

: >"$STUB_LOG"
mkdir -p "$XDG_CONFIG_HOME/calendar-sync"
printf 'url_command = rbw get -- my-entry\n' >"$XDG_CONFIG_HOME/calendar-sync/config"
"$sync_bin" --now >"$work/unlocked.out" 2>&1
rm "$XDG_CONFIG_HOME/calendar-sync/config"
check "entry name comes from the config" grep -qx 'rbw get -- my-entry' "$STUB_LOG"
check "unlocked vault syncs" test -s "$XDG_CACHE_HOME/calendar/events.json"
check "the address stays out of the cache" test "$(grep -rc "$secret" "$XDG_CACHE_HOME" | grep -vc ':0$')" -eq 0
check "the address stays out of output" test "$(grep -c "$secret" "$work/unlocked.out")" -eq 0

# --- unlocked vault with no entry is the same as not configured ---------------
export XDG_CACHE_HOME="$work/cache_unconfigured"
: >"$FEED_URL_FILE"
RBW_STATE=unlocked "$sync_bin" >"$work/unconfigured.out" 2>&1
check "missing entry exits quietly" test ! -s "$work/unconfigured.out"
check "missing entry writes no error.json" test ! -e "$XDG_CACHE_HOME/calendar/error.json"
check "missing entry writes no events.json" test ! -e "$XDG_CACHE_HOME/calendar/events.json"
RBW_STATE=unlocked "$sync_bin" --now >"$work/unconfigured_now.out" 2>&1
check "missing entry hints under --now" test -s "$work/unconfigured_now.out"

# --- file:// is refused unless the test switch is set ------------------------
export XDG_CACHE_HOME="$work/cache_file_url"
printf 'file://%s/%s/feed.ics\n' "$work" "$secret" >"$FEED_URL_FILE"
if CALENDAR_SYNC_ALLOW_FILE_URL=0 "$sync_bin" >"$work/file_url.out" 2>&1; then
  echo "FAIL: file:// should be refused without the switch"
  failures=$((failures + 1))
fi
check "file:// refusal says why" grep -q 'not an https address' "$work/file_url.out"
check "file:// refusal keeps the address out of output" test "$(grep -c "$secret" "$work/file_url.out")" -eq 0
check "file:// refusal writes no events" test ! -e "$XDG_CACHE_HOME/calendar/events.json"

# --- failure keeps the last good cache --------------------------------------
export XDG_CACHE_HOME="$work/cache_rbw"
before=$(cat "$XDG_CACHE_HOME/calendar/events.json")
printf 'file://%s/%s/missing.ics\n' "$work" "$secret" >"$FEED_URL_FILE"
"$sync_bin" >"$work/failed.out" 2>&1 || {
  echo "FAIL: a transient fetch failure should exit 0"
  failures=$((failures + 1))
}
check "failed fetch keeps events.json" test "$(cat "$XDG_CACHE_HOME/calendar/events.json")" = "$before"
check "failed fetch writes error.json" grep -q '"error"' "$XDG_CACHE_HOME/calendar/error.json"
check "the address stays out of the error" test "$(grep -rc "$secret" "$XDG_CACHE_HOME" "$work/failed.out" | grep -vc ':0$')" -eq 0

printf 'file://%s/%s/feed.ics\n' "$work" "$secret" >"$FEED_URL_FILE"
"$sync_bin" >/dev/null 2>&1
check "a good sync clears error.json" test ! -e "$XDG_CACHE_HOME/calendar/error.json"

# --- url_command from the config -----------------------------------------------
mkdir -p "$XDG_CONFIG_HOME/calendar-sync"
cat >"$work/print_url" <<STUB
#!/bin/sh
echo "print_url \$*" >>"$STUB_LOG"
cat "$FEED_URL_FILE"
STUB
cat >"$work/fail_url" <<'STUB'
#!/bin/sh
cat "$FEED_URL_FILE"
cat "$FEED_URL_FILE" >&2
exit 3
STUB
cat >"$work/hang_url" <<'STUB'
#!/bin/sh
sleep 30
STUB
chmod +x "$work/print_url" "$work/fail_url" "$work/hang_url"
printf 'file://%s/%s/feed.ics\n' "$work" "$secret" >"$FEED_URL_FILE"
write_config() { printf '# comment\n\nurl_command = %s\n' "$1" >"$XDG_CONFIG_HOME/calendar-sync/config"; }

export XDG_CACHE_HOME="$work/cache_command"
: >"$STUB_LOG"
write_config "$work/print_url one"
RBW_STATE=locked "$sync_bin" --now >"$work/command.out" 2>&1
check "url_command from the config syncs" test -s "$XDG_CACHE_HOME/calendar/events.json"
check "url_command receives its arguments" grep -qx 'print_url one' "$STUB_LOG"
check "a non-rbw command skips the rbw lock check" test "$(grep -c '^rbw' "$STUB_LOG")" -eq 0
check "url_command output stays out of the cache" test "$(grep -rc "$secret" "$XDG_CACHE_HOME" | grep -vc ':0$')" -eq 0
check "url_command output stays out of stdout and stderr" test "$(grep -c "$secret" "$work/command.out")" -eq 0

export XDG_CACHE_HOME="$work/cache_failing"
write_config "$work/fail_url"
status=0
"$sync_bin" >"$work/failing_quiet.out" 2>&1 || status=$?
check "a failing url_command exits 0" test "$status" -eq 0
check "a failing url_command is silent" test ! -s "$work/failing_quiet.out"
"$sync_bin" --now >"$work/failing.out" 2>&1
check "a failing url_command hints under --now" test -s "$work/failing.out"
check "a failing command's output stays out of the hint" test "$(grep -c "$secret" "$work/failing.out")" -eq 0
check "a failing url_command writes nothing" test ! -e "$XDG_CACHE_HOME/calendar/error.json" -a ! -e "$XDG_CACHE_HOME/calendar/events.json"

export XDG_CACHE_HOME="$work/cache_hanging"
write_config "$work/hang_url"
started=$SECONDS
status=0
CALENDAR_SYNC_COMMAND_TIMEOUT=1 "$sync_bin" >"$work/hanging.out" 2>&1 || status=$?
check "a hanging url_command exits 0 silently" test "$status" -eq 0 -a ! -s "$work/hanging.out"
check "a hanging url_command is cut off by the timeout" test $((SECONDS - started)) -lt 10
check "a hanging url_command writes nothing" test ! -e "$XDG_CACHE_HOME/calendar/error.json"

# A descendant in its own session keeps the pipe open past the process group kill.
cat >"$work/escape_url" <<'STUB'
#!/bin/sh
setsid sleep 12 &
sleep 30
STUB
cat >"$work/flood_url" <<'STUB'
#!/bin/sh
head -c 200000 /dev/zero | tr '\0' a
STUB
chmod +x "$work/escape_url" "$work/flood_url"
export XDG_CACHE_HOME="$work/cache_escape"
write_config "$work/escape_url"
started=$SECONDS
status=0
CALENDAR_SYNC_COMMAND_TIMEOUT=1 "$sync_bin" >"$work/escape.out" 2>&1 || status=$?
check "an escaped descendant cannot hold the sync past the timeout" test $((SECONDS - started)) -lt 8 -a "$status" -eq 0 -a ! -s "$work/escape.out"
write_config "$work/flood_url"
status=0
"$sync_bin" >"$work/flood.out" 2>&1 || status=$?
check "oversized command output is treated as not configured" test "$status" -eq 0 -a ! -s "$work/flood.out" -a ! -e "$XDG_CACHE_HOME/calendar/events.json"

rm "$XDG_CONFIG_HOME/calendar-sync/config"

# --- a feed that does not parse is a real failure ------------------------------
printf 'this is not a calendar\n' >"$work/garbage.ics"
if XDG_CACHE_HOME="$work/cache_garbage" "$sync_bin" --ics "$work/garbage.ics" >/dev/null 2>&1; then
  echo "FAIL: an unparsable feed should exit non-zero"
  failures=$((failures + 1))
else
  echo "ok: an unparsable feed exits non-zero"
fi
check "an unparsable feed writes error.json" grep -q 'could not be parsed' "$work/cache_garbage/calendar/error.json"

# --- guided setup ---------------------------------------------------------------
feed_address="file://$work/$secret/feed.ics"
setup_runs=0

# A PATH where rbw is not installed: only the tools the script and stubs need, plus every stub but rbw.
without_rbw="$work/without_rbw"
mkdir -p "$without_rbw"
for tool in env bash python3 sh cat head rm sleep setsid; do
  ln -s "$(command -v "$tool")" "$without_rbw/$tool"
done
for stub in "$stubs"/*; do
  [ "$(basename "$stub")" = rbw ] || ln -s "$stub" "$without_rbw/"
done

# Fresh home, config, data, cache, vault and keyring for each scenario.
fresh_setup_env() {
  setup_runs=$((setup_runs + 1))
  local base="$work/setup_$setup_runs"
  export HOME="$base/home" XDG_CONFIG_HOME="$base/config" XDG_DATA_HOME="$base/data" XDG_CACHE_HOME="$base/cache"
  export RBW_STORE_DIR="$base/vault" KEYRING_FILE="$base/keyring" RBW_STATE=unlocked KEYRING_MODE=up
  unset RBW_FAIL RBW_AMBIGUOUS
  mkdir -p "$HOME/.config/systemd/user" "$RBW_STORE_DIR"
  : >"$HOME/.config/systemd/user/calendar-sync.timer"
  : >"$STUB_LOG"
  setup_out="$base/out"
}

# run_setup answer...: feeds the answers, one per line, through the test seam.
# SETUP_PATH replaces PATH for the run, to simulate a machine without rbw.
run_setup() {
  printf '%s\n' "$@" >"$work/answers"
  setup_status=0
  PATH="${SETUP_PATH:-$PATH}" CALENDAR_SYNC_SETUP_ANSWERS="$work/answers" "$sync_bin" setup --at "$fixed_now" >"$setup_out" 2>&1 || setup_status=$?
}

assert_address_not_leaked() {
  local label=$1
  check "$label: address not in output, stub argv, config or cache" test "$(grep -rc "$secret" "$setup_out" "$STUB_LOG" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" 2>/dev/null | grep -vc ':0$')" -eq 0
}

fresh_setup_env
run_setup n "$feed_address" "" ""
check "auto picks rbw when unlocked" test -s "$RBW_STORE_DIR/google-calendar-ical"
check "rbw setup writes an explicit config" grep -qx 'url_command = rbw get -- google-calendar-ical' "$XDG_CONFIG_HOME/calendar-sync/config"
check "config directory is mode 700" test "$(stat -c %a "$XDG_CONFIG_HOME/calendar-sync")" = 700
check "setup validates and reports the count" grep -q '^Found [0-9]* events in the next 365 days' "$setup_out"
check "setup enables the timer" grep -qx 'systemctl --user enable --now calendar-sync.timer' "$STUB_LOG"
check "setup runs the first sync" test -s "$XDG_CACHE_HOME/calendar/events.json"
check "setup exits 0" test "$setup_status" -eq 0
check "a new rbw entry uses add with --" grep -qx 'rbw add -- google-calendar-ical' "$STUB_LOG"
assert_address_not_leaked "rbw"

fresh_setup_env
SETUP_PATH="$without_rbw" run_setup n "$feed_address" ""
check "auto picks the keyring when rbw is absent" test -s "$KEYRING_FILE"
check "keyring config names secret-tool" grep -qx 'url_command = secret-tool lookup service calendar-sync key ical-url' "$XDG_CONFIG_HOME/calendar-sync/config"
check "keyring setup syncs" test -s "$XDG_CACHE_HOME/calendar/events.json"
assert_address_not_leaked "keyring"

fresh_setup_env
RBW_STATE=locked run_setup n "$feed_address" "" keyring
check "a locked rbw has no Auto choice" grep -q 'no Auto choice' "$setup_out"
check "a locked rbw is listed" grep -q 'rbw (locked, unlock it first)' "$setup_out"
check "the user can still pick another backend" test -s "$KEYRING_FILE"
fresh_setup_env
RBW_STATE=locked run_setup n "$feed_address" rbw-locked file
check "picking the locked rbw asks to unlock it first" grep -q 'Unlock rbw first' "$setup_out"

fresh_setup_env
KEYRING_MODE=locked SETUP_PATH="$without_rbw" run_setup n "$feed_address" ""
file_path="$XDG_DATA_HOME/calendar-sync/ical-url"
check "a locked keyring is not offered" grep -q 'keyring is locked' "$setup_out"
check "auto falls back to a private file" test -s "$file_path"
check "private file is mode 600" test "$(stat -c %a "$file_path")" = 600
check "private file directory is mode 700" test "$(stat -c %a "$(dirname "$file_path")")" = 700
check "file config uses cat" grep -q '^url_command = cat ' "$XDG_CONFIG_HOME/calendar-sync/config"
check "file setup syncs" test -s "$XDG_CACHE_HOME/calendar/events.json"
check "a locked keyring is never stored to" test "$(grep -c '^secret-tool' "$STUB_LOG")" -eq 0
assert_address_not_leaked "file"

fresh_setup_env
mkdir -p "$XDG_DATA_HOME/calendar-sync"
chmod 755 "$XDG_DATA_HOME/calendar-sync"
run_setup y "$feed_address" file
check "an explicit file choice beats auto" test -s "$XDG_DATA_HOME/calendar-sync/ical-url"
check "an existing data directory is tightened" test "$(stat -c %a "$XDG_DATA_HOME/calendar-sync")" = 700
check "the browser is opened when asked" grep -q '^xdg-open https://calendar.google.com/calendar/r/settings$' "$STUB_LOG"

fresh_setup_env
run_setup n "$feed_address" keyring
check "an explicit keyring choice works" test -s "$KEYRING_FILE"

fresh_setup_env
run_setup n "$feed_address" rbw my-cal
check "an explicit rbw entry is stored" test -s "$RBW_STORE_DIR/my-cal"
check "a custom rbw entry gets a config" grep -qx 'url_command = rbw get -- my-cal' "$XDG_CONFIG_HOME/calendar-sync/config"
assert_address_not_leaked "rbw custom entry"

# An existing rbw entry is edited in place, keeping its notes, and never removed.
fresh_setup_env
printf 'Existing entry\n' >"$RBW_STORE_DIR/google-calendar-ical"
printf 'my notes\n' >"$RBW_STORE_DIR/google-calendar-ical.notes"
run_setup n "$feed_address" rbw "" n
check "declining an rbw update keeps the entry" test "$(cat "$RBW_STORE_DIR/google-calendar-ical")" = "Existing entry"
check "declining an rbw update exits 1" test "$setup_status" -eq 1
RBW_FAIL=edit run_setup n "$feed_address" rbw "" y
check "a failed rbw edit exits 1" test "$setup_status" -eq 1
check "a failed rbw edit leaves the entry" test "$(cat "$RBW_STORE_DIR/google-calendar-ical")" = "Existing entry"
check "a failed rbw edit writes no config" test ! -e "$XDG_CONFIG_HOME/calendar-sync/config"
run_setup n "$feed_address" rbw "" y
check "an rbw update stores the address" test "$(cat "$RBW_STORE_DIR/google-calendar-ical")" = "$feed_address"
check "an rbw update keeps the notes" test "$(cat "$RBW_STORE_DIR/google-calendar-ical.notes")" = "my notes"
check "an rbw update uses edit with --" grep -qx 'rbw edit -- google-calendar-ical' "$STUB_LOG"
check "an rbw entry is never removed" test "$(grep -c '^rbw remove' "$STUB_LOG")" -eq 0
assert_address_not_leaked "rbw update"

fresh_setup_env
RBW_FAIL=add run_setup n "$feed_address" rbw ""
check "a failed rbw add exits 1" test "$setup_status" -eq 1
check "a failed rbw add stores nothing" test ! -e "$RBW_STORE_DIR/google-calendar-ical"

fresh_setup_env
printf 'Existing entry\n' >"$RBW_STORE_DIR/google-calendar-ical"
RBW_AMBIGUOUS=1 run_setup n "$feed_address" rbw ""
check "duplicate rbw names stop setup" grep -q 'several entries' "$setup_out"
check "duplicate rbw names add no copy" test "$(grep -cE '^rbw (add|edit)' "$STUB_LOG")" -eq 0

fresh_setup_env
mkdir -p "$XDG_CONFIG_HOME/calendar-sync"
printf 'url_command = echo old\n' >"$XDG_CONFIG_HOME/calendar-sync/config"
run_setup n "$feed_address" file n
check "the existing config is shown" grep -q 'url_command = echo old' "$setup_out"
check "declining keeps the old config" grep -qx 'url_command = echo old' "$XDG_CONFIG_HOME/calendar-sync/config"
check "declining writes no secret" test ! -e "$XDG_DATA_HOME/calendar-sync/ical-url"
run_setup n "$feed_address" file y
check "accepting replaces the config" grep -q 'cat ' "$XDG_CONFIG_HOME/calendar-sync/config"

fresh_setup_env
mkdir -p "$XDG_CONFIG_HOME/calendar-sync"
printf 'url_command = echo old\ndays_ahead = 90\n' >"$XDG_CONFIG_HOME/calendar-sync/config"
run_setup n "$feed_address" file y
check "replacing the command keeps the window settings" grep -qx 'days_ahead = 90' "$XDG_CONFIG_HOME/calendar-sync/config"
check "setup validates against the configured window" grep -q '^Found [0-9]* events in the next 90 days' "$setup_out"

# Moving the address to another backend reports, and can delete, the old private file.
fresh_setup_env
run_setup n "$feed_address" file
run_setup n "$feed_address" keyring y y
check "an older private file is reported" grep -q 'older copy of the address is still in the private file' "$setup_out"
check "the older private file can be deleted" test ! -e "$XDG_DATA_HOME/calendar-sync/ical-url"
assert_address_not_leaked "backend switch"

git init -q "$work/work_tree_repo"
fresh_setup_env
XDG_DATA_HOME="$work/work_tree_repo/data" run_setup n "$feed_address" file
check "a private file inside a work tree is refused" test "$setup_status" -eq 1 -a ! -e "$work/work_tree_repo/data"
fresh_setup_env
XDG_CONFIG_HOME="$work/work_tree_repo/config" run_setup n "$feed_address" file
check "a config inside a work tree is refused" test "$setup_status" -eq 1 -a ! -e "$work/work_tree_repo/config" -a ! -e "$XDG_DATA_HOME/calendar-sync"

fresh_setup_env
run_setup n "file://$work/$secret/missing.ics" n
check "a failed validation exits 1" test "$setup_status" -eq 1
check "a failed validation names no address" test "$(grep -c "$secret" "$setup_out")" -eq 0
check "a failed validation writes nothing" test ! -e "$XDG_CONFIG_HOME" -a ! -e "$XDG_DATA_HOME" -a ! -s "$KEYRING_FILE" -a -z "$(ls "$RBW_STORE_DIR")"
run_setup n "file://$work/$secret/missing.ics" y "$feed_address" file
check "a failed validation can be retried" test -s "$XDG_DATA_HOME/calendar-sync/ical-url"

fresh_setup_env
status=0
"$sync_bin" setup >"$setup_out" 2>&1 </dev/null || status=$?
check "setup refuses without a terminal" test "$status" -eq 2
check "the refusal explains itself" grep -q 'needs a terminal' "$setup_out"
printf 'n\n' >"$work/answers"
status=0
env -u CALENDAR_SYNC_ALLOW_FILE_URL CALENDAR_SYNC_SETUP_ANSWERS="$work/answers" "$sync_bin" setup >"$setup_out" 2>&1 </dev/null || status=$?
check "the answers seam needs the test switch" test "$status" -eq 2

# --check: 0 connected, 1 not connected, 3 rbw locked, 4 keyring locked.
fresh_setup_env
status=0
"$sync_bin" setup --check >/dev/null 2>&1 || status=$?
check "--check fails when rbw has no entry" test "$status" -eq 1
RBW_STATE=locked "$sync_bin" setup --check >/dev/null 2>&1 || status=$?
check "--check reports a locked rbw as 3" test "$status" -eq 3
mkdir -p "$XDG_CONFIG_HOME/calendar-sync"
printf 'url_command = secret-tool lookup service calendar-sync key ical-url\n' >"$XDG_CONFIG_HOME/calendar-sync/config"
KEYRING_MODE=locked "$sync_bin" setup --check >/dev/null 2>&1 || status=$?
check "--check reports a locked keyring as 4" test "$status" -eq 4
printf 'url_command = cat %s/feed_address\n' "$work" >"$XDG_CONFIG_HOME/calendar-sync/config"
printf '%s\n' "$feed_address" >"$work/feed_address"
status=0
"$sync_bin" setup --check || status=$?
check "--check passes with a working config" test "$status" -eq 0

# --- the timer never prompts for a locked store, and the config must be trusted --
fresh_setup_env
printf '%s\n' "$feed_address" >"$KEYRING_FILE"
mkdir -p "$XDG_CONFIG_HOME/calendar-sync"
printf 'url_command = secret-tool lookup service calendar-sync key ical-url\n' >"$XDG_CONFIG_HOME/calendar-sync/config"
: >"$STUB_LOG"
status=0
KEYRING_MODE=locked "$sync_bin" >"$work/locked_keyring.out" 2>&1 || status=$?
check "a locked keyring is skipped quietly" test "$status" -eq 0 -a ! -s "$work/locked_keyring.out"
check "a locked keyring never runs secret-tool" test "$(grep -c '^secret-tool' "$STUB_LOG")" -eq 0
KEYRING_MODE=down "$sync_bin" >"$work/unknown_keyring.out" 2>&1
check "an unknown keyring state counts as locked" test "$(grep -c '^secret-tool' "$STUB_LOG")" -eq 0
"$sync_bin" >/dev/null 2>&1
check "an unlocked keyring syncs" test -s "$XDG_CACHE_HOME/calendar/events.json"

printf 'url_command = FOO=1 /usr/local/bin/rbw get -- x\n' >"$XDG_CONFIG_HOME/calendar-sync/config"
: >"$STUB_LOG"
RBW_STATE=locked "$sync_bin" >/dev/null 2>&1
check "an env-prefixed rbw command still gets the lock check" test "$(grep -c '^rbw get' "$STUB_LOG")" -eq 0

printf 'url_command = %s/print_url trusted\n' "$work" >"$XDG_CONFIG_HOME/calendar-sync/config"
chmod 664 "$XDG_CONFIG_HOME/calendar-sync/config"
: >"$STUB_LOG"
status=0
"$sync_bin" >"$work/untrusted.out" 2>&1 || status=$?
check "a group-writable config is refused" test "$status" -eq 1
check "a group-writable config never runs the command" test "$(grep -c '^print_url' "$STUB_LOG")" -eq 0
check "the refusal is recorded in error.json" grep -q 'writable by others' "$XDG_CACHE_HOME/calendar/error.json"
chmod 600 "$XDG_CONFIG_HOME/calendar-sync/config"
chmod 775 "$XDG_CONFIG_HOME/calendar-sync"
status=0
"$sync_bin" >/dev/null 2>&1 || status=$?
check "a group-writable config directory is refused" test "$status" -eq 1
chmod 700 "$XDG_CONFIG_HOME/calendar-sync"
mkdir -p "$work/work_tree_repo/linked"
printf 'url_command = %s/print_url linked\n' "$work" >"$work/work_tree_repo/linked/config"
rm "$XDG_CONFIG_HOME/calendar-sync/config"
ln -s "$work/work_tree_repo/linked/config" "$XDG_CONFIG_HOME/calendar-sync/config"
: >"$STUB_LOG"
status=0
"$sync_bin" >/dev/null 2>&1 || status=$?
check "a config linked into a work tree is refused" test "$status" -eq 1 -a "$(grep -c '^print_url' "$STUB_LOG")" -eq 0
rm "$XDG_CONFIG_HOME/calendar-sync/config"

# Later sections expect the shared environment from before the setup tests.
export HOME="$real_home"
unset RBW_STORE_DIR KEYRING_FILE KEYRING_MODE
export XDG_CONFIG_HOME="$work/config"

# --- cache inside a git work tree is refused ---------------------------------
mkdir -p "$work/repo"
git -C "$work/repo" init -q
if XDG_CACHE_HOME="$work/repo/cache" "$sync_bin" --ics "$fixture" >/dev/null 2>&1; then
  echo "FAIL: cache in a work tree should be refused"
  failures=$((failures + 1))
else
  echo "ok: cache in a work tree is refused"
fi
check "nothing is written in the work tree" test ! -e "$work/repo/cache"

if [ "$failures" -ne 0 ]; then
  echo "$failures calendar-sync test(s) failed"
  exit 1
fi
echo "calendar-sync tests passed"
