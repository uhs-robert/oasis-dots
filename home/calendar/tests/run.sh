#!/usr/bin/env bash
# Runs calendar-sync against the synthetic fixture. rbw and qs-ipc are stubs on
# PATH, so nothing touches a real vault, feed or bar.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
sync_bin="$here/../.local/bin/calendar-sync"
fixture="$here/fixtures/sample.ics"
fixed_now="2026-10-12T09:00:00+00:00"
secret="SECRETTOKEN123"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stubs="$work/stubs"
mkdir -p "$stubs"

# RBW_STATE is "locked" or "unlocked"; rbw get prints the file named by FEED_URL_FILE.
cat >"$stubs/rbw" <<'STUB'
#!/usr/bin/env bash
echo "rbw $*" >>"$STUB_LOG"
case "$1" in
unlocked) [ "$RBW_STATE" = unlocked ] ;;
get) cat "$FEED_URL_FILE" ;;
esac
STUB
cat >"$stubs/qs-ipc" <<'STUB'
#!/usr/bin/env bash
echo "qs-ipc $*" >>"$STUB_LOG"
STUB
chmod +x "$stubs"/*

export PATH="$stubs:$PATH"
export STUB_LOG="$work/stub.log"
export FEED_URL_FILE="$work/feed_url"
export RBW_STATE=unlocked
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
import base64, json, sys

data = json.load(open(sys.argv[1]))
assert data["source"] == "ical" and data["updated"].startswith("2026-10-12T09:00:00")
events = data["events"]
by_title = {}
for event in events:
    by_title.setdefault(event["title"], []).append(event)

expected_keys = {"uid", "title", "start", "end", "all_day", "location", "meet_url",
                 "event_url", "status", "organizer", "attendees"}
assert all(set(event) == expected_keys for event in events)

titles = [event["title"] for event in events]
assert "Too old" not in titles and "Too far ahead" not in titles, "window"
assert [e["start"][:10] for e in events] == sorted(e["start"][:10] for e in events), "sorted"

def eid(url):
    raw = url.split("eid=")[1]
    return base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)).decode()

review = by_title["Design review"][0]
assert review["start"].startswith("2026-10-13T14:00:00"), review["start"]
assert review["end"].startswith("2026-10-13T15:00:00")
assert not review["all_day"]
assert review["location"] == "Room 4, second floor"
assert review["meet_url"] == "https://meet.google.com/abc-defg-hij"
assert review["organizer"] == "alice@example.com"
assert review["attendees"] == ["alice@example.com", "bob@example.com"]
assert eid(review["event_url"]) == "review1 alice@example.com"

offsite = by_title["Team offsite"][0]
assert offsite["all_day"] and offsite["start"].startswith("2026-10-14T00:00:00")
assert offsite["end"].startswith("2026-10-15T00:00:00")
assert offsite["meet_url"] is None

old_sync = by_title["Old sync"][0]
assert old_sync["status"] == "cancelled"

planning = by_title["Planning"][0]
assert planning["status"] == "tentative"
assert planning["meet_url"] == "https://meet.google.com/lmn-opqr-stu"
assert planning["event_url"] == "https://calendar.google.com/calendar/r/day/2026/10/16", "day view fallback"

standups = by_title["Standup"]
standup_days = [e["start"][:10] for e in standups]
assert standup_days == ["2026-10-07", "2026-10-28", "2026-11-04", "2026-11-11"], standup_days
assert "2026-10-14" not in standup_days, "EXDATE"
assert all(e["meet_url"] == "https://meet.google.com/xyz-wxyz-uvw" for e in standups)
assert len({e["uid"] for e in events}) == len(events), "uids unique"
assert eid(standups[1]["event_url"]) == "standup1_20261028T093000Z alice@example.com"

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

events = {e["title"]: e for e in json.load(open(sys.argv[1]))["events"]}
assert events["Design review"]["start"] == "2026-10-13T10:00:00-04:00"
assert events["Team offsite"]["start"] == "2026-10-14T00:00:00-04:00"
PY
}
check "times are written in the local zone" assert_local_offset

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
CALENDAR_SYNC_RBW_ENTRY=my-entry "$sync_bin" --now >"$work/unlocked.out" 2>&1
check "entry name comes from the environment" grep -qx 'rbw get my-entry' "$STUB_LOG"
check "unlocked vault syncs" test -s "$XDG_CACHE_HOME/calendar/events.json"
check "the address stays out of the cache" test "$(grep -rc "$secret" "$XDG_CACHE_HOME" | grep -vc ':0$')" -eq 0
check "the address stays out of output" test "$(grep -c "$secret" "$work/unlocked.out")" -eq 0

# --- failure keeps the last good cache --------------------------------------
before=$(cat "$XDG_CACHE_HOME/calendar/events.json")
printf 'file://%s/%s/missing.ics\n' "$work" "$secret" >"$FEED_URL_FILE"
if "$sync_bin" >"$work/failed.out" 2>&1; then
  echo "FAIL: failed fetch should exit non-zero"
  failures=$((failures + 1))
fi
check "failed fetch keeps events.json" test "$(cat "$XDG_CACHE_HOME/calendar/events.json")" = "$before"
check "failed fetch writes error.json" grep -q '"error"' "$XDG_CACHE_HOME/calendar/error.json"
check "the address stays out of the error" test "$(grep -rc "$secret" "$XDG_CACHE_HOME" "$work/failed.out" | grep -vc ':0$')" -eq 0

printf 'file://%s/%s/feed.ics\n' "$work" "$secret" >"$FEED_URL_FILE"
"$sync_bin" >/dev/null 2>&1
check "a good sync clears error.json" test ! -e "$XDG_CACHE_HOME/calendar/error.json"

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
