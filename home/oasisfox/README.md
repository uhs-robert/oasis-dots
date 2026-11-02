# OasisFox config

My OasisFox keymap, search engines and settings. `just stow oasisfox` links this directory to `~/.config/oasisfox/`. `just oasisfox-config` merges it into Firefox's managed storage file, and `qr` in the browser reloads the extension.

Run `just build` in the OasisFox checkout first. The recipe finds that checkout at `$OASISFOX_DIR`, or at `repos/oasisfox` when unset. `just repos` sets that checkout up.

Private bindings and container names join through `keymap.d/` files from a private repo. Each binding is one line of the command grammar described in the OasisFox README. Nothing private belongs here.

## Code

- `.config/oasisfox/keymap.toml`: bindings per mode, plus the `search_keys` and `container_keys` shortcuts. Entries equal to OasisFox's defaults are left out.
- `.config/oasisfox/search_engines.toml`: engine URL templates and labels.
- `.config/oasisfox/settings.toml`: the default engine and the new tab page.
