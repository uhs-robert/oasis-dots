# Actions

Each thing the desktop can do is one action: an id, a label, typed params and a `run`. Keys, the `hypr-act` script, the bar and voice all perform it through the same path.

- `init.lua` is the `Act` library. `Act.define` registers an action. `Act.bind` adds a key to one. `Act.run` and `Act.run_cli` perform one by id.
- `defer.lua` builds a `run` that calls a performer in `lib/desktop/` when the key fires, so a defs file loads without Config or a session.
- `defs/` holds the definitions, one file per action group, all the same shape. `tools.lua` has the tools, `pickers.lua` the pickers and HyprVim, and the bar areas each have a file for the IPC actions no key reaches.

## Keys

Shipped actions carry no key. `lib/` says what an action does and `keymaps/` says which key runs it, so moving a key never means editing an action. A define in `custom/` may still pass `key` and `extra_keys`. See [keymaps](../../keymaps/README.md) for where each key lives.

A defs file is live only if a keymap requires it, for example `keymaps/global/tools.lua`. The actions with no key at all load from `keymaps/global/keyless.lua`.

## Running them

`hypr-act list` and `hypr-act <id> [args...]` (`home/hypr/.local/bin/hypr-act`) list and run actions in the live session. Its header lists the exit codes. No list is committed: the running Hyprland builds it.

## Checks

The `registry` check step loads the defs under stubs (`home/hypr/tests/act_refs.lua`) and checks the ids, IPC functions and scripts they name. A new `require` in a defs file needs a stub line there. A new bind or typed IPC function needs an action, or a reasoned line in `lib/check/registry.allow`.
