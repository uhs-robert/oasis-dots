# Notifications

`notifications/` holds `NotificationState` (history, toasts, Do Not Disturb), its IPC handler, `NotificationMarkup.js`, the notification center popup with its header button and cards, and the toasts with their card.

Notification history is kept in memory only (the last 100) and is gone when the shell restarts. The Do Not Disturb flag is saved as `{ "dnd": true }` in `notifications.json` in the Quickshell state folder (`$XDG_STATE_HOME/quickshell/`, default `~/.local/state/quickshell/`).

`qs-ipc call notifications history <count> <app>` prints that history as a JSON array, newest first: the newest `count` entries (`0` or less for all), only those from `app` when it is not `""`. Each entry is `get_last`'s fields plus the time it arrived, its urgency and whether the center has been opened since:

```json
[{"time": "2026-10-12T14:03:07.512Z", "app": "voxcmd", "summary": "voxcmd failed", "body": "Lock", "icon": "", "urgency": "normal", "read": false}]
```

Transient notifications (`notify-send --transient`) are shown as toasts but never kept, so the history holds only notifications sent without that hint; voxcmd, for one, sends only its errors that way. Notifications an app closes or replaces leave the history too.
