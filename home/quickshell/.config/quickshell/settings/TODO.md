# Settings panel roadmap

Tracks the Settings panel that drops from the center island (issue #361). Update the checkboxes as work lands so it can be resumed later.

## How it fits together

- `SettingsPopup.qml` is the panel: a grouped sidebar plus a pane that lazily loads one section.
- `Sections.js` is the registry. A new section is one file under `sections/` plus one entry there.
- `SettingsPane.qml` is the section base; `RowsSection.qml` + `ChoiceRow.qml` give declarative `h`/`l` choice rows.
- `SettingsNav.open(id)` and `qs-ipc call settings open <id>` deep-link to a section.
- Keys: sidebar `j`/`k`, `l`/`Enter` into the pane; pane `j`/`k` rows, `h`/`l` change; `Esc` back; `/` find; `q` close.

## Decisions

- UI edits go to state files under `~/.local/state/`, never to tracked config. They override the tracked defaults.
- Monitor UI state wins over the machine's `<hostname>.lua` profile.
- Display changes auto-revert unless confirmed within a countdown.
- Monitor arrangement is keyboard-first: `hjkl` nudges the selected monitor and snaps to edges; mouse drag is secondary.
- Theme options and theme audio come from a per-style `settings: [{ key, type, default }]` schema, rendered generically.

## Step 1: panel shell (done)

- [x] Panel, sidebar, pane loader, section registry, deep-link IPC
- [x] Style section (moved from the Start menu's Style popup)
- [x] Lock screen section (screen, tint, backdrop, music, preview)
- [x] Login screen section (follow or override the lock choices, music, session, sync), saved to `greeter.json`
- [x] Start menu "Settings" row and leader `S` open the panel
- [x] Live test on the bar and fix what turns up
- [x] Review findings resolved, PR merged
- [ ] Optional: move lock settings out of `style.json` into their own state file

## Step 2: bar modules

- [x] State file `state/quickshell/bars.json` merged over the tracked `bars.json`
- [x] Module visibility toggles
- [x] Module reordering (left, center, right)
- [x] Per-monitor bar overrides
- [ ] Live test on the bar (rebuild on edit, monitor targeting, own layout on and off)
- [ ] Edit the `compact` flag per monitor; the override only seeds it
- [ ] Add and remove module arguments (`system:temperature`); entries with arguments are only listed once a rule or the state names them

## Step 3: displays

- [ ] Monitor state file read by `hypr/config/monitors/init.lua`, winning over `<hostname>.lua`
- [ ] Live apply through `hyprctl` with a keep-or-revert countdown
- [ ] Resolution, refresh rate, scale, orientation, enable/disable
- [ ] Visual arrangement: `hjkl` nudge, edge snapping, mouse drag secondary

## Step 4: system

- [ ] Default applications and XDG associations (`xdg-mime`, `~/.config/mimeapps.list`)
- [ ] Power and session configuration (decide how `hypridle.conf` is generated or templated)

## Step 5: themes

- [ ] Per-style `settings` schema in `Style.qml`
- [ ] Theme-specific settings section rendered from the schema
- [ ] Theme audio configuration
- [ ] Color scheme selection
