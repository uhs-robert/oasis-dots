# Notifications

`notifications/` holds `NotificationState` (history, toasts, Do Not Disturb), its IPC handler, `NotificationMarkup.js`, the notification center popup with its header button and cards, and the toasts with their card.

Notification history is kept in memory only (the last 100) and is gone when the shell restarts. The Do Not Disturb flag is saved as `{ "dnd": true }` in `notifications.json` in the Quickshell state folder (`$XDG_STATE_HOME/quickshell/`, default `~/.local/state/quickshell/`).

`qs-ipc call notifications history <count> <app>` prints that history as a JSON array, newest first: the newest `count` entries (`0` or less for all), only those from `app` when it is not `""`. Each entry is `get_last`'s fields plus the time it arrived, its urgency and whether the center has been opened since:

```json
[{"time": "2026-10-12T14:03:07.512Z", "app": "voxcmd", "summary": "voxcmd failed", "body": "Lock", "icon": "", "urgency": "normal", "read": false}]
```

Transient notifications (`notify-send --transient`) are shown as toasts but never kept, so the history holds only notifications sent without that hint; voxcmd, for one, sends only its errors that way. Notifications an app closes or replaces leave the history too.

## Toasts

`NotificationToasts.qml` shows the newest five toasts at the top right. With the frame on, the screen is the one focused when the stack opens and stays through the show; floating cards follow the focused screen.

- **Frame on:** the stack is one drawer (`ui/frames/TransientDrawer.qml`, pocketed against the right band) that grows to the stack's height over 190 ms and folds over 120 ms. A card added or removed, or one arriving mid-fold, retargets the same depth (`Behavior on extent`) rather than restarting it. Cards take no arrival art (`in_drawer` in `NotificationToastCard.qml`), fade out when closed, and share the drawer's material, split by a rule. The window is five tall cards deep, or what the frame leaves; a stack taller than that clips its last card and drops none. It may overlap the OSD at the top right, with no offset. A switch of the frame or the bar edge while shown restarts the drawer from closed.
- **Frame off:** floating cards at 8 px from the corner, each with its own arrival and fade, as before.
- **Input:** the window's mask is the drawer body, so clicks and hover reach the cards while the rest of the window is click-through. Cards slide under a still cursor while the drawer moves, so hover is ignored then and settled once afterwards (`ToastExtent.hover_action`): a card still hovered pauses its countdown, and one the cursor has left resumes it from the full interval.
- **Keys:** `toast_focus` holds the keyboard only while the window is shown; the fold ends it.
