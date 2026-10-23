# Bar

`bar/` holds the bar and its islands (`Island.qml`, with the one-polygon shapes' geometry in `ui/frames/IslandOutlines.js`), the submap and voice-mode tabs, the hot corner, one file per module in `modules/`, `BarSettings` with `BarLayout.js` and `BarModules.js` (the layout and module registry), `LualineState`, `SubmapState`, the command-status state and IPC handler, the badged glyph and done/wait pulses the modules draw, and the neovim style's mode chip, buffer line, lualine sections and window segment in `neovim/`.

## Island shapes

Settings > Theme options > Island shape (`bar_island_shape`) picks the islands' outline. Slant, octagon, watch, window, capsule and visor have their own layers in `Island.qml`; chevron, lean, hex, ticket, tab, pixel, notch and rect (square corners) are each one polygon from `IslandOutlines.js`, which gives an open end's profile from the screen edge to the open edge and derives the fill, the rim (inset by half the border, open on the screen edge and on an end flush with the screen's side) and `fill_span`'s clipping from it. None, underline and brackets (`IslandOutlines.stroke_only`, `Style.island_filled`) draw no plate: `Island.qml` skips the fill, shade, slant caps, dither and scanlines (`filled`), `cap_width` is only a content pad, and underline and brackets add one stroke layer in `border_color`, mirrored under a bottom bar. A popup or tab hung from such an island keeps the style's bar colour. A new outline shape is a profile and a `cap_width` there, plus its entries in `Style.island_shapes`, `island_shape_kits` and `borrow_names`.

Full bar (`full`, whose kit sets `strip: true`, so `Style.strip_shape`) draws one strip across the bar instead: `Bar.qml` loads `StripBackground.qml` under the islands, which draw as `none` (`Style.island_plate` is false) and take `Style.strip_color` (`bar_side_bg`), so popups, tooltips and the submap tab hung from them match the strip. The strip is a `BandFill.qml`: fill at Island opacity with the frame shade always running from the screen edge to the open edge, dither, scanlines, an inset line and the rim in the bar border colour, its geometry in `BandGeometry.js`. Neither knows the bar: a band is drawn in the top-bar frame along any screen edge (`band_frame`, `band_affine`), with insets where the rim and inset line stop, pattern phases and an ornament slot, which the screen frame uses. A style's tick scale (`bar_ticks`) stays per island, and no dividers mark the islands' ends.

## Screen frame

Settings > Theme options > Screen frame (`screen_frame`, one of `Style.screen_frames`: Off, or the corner profile Round, Chamfer, Pixel or Square) draws bands in the strip colour round the screen's other edges, joined to the bar, with a hole in that profile the windows tile in; a screen with the bar off gets four bands. Every style defaults to Off; lualine styles and terminal (`screen_frame_offered: false`) do not offer it. While a kit applies (`Style.screen_frame_kit`, read from `Style.active`, so the style picker previews it), `Style.active` lays the full bar's tokens over the saved shape, the Island shape row shows "Full bar (frame)" and is locked, and the saved shape returns when the frame goes.

- `ui/frames/FrameGeometry.js` (with `BandGeometry.js`, `Corners.js`, `DrawerGeometry.js`, `IslandOutlines.js` and `DrawerShape.qml`, which moved there so a drawer outside `bar/` imports no sibling feature) holds the outline, all in one canonical frame: the bar's band frame (u along the bar's edge, v away from it; a bottom bar mirrors v). `frame_layout` gives the hole (`near`/`far`, `start`/`end`, the clamped radius), each edge's exclusive zone, the `straight` stretch of the near edge and the `overlap` (how far the fill reaches up under the strip; 0 under translucent islands); `hole_path`, `frame_region`, `frame_stroke` and `frame_blocks` give the outline, the fill, the rim's path and disjoint rectangles for dither and scanlines; `stroke_clip_top` is where the frame window's copy of the rim starts, above its fill's top so a frame window stacked over the strip does not cover the corners' rim with that overlap. Its tests are in `tests/island_shapes.js`.
- `ScreenFrame.qml`, per screen in `shell.qml`: one full-screen click-through window (`quickshell-frame`, ignoring zones) draws every band but the bar's, flat in the strip colour, filling only past the strip's open edge so translucent bands never overlap the strip; four 1x1 windows (`quickshell-frame-zone`) reserve the edges, the bar edge at the bar's height, and the bar window reserves nothing (zone -1), so the zones add up the same in any layer order.
- The rim and inset line run on round the hole: the strip's stop at the corners (`StripBackground`'s `frame`), and `FrameStrokes.qml` draws the rest in both windows, each clipped to its side of the join. The whole line, the strip's straight part and the hole's corners and sides alike, is at the bar's border width and switches together with focus (`Style.screen_frame_rim_color`, `screen_frame_inset_color`): the bar's colours on the focused monitor, mixed most of the way into the strip on the others (a screen with the bar off included), with a 200 ms colour animation as focus moves. Dither and scanlines tile from the canonical origin, so they run on across the join.
- The side islands sit `start`/`end` in from the screen's sides (`Bar.qml`'s `frame`), where the side zones put the side popups. `PopupScrim` spans the bands too, with the bar's rect cut out of its input, so a click on a band closes an open popup.
- `ScreenFrameSync.qml` sends the profile, the drawn radius, the rim width and the rim's focused and dimmed colours to Hyprland's `ScreenFrame.set` (`ScreenFrame.clear` for no frame; `home/hypr/.config/hypr/config/general/frame.lua`), so windows follow the frame: round is the radius less `gaps_out`, square is 0, chamfer and pixel are a named window rule (`rounding_power` 1, rounding twice the chamfer leg shrunk to stay concentric) toggled with `set_enabled`, so open windows update; the borders take the rim width and colours. frame.lua keeps the user's rounding, `rounding_power`, border size and colours to restore, and restores them on its own when the `quickshell-frame` layer has been gone for about 6 s. A Hyprland reload resets the config and the Lua state, and Quickshell sends again on `configreloaded`.
- `ScreenFrames.qml` (singleton) gives each screen's layout by `layout_for(screen)`, which `shell.qml` and, later, drawers use. `FrameGeometry.hole_rect` and `seam_of` give the hole as a screen rect and its edge on each side.

