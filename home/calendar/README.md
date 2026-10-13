# calendar

`calendar-sync` keeps a local copy of your Google Calendar for the bar and voice commands to read. A systemd user timer runs it every 5 minutes. It reads your calendar's private iCal address, so it needs no OAuth and no Google Cloud project.

## Setup

1. In Google Calendar, open Settings, pick the calendar, and copy "Secret address in iCal format".
2. Store it in a password manager. By default `calendar-sync` runs `rbw get google-calendar-ical`, so with rbw: `rbw add google-calendar-ical`, then paste the address as the password, and unlock rbw.
3. The package is optional: the installer enables the timer only when you chose `calendar` (or ran `just stow calendar` before it). To enable it by hand: `systemctl --user enable --now calendar-sync.timer`.

### Another password manager

Create `${XDG_CONFIG_HOME:-~/.config}/calendar-sync/config` with a command that prints the address on stdout. Blank lines and lines starting with `#` are ignored. The file holds a command only, never the address, and is not part of the stow package.

```ini
# pick one
url_command = rbw get google-calendar-ical
url_command = pass show calendar/google-ical
url_command = secret-tool lookup service calendar-sync
url_command = op read "op://Personal/Google Calendar/ical"
url_command = cat ~/.config/calendar-sync/ical-address
```

The last one reads a file you keep yourself; make it `chmod 600` and keep it out of every repo.

The command runs through `sh -c` with no terminal, no stdin and its stderr discarded, and gets 20 seconds. A non-zero exit, empty output or a timeout counts as "not configured": the timer stays silent and `calendar-sync --now` prints a hint. The command therefore must not prompt. A manager that asks for a passphrase through gpg or pinentry must already be unlocked (for example by a running agent), or the run times out without ever showing the prompt. With `rbw get` (the default, or any command starting with `rbw `) a locked vault is detected first with `rbw unlocked`.

`CALENDAR_SYNC_RBW_ENTRY` still changes the entry name of the default `rbw get` command, for example in a drop-in: `systemctl --user edit calendar-sync.service`. A `url_command` replaces it.

The address is a credential: anyone holding it can read the whole calendar. It goes from the command into memory only. It is never in a command line, a log, the cache or an error message. If it leaks, reset it in Google Calendar settings. Only https addresses are accepted.

## Behavior

- When rbw is locked, or the address command fails, prints nothing or times out, the timer does nothing and says nothing; it never opens a password prompt. The cache stays as it was and catches up on the first run after you unlock.
- Events from 7 days back to 60 days ahead are written to `${XDG_CACHE_HOME:-~/.cache}/calendar/events.json`. Recurring events are expanded into one entry per occurrence.
- Without the two Python libraries it also does nothing and says nothing (`--now` prints a hint).
- On failure the last `events.json` is kept and `error.json` next to it holds a short, address-free message. The next good sync removes it. A network or HTTP failure still exits 0, so a laptop that goes offline does not leave the unit in `systemctl --failed`; a feed that cannot be parsed exits 1. Consumers should treat `error.json` as stale when its `at` is older than `events.json`'s `updated`.
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
    "location": "...", "join_url": "https://meet.google.com/...|https://teams.microsoft.com/...|null",
    "event_url": "https://calendar.google.com/...", "status": "confirmed|tentative|cancelled",
    "organizer": "...", "attendees": ["..."] } ] }
```

- Times carry the local UTC offset. An all-day event runs from local midnight of its first day to local midnight after its last (exclusive end).
- `uid` is the feed's UID; an occurrence of a recurring event adds `#<original start>` so every entry is unique.
- `join_url` is the link that joins the call, https only. A Google Meet link wins: `X-GOOGLE-CONFERENCE`, else a Meet link in the location, description or URL. Otherwise a Microsoft Teams link: `X-MICROSOFT-SKYPETEAMSMEETINGURL`, else a `teams.microsoft.com/l/meetup-join/` link in the description or location.
- `event_url` is Google's event page when it can be derived from the feed's UID and calendar id, and otherwise the calendar's day view for the event's date.

## Tests

```bash
home/calendar/tests/run.sh
```

It runs `calendar-sync` on `tests/fixtures/sample.ics` (placeholder data only) with stub `rbw` and `qs-ipc` on `PATH`, so it never reaches a real vault, feed or bar. `just check` runs it when `python-icalendar` and `python-recurring-ical-events` are installed.
