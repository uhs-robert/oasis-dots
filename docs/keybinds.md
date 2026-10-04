# Changing keybinds

The keys this setup ships are defined in Lua under `~/.config/hypr/keymaps/`. Leave those files alone: your changes go in one file of your own, `custom/keymaps.lua`, which can add binds, replace shipped ones and define new [submaps](https://wiki.hypr.land/Configuring/Basics/Binds/#submaps). It is gitignored, so `git pull` never conflicts with it, and you can track it in a repo of your own.

## Finding what a key does

You rarely need to open a file to find a bind.

- `SUPER + /` searches every bind in the mode you are in and runs the one you pick. Submaps are listed first, each with a `+` in front of its name, so it doubles as a map of the submaps you can enter from here.
- `SUPER + SHIFT + /` opens which-key from anywhere, showing every bind in the current submap at a glance, or the global binds when you are in none.
- Entering a submap also shows its binds in which-key.

All of them read the description written next to each bind, so anything you add shows up in them too.

## Where the shipped binds live

Open these to see how a bind is written or which submap a key belongs to:

```
keymaps/
  init.lua             loads the two folders below
  global/              keys that work everywhere
    general.lua        windows, focus, scratchpad, monitors
    workspace.lua      workspaces
    shortcuts.lua      terminal, file manager, pickers
    tools.lua          screenshots and other tools
    media.lua          volume, brightness, playback
    power.lua          lock, sleep, power
    mouse.lua          mouse binds
  submaps/             submaps: press one key to enter, then another to act
    leader/  apps/  go/  system/  delete/  windows/  monitors/
    groups/  cursor/  resize/  move/  bar/
```

A global bind fires the moment you press it. A submap is a separate set of binds: its entry key switches the keyboard into it, where plain keys such as `F` or `SHIFT + S` do things, and which-key lists those binds as you enter it. Each submap's name, which you need for changing it, is the `name` field at the top of its file: `Applications`, `Windows`, `Leader` and so on.

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
local Cmd = require("lib.actions.cmd")
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

The third argument is the description shown in search and which-key. The built-in actions live in `lib/actions/`, grouped by subject (`window.lua`, `workspace.lua`, `apps.lua`, `cmd.lua`, `menu.lua`, `media.lua` and others). The ones you will reach for most:

| Action | Does |
| --- | --- |
| `Cmd.run("command")` | Runs a command |
| `Cmd.term("command")` | Runs it in your terminal |
| `Cmd.open_term()` | Opens your terminal |
| `Cmd.bottom_terminal("command")` | Runs it in a terminal that drops in at the bottom of the screen |

A bind that should also work while you are inside a submap passes its options in place of the description. This replaces the calculator line above, rather than adding to it:

```lua
Bind.leader_cmd("F9", "qalculate-gtk", { submap_universal = true, desc = "Calculator" })
```

## Changing or removing a shipped bind

Binding a key that is already bound does not replace it: Hyprland keeps both binds and runs both. So remove the shipped one first, then bind yours. To move the terminal from `SUPER + RETURN` to `SUPER + BACKSPACE`:

```lua
Bind.leader_unbind("RETURN")
Bind.leader_fn("BACKSPACE", Cmd.open_term(), "Terminal")
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

Some submaps, such as Applications and Leader, are one-shot: any key leaves them. A bind you add this way does not leave the submap on its own, so finish its action with `Submap.reset()`. To add a PDF viewer to the Applications submap (`SUPER + A`) on `Z`:

```lua
Bind.submap("Applications", function()
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
    { "T", Cmd.term("nvim ~/notes/today.md"), "Today" },
    { "I", Cmd.term("nvim ~/notes/inbox.md"), "Inbox" },
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
