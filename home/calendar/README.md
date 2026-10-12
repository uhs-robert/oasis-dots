# calendar

`calendar-sync` keeps a local copy of your Google Calendar for the bar and voice commands to read. A systemd user timer runs it every 5 minutes. It reads your calendar's private iCal address, so it needs no OAuth and no Google Cloud project.

## Setup

1. In Google Calendar, open Settings, pick the calendar, and copy "Secret address in iCal format".
2. Save it in rbw as an entry named `google-calendar-ical`: `rbw add google-calendar-ical`, then paste the address as the password.
3. Unlock rbw. The timer was enabled by the installer; to enable it by hand: `systemctl --user enable --now calendar-sync.timer`.

The address is a credential: anyone holding it can read the whole calendar. It goes from rbw into memory only. It is never in a command line, a log, the cache or an error message. If it leaks, reset it in Google Calendar settings.

To use another entry name, set `CALENDAR_SYNC_RBW_ENTRY`, for example in a drop-in: `systemctl --user edit calendar-sync.service`.

## Behavior

- When rbw is locked the timer does nothing and says nothing; it never opens a password prompt. The cache stays as it was and catches up on the first run after you unlock.
- Events from 7 days back to 60 days ahead are written to `${XDG_CACHE_HOME:-~/.cache}/calendar/events.json`. Recurring events are expanded into one entry per occurrence.
- On failure the last `events.json` is kept and `error.json` next to it holds a short, address-free message. The next good sync removes it.
- The script refuses to run when the cache path is inside a git work tree, so event data cannot land in a checkout.
- After each sync it runs `qs-ipc call calendar refresh` so the bar reloads at once. A bar without that target is ignored.

## Manual use

```bash
calendar-sync --now                # sync now, print the outcome
calendar-sync --ics feed.ics       # read a file instead of rbw and the network
```

`--at <ISO8601>` pretends it is that moment; the tests use it with the fixture.

## events.json

```json
{ "updated": "ISO8601", "source": "ical", "events": [
  { "uid": "...", "title": "...", "start": "ISO8601", "end": "ISO8601", "all_day": false,
    "location": "...", "meet_url": "https://meet.google.com/...|null",
    "event_url": "https://calendar.google.com/...", "status": "confirmed|tentative|cancelled",
    "organizer": "...", "attendees": ["..."] } ] }
```

- Times carry the local UTC offset. An all-day event runs from local midnight of its first day to local midnight after its last (exclusive end).
- `uid` is the feed's UID; an occurrence of a recurring event adds `#<original start>` so every entry is unique.
- `meet_url` comes from `X-GOOGLE-CONFERENCE`, else a Meet link in the location, description or URL.
- `event_url` is Google's event page when it can be derived from the feed's UID and calendar id, and otherwise the calendar's day view for the event's date.

## Tests

```bash
home/calendar/tests/run.sh
```

It runs `calendar-sync` on `tests/fixtures/sample.ics` (placeholder data only) with stub `rbw` and `qs-ipc` on `PATH`, so it never reaches a real vault, feed or bar. `just check` runs it when `python-icalendar` and `python-recurring-ical-events` are installed.
