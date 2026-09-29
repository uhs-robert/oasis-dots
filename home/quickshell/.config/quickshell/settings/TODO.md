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
- [x] PR merged (two review findings still open, below)
- [ ] Move lock settings out of `style.json` into `lock.json`, migrating current values on first load (bar fixes track)

## Step 2: bar modules (done)

- [x] State file `state/quickshell/bars.json` merged over the tracked `bars.json`
- [x] Module visibility toggles
- [x] Module reordering (left, center, right)
- [x] Per-monitor bar overrides
- [x] Live test on the bar (rebuild on edit, monitor targeting, own layout on and off)
- [x] PR merged (two review findings still open, below)
- [ ] Edit the `compact` flag per monitor; the override only seeds it
- [ ] Add and remove module arguments (`system:temperature`); entries with arguments are only listed once a rule or the state names them
- [ ] Re-test on the bar after the review fixes: hide/show keeps position across a restart, lualine (neovim style) reorders within x/y/z only
- [ ] Fix first (open Codex findings): shared J/K on a monitor whose rule lacks some modules (the HP Z22n has no weather/volume/battery) pushes those modules to the end of the other monitor's bar. `order_from` in `BarLayout.js` should merge the edited view into the old order without relocating entries absent from the view
- [ ] Fix: `resolve_key` drops a stale override when its old connector is now used by a different monitor; only reserve a key when that connector holds a live screen with the same description

## Next up (resume here)

State on 2026-09-29: steps 1 and 2 merged (#366, #368). Step 2 merged with two open Codex findings, listed under step 2; fix those first.

Plan for the next session, all decided, no open questions: run four tracks in parallel, each in its own worktree off `main`. Each branch gets a review and a Codex pass, then a live test on the bar one at a time, and merges only after that test.

1. Bar fixes: every open step 2 item (the two findings, per-monitor `compact`, module arguments, then the re-test) plus moving lock settings into `lock.json` (step 1 list). Goes first, before Themes touches `Style.qml`; the other branches rebase on it.
2. Displays (step 3).
3. System (step 4).
4. Themes (step 5).

Answers given for these tracks:

- Displays: keep-or-revert countdown is 15 seconds.
- Color scheme: the Oasis palettes, picked in a Settings Colors section with a live preview. A choice recolors everything through the existing pipeline (save, reload Hyprland, every generator reruns); the palette drives Quickshell's primary, secondary and other colors. The rofi switch (`theme/switch.lua`, Start right-click) stays as is.
- Theme audio covers lock/login music, UI sound effects (cursor, confirm, cancel), and notification sounds. Sounds are chiptune generated with sox per style and tracked in the repo, with a gitignored override folder for the user's own files.
- Theme-specific options: expose the per-style knobs that already exist in `Style.qml` (scanlines, glow, dither, fonts, effects); the user trims after testing.
- Power: idle timeouts (dim, lock, screen off, suspend; separate AC and battery), lid and power button actions, and the power profile on AC and battery.
- Default apps: one state file drives both `xdg-mime` associations and Hyprland's `Config.app` launch binds; it wins over `<hostname>.lua`, like monitors.

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
