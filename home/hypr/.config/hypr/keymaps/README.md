# Keymaps

All shipped keys. Come here to find or move a key. [Changing keybinds](../../../../../docs/keybinds.md) is the guide for users, who add or replace keys from `custom/` without editing these files.

## Where a key lives

Shipped actions carry no key, so a key is a line here. A global key is an `Act.bind(id, { key, args, desc })` line in `global/`, and a submap key is a row in that submap's file. To move a shipped key, edit that line. See [actions](../lib/act/README.md).

## Binding rules

Register binds through `lib/key/bind.lua` (`Bind.key`, `Bind.submap`), never raw `hl.bind` or `hl.define_submap`. `Bind` tracks binds per submap, so `Bind.unbind` can remove a key from one submap. `Bind.unbind` and `Bind.submap` are public API for `custom/`: keep their signatures stable.

## Submaps

`Submap.define` (`lib/key/submap.lua`) builds a submap from bind rows.

- `hint` groups action ids into the compact hint bar. `lib/key/submap_hint.lua` derives the keys and labels from the rows and sends the result to Quickshell's `submap_hints` target on every entry. A submap with a hint is left out of which-key's auto-show in `hyprland.lua`. `home/hypr/tests/submap_hints.lua` pins what each hint lists.
- `targets` (Windows, Resize, Move) marks a submap whose keys act on the focused window or the selection. `lib/selection.lua` holds that selection and carries it between such submaps. It clears the selection on any other switch (`Submap.enter`, `Submap.reset` and Hyprland's submap event). It draws each selected window's border with `set_prop`, kept in step with config changes and reloads through window tags, and sends the selection to Quickshell, which numbers the windows.

## Code

- `init.lua`: loads `global/` and `submaps/`.
- `global/init.lua`: loads the files below, in order.
- `global/general.lua`: window keys (close, fullscreen, maximize, float, scratchpad, monitors), the keybind help and the direction keys.
- `global/workspace.lua`: workspace focus and move keys, numbered per monitor when workspaces are persistent.
- `global/shortcuts.lua`: terminal, menu, file manager and task manager keys, and `B` into the Bar submap.
- `global/tools.lua`: screenshot, zoom, voice, password picker and overview keys.
- `global/pickers.lua`: clipboard, directory and emoji pickers and the HyprVim keys.
- `global/media.lua`: media keys and their Leader forms.
- `global/keyless.lua`: loads the defs for actions that have no key.
- `global/power.lua`: the lid switch and power button.
- `global/mouse.lua`: wheel workspace cycling, window drag and resize.
- `submaps/init.lua`: loads each submap.
- `submaps/<name>/init.lua`: one submap each, all the same shape.
- `submaps/bar/rows.lua`: the Bar popup rows, shared with Leader.
