# dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/). Packages live under `home/`.

## Full Install (Automated)

```bash
./install.sh        # full install (Arch only)
./install.sh -m     # minimal (skip optional components)
./install.sh -y     # auto-confirm all prompts
./uninstall.sh      # remove symlinks
```

Installs system packages, AUR packages, fonts, and dev tools, then stows dotfiles into `~/`. Prompts for optional components (greetd, Steam, Nvidia, dev runtimes).

Flags: `--no-aur`, `--no-cargo`, `--no-system-files`, `--no-services`.

## Partial Install (Manual Stow)

If you don't want to install the full dotfiles then you may also manually stow the individual packages that you want.

```bash
stow -d home <package>     # deploy a package
stow -d home -D <package>  # remove a package
```

## Yazi packages

Yazi plugins managed by `ya pkg` use `~/.config/yazi/package.toml` as the reproducible package manifest. Keep that file tracked in this repository and let `ya pkg` manage package state rather than manually editing package-managed plugin files.

```bash
ya pkg add <package>     # add a plugin and update package.toml
ya pkg delete <package>  # remove a plugin and update package.toml
ya pkg upgrade           # update installed packages and package.toml
ya pkg install           # restore packages recorded in package.toml
```

After changing Yazi packages, commit the resulting `home/yazi/.config/yazi/package.toml` change. Package-managed plugin directories under `home/yazi/.config/yazi/plugins/` are generated state and are ignored; only local plugins are tracked there. Do not hand-author package metadata or copy upstream plugin files as a substitute for running `ya pkg`.

## Justfile