### Corner profiles

The Screen frame choice (`Style.frame_corners`) also picks how the hole's corners and every drawer's fillets and free corners are drawn: `round`, `chamfer` (a diagonal, at most 12 px), `pixel` (a stair, at most 18 px) or `square`. A style's `screen_frame_corners` token is only a hint (gameboy pixel, tie chamfer, reticle square) that decides what an older saved "plain" frame becomes (`OptionMigrations.js`, options_version 3). `Corners.js` is the one place that draws a profile (`corner_points`) and fits it to its room (`fit`: the pixel radius is a whole number of whole-pixel steps, its step is the style's `screen_frame_step`, 2 for gameboy, and grows when a stair would pass eight steps; a corner too small for one step is square). `Style.screen_frame_profile` hands `{ corner, radius, step }` to `ScreenFrames.layout_for` and to each drawer's `drawer_layout` spec; a spec without `corner` is round. A pixel drawer rounds its body up and its extent to whole pixels so every stair lands on a pixel. The radius caps keep a window's corners inside the cut; Hyprland has no stair, so pixel frames get chamfered windows.

`FrameExport.qml` writes the drawn corner to `frame.json` in the state dir, and `scripts/frame-app-corners` turns that into yazi's border (`~/.config/yazi/frame-border.lua`: round is `rounded`, the rest `plain`, since a stair or chamfer has no Yazi border) and each Firefox profile's `chrome/frame.css` (`--tf-rounding`, plus, for a chamfer, a painted bevel over each corner of TextFox's panes (never a clip, which would cut the URL bar's results)). Both apps read them at start-up only; a failed generator run is logged as a `console.warn`.

