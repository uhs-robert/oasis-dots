# Clock and calendar

`clock/` holds `TimeFormat`, the clock and calendar settings, state and IPC, `Timezones`, the clock popup with its per-style status clocks in `views/`, and the meeting markers in `markers/`.

The clock shows your Google Calendar from a cache that `calendar-sync` writes to `$XDG_CACHE_HOME/calendar/events.json` (default `~/.cache/calendar/`); the shell never talks to Google. With no cache file nothing changes: no countdown, no dots, no timer, and the popup has no dots or agenda. The service (`features/clock/CalendarState.qml`) reloads when the file changes, and `qs-ipc call calendar refresh` rereads it at once (a file that did not exist when the shell started is only noticed through that call or a restart). Cancelled events are ignored, and so are timed events over 12 hours for the chip and dot (out-of-office and conference blocks). The `join_url` field of an event holds a Google Meet or Microsoft Teams link. If `error.json` sits beside the cache, the events are the last good copy and the agenda header says so.

- Bar clock: within 15 minutes of the next meeting's start (even across midnight), a hollow dot and the minutes left (`12m`) follow the date; while a meeting is in progress the dot is solid. Hovering shows the current or next event and its time. All-day events never count as meetings.
- Clock popup: a dot under each day with events, and below the grid an agenda for the selected day (today by default). Event times follow the zone the popup is cycled to (as does the clock tooltip); events stay grouped by your local day.

Settings > Calendar shows whether `calendar-sync` is connected and when it last synced. Enter offers Connect (or Reconnect), which opens your terminal on `calendar-sync setup`, and Sync now. The row asks `calendar-sync setup --check` once when the section opens, never on a timer, so a locked rbw or keyring shows as such without being prodded repeatedly.

## Clock popup keys

The popup has two levels, both fully keyboard driven. At the grid level the cursor day's agenda is a read-only preview.

| Grid level | |
| --- | --- |
| `h` / `l`, `Left` / `Right` | Cursor day, back or forward one day (the shown month follows past its edge) |
| `j` / `k`, `Down` / `Up` | Cursor day, forward or back one week |
| `H` / `L`, `J` / `K` (Shift) | Month, then year; the cursor keeps its day of the month |
| `Enter` | Open day level for the cursor day (with a cache; an empty day shows "No events") |
| `n` / `N` | Jump the cursor to the next / previous day that has events, anywhere in the cache (does nothing past the last one) |
| `o` | Open the cursor day in Google Calendar's day view |
| `c` | Create an event on the cursor day |
| `t` / `gg` | Back to today |
| `Tab`, `[` `]` | Time zone |

| Day level | |
| --- | --- |
| `j` / `k`, `Down` / `Up` | Move between the day's events; the highlighted one is detailed below the list (time or "All day", title, location, organizer, guest count, "Tentative", and what Enter does) |
| `Enter` | Join the event's `join_url` (Google Meet or Teams), else open its Calendar page, else that day in Calendar |
| `Esc`, `h`, `Left` | Back to the grid, same day |
| `n` / `N` | Next / previous day with events; stays at day level and highlights that day's first open meeting |
| `o` / `e` | Open the highlighted event in Google Calendar to view it (its `event_url`) or to edit it (`.../r/eventedit/<eid>`, the `eid` taken from `event_url`); with no `eid` or no event both open that day's view |
| `c` | Create an event on that day: Google's form, in UTC, 9:00 to 10:00, or for today the next whole hour (9:00 tomorrow after 22:00) |
| `q` | Close |

Moving the cursor works without a calendar cache; the dots, the agenda and day level need one. Clicking a day equals moving to it and pressing Enter, and clicking an event highlights it, but nothing needs the mouse. `calendar open_day <date>` opens the popup at grid level on that date. The agenda area keeps one height across both levels and every day (the list shows eight rows at grid level and three beside the details at day level), so the popup never resizes.

When `events.json` carries `window_start` and `window_end` (the span calendar-sync fetched, end exclusive), days outside it are drawn faded and show "Not synced" instead of "No events", and `n`/`N` stay inside it; older caches without them dim nothing.

Links open with `firefox --new-tab`, or `xdg-open` when Firefox is not installed, and the script then focuses the Firefox window itself through `hyprctl`, since a launch without an activation token is not raised by Hyprland. Joining and creating share this path. Clicking a day selects it.

## Time zones

The calendar clock cycles through the local zone plus any listed in `quickshell/timezones.json`, for example `["America/Los_Angeles", "America/Denver"]`; there is no Settings page for it.
