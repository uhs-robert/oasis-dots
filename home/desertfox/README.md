# DesertFox config

My DesertFox keymap, search engines and settings. `just stow desertfox` links this directory to `~/.config/desertfox/`. `just desertfox-config` merges it into Firefox's managed storage file. It first warns, and still runs, when the DesertFox checkout is behind its upstream or `dist/commands.json` is older than the checkout's last commit. `qr` in the browser reloads the extension.

Run `just build` in the DesertFox checkout first. The recipe finds that checkout at `$DESERTFOX_DIR`, or at `repos/desertfox` when unset. `just repos` sets that checkout up.

Private bindings and container names join through `keymap.d/` files from a private repo. Each binding is one line of the command grammar described in the DesertFox README. Nothing private belongs here.

## Hosts

`just desertfox-host` installs or updates the two native hosts and the `desertfox` CLI from the latest DesertFox release. `install.sh` runs it too, except with `--server`. The Firefox permission click on `:native.install` stays manual.

## Desktop theme sync

Every Hyprland reload (login and each theme switch) runs `desertfox theme <name>` with the desktop theme name, from `home/hypr/.config/hypr/theme/generate/desertfox.lua`. The push is best effort: with the browser closed it fails silently and the browser keeps its old palette until the next reload. `settings.toml` sets `theme = "desktop"`, so DesertFox follows the push. When the saved palette cannot load and Hyprland renders the embedded fallback, the push names `oasis_moonlight`.

## External editor

In insert mode, `<C-i>` (`text.edit_external`) opens the focused text field in Neovim in a floating kitty window. Saving with `:w` closes the window and returns the text to the field. `editor.toml` sets the command, `just restow desertfox` links it, and the window rule in `home/hypr/.config/hypr/config/rules/init.lua` floats it. The [DesertFox host README](https://github.com/uhs-robert/desertfox/blob/main/host/README.md) has the file format.

## Code

- `.config/desertfox/editor.toml`: the editor the host opens for a text field (Neovim in kitty). The window rule in `home/hypr/.config/hypr/config/rules/init.lua` floats its `desertfox-editor` class.
- `.config/desertfox/keymap.toml`: bindings per mode, plus the `search_keys` and `container_keys` shortcuts. Entries equal to DesertFox's defaults are left out.
- `.config/desertfox/search_engines.toml`: engine URL templates and labels.
- `.config/desertfox/settings.toml`: the default engine, the new tab page, the bridge switch and the `desktop` theme.
