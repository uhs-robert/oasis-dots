# DesertFox config

My DesertFox keymap, search engines and settings. `just stow desertfox` links this directory to `~/.config/desertfox/`. `just desertfox-config` merges it into Firefox's managed storage file, and `qr` in the browser reloads the extension.

Run `just build` in the DesertFox checkout first. The recipe finds that checkout at `$DESERTFOX_DIR`, or at `repos/desertfox` when unset. `just repos` sets that checkout up.

Private bindings and container names join through `keymap.d/` files from a private repo. Each binding is one line of the command grammar described in the DesertFox README. Nothing private belongs here.

## Code

- `.config/desertfox/keymap.toml`: bindings per mode, plus the `search_keys` and `container_keys` shortcuts. Entries equal to DesertFox's defaults are left out.
- `.config/desertfox/search_engines.toml`: engine URL templates and labels.
- `.config/desertfox/settings.toml`: the default engine and the new tab page.
