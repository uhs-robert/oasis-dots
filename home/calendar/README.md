# calendar

`calendar-sync` keeps a local copy of your Google Calendar for the bar and voice commands to read. A systemd user timer runs it every 5 minutes. It reads your calendar's private iCal address, so it needs no OAuth and no Google Cloud project.

## Setup

```bash
calendar-sync setup
```

The guide walks you through it in a terminal:

1. It points you to Google Calendar > Settings > your calendar > Integrate calendar > "Secret address in iCal format" (the secret one, not the public one) and offers to open the settings page.
2. You paste the address with hidden input. It converts `webcal://`, requires https, then fetches and parses it and prints "Found N events in the next 60 days", or a clear error without the address, so you can retry.
3. You choose where to keep it. Only backends that work on your machine are listed; Enter picks Auto, the first of: rbw (installed and unlocked), the system keyring (`secret-tool`, with the default collection unlocked), or a private file at `${XDG_DATA_HOME:-~/.local/share}/calendar-sync/ical-url` (mode 0600 in a 0700 directory, refused inside a git work tree). A locked rbw is listed as locked and turns Auto off, so a lock never quietly sends the address somewhere weaker; unlock it and run setup again, or pick another. An existing rbw entry is updated in place with `rbw edit`, keeping its notes, and never removed. If an older copy of the address is left in another backend, setup says where and offers to delete the private file.
4. It writes `${XDG_CONFIG_HOME:-~/.config}/calendar-sync/config` with the matching `url_command`, asking before it replaces an existing one, and reads the address back through it to prove the round trip.
5. It enables the timer and runs the first sync.

Nothing is half-written if you press Ctrl-C: the address is stored first, then the config, then the timer. The installer offers to run it when you chose the `calendar` package.

The package is optional: the installer enables the timer only when you chose `calendar` (or ran `just stow calendar` before it). To enable it by hand: `systemctl --user enable --now calendar-sync.timer`.

## Advanced: url_command

`setup` writes this for you; to do it by hand, create `${XDG_CONFIG_HOME:-~/.config}/calendar-sync/config` with a command that prints the address on stdout. Blank lines and lines starting with `#` are ignored. The file holds a command only, never the address, and is not part of the stow package.

```ini
# pick one
url_command = rbw get -- google-calendar-ical
url_command = pass show calendar/google-ical
url_command = secret-tool lookup service calendar-sync key ical-url
url_command = op read "op://Personal/Google Calendar/ical"
url_command = cat ~/.local/share/calendar-sync/ical-url
```

The last one is the file `setup` creates; keep such a file `chmod 600`, outside `~/.config` (which may be a stow link into a checkout) and outside every repo.

The config is trusted like a script: before running it, `calendar-sync` requires that the file and its directory belong to you, are not writable by group or others, and are not inside a git work tree, and otherwise refuses with an error in `error.json`.

The command runs through `sh -c` with no terminal, no stdin and its stderr discarded, and gets 20 seconds. A non-zero exit, empty output or a timeout counts as "not configured": the timer stays silent and `calendar-sync --now` prints a hint. The command therefore must not prompt: it has no terminal, but an agent-based manager can still pop a graphical pinentry, and the timeout only bounds the wait, so keep the manager unlocked. A command that starts with `rbw` (leading `VAR=value` words are skipped) gets an `rbw unlocked` check first. One that starts with `secret-tool` gets a check of the default keyring collection's `Locked` property over D-Bus (`busctl`, else `gdbus`); a locked or unreachable keyring is skipped quietly, so the keyring must be unlocked at login (for example by PAM) for the timer to use it. The command's output is capped at 64 KiB, and the unit has `TimeoutStartSec=2min` as a last bound.

Without a config the command is `rbw get -- google-calendar-ical`.

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

It runs `calendar-sync` on `tests/fixtures/sample.ics` (placeholder data only) with stub `rbw`, `secret-tool`, `systemctl`, `xdg-open` and `qs-ipc` on `PATH`, so it never reaches a real vault, feed or bar. `just check` runs it when `python-icalendar` and `python-recurring-ical-events` are installed.

`calendar-sync setup` is driven in tests through `CALENDAR_SYNC_SETUP_ANSWERS`, a file with one answer per line that replaces the terminal. It is for tests only; prompts are still printed and answers never are.
