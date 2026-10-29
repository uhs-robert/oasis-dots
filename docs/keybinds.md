# Changing keybinds

The keys this setup ships are defined in Lua under `~/.config/hypr/keymaps/`. Leave those files alone: your changes go in one file of your own, `custom/keymaps.lua`, which can add binds, replace shipped ones and define new [submaps](https://wiki.hypr.land/Configuring/Basics/Binds/#submaps). It is gitignored, so `git pull` never conflicts with it, and you can track it in a repo of your own. A shipped keymap file that fails to load costs only its own keys: the others load and one warning names the file.

## Finding what a key does

You rarely need to open a file to find a bind.

- `SUPER + /` searches every bind in the mode you are in and runs the one you pick. Submaps are listed first, each with a `+` in front of its name, so it doubles as a map of the submaps you can enter from here.
- `SUPER + SHIFT + /` opens which-key from anywhere, showing every bind in the current submap at a glance, or the global binds when you are in none.
- Entering a submap also shows its binds in which-key, except Windows, Resize, Move and Cursor: they show a compact hint bar of their main keys instead, and `?` there opens the full which-key list.
- Inside a submap, `?` hides or shows which-key without leaving it.
- In Windows, Resize and Move the keys act on the focused window, or on the selection: `SPACE` in Windows selects windows (a thick border in the theme's secondary colour, a number in selection order, "N selected" in the hint bar), and every Windows, Resize and Move key then acts on all of them. Each of the three switches straight to the other two (`w` Windows, `r` Resize, `m` Move), and the selection carries between them, through those keys and `BackSpace`, and clears when you leave them.

All of them read the description written next to each bind, so anything you add shows up in them too.

## Where the shipped binds live

Open these to see how a bind is written or which submap a key belongs to:

```
keymaps/
  init.lua             loads the two folders below
  global/              keys that work everywhere
    general.lua        windows, focus, scratchpad, monitors
    workspace.lua      workspaces
    shortcuts.lua      terminal, file manager, menus
    tools.lua          screenshots, voice, overviews
    pickers.lua        clipboard, emoji and directory pickers, HyprVim
    media.lua          volume, brightness, playback
    power.lua          lock, sleep, power
    mouse.lua          mouse binds
  submaps/             submaps: press one key to enter, then another to act
    leader/  apps/  go/  system/  delete/  windows/
    groups/  cursor/  resize/  move/  bar/
    bar/rows.lua       the popup keys, shared by Bar and Leader
```

Every key lives in these files. Most name an action by id, as `Act.bind("terminal.open", { key = ... })` or a submap row `{ "E", "files.open" }`; what an action does is defined apart, in `home/hypr/.config/hypr/lib/act/defs/`, so a key moves without touching the action.

A global bind fires the moment you press it. A submap is a separate set of binds: its entry key switches the keyboard into it, where plain keys such as `F` or `SHIFT + S` do things, and which-key lists those binds as you enter it. Each submap's name, which you need for changing it, is the `name` field at the top of its file: `System`, `Windows`, `Leader` and so on.

## Setting up your keymap file

`hyprland.lua` runs `custom/init.lua` last, after every shipped bind is registered. Load your keymap file from there:

```lua
-- ~/.config/hypr/custom/init.lua
require("custom.keymaps")
```

Then start `~/.config/hypr/custom/keymaps.lua` with the helpers the examples below use:

```lua
-- ~/.config/hypr/custom/keymaps.lua
local Bind = require("lib.key.bind")
local Submap = require("lib.key.submap")
local Hypr = require("lib.hypr")
local Terminal = require("lib.desktop.terminal")
```

Apply every change with:

```
hyprctl reload
```

## Key names

Keys are written as modifiers and a key name joined by ` + `, for example `"CTRL + SHIFT + ESCAPE"`. Key names are Hyprland's: letters and digits as they are, and names such as `RETURN`, `SPACE`, `TAB`, `SLASH`, `PERIOD`, `BRACKETLEFT`. A key tester such as `wev` (not installed by default) prints the name of any key you press.

## The leader key

Most global binds start with one modifier, the leader. It is `SUPER` by default. To change it for one machine, set it in that machine's profile:

```lua
-- config/machines/<hostname>.lua
return {
  leader = "ALT",
}
```

Every `Bind.leader_*` helper and every submap entered with `Config.leader .. " + ..."` follows it, yours included. See `config/machines/README.md` for how profiles work.

## Adding a bind

Pick the helper that matches what the key should do:

| Helper | Use it for |
| --- | --- |
| `Bind.leader_cmd(key, "command", "Description")` | A shell command, with the leader |
| `Bind.leader_fn(key, action, "Description")` | One of the built-in actions, with the leader |
| `Bind.cmd(key, "command", "Description")` | A shell command with no leader, so you write the modifiers yourself |
| `Bind.fn(key, action, "Description")` | An action with no leader |

For example, a calculator on `SUPER + F9` and a notes file on `CTRL + ALT + N`:

```lua
Bind.leader_cmd("F9", "qalculate-gtk", "Calculator")
Bind.cmd("CTRL + ALT + N", "kitty -e nvim ~/notes.md", "Notes")
```

The third argument is the description shown in search and which-key. The built-in desktop functions live in `home/hypr/.config/hypr/lib/desktop/`, one file per area (`window.lua`, `workspace.lua`, `apps.lua`, `terminal.lua`, `menu.lua`, `media.lua` and others), and `Hypr.exec` is in `home/hypr/.config/hypr/lib/hypr.lua`. The ones you will reach for most:

| Function | Does |
| --- | --- |
| `Hypr.exec("command")` | Runs a command |
| `Terminal.run("command")` | Runs it in your terminal |
| `Terminal.open()` | Opens your terminal |
| `Terminal.bottom("command")` | Runs it in a terminal that drops in at the bottom of the screen |

A bind that should also work while you are inside a submap passes its options in place of the description. This replaces the calculator line above, rather than adding to it:

```lua
Bind.leader_cmd("F9", "qalculate-gtk", { submap_universal = true, desc = "Calculator" })
```

## Changing or removing a shipped bind

Binding a key that is already bound does not replace it: Hyprland keeps both binds and runs both. So remove the shipped one first, then bind yours. To move the terminal from `SUPER + RETURN` to `SUPER + BACKSPACE`:

```lua
Bind.leader_unbind("RETURN")
Bind.leader_fn("BACKSPACE", Terminal.open(), "Terminal")
```

A shipped bind that runs an action has its id in the Id column of the [table below](#every-shipped-bind). Binding the id instead keeps the action's label and shows your key in `hypr-act list`:

```lua
local Act = require("lib.act")
Bind.leader_unbind("RETURN")
Act.bind("terminal.open", { key = { key = "BACKSPACE", leader = true } })
```

To drop a bind without replacing it, unbind it and stop there:

```lua
Bind.leader_unbind("CTRL + RETURN")   -- no more SSH picker on SUPER + CTRL + RETURN
```

`Bind.leader_unbind(key)` is `Bind.unbind("SUPER + " .. key)` with your leader in place of `SUPER`. Keys match the way they were bound, ignoring case and spaces. Both return how many binds they removed, so a `0` means the key was written differently or is not one of this config's binds. On Hyprland 0.56 and older an unbound key is disabled rather than removed, so it stops firing but still appears in `SUPER + /`; `custom/README.md` explains why.

## Changing a key inside a submap

Pass the submap's name to `Bind.unbind` to remove a key from that submap only; the same key in other submaps is untouched. Then add your own with `Bind.submap`, which adds to an existing submap:

```lua
-- In the Windows submap, H focuses left instead of what it did before.
Bind.unbind("H", "Windows")
Bind.submap("Windows", function()
  Bind.key("H", hl.dsp.focus({ direction = "left" }), "Focus left")
end)
```

Some submaps, such as Go and Leader, are one-shot: any key leaves them. A bind you add this way does not leave the submap on its own, so finish its action with `Submap.reset()`. To add a PDF viewer to the Go submap (`SUPER + G`) on `Z`:

```lua
Bind.submap("Go", function()
  Bind.key("Z", function()
    hl.dispatch(hl.dsp.exec_cmd("zathura"))
    Submap.reset()
  end, "PDF viewer")
end)
```

Submaps that stay active until you press `ESCAPE`, such as Windows, Resize and Move, need no `Submap.reset()`; each one's `catchall` field says which kind it is (see the table below).

## Defining a submap of your own

`Submap.define` builds a submap from rows of key, action and description:

```lua
Submap.define({
  name = "Notes",
  desc = "+Notes",
  enter = Bind.leader .. " + SHIFT + N",

  escape = "reset",
  catchall = "reset",

  binds = {
    { "T", Terminal.run("nvim ~/notes/today.md"), "Today" },
    { "I", Terminal.run("nvim ~/notes/inbox.md"), "Inbox" },
  },
}).setup()
```

`SUPER + SHIFT + N` then `T` opens today's note. What the fields mean:

| Field | Meaning |
| --- | --- |
| `name` | The submap's name in Hyprland, and the name `Bind.unbind` and `Bind.submap` take |
| `desc` | The label shown when you enter it. A leading `+` marks it as a submap in the bind search and which-key |
| `enter` | The key that opens it. Check it is free with `SUPER + /` first |
| `escape` | What `ESCAPE` does. `"reset"` leaves all submaps, `"previous"` goes back one, a submap name jumps to that one |
| `catchall` | What an unlisted key does. `"reset"` makes the submap one-shot: any key leaves it, and its rows leave it for you. `"stay"` keeps it active until you escape, for submaps you press repeatedly |
| `hint` | Optional. Shows the Quickshell hint bar on entry instead of which-key: a list of groups, each a heading then the action ids whose rows it lists (a row that runs a function cannot be listed), e.g. `{ { "Notes", "notes.today", "notes.inbox" } }`. The keys and labels come from your rows; an item can be `{ id, label = "Short" }` to rename it, with `mods` and `args` to pick some of its rows. Speed tiers (a `(Fast)` row beside its plain one) are left to which-key; `tiers = "speed"` sums them up as one `S/C speed` entry (see `home/hypr/.config/hypr/lib/key/submap_hint.lua`). A hint set from `custom/` still opens which-key as well, since HyprVim reads its list before `custom/` loads |
| `targets` | Optional, `true` for a submap whose keys act on the focused window or the Windows selection (`home/hypr/.config/hypr/lib/selection.lua`): selected windows get a thick border and a number while it is up, and the selection carries between submaps with `targets` and clears on any other switch |

In a one-shot submap, a row can stay in it instead by adding `{ keep = true }` as a fourth item.

To reach your submap from the Leader submap as well, add a row there that switches to it. `Submap.switch` moves straight into your submap, so this row needs no `Submap.reset()`:

```lua
Bind.submap("Leader", function()
  Bind.key("SHIFT + N", Submap.switch("Notes"), "+Notes")
end)
```

## Keeping your changes

Everything in `custom/` except its README is gitignored, so updates never touch your keymap file, and it is never committed to this repo. To keep it under version control and carry it between machines, store it in a repo of your own and link it in; see "Keeping your files" in `custom/README.md`. A machine-specific leader belongs in that machine's profile under `config/machines/`, linked the same way.

## When a bind does not work

- **Nothing changed:** run `hyprctl reload`, and check that `custom/init.lua` requires `custom.keymaps`. A Lua error in your file shows up as a Hyprland error on reload.
- **The old action still fires as well:** the shipped bind is still there. Unbind it before binding the key again; `Bind.unbind` returning `0` means the key did not match.
- **A key does nothing:** check the key name. `SLASH` is not `/`, and `RETURN` is not `ENTER`.
- **A global bind does nothing inside a submap:** inside a submap, its own binds apply. A global bind works there only with `submap_universal = true`.
- **A key you added to a one-shot submap stays in it:** end its action with `Submap.reset()`.

## Every shipped bind

The table below lists every bind the shipped keymaps register, with the default leader (`SUPER`) and no machine settings. Binds from `custom/` and per-machine settings are not reflected. It is generated: run `just docs-gen` after changing a keymap, and the `docs-generated` check fails while it is stale.

The table is read with no monitors connected. The `Go` submap gains one row per connected monitor (keys `1`, `2`, and so on, in monitor order) that is not listed. An empty Id means the bind runs no registered action (a mouse bind, a catch-all, a leader key, an `XF86` key). The same key can appear twice in a submap: `On` tells a press from a release. The no-op binds on `SLASH`, `Shift_L` and `Shift_R` that keep the which-key chord from ending a submap are not listed.

<!-- BEGIN generated -->
| Key | On | Submap | Label | Id |
| --- | --- | --- | --- | --- |
| `SUPER + SLASH` | press | global | Keybind Help | `help.keybinds` |
| `SUPER + X` | press | global | Close Window | `window.close` |
| `SUPER + F` | press | global | Toggle Fullscreen | `window.fullscreen` |
| `SUPER + M` | press | global | Toggle Maximize | `window.maximize` |
| `SUPER + U` | press | global | Restore Closed Window | `window.restore_closed` |
| `SUPER + S` | press | global | Toggle Scratchpad | `scratchpad.toggle` |
| `SUPER + SHIFT + S` | press | global | Move to Scratchpad | `scratchpad.move` |
| `SUPER + H` | press | global | Focus Left | `window.focus` |
| `SUPER + LEFT` | press | global |  | `window.focus` |
| `SUPER + J` | press | global | Focus Down | `window.focus` |
| `SUPER + DOWN` | press | global |  | `window.focus` |
| `SUPER + K` | press | global | Focus Up | `window.focus` |
| `SUPER + UP` | press | global |  | `window.focus` |
| `SUPER + L` | press | global | Focus Right | `window.focus` |
| `SUPER + RIGHT` | press | global |  | `window.focus` |
| `SUPER + SHIFT + H` | press | global | Move Window Left | `window.move` |
| `SUPER + SHIFT + LEFT` | press | global |  | `window.move` |
| `SUPER + SHIFT + J` | press | global | Move Window Down | `window.move` |
| `SUPER + SHIFT + DOWN` | press | global |  | `window.move` |
| `SUPER + SHIFT + K` | press | global | Move Window Up | `window.move` |
| `SUPER + SHIFT + UP` | press | global |  | `window.move` |
| `SUPER + SHIFT + L` | press | global | Move Window Right | `window.move` |
| `SUPER + SHIFT + RIGHT` | press | global |  | `window.move` |
| `SUPER + BRACKETLEFT` | press | global | Prev Toast/Popup/Float | `window.cycle_float` |
| `SUPER + BRACKETRIGHT` | press | global | Next Toast/Popup/Float | `window.cycle_float` |
| `SUPER + CTRL + 1` | press | global | Focus Monitor 1 | `monitor.focus` |
| `SUPER + CTRL + SHIFT + 1` | press | global | Move to Monitor 1 | `monitor.move_window` |
| `SUPER + CTRL + 2` | press | global | Focus Monitor 2 | `monitor.focus` |
| `SUPER + CTRL + SHIFT + 2` | press | global | Move to Monitor 2 | `monitor.move_window` |
| `SUPER + CTRL + 3` | press | global | Focus Monitor 3 | `monitor.focus` |
| `SUPER + CTRL + SHIFT + 3` | press | global | Move to Monitor 3 | `monitor.move_window` |
| `SUPER + CTRL + 4` | press | global | Focus Monitor 4 | `monitor.focus` |
| `SUPER + CTRL + SHIFT + 4` | press | global | Move to Monitor 4 | `monitor.move_window` |
| `SUPER + CTRL + 5` | press | global | Focus Monitor 5 | `monitor.focus` |
| `SUPER + CTRL + SHIFT + 5` | press | global | Move to Monitor 5 | `monitor.move_window` |
| `SUPER + CTRL + 6` | press | global | Focus Monitor 6 | `monitor.focus` |
| `SUPER + CTRL + SHIFT + 6` | press | global | Move to Monitor 6 | `monitor.move_window` |
| `SUPER + CTRL + 7` | press | global | Focus Monitor 7 | `monitor.focus` |
| `SUPER + CTRL + SHIFT + 7` | press | global | Move to Monitor 7 | `monitor.move_window` |
| `SUPER + CTRL + 8` | press | global | Focus Monitor 8 | `monitor.focus` |
| `SUPER + CTRL + SHIFT + 8` | press | global | Move to Monitor 8 | `monitor.move_window` |
| `SUPER + CTRL + 9` | press | global | Focus Monitor 9 | `monitor.focus` |
| `SUPER + CTRL + SHIFT + 9` | press | global | Move to Monitor 9 | `monitor.move_window` |
| `SUPER + CTRL + 0` | press | global | Focus Monitor 10 | `monitor.focus` |
| `SUPER + CTRL + SHIFT + 0` | press | global | Move to Monitor 10 | `monitor.move_window` |
| `SUPER + 1` | press | global | Go to Workspace 1 | `workspace.focus` |
| `SUPER + SHIFT + 1` | press | global | Move to Workspace 1 | `workspace.move` |
| `SUPER + 2` | press | global | Go to Workspace 2 | `workspace.focus` |
| `SUPER + SHIFT + 2` | press | global | Move to Workspace 2 | `workspace.move` |
| `SUPER + 3` | press | global | Go to Workspace 3 | `workspace.focus` |
| `SUPER + SHIFT + 3` | press | global | Move to Workspace 3 | `workspace.move` |
| `SUPER + 4` | press | global | Go to Workspace 4 | `workspace.focus` |
| `SUPER + SHIFT + 4` | press | global | Move to Workspace 4 | `workspace.move` |
| `SUPER + 5` | press | global | Go to Workspace 5 | `workspace.focus` |
| `SUPER + SHIFT + 5` | press | global | Move to Workspace 5 | `workspace.move` |
| `SUPER + CTRL + H` | press | global | Prev WS on Monitor | `workspace.cycle` |
| `SUPER + CTRL + LEFT` | press | global |  | `workspace.cycle` |
| `SUPER + CTRL + L` | press | global | Next WS on Monitor | `workspace.cycle` |
| `SUPER + CTRL + RIGHT` | press | global |  | `workspace.cycle` |
| `SUPER + CTRL + J` | press | global | Move window to prev WS | `workspace.move_window` |
| `SUPER + CTRL + DOWN` | press | global |  | `workspace.move_window` |
| `SUPER + CTRL + K` | press | global | Move window to next WS | `workspace.move_window` |
| `SUPER + CTRL + UP` | press | global |  | `workspace.move_window` |
| `SUPER + RETURN` | press | global | Terminal | `terminal.open` |
| `SUPER + SHIFT + RETURN` | press | global | Bottom Terminal | `terminal.bottom` |
| `SUPER + CTRL + RETURN` | press | global | SSH Select | `menu.ssh` |
| `SUPER + E` | press | global | File Manager | `files.open` |
| `SUPER + O` | press | global | Open Application | `menu.drun` |
| `SUPER + CTRL + A` | press | global | Agent Sessions | `menu.agents` |
| `SUPER + Y` | press | global | Yazi | `terminal.yazi` |
| `CTRL + SHIFT + ESCAPE` | press | global | Task Manager | `terminal.task_manager` |
| `SUPER + B` | press | global | +Bar | `submap.enter` |
| `Print` | press | global | Screenshot | `screenshot.take` |
| `SUPER + I` | press | global | Screenshot | `screenshot.take` |
| `SUPER + P` | press | global | Color Picker | `screenshot.pixel` |
| `SUPER + Z` | press | global | Zoom | `zoom.toggle` |
| `SUPER + PERIOD` | press | global | Speech to Text | `voice.dictate` |
| `SUPER + COMMA` | press | global | Voice Command | `voice.command` |
| `SUPER + SHIFT + COMMA` | press | global | Stop Voice | `voice.stop` |
| `SUPER + CTRL + COMMA` | press | global | Rapid Mode | `voice.rapid` |
| `SUPER + CTRL + PERIOD` | press | global | Wake Word | `voice.wake` |
| `SUPER + CTRL + P` | press | global | Passwords | `picker.passwords` |
| `SUPER + T` | press | global | Search windows | `overview.search` |
| `SUPER + SHIFT + T` | press | global | Move window in overview | `overview.move` |
| `ALT + TAB` | press | global | Workspace overview | `overview.open` |
| `SUPER + TAB` | press | global | Workspace overview | `overview.open` |
| `ALT + GRAVE` | press | global | Tmux overview | `tmux.overview` |
| `SUPER + CTRL + V` | press | global | Clipboard History | `picker.clipboard` |
| `SUPER + CTRL + SPACE` | press | global | Jump to Directory | `picker.directory` |
| `SUPER + CTRL + E` | press | global | Emoji Picker | `picker.emoji` |
| `SUPER + SHIFT + SEMICOLON` | press | global | HyprVim Terminal | `hyprvim.terminal` |
| `SUPER + APOSTROPHE` | press | global | Jump to Mark | `hyprvim.jump_mark` |
| `SUPER + N` | press | global | Edit Selection in Vim | `hyprvim.edit_selection` |
| `SUPER + ALT + H` | press | global | Previous Track | `media.prev` |
| `XF86AudioPrev` | press | global | Previous Track | `media.prev` |
| `SUPER + ALT + L` | press | global | Next Track | `media.next` |
| `XF86AudioNext` | press | global | Next Track | `media.next` |
| `SUPER + ALT + SPACE` | press | global | Play/Pause Media | `media.play_pause` |
| `XF86AudioPlay` | press | global | Play/Pause Media | `media.play_pause` |
| `XF86AudioPause` | press | global | Play/Pause Media | `media.play_pause` |
| `SUPER + ALT + K` | press | global | Volume Up | `media.volume_up` |
| `XF86AudioRaiseVolume` | press | global | Volume Up | `media.volume_up` |
| `SUPER + ALT + J` | press | global | Volume Down | `media.volume_down` |
| `XF86AudioLowerVolume` | press | global | Volume Down | `media.volume_down` |
| `SUPER + ALT + M` | press | global | Mute | `media.mute` |
| `XF86AudioMute` | press | global | Mute | `media.mute` |
| `XF86AudioMicMute` | press | global | Mute Mic | `media.mute_mic` |
| `XF86MonBrightnessUp` | press | global | Brightness Up | `media.brightness_up` |
| `XF86MonBrightnessDown` | press | global | Brightness Down | `media.brightness_down` |
| `switch:on:Lid Switch` | press | global | Lid Closed |  |
| `XF86PowerOff` | press | global | Power Button |  |
| `SUPER + mouse_down` | press | global |  | `workspace.cycle` |
| `SUPER + mouse_up` | press | global |  | `workspace.cycle` |
| `SUPER + mouse:272` | press | global |  |  |
| `SUPER + mouse:273` | press | global |  |  |
| `SUPER + SPACE` | press | global | +Leader |  |
| `SUPER + A` | press | global | +Applications |  |
| `SUPER + G` | press | global | +Go |  |
| `SUPER + Q` | press | global | +System |  |
| `SUPER + D` | press | global | +Delete |  |
| `SUPER + W` | press | global | +Windows |  |
| `SUPER + SHIFT + G` | press | global | +Groups |  |
| `SUPER + SEMICOLON` | press | global | +Quick Click |  |
| `SUPER + C` | press | global | +Cursor |  |
| `SUPER + R` | press | global | +Resize |  |
| `SUPER + SHIFT + M` | press | global | +Move |  |
| `SPACE` | press | Applications | Search Windows | `overview.search` |
| `SLASH` | press | Applications | Search Applications | `menu.drun` |
| `B` | press | Applications | Bottles | `apps.open` |
| `SHIFT + C` | press | Applications | Calculator | `apps.open` |
| `D` | press | Applications | Discord | `apps.open` |
| `E` | press | Applications | Editor | `terminal.editor` |
| `F` | press | Applications | Firefox | `apps.open` |
| `G` | press | Applications | Gimp | `apps.open` |
| `I` | press | Applications | Inkscape | `apps.open` |
| `M` | press | Applications | Mail | `apps.focus` |
| `P` | press | Applications | ProtonPlus | `apps.focus` |
| `Q` | press | Applications | QuteBrowser | `apps.open` |
| `R` | press | Applications | Radio (cliamp) | `apps.focus` |
| `S` | press | Applications | Slack | `apps.focus` |
| `SHIFT + S` | press | Applications | Steam | `apps.focus` |
| `T` | press | Applications | Torrent | `apps.open` |
| `W` | press | Applications | LibreOffice Writer | `apps.open` |
| `X` | press | Applications | LibreOffice Calc | `apps.open` |
| `ESCAPE` | press | Applications | Exit Applications |  |
| `BackSpace` | press | Applications | Back |  |
| `SHIFT + SLASH` | press | Applications | Toggle which-key help |  |
| `catchall` | release | Applications |  |  |
| `A` | press | Bar | Agents | `menu.agents` |
| `B` | press | Bar | Bluetooth | `popup.open` |
| `C` | press | Bar | Calendar | `popup.open` |
| `I` | press | Bar | Network and Internet | `popup.open` |
| `M` | press | Bar | Media | `popup.open` |
| `N` | press | Bar | Notifications | `popup.open` |
| `P` | press | Bar | Power and Brightness | `popup.open` |
| `Q` | press | Bar | System | `popup.open` |
| `S` | press | Bar | Start Menu | `popup.open` |
| `SHIFT + S` | press | Bar | Settings | `popup.open` |
| `T` | press | Bar | Tray | `popup.open` |
| `U` | press | Bar | Updates | `system.update` |
| `V` | press | Bar | Volume | `popup.open` |
| `W` | press | Bar | Weather | `popup.open` |
| `ESCAPE` | press | Bar | Exit Bar |  |
| `BackSpace` | press | Bar | Back |  |
| `SHIFT + SLASH` | press | Bar | Toggle which-key help |  |
| `catchall` | release | Bar |  |  |
| `SEMICOLON` | press | Cursor | Floating Click (Exit) | `cursor.pointer_mode` |
| `SUPER + SEMICOLON` | press | Cursor |  | `cursor.pointer_mode` |
| `SHIFT + SEMICOLON` | press | Cursor | Tiling Click (Exit) | `cursor.pointer_mode` |
| `APOSTROPHE` | press | Cursor | Floating Right Click | `cursor.pointer_mode` |
| `SHIFT + APOSTROPHE` | press | Cursor | Tiling Right Click | `cursor.pointer_mode` |
| `F` | press | Cursor | Floating Click | `cursor.pointer_mode` |
| `SHIFT + F` | press | Cursor | Floating Right Click | `cursor.pointer_mode` |
| `CTRL + F` | press | Cursor | Floating Move | `cursor.pointer_mode` |
| `T` | press | Cursor | Tiling Click | `cursor.pointer_mode` |
| `SHIFT + T` | press | Cursor | Tiling Right Click | `cursor.pointer_mode` |
| `CTRL + T` | press | Cursor | Tiling Move | `cursor.pointer_mode` |
| `G` | press | Cursor | Split Click | `cursor.pointer_mode` |
| `SHIFT + G` | press | Cursor | Split Right Click | `cursor.pointer_mode` |
| `CTRL + G` | press | Cursor | Split Move | `cursor.pointer_mode` |
| `SPACE` | press | Cursor | Left Click | `cursor.click` |
| `CTRL + SPACE` | press | Cursor | Left Click (Exit) | `cursor.click` |
| `R` | press | Cursor | Right Click | `cursor.click` |
| `CTRL + R` | press | Cursor | Right Click (Exit) | `cursor.click` |
| `M` | press | Cursor | Middle Click | `cursor.click` |
| `CTRL + M` | press | Cursor | Middle Click (Exit) | `cursor.click` |
| `CTRL + U` | press | Cursor | Page Up | `cursor.send_key` |
| `CTRL + D` | press | Cursor | Page Down | `cursor.send_key` |
| `ALT + H` | press | Cursor | Arrow Left | `cursor.send_key` |
| `ALT + J` | press | Cursor | Arrow Down | `cursor.send_key` |
| `ALT + K` | press | Cursor | Arrow Up | `cursor.send_key` |
| `ALT + L` | press | Cursor | Arrow Right | `cursor.send_key` |
| `H` | press | Cursor | Cursor Left | `cursor.move` |
| `LEFT` | press | Cursor |  | `cursor.move` |
| `J` | press | Cursor | Cursor Down | `cursor.move` |
| `DOWN` | press | Cursor |  | `cursor.move` |
| `K` | press | Cursor | Cursor Up | `cursor.move` |
| `UP` | press | Cursor |  | `cursor.move` |
| `L` | press | Cursor | Cursor Right | `cursor.move` |
| `RIGHT` | press | Cursor |  | `cursor.move` |
| `SHIFT + H` | press | Cursor | Cursor Left (Fast) | `cursor.move` |
| `SHIFT + LEFT` | press | Cursor |  | `cursor.move` |
| `SHIFT + J` | press | Cursor | Cursor Down (Fast) | `cursor.move` |
| `SHIFT + DOWN` | press | Cursor |  | `cursor.move` |
| `SHIFT + K` | press | Cursor | Cursor Up (Fast) | `cursor.move` |
| `SHIFT + UP` | press | Cursor |  | `cursor.move` |
| `SHIFT + L` | press | Cursor | Cursor Right (Fast) | `cursor.move` |
| `SHIFT + RIGHT` | press | Cursor |  | `cursor.move` |
| `CTRL + H` | press | Cursor | Cursor Left (Pixel) | `cursor.move` |
| `CTRL + LEFT` | press | Cursor |  | `cursor.move` |
| `CTRL + J` | press | Cursor | Cursor Down (Pixel) | `cursor.move` |
| `CTRL + DOWN` | press | Cursor |  | `cursor.move` |
| `CTRL + K` | press | Cursor | Cursor Up (Pixel) | `cursor.move` |
| `CTRL + UP` | press | Cursor |  | `cursor.move` |
| `CTRL + L` | press | Cursor | Cursor Right (Pixel) | `cursor.move` |
| `CTRL + RIGHT` | press | Cursor |  | `cursor.move` |
| `CTRL + SHIFT + H` | press | Cursor | Cursor Left (Ultra Fast) | `cursor.move` |
| `CTRL + SHIFT + LEFT` | press | Cursor |  | `cursor.move` |
| `CTRL + SHIFT + J` | press | Cursor | Cursor Down (Ultra Fast) | `cursor.move` |
| `CTRL + SHIFT + DOWN` | press | Cursor |  | `cursor.move` |
| `CTRL + SHIFT + K` | press | Cursor | Cursor Up (Ultra Fast) | `cursor.move` |
| `CTRL + SHIFT + UP` | press | Cursor |  | `cursor.move` |
| `CTRL + SHIFT + L` | press | Cursor | Cursor Right (Ultra Fast) | `cursor.move` |
| `CTRL + SHIFT + RIGHT` | press | Cursor |  | `cursor.move` |
| `E` | press | Cursor | Scroll Up | `cursor.scroll` |
| `Y` | press | Cursor | Scroll Down | `cursor.scroll` |
| `COMMA` | press | Cursor | Scroll Left | `cursor.scroll` |
| `PERIOD` | press | Cursor | Scroll Right | `cursor.scroll` |
| `SHIFT + E` | press | Cursor | Scroll Up (Fast) | `cursor.scroll` |
| `SHIFT + Y` | press | Cursor | Scroll Down (Fast) | `cursor.scroll` |
| `SHIFT + COMMA` | press | Cursor | Scroll Left (Fast) | `cursor.scroll` |
| `SHIFT + PERIOD` | press | Cursor | Scroll Right (Fast) | `cursor.scroll` |
| `CTRL + E` | press | Cursor | Scroll Up (Pixel) | `cursor.scroll` |
| `CTRL + Y` | press | Cursor | Scroll Down (Pixel) | `cursor.scroll` |
| `CTRL + COMMA` | press | Cursor | Scroll Left (Pixel) | `cursor.scroll` |
| `CTRL + PERIOD` | press | Cursor | Scroll Right (Pixel) | `cursor.scroll` |
| `ESCAPE` | press | Cursor | Exit Cursor |  |
| `BackSpace` | press | Cursor | Back |  |
| `SHIFT + SLASH` | press | Cursor | Toggle which-key help |  |
| `catchall` | release | Cursor |  |  |
| `B` | press | Delete | Close Browsers | `delete.close_group` |
| `C` | press | Delete | Clear Clipboard | `delete.clear_clipboard` |
| `D` | press | Delete | Close All on WS | `delete.close_workspace` |
| `SHIFT + D` | press | Delete | Kill All on WS | `delete.close_workspace` |
| `E` | press | Delete | Close Editors | `delete.close_group` |
| `F` | press | Delete | Close File Managers | `delete.close_group` |
| `G` | press | Delete | Close Games | `delete.close_group` |
| `M` | press | Delete | Close Mail | `delete.close_group` |
| `N` | press | Delete | Clear Notifications | `notifications.clear_all` |
| `O` | press | Delete | Close Others on WS | `delete.close_workspace` |
| `SHIFT + O` | press | Delete | Kill Others on WS | `delete.close_workspace` |
| `P` | press | Delete | Close Media Players | `delete.close_group` |
| `S` | press | Delete | Close Chat | `delete.close_group` |
| `T` | press | Delete | Close Terminals | `delete.close_group` |
| `W` | press | Delete | Close Window | `window.close` |
| `SHIFT + W` | press | Delete | Kill Window | `window.kill` |
| `ESCAPE` | press | Delete | Exit Delete |  |
| `BackSpace` | press | Delete | Back |  |
| `SHIFT + SLASH` | press | Delete | Toggle which-key help |  |
| `catchall` | release | Delete |  |  |
| `TAB` | press | Go | Last Workspace | `workspace.focus_last` |
| `A` | press | Go | Agent Sessions Picker | `picker.agents` |
| `B` | press | Go | Browser | `apps.focus` |
| `C` | press | Go | Tmuxifier Config | `apps.focus` |
| `M` | press | Go | Mail | `apps.focus` |
| `P` | press | Go | Project | `menu.tmux` |
| `Q` | press | Go | QuteBrowser | `apps.focus` |
| `S` | press | Go | Slack | `apps.focus` |
| `SHIFT + S` | press | Go | Steam | `apps.focus` |
| `T` | press | Go | Terminal | `apps.focus` |
| `V` | press | Go | Editor | `terminal.editor` |
| `W` | press | Go | Search Windows | `overview.search` |
| `Y` | press | Go | Yazi | `apps.focus` |
| `ESCAPE` | press | Go | Exit Go |  |
| `BackSpace` | press | Go | Back |  |
| `SHIFT + SLASH` | press | Go | Toggle which-key help |  |
| `catchall` | release | Go |  |  |
| `SPACE` | press | Groups | Toggle Group | `groups.toggle` |
| `TAB` | press | Groups | Next Group Window | `groups.next` |
| `BRACKETRIGHT` | press | Groups | Next Group Window | `groups.next` |
| `SHIFT + TAB` | press | Groups | Previous Group Window | `groups.prev` |
| `BRACKETLEFT` | press | Groups | Previous Group Window | `groups.prev` |
| `X` | press | Groups | Move Out of Group | `groups.move_out` |
| `SHIFT + X` | press | Groups | Toggle Group Lock | `groups.lock_toggle` |
| `H` | press | Groups | Focus Left | `window.focus` |
| `LEFT` | press | Groups |  | `window.focus` |
| `J` | press | Groups | Focus Down | `window.focus` |
| `DOWN` | press | Groups |  | `window.focus` |
| `K` | press | Groups | Focus Up | `window.focus` |
| `UP` | press | Groups |  | `window.focus` |
| `L` | press | Groups | Focus Right | `window.focus` |
| `RIGHT` | press | Groups |  | `window.focus` |
| `SHIFT + H` | press | Groups | Group Left | `groups.move` |
| `SHIFT + LEFT` | press | Groups |  | `groups.move` |
| `SHIFT + J` | press | Groups | Group Down | `groups.move` |
| `SHIFT + DOWN` | press | Groups |  | `groups.move` |
| `SHIFT + K` | press | Groups | Group Up | `groups.move` |
| `SHIFT + UP` | press | Groups |  | `groups.move` |
| `SHIFT + L` | press | Groups | Group Right | `groups.move` |
| `SHIFT + RIGHT` | press | Groups |  | `groups.move` |
| `ESCAPE` | press | Groups | Exit Groups |  |
| `BackSpace` | press | Groups | Back |  |
| `SHIFT + SLASH` | press | Groups | Toggle which-key help |  |
| `catchall` | release | Groups |  |  |
| `SPACE` | press | Leader | Agent Sessions Picker | `picker.agents` |
| `SLASH` | press | Leader | Directory | `picker.directory` |
| `O` | press | Leader | Open Application | `menu.drun` |
| `SHIFT + O` | press | Leader | Session Launcher |  |
| `CTRL + V` | press | Leader | Clipboard | `picker.clipboard` |
| `TAB` | press | Leader | Workspace Overview | `overview.open` |
| `SHIFT + TAB` | press | Leader | Tmux Overview | `tmux.overview` |
| `E` | press | Leader | Emoji | `picker.emoji` |
| `PERIOD` | press | Leader | Speech to Text | `voice.dictate` |
| `COMMA` | press | Leader | Voice Command | `voice.command` |
| `SHIFT + COMMA` | press | Leader | Stop Voice | `voice.stop` |
| `CTRL + COMMA` | press | Leader | Rapid Mode | `voice.rapid` |
| `CTRL + PERIOD` | press | Leader | Wake Word | `voice.wake` |
| `CTRL + SLASH` | press | Leader | Voice Help |  |
| `G` | press | Leader | +Groups | `submap.enter` |
| `A` | press | Leader | Agents | `menu.agents` |
| `B` | press | Leader | Bluetooth | `popup.open` |
| `C` | press | Leader | Calendar | `popup.open` |
| `I` | press | Leader | Network and Internet | `popup.open` |
| `M` | press | Leader | Media | `popup.open` |
| `N` | press | Leader | Notifications | `popup.open` |
| `P` | press | Leader | Power and Brightness | `popup.open` |
| `Q` | press | Leader | System | `popup.open` |
| `S` | press | Leader | Settings | `popup.open` |
| `SHIFT + S` | press | Leader | Settings | `popup.open` |
| `T` | press | Leader | Tray | `popup.open` |
| `U` | press | Leader | Updates | `system.update` |
| `V` | press | Leader | Volume | `popup.open` |
| `W` | press | Leader | Weather | `popup.open` |
| `ESCAPE` | press | Leader | Exit Leader |  |
| `BackSpace` | press | Leader | Back |  |
| `SHIFT + SLASH` | press | Leader | Toggle which-key help |  |
| `catchall` | release | Leader |  |  |
| `F` | press | Move | Toggle Floating | `windows.float_selected` |
| `W` | press | Move | +Windows | `submap.enter` |
| `R` | press | Move | +Resize | `submap.enter` |
| `H` | press | Move | Move Left | `move.step` |
| `LEFT` | press | Move |  | `move.step` |
| `J` | press | Move | Move Down | `move.step` |
| `DOWN` | press | Move |  | `move.step` |
| `K` | press | Move | Move Up | `move.step` |
| `UP` | press | Move |  | `move.step` |
| `L` | press | Move | Move Right | `move.step` |
| `RIGHT` | press | Move |  | `move.step` |
| `SHIFT + H` | press | Move | Move Left (Fast) | `move.step` |
| `SHIFT + LEFT` | press | Move |  | `move.step` |
| `SHIFT + J` | press | Move | Move Down (Fast) | `move.step` |
| `SHIFT + DOWN` | press | Move |  | `move.step` |
| `SHIFT + K` | press | Move | Move Up (Fast) | `move.step` |
| `SHIFT + UP` | press | Move |  | `move.step` |
| `SHIFT + L` | press | Move | Move Right (Fast) | `move.step` |
| `SHIFT + RIGHT` | press | Move |  | `move.step` |
| `CTRL + H` | press | Move | Move Left (Pixel) | `move.step` |
| `CTRL + LEFT` | press | Move |  | `move.step` |
| `CTRL + J` | press | Move | Move Down (Pixel) | `move.step` |
| `CTRL + DOWN` | press | Move |  | `move.step` |
| `CTRL + K` | press | Move | Move Up (Pixel) | `move.step` |
| `CTRL + UP` | press | Move |  | `move.step` |
| `CTRL + L` | press | Move | Move Right (Pixel) | `move.step` |
| `CTRL + RIGHT` | press | Move |  | `move.step` |
| `CTRL + SHIFT + H` | press | Move | Move Left (Ultra Fast) | `move.step` |
| `CTRL + SHIFT + LEFT` | press | Move |  | `move.step` |
| `CTRL + SHIFT + J` | press | Move | Move Down (Ultra Fast) | `move.step` |
| `CTRL + SHIFT + DOWN` | press | Move |  | `move.step` |
| `CTRL + SHIFT + K` | press | Move | Move Up (Ultra Fast) | `move.step` |
| `CTRL + SHIFT + UP` | press | Move |  | `move.step` |
| `CTRL + SHIFT + L` | press | Move | Move Right (Ultra Fast) | `move.step` |
| `CTRL + SHIFT + RIGHT` | press | Move |  | `move.step` |
| `ESCAPE` | press | Move | Exit Move |  |
| `BackSpace` | press | Move | Back |  |
| `SHIFT + SLASH` | press | Move | Toggle which-key help |  |
| `catchall` | release | Move |  |  |
| `SEMICOLON` | press | Quick Click | Floating Click (Exit) | `cursor.pointer_mode` |
| `APOSTROPHE` | press | Quick Click | Floating Right Click | `cursor.pointer_mode` |
| `SHIFT + SEMICOLON` | press | Quick Click | Tile Click (Exit) | `cursor.pointer_mode` |
| `SUPER + SEMICOLON` | press | Quick Click |  | `cursor.pointer_mode` |
| `SUPER + APOSTROPHE` | press | Quick Click |  | `cursor.pointer_mode` |
| `F` | press | Quick Click | Floating Click | `cursor.pointer_mode` |
| `SHIFT + F` | press | Quick Click | Floating Right Click | `cursor.pointer_mode` |
| `CTRL + F` | press | Quick Click | Floating Move | `cursor.pointer_mode` |
| `T` | press | Quick Click | Tiling Click | `cursor.pointer_mode` |
| `SHIFT + T` | press | Quick Click | Tile Right Click | `cursor.pointer_mode` |
| `CTRL + T` | press | Quick Click | Tiling Move | `cursor.pointer_mode` |
| `G` | press | Quick Click | Split Click | `cursor.pointer_mode` |
| `SHIFT + G` | press | Quick Click | Split Right Click | `cursor.pointer_mode` |
| `CTRL + G` | press | Quick Click | Split Move | `cursor.pointer_mode` |
| `ESCAPE` | press | Quick Click | Exit Quick Click |  |
| `BackSpace` | press | Quick Click | Back |  |
| `SHIFT + SLASH` | press | Quick Click | Toggle which-key help |  |
| `catchall` | release | Quick Click |  |  |
| `EQUAL` | press | Resize | Reset Size | `resize.reset` |
| `W` | press | Resize | +Windows | `submap.enter` |
| `M` | press | Resize | +Move | `submap.enter` |
| `H` | press | Resize | Resize Left | `resize.step` |
| `LEFT` | press | Resize |  | `resize.step` |
| `J` | press | Resize | Resize Down | `resize.step` |
| `DOWN` | press | Resize |  | `resize.step` |
| `K` | press | Resize | Resize Up | `resize.step` |
| `UP` | press | Resize |  | `resize.step` |
| `L` | press | Resize | Resize Right | `resize.step` |
| `RIGHT` | press | Resize |  | `resize.step` |
| `SHIFT + H` | press | Resize | Resize Left (Fast) | `resize.step` |
| `SHIFT + LEFT` | press | Resize |  | `resize.step` |
| `SHIFT + J` | press | Resize | Resize Down (Fast) | `resize.step` |
| `SHIFT + DOWN` | press | Resize |  | `resize.step` |
| `SHIFT + K` | press | Resize | Resize Up (Fast) | `resize.step` |
| `SHIFT + UP` | press | Resize |  | `resize.step` |
| `SHIFT + L` | press | Resize | Resize Right (Fast) | `resize.step` |
| `SHIFT + RIGHT` | press | Resize |  | `resize.step` |
| `CTRL + H` | press | Resize | Resize Left (Pixel) | `resize.step` |
| `CTRL + LEFT` | press | Resize |  | `resize.step` |
| `CTRL + J` | press | Resize | Resize Down (Pixel) | `resize.step` |
| `CTRL + DOWN` | press | Resize |  | `resize.step` |
| `CTRL + K` | press | Resize | Resize Up (Pixel) | `resize.step` |
| `CTRL + UP` | press | Resize |  | `resize.step` |
| `CTRL + L` | press | Resize | Resize Right (Pixel) | `resize.step` |
| `CTRL + RIGHT` | press | Resize |  | `resize.step` |
| `CTRL + SHIFT + H` | press | Resize | Resize Left (Ultra Fast) | `resize.step` |
| `CTRL + SHIFT + LEFT` | press | Resize |  | `resize.step` |
| `CTRL + SHIFT + J` | press | Resize | Resize Down (Ultra Fast) | `resize.step` |
| `CTRL + SHIFT + DOWN` | press | Resize |  | `resize.step` |
| `CTRL + SHIFT + K` | press | Resize | Resize Up (Ultra Fast) | `resize.step` |
| `CTRL + SHIFT + UP` | press | Resize |  | `resize.step` |
| `CTRL + SHIFT + L` | press | Resize | Resize Right (Ultra Fast) | `resize.step` |
| `CTRL + SHIFT + RIGHT` | press | Resize |  | `resize.step` |
| `ESCAPE` | press | Resize | Exit Resize |  |
| `BackSpace` | press | Resize | Back |  |
| `SHIFT + SLASH` | press | Resize | Toggle which-key help |  |
| `catchall` | release | Resize |  |  |
| `SLASH` | press | System | Edit Keymaps | `system.edit_keymaps` |
| `SPACE` | press | System | Task Manager | `terminal.task_manager` |
| `A` | press | System | AI Manager | `terminal.tool` |
| `SHIFT + A` | press | System | Aria2tui | `terminal.tool` |
| `B` | press | System | Restart Bar | `system.restart_bar` |
| `C` | press | System | Calculate (qalc) | `terminal.tool` |
| `D` | press | System | DNS (doggo) | `terminal.tool` |
| `E` | press | System | Logout | `power.confirm` |
| `G` | press | System | Ping (gping) | `terminal.tool` |
| `H` | press | System | Reload Hyprland | `system.reload_hyprland` |
| `SHIFT + H` | press | System | Reload Hyprpm Plugins | `system.reload_plugins` |
| `J` | press | System | Journal (lazyjournal) | `terminal.tool` |
| `K` | press | System | Kill App (Click) | `system.kill_app` |
| `L` | press | System | Lock | `power.confirm` |
| `SHIFT + L` | press | System | Toggle Auto-Lock | `system.toggle_autolock` |
| `R` | press | System | Reboot | `power.confirm` |
| `SHIFT + R` | press | System | Replay Autostart | `system.replay_autostart` |
| `P` | press | System | Power Off | `power.confirm` |
| `U` | press | System | Disk Usage (gdu) | `terminal.tool` |
| `V` | press | System | Voxtype Settings | `system.voxtype_settings` |
| `SHIFT + V` | press | System | Voxtype Restart | `system.voxtype_restart` |
| `W` | press | System | HTTP (xh) | `terminal.tool` |
| `X` | press | System | Toggle Hypr Errors | `system.toggle_errors` |
| `ESCAPE` | press | System | Exit System |  |
| `BackSpace` | press | System | Back |  |
| `SHIFT + SLASH` | press | System | Toggle which-key help |  |
| `catchall` | release | System |  |  |
| `R` | press | Windows | +Resize | `submap.enter` |
| `M` | press | Windows | +Move | `submap.enter` |
| `C` | press | Windows | +Cursor | `submap.enter` |
| `BRACKETLEFT` | press | Windows | Prev Float | `windows.step_float` |
| `BRACKETRIGHT` | press | Windows | Next Float | `windows.step_float` |
| `X` | press | Windows | Close Window | `windows.close_selected` |
| `F` | press | Windows | Toggle Floating | `windows.float_selected` |
| `P` | press | Windows | Toggle Pseudo | `windows.pseudo_selected` |
| `MINUS` | press | Windows | Toggle Split | `windows.split_selected` |
| `RETURN` | press | Windows | Confirm Selection | `windows.confirm` |
| `SPACE` | press | Windows | Select Window | `windows.select_toggle` |
| `S` | press | Windows | Swap with Selected | `windows.swap_selected` |
| `H` | press | Windows | Focus Left | `window.focus` |
| `LEFT` | press | Windows |  | `window.focus` |
| `J` | press | Windows | Focus Down | `window.focus` |
| `DOWN` | press | Windows |  | `window.focus` |
| `K` | press | Windows | Focus Up | `window.focus` |
| `UP` | press | Windows |  | `window.focus` |
| `L` | press | Windows | Focus Right | `window.focus` |
| `RIGHT` | press | Windows |  | `window.focus` |
| `SHIFT + H` | press | Windows | Move Left | `windows.move_selected` |
| `SHIFT + LEFT` | press | Windows |  | `windows.move_selected` |
| `SHIFT + J` | press | Windows | Move Down | `windows.move_selected` |
| `SHIFT + DOWN` | press | Windows |  | `windows.move_selected` |
| `SHIFT + K` | press | Windows | Move Up | `windows.move_selected` |
| `SHIFT + UP` | press | Windows |  | `windows.move_selected` |
| `SHIFT + L` | press | Windows | Move Right | `windows.move_selected` |
| `SHIFT + RIGHT` | press | Windows |  | `windows.move_selected` |
| `CTRL + H` | press | Windows | Workspace Left | `workspace.cycle` |
| `CTRL + LEFT` | press | Windows |  | `workspace.cycle` |
| `CTRL + J` | press | Windows | Workspace Down | `windows.workspace_selected` |
| `CTRL + DOWN` | press | Windows |  | `windows.workspace_selected` |
| `CTRL + K` | press | Windows | Workspace Up | `windows.workspace_selected` |
| `CTRL + UP` | press | Windows |  | `windows.workspace_selected` |
| `CTRL + L` | press | Windows | Workspace Right | `workspace.cycle` |
| `CTRL + RIGHT` | press | Windows |  | `workspace.cycle` |
| `SHIFT + 1` | press | Windows | Move to WS 1 | `windows.workspace_move_selected` |
| `SHIFT + 2` | press | Windows | Move to WS 2 | `windows.workspace_move_selected` |
| `SHIFT + 3` | press | Windows | Move to WS 3 | `windows.workspace_move_selected` |
| `SHIFT + 4` | press | Windows | Move to WS 4 | `windows.workspace_move_selected` |
| `SHIFT + 5` | press | Windows | Move to WS 5 | `windows.workspace_move_selected` |
| `1` | press | Windows | Monitor 1 | `monitor.focus` |
| `2` | press | Windows | Monitor 2 | `monitor.focus` |
| `3` | press | Windows | Monitor 3 | `monitor.focus` |
| `4` | press | Windows | Monitor 4 | `monitor.focus` |
| `5` | press | Windows | Monitor 5 | `monitor.focus` |
| `6` | press | Windows | Monitor 6 | `monitor.focus` |
| `7` | press | Windows | Monitor 7 | `monitor.focus` |
| `8` | press | Windows | Monitor 8 | `monitor.focus` |
| `9` | press | Windows | Monitor 9 | `monitor.focus` |
| `0` | press | Windows | Monitor 10 | `monitor.focus` |
| `ESCAPE` | press | Windows | Exit Windows |  |
| `BackSpace` | press | Windows | Back |  |
| `SHIFT + SLASH` | press | Windows | Toggle which-key help |  |
| `catchall` | release | Windows |  |  |
<!-- END generated -->
