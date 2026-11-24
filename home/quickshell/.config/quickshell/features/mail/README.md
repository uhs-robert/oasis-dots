# Mail

The `mail` bar module shows how many unread messages Thunderbird holds. A badge on a mail glyph gives the total. Hover it for the folders behind the count, or right-click to check again now. It draws nothing while nothing is unread, and nothing while Thunderbird or its bridge is off.

The pill and its tooltip show counts only. Sender and subject appear only in the hover popup, and only when you turn on Settings > Mail > Show headers (off by default).

## Set up

1. Install the DesertFox command line (`just desertfox-host`) and DesertBird in Thunderbird.
2. In DesertBird's options turn on `bridge` and `bridge_share_folders`. Both are off by default.
3. Add `mail` to the bar in the bar editor. The default layout leaves it out, because new mail already raises a notification. Without the pill, `SUPER + B` then `E` still opens the popup.

The module runs `desertfox --app thunderbird mail folders --json` once a minute and when its popup opens. A bridge that answers but refuses (a share setting is off) shows a warning badge, and its tooltip and the popup give the bridge's message. No `desertfox`, an older one without the mail commands, Thunderbird closed and the bridge off all leave the module hidden.

Gmail's `[Gmail]/All Mail`, `Important` and `Starred` (also under `[Google Mail]`) are always left out, since they repeat the inbox's messages. Gmail label folders still count a labelled unread message once for each label and once for the inbox, so a Gmail account with labels can show a total above its real unread count.

Trash and junk folders are left out of the count by default. Settings > Mail changes that and the interval (see [settings](../settings/README.md#mail-settings)).

## Popup

One row per folder with unread mail: its path, its account and its count, at most twelve. `j`/`k` move, `r` checks again, `/` searches, `q` closes.

Two buttons change only what Thunderbird shows: `i` (Inbox) opens the Inbox and `u` (Next unread) steps to the next unread message, going on to another folder when this one has none left. It selects a message, so Thunderbird's own setting for marking a message read when it is selected can mark it read, as `]U` does in DesertBird. Each raises the Thunderbird or Betterbird window first and then runs the command through the bridge. Nothing marks, moves, deletes or replies to mail.

With Show headers on (it also needs `bridge_share_headers` in DesertBird), the popup lists the newest five unread messages of the folder under the cursor: subject, sender and date, as plain text cut short. They are fetched when the popup opens or the cursor moves to another folder, never on a timer. They are not fetched, and any already shown are dropped, while a recording or screen share runs or the screen is locked.

## Code

- `MailState.qml`: the singleton that polls the command and holds the state (`ok`, `refused` or `unavailable`), the folders and the total.
- `MailParse.js`: strips the `<<<UNTRUSTED ... nonce=...>>>` envelope the command wraps around its output (the last line must carry the first line's nonce), validates and cuts each folder, turns an exit code into a state, and filters trash and junk. Tested by `tests/mail_parse.js`.
- `MailSettings.qml`: `mail.json`, the interval and the skipped folders.
- `MailPreviewState.qml`: the headers of the cursor folder, fetched on demand and gated by `MailParse.preview_allowed`. `MailActions.qml`: the two buttons (focus the mail window, then `run folder.open --special=inbox` or `run step.unread --next --all-folders`).
- `MailPopup.qml`: the folder list, the headers and the buttons.
- `../bar/modules/Mail.qml`: the bar pill. `../settings/sections/MailSection.qml`: the settings page.
- There is no unread event on the bridge, so this polls; a shorter interval makes Thunderbird read every folder's counts more often.