Firefox setup (any profile): set `toolkit.legacyUserProfileCustomizations.stylesheets` to true in `about:config`, then add `@import url("frame.css");` to `<profile>/chrome/userChrome.css` after any other `@import` and before the first style rule (Firefox silently ignores an `@import` that follows a rule; a missing `frame.css` is ignored). `frame.css` only sets `--tf-rounding` (the variable Textfox's `defaults.css`/`config.css` use for window rounding), so a profile without Textfox also needs a rule that reads it, for example `#navigator-toolbox, #browser { border-radius: var(--tf-rounding, 0); overflow: clip; }`. The generator finds each `*.default-release` profile (creating its `chrome/` if absent) under `~/.config/mozilla/firefox` and `~/.mozilla/firefox`; for other profiles set `FIREFOX_CHROME_DIRS` (colon-separated chrome directories) in the environment the bar starts with.

### Drawers

Bar-hung popups, the docked pickers, the which-key HUD and the OSD use these with the frame on (see popups/README.md "Frame drawers"). `ui/frames/DrawerGeometry.js` and `DrawerShape.qml` draw a surface that grows out of the frame's edge, in the frame's material, in the surface's own window. The shape is drawn in a band frame: u along the attached edge, v away from the window's edge, which sits `cover` px out in the band (`cover_depth`: the rim and inset line's depth plus a pixel) so the drawer paints over the frame's line along its mouth and the seam is at v = cover; `band_affine` places it on any edge. Each end is a `fillet` (a concave arc where the drawer meets the band it hangs from) or a `pocket` (fills the hole's corner and runs flush down the side band, with the arc where its far edge meets that band). The surface keeps its full size and only the shape follows `extent`; at 0 it is the cover strip, which looks the same as the band. The rim and inset line are the frame's, open on the attached side and `LEAD` px longer than the arcs so a window a fraction of a pixel off reads as a fuller line. `body_rect` is the part that takes input. `end_kinds`, `place` (anchors and integer margins against the seam) and `window_rect` are shared by every drawer window; `DrawerWindowPublisher.qml` keeps its translucent window rect in `ScreenFrames.drawer_windows`. `ui/frames/TransientDrawer.qml` bundles all of that (layout, placement, shape, the 190 ms open and 120 ms close animations, `extent` in pixels) for the OSD and the which-key HUD; each keeps its window's anchors, lifecycle and publisher. The frame's dither and scanlines (`Style.dither`, `Style.bar_scanline_color`) run on across the join: `DrawerShape` tiles them from the drawer's place in the frame's canonical frame (`texture_origin`, `BandGeometry.phase_wrap`) and cuts them to the fill row by row (`fill_row_spans`). Its tests are in `tests/drawer_shapes.js`.

## Island fills

Every island fill (the base colour, shade, dither, scanlines and the lualine sections) goes through `Style.island_fill`, which applies Settings > Theme options > Island opacity; module content, borders, rims, insets and ticks do not. Below 100% (`Style.islands_translucent`) no pixel may be filled twice, because each fill fades on its own and stacked ones show darker. So `Island.qml` drops the 1px overlap between caps and body, the frame fill drops its 1px overlap under the strip (`ScreenFrames.qml` passes `fill_overlap` 0), and under lualine the island fills only behind modules that set no `lualine_fill` of their own, section c stops at the islands' caps, and the mode chip, buffers and sections draw each arrow as two colours side by side instead of one over the other. At 100% the overlapping opaque geometry, which hides fractional-scaling seams, is kept. A new fill follows the same rule.

## Bar layout

`bars.json` is a JSON array of rules. The first rule that matches a monitor decides its bar, and a monitor no rule matches gets no bar (the log says so). The tracked file ships one `"*"` rule. Edit it live, the bar reloads on save, and a broken file keeps the last good layout (if it is broken when the shell starts, there is no last good layout, so a minimal bar with workspaces, clock and tray shows and a notification names the error, until you save a valid file).

| Key | Meaning |
| --- | --- |
| `match` | `"*"` for every monitor, or `{ "name": "DP-*", "description": "*Dell*" }`. Both keys are optional globs (`*`, `?`) and must all match. `{}` or any string other than `"*"` never matches. `name` is the connector, `description` is Hyprland's monitor description (`hyprctl monitors`) |
| `compact` | Tighter bar that hides every `system` module. Defaults to false |
| `height` | Bar height in pixels. Defaults to the style's bar height, else 34 |
| `position` | Screen edge the bar sits on: `"top"` (default) or `"bottom"`. A bottom bar mirrors its islands' decoration and its popups, tooltips and submap tab rise from it; the OSD moves to the top (a frame drawer on the edge opposite the bar) and the hot corner to the bottom-left. `"left"` and `"right"` are reserved for vertical bars and fall back to top with a warning, as does any other value |
| `bar` | `false` shows no bar on matching monitors |
| `left`, `center`, `right` | Module names, in draw order. Repeats within one list are dropped (a module in both `left` and `right` draws twice), unknown names are skipped with a warning. Lualine styles draw `center` inside the right island and re-sort it with `right` into their x/y/z sections, so the listed order only holds within a section |

Modules (the registry is `features/bar/BarModules.js`): `start` (Start button), `workspaces`, `clock` (calendar popup), `tray`, `volume`, `battery`, `bluetooth`, `network`, `weather`, `keeptabs` (optional: needs the keeptabs tools in `~/.local/bin` and, for its usage tab, the `claude` CLI; shows AI agent sessions busy, done or waiting and jumps to one; hidden while none run or when keeptabs is not installed, and removable from `bars.json`), `cmdstatus` (status pills from your own commands, see Command status below; hidden without any), `updates` (pending package updates), `voxtype` (dictation status; its tooltip gives the exit hint while a voxcmd voice session is open), `recording` (screen recording chip), `notifications` (center and Do Not Disturb), `media` (now playing, not in the default layout) and `system`. `system` takes an argument, `system:cpu`, `system:memory` or `system:temperature`, and can be listed more than once with different arguments; bare `system` starts on `cpu`.

The Hyprland submap shows as a dropdown tab (`SubmapTab.qml`) under the center island, or, with the screen frame on and a center island, as a chip beside the clock in it (a frame with no center modules keeps the tab); both show on the focused monitor only, and lualine styles keep their mode chip. The tab and chip stay hidden for the which-key delay after a submap is entered (`HyprInputSettings` `which_key_delay_ms`, 0 when unset), so they do not flash before the HUD; they hide the moment the HUD opens and return 250 ms after it closes (`SubmapState.indicator_shown`, fed from the HUD's `visible` in `shell.qml`).

While a voxcmd voice session is open (`$XDG_RUNTIME_DIR/voxcmd/session.json`, ignored once its owner process is gone), the current mode (rapid, click, type...) hangs from the center island as a tab beside the Hyprland submap tab, tinted per mode `kind` from the theme's submap palette (`features/voice/VoxSessionState.qml`). Its text is the file's `label`; the `voxtype` tooltip shows its `exit_hint`.

While voxcmd's wake word listener holds the microphone (`$XDG_RUNTIME_DIR/voxcmd/wake.json` says `armed`; `voxcmd wake on` in the voxcmd README), the `voxtype` module shows a small dot beside its icon in the theme's secondary colour and its tooltip reads "Listening for \"Cortana\"" (`features/voice/VoxWakeState.qml`). It is deliberately not the recording pulse or colour: it shows only while voxtype is idle, and goes when the listener is off. While it is paused (`paused` in the file, with a `reason` naming the check that paused) and voxtype is idle, the dot stays but dimmed, and the tooltip says why: \"Wake word paused: another app is using the mic\" (`mic_in_use`), \"...: media is playing\" (`media_playing`) or \"...: a voice command is running\" (`voxtype_recording`, `session_open`); a missing or unknown reason reads \"Wake word paused\". When the file says `ready` (the listener's trigger started a recording and voxtype reports `recording`), the dot turns the theme's `ok` colour and blinks three times as the cue to speak, then clears with the recording.

```json
[
  { "match": { "name": "eDP-*" }, "compact": true, "left": ["start", "workspaces"], "center": ["clock"], "right": ["volume", "battery"] },
  { "match": { "description": "*DELL U2720Q*" }, "height": 40, "left": ["start", "workspaces", "media"], "center": ["clock"], "right": ["tray", "network"] },
  { "match": "*", "left": ["start", "workspaces"], "center": ["clock"], "right": ["volume"] }
]
```

Settings > Bar modules edits the layout without touching the tracked file. It saves to `quickshell/bars.json` in the state folder (see [Settings panel](../settings/README.md)), with three kinds of override over the matching rule:

- `shared` applies to every monitor without its own layout. `place` maps a module to `left`, `center`, `right` or `hidden`, and `order` lists modules that swap among the slots they already fill on each side, and the rest do not move. `position` (`top` or `bottom`, set by the Position row with All monitors as the target) is the global position: it applies to every monitor, own layout or not, and wins over the rule's `position`.
- `monitors` holds one full `left`/`center`/`right` layout (and `compact`) per monitor, keyed by `<description> @ <connector>`, or by the connector alone when the monitor has no description. After a connector change, the only saved key with the same description is reused. It replaces the rule's lists outright, so later edits to the tracked file no longer reach that monitor. `height` and `bar` always come from the rule.
- `positions` maps a monitor key (as in `monitors`) to `top` or `bottom`, set by the Position row with that monitor as the target and applied over the global position and the rule's `position`. It is kept apart from `monitors`, so a monitor needs no layout of its own to move its bar, and turning Own layout on or off leaves its position alone.

A bar's position is therefore the monitor's entry in `positions`, else `shared.position`, else the rule's `position`, else `top`. The Position row names what a value follows when it is not saved at that level, as in `bottom (global)`, `top (bars.json)` or `top (default)`; `x` on the row forgets the saved value after a `y`/`n` prompt naming what the bar will follow, so a monitor follows the global position again and All monitors follows `bars.json`.

Delete the state file to go back to the tracked layout.

## Command status

The `cmdstatus` module shows a small pill per command you declare in `custom/command-status.json` (gitignored, see `custom/README.md`), so a machine-local tool can put its state on the bar without living in this repo. It sits after `workspaces` in the left island of the default layout and draws nothing until the file has an entry. A monitor with its own layout in Settings > Bar modules needs it added there.

```json
[
  { "id": "timer", "command": "~/.local/bin/timer-status", "interval": 10, "on_click": "~/.local/bin/timer-toggle", "on_right_click": ["xdg-open", "https://example.com"] }
]
```

| Key | Meaning |
| --- | ------- |
| `id` | Unique name; the tooltip title and the IPC handle |
| `command` | A string run through `sh -c` (so `~` and pipes work), or an argv array |
| `interval` | Seconds between runs (default 30). `0` runs once when the module appears, then only on a click or IPC refresh |
| `on_click`, `on_right_click` | Optional commands for left and right click; the status command reruns once they exit |

The command prints one line of JSON (the last line counts):

```json
{ "text": "1:24", "tooltip": "Running since 09:10", "class": "active", "hidden": false }
```

`class` is `idle` (bar text color), `active` (primary), `warn` or `error`, and anything else reads as `idle`. `hidden: true` drops the pill until the next run says otherwise. A non-zero exit or output that is not a JSON object shows an alert glyph in the error color, with the exit code and the last lines of stderr, or the parse error, in its tooltip. Text is plain, not markup.

Commands run asynchronously and only while a `cmdstatus` module is on a bar. A run still going when the next one is due is skipped, so a slow command never stacks up. The file is watched, so edits apply at once. After changing state from a script, `qs-ipc call cmdstatus refresh <id>` reruns that entry now instead of waiting for its interval.

## Tools

Everything here is optional; a missing tool only disables the feature next to it.

| Tool | Used for |
| --- | --- |
| `keeptabs-status` (keeptabs) | The `keeptabs` module |
| `voxtype` | The `voxtype` module and dictation overlays |
