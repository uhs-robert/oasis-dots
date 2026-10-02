# Changing keybinds

Every key in this setup is defined in Lua under `~/.config/hypr/keymaps/`. This page covers how to find a bind, change it, add your own, and build a new menu of keys.

## Finding what a key does

You rarely need to open a file to find a bind.

- `SUPER + /` searches the binds of the mode you are in, and runs the one you pick.
- `SUPER + SPACE` opens the Leader menu, which lists every other menu.
- Entering any menu shows its keys in the which-key overlay.

All three read the same descriptions you write next to each bind, so anything you add shows up in them automatically.

## How the files are laid out

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
  submaps/             menus: press one key to enter, then another to act
    leader/  apps/  go/  system/  delete/  windows/
    groups/  cursor/  resize/  move/  zoom/  bar/
```

A global bind fires the moment you press it. A submap is a menu: its entry key switches the keyboard into that menu, where plain keys such as `F` or `SHIFT + S` do things, and then it exits.

## The leader key

Most global binds start with one modifier, the leader. It is `SUPER` by default. To change it for one machine, set it in your machine profile:

```lua
-- config/machines/<hostname>.lua
return {
  leader = "ALT",
}
```

Every bind written with `Bind.leader_key` and every submap entered with `Config.leader .. " + ..."` follows it. See `config/machines/README.md` for how profiles work.

## Changing or removing a bind

Find the line, edit the key, save, and reload:

```
hyprctl reload
```

Global binds look like this, in `keymaps/global/shortcuts.lua`:

```lua
Bind.leader_fn("RETURN", Cmd.open_term(),    "Terminal")
Bind.leader_cmd("E",     FILES,              "File Manager")
Bind.fn("CTRL + SHIFT + ESCAPE", Cmd.term("btop"), "Task Manager")
```

The first argument is the key, the second what it does, the third the description shown in search and which-key. To move the terminal to `SUPER + BACKSPACE`, change `"RETURN"` to `"BACKSPACE"`. To remove a bind, delete the line or comment it out with `--`.

Keys are written as modifiers and a key name joined by ` + `, for example `"CTRL + SHIFT + ESCAPE"`. Key names are Hyprland's: letters and digits as they are, and names such as `RETURN`, `SPACE`, `TAB`, `SLASH`, `PERIOD`, `BRACKETLEFT`. A key tester such as `wev` (not installed by default) prints the name of any key you press.

## Adding a bind

Pick the helper that matches what the key should do. All of them come from `lib/key/bind.lua`.

| Helper | Use it for |
| --- | --- |
| `Bind.leader_cmd(key, "command", "Description")` | Running a shell command, with the leader |
| `Bind.leader_fn(key, action, "Description")` | Running one of the built-in actions, with the leader |
| `Bind.cmd(key, "command", "Description")` | A shell command with no leader, so you write the modifiers yourself |
| `Bind.fn(key, action, "Description")` | An action with no leader |

For example, to open a calculator on `SUPER + F9` and a file on `CTRL + ALT + N`:

```lua
Bind.leader_cmd("F9", "qalculate-gtk", "Calculator")
Bind.cmd("CTRL + ALT + N", "kitty -e nvim ~/notes.md", "Notes")
```

The built-in actions live in `lib/actions/`, grouped by subject: `window.lua`, `workspace.lua`, `apps.lua`, `cmd.lua`, `menu.lua`, `media.lua` and others. The ones you will reach for most:

| Action | Does |
| --- | --- |
| `Cmd.run("command")` | Runs a command |
| `Cmd.term("command")` | Runs it in your terminal |
| `Cmd.bottom_terminal("command")` | Runs it in a terminal that drops in at the bottom of the screen |
| `Apps.open("command")` | Starts an app |
| `Apps.focus_or_launch(app)` | Jumps to the app if it is open, otherwise starts it |

A bind that should also work while you are inside a menu takes one more argument:

```lua
Bind.leader_key("S", Window.toggle_special("scratchpad"), { submap_universal = true, desc = "Toggle Scratchpad" })
```

## Adding a key to a menu

Each submap is a list of rows: key, action, description. To add an app to the Applications menu (`SUPER + A`), add a row to `keymaps/submaps/apps/init.lua`:

```lua
binds = {
  { "F", Apps.open("firefox"),  "Firefox" },
  { "Z", Apps.open("zathura"),  "PDF viewer" },   -- new
},
```

After a reload, `SUPER + A` then `Z` opens it, and the row appears in which-key.

## Making a menu of your own

Create `keymaps/submaps/notes/init.lua`:

```lua
local Config = require("config")
local Cmd = require("lib.actions.cmd")
local Submap = require("lib.key.submap")

Submap.define({
  name = "Notes",
  desc = "+Notes",
  enter = Config.leader .. " + SHIFT + N",

  escape = "reset",
  catchall = "reset",

  binds = {
    { "T", Cmd.term("nvim ~/notes/today.md"), "Today" },
    { "I", Cmd.term("nvim ~/notes/inbox.md"), "Inbox" },
  },
}).setup()
```

Then load it by adding one line to `keymaps/submaps/init.lua`:

```lua
require("keymaps.submaps.notes")
```

What the fields mean:

| Field | Meaning |
| --- | --- |
| `name` | The submap's name in Hyprland |
| `desc` | The label shown when you enter it. A leading `+` marks it as a menu |
| `enter` | The key that opens it. Check it is not already taken, with `SUPER + /` |
| `escape` | What `ESCAPE` does. `"reset"` leaves all menus, `"previous"` goes back one, a submap name jumps to that one |
| `catchall` | What an unlisted key does. `"reset"` makes the menu one-shot: it closes after any key. `"stay"` keeps it open until you escape, for menus you press repeatedly, such as resize |

In a one-shot menu, a row can opt out and keep the menu open by adding `{ keep = true }` as a fourth item.

To reach your menu from the Leader menu as well, add a row to `keymaps/submaps/leader/init.lua` that switches to it:

```lua
{ "SHIFT + N", Submap.switch("Notes"), "+Notes", { keep = true } },
```

## Keeping your changes through updates

The keymap files are tracked in the repo, so your edits are changes to tracked files. `git pull` will stop if upstream touched the same lines. Two ways to live with that:

- Keep your changes on your own branch or fork and merge upstream into it.
- Keep additions in files of your own, such as the `notes` submap above. A new file never conflicts; only the one `require` line you added can.

Machine-specific values, such as the leader key or your default terminal, belong in `config/machines/<hostname>.lua`, which git ignores.

## When a bind does not work

- Reload first: `hyprctl reload`. If nothing you changed takes effect, look for a Lua error: a mistake in one keymap file can stop the files after it from loading.
- Check for a clash. If two binds use the same key, search it with `SUPER + /`.
- Check the key name. `SLASH` is not `/`, and `RETURN` is not `ENTER`.
- Inside a menu, plain keys belong to the menu. A global bind only works there if it was marked `submap_universal`.