Common tasks are wrapped in a `justfile` (run with [`just`](https://github.com/casey/just)). With `just`, you can just run:

```bash
just                  # list recipes
just stow <package>   # symlink one package
just unstow <package> # remove one package's symlinks
just install          # run install.sh
just uninstall        # run uninstall.sh
just sync-root-yazi   # regenerate root's Yazi keymap from the user's
```

## Betterbird / tbkeys

Vim-style keybindings for Betterbird, provided by the tbkeys add-on. Two locations matter:

- `home/thunderbird/tbkeys/keys.json` - the keymap, one line per binding.
- `home/thunderbird/.config/tbkeys/*.js` - the code the bindings call, split into cohesive feature modules. Stowed to `~/.config/tbkeys/` by the `thunderbird` package, and loaded automatically each time Betterbird starts.

`system/opt/betterbird/betterbird.cfg` resolves `~/.config/tbkeys/` once per window and loads the modules through `Services.scriptloader.loadSubScriptWithOptions` in a fixed dependency order: `core.js`, `selection.js`, `folders.js`, `motions.js`, `navigation.js`, `actions.js`, `yank.js`, `editor.js`, `search.js`, `command.js`, `ui.js`, `whichkey.js`. A missing or failing module logs which file it was rather than a generic error, and loading stops there for that window.

Each module is `(function (tk) { "use strict"; ... })(window.tk);`, populating the shared `window.tk` namespace rather than using ES modules, imports, a bundler, or a build step. `core.js` is the exception: it first runs the teardown hooks the previous load left behind (`whichkey_teardown`, `ui_teardown`, `command_teardown`, `editor_teardown`) so a reload doesn't leak listeners or injected elements, then creates a fresh `window.tk = {}` before populating it, so a reload never carries stale functions from a previous version.

Module responsibilities, following a one-way dependency direction (later modules may call into earlier ones, never the reverse):

- `core.js` - fresh `window.tk` init, shared window/tree accessors, count handling, `repeat_command`, last-action recording, and other primitives with no feature dependency.
- `selection.js` - visual-mode state (`window.vim`/`visualAnchor`/`visualEnd`) and `tk_toggle_visual`. Motions, navigation, and actions read this state directly rather than each owning a copy.
- `folders.js` - folder lookup/display, jump-list history, folder marks, folder-tree expand/collapse helpers, and `g`-prefixed goto commands.
- `motions.js` - `h/j/k/l`, `gg`/`G`, paging, viewport repositioning (`zz`/`zt`/`zb`), and the thread/folder fold commands (`zM`/`zR`).
- `navigation.js` - higher-level stepping (unread/thread/starred/attachment), focus switching, and tab navigation.
- `actions.js` - message mutations (read/unread/flag/junk/delete/archive/move) and `.` repeat-last-action.
- `yank.js` - non-mutating message metadata/content yanks and privileged clipboard writes.
- `editor.js` - the compose bridge: secure per-window temp files, asynchronous Kitty/Neovim/Pandoc sessions, conflict detection, Markdown-to-HTML conversion, and compose-editor write-back. Plain-text compose opens as text; HTML compose opens as Markdown.
- `search.js` - context-sensitive `/` search: incremental folder search, Quick Filter Bar thread search, native message find, repeat/cancel state, and `tk_escape`.
- `command.js` - the Vim-style `:` command line: input UI, parser, and a declarative command registry (`archive`, `move`, `filter`, `open`, `edit`) that calls into the existing folder/action helpers rather than duplicating them.
- `ui.js` - the persistent mode/count/status indicator and lightweight transient feedback.
- `whichkey.js` - the passive which-key overlay: chord trie, timers, and transient rendering. Loaded last, and fires the initial `tk.repaint_mode()` once every module is in place. Visualization only - it never touches Mousetrap or tbkeys keyboard dispatch.

New behavior belongs in the module matching its responsibility above; a feature spanning several (e.g. an operator acting over a range) should consume the existing `selection.js`/`motions.js`/`actions.js` primitives rather than reimplementing them.

After editing any module, restart Betterbird.

The `e` binding and `:edit` command open the current compose body in Kitty/Neovim. `Ctrl+E` is also a direct compose-body shortcut. Plain-text messages open as text; HTML messages are converted to Markdown and converted back to HTML after saving. Pandoc must be installed for HTML compose editing. The compose body displays INSERT mode while typing; `Ctrl+O` enters NORMAL mode for one command, after which the body returns to INSERT. In that NORMAL window, `e` opens Neovim. To use another terminal/editor launcher, set `window.__tbkeys_external_editor_command` to an argument array before invoking it; the file path is appended automatically (for example, `["wezterm", "start", "--", "nvim"]`). The converter can be overridden with `window.__tbkeys_markdown_converter_command` (for example, `["pandoc"]`). In a mail window, `/` searches the focused pane: folders use the incremental folder search, the thread list uses Thunderbird's Quick Filter Bar, and the message pane uses native find-in-message; `n`/`N` repeat folder or message searches.

After editing `keys.json`, paste its contents into the add-on's options page (Add-ons Manager, tbkeys, Options). That file is a tracked copy, not something the add-on reads from disk. The same is true of `quicktext.json`.

Betterbird upgrades wipe the startup file that loads these modules, so `install.sh` sets up a pacman hook that puts it back automatically. Nothing to do after an upgrade.

## Root Yazi

The user Yazi keymap uses `~` and `$USER`, which resolve to `/root` when Yazi runs as root, so root gets a rewritten copy at `/root/.config/yazi/keymap.toml` rather than a symlink. Launch root Yazi with `yazi-root` (installed to `/usr/local/bin` by `install.sh`): it regenerates that copy from the current user keymap on every launch, so the two never drift. It finds the user config by resolving the `yazi.toml` symlink in `/root/.config/yazi`, so no username is configured anywhere. To refresh the copy without launching Yazi, run `yazi-root --sync-only` or `just sync-root-yazi`.

Plain `sudo yazi` stays in sync too, via a shim at `/usr/local/sbin/yazi` that runs the same regeneration before exec'ing the real binary. `sudo` ignores the caller's `PATH` in favour of `secure_path`, which starts with `/usr/local/sbin`, while a normal user's `PATH` has no `sbin` entries, so the shim applies to `sudo yazi` only, and your own `yazi` still runs `/usr/bin/yazi` directly.
