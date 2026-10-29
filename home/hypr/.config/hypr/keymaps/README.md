# Keymaps

All shipped keys. [Changing keybinds](../../../../../docs/keybinds.md) is the guide for users, who add or replace keys from `custom/` without editing these files.

## Where a key lives

- `global/`: keys outside any submap, one file per topic.
- `submaps/<name>/init.lua`: one folder per submap, all the same shape. The list is in `submaps/init.lua`.
- `submaps/bar/rows.lua`: the Bar popup rows. The Leader submap reuses them.

Shipped actions carry no key, so a key is a line here. A global key is an `Act.bind(id, { key, args, desc })` line in `global/`, and a submap key is a row in that submap's file. To move a shipped key, edit that line. See [actions](../lib/act/README.md).

## Binding rules

Register binds through `lib/key/bind.lua` (`Bind.key`, `Bind.submap`), never raw `hl.bind` or `hl.define_submap`. `Bind` tracks binds per submap, so `Bind.unbind` can remove a key from one submap. `Bind.unbind` and `Bind.submap` are public API for `custom/`: keep their signatures stable.

## Submaps

`Submap.define` (`lib/key/submap.lua`) builds a submap from bind rows.

- `hint` groups action ids into the compact hint bar. `lib/key/submap_hint.lua` derives the keys and labels from the rows and sends the result to Quickshell's `submap_hints` target on every entry. A submap with a hint is left out of which-key's auto-show in `hyprland.lua`. `home/hypr/tests/submap_hints.lua` pins what each hint lists.
- `targets` (Windows, Resize, Move) marks a submap whose keys act on the focused window or the selection. `lib/selection.lua` holds that selection and carries it between such submaps. It clears the selection on any other switch (`Submap.enter`, `Submap.reset` and Hyprland's submap event). It draws each selected window's border with `set_prop`, kept in step with config changes and reloads through window tags, and sends the selection to Quickshell, which numbers the windows.
