# actions

One list of what the desktop can do, independent of the tool that does it, and `act` to run any of it.

- `.config/actions/actions.json`: each action's `id` (`area.verb`), `label`, `intent`, positional `params` (`int`, `float`, `string`, `bool`, `enum` with `values`; a `default` makes one optional), its default `key` and `extra_keys`. A key is `{key, leader, universal}`: `leader` puts it behind the leader key, `universal` keeps it live inside submaps. Schema: `specs/schema/actions.yaml`.
- `.config/actions/bindings/quickshell.json`: how the bar performs each id, either `ipc` (`target`, `function`, `args`) or `command` (`argv`, for what has no IPC function). A word may hold `{param}`; `~/` starts a home path. Schema: `specs/schema/bindings.yaml`.
- `src/`, `Cargo.toml`: the Rust crate. `src/lib.rs` (package `actions`) loads the manifest and bindings, checks params and plans the command; `src/main.rs` is the `act` binary over it. voxcmd can depend on the library by path (`actions = { path = "../actions" }`) when it gains `action = "<id>"`. It reads `serde_json` only, no async runtime.
- `act <id> [param...]`: exit 0 done, 1 the performer failed or would not start, 2 an unknown id, bad param or unreadable manifest (nothing runs). It needs the logged-in session: it calls the bar through `~/.config/hypr/scripts/qs-ipc`. `ACT_CONFIG_DIR` points it at another manifest folder.

`act` is built, not stowed: the installer runs `build_act` (`lib/install/actions.sh`) after stowing, which `cargo install`s the crate under `~/.local/share/actions-rs` and links `~/.local/bin/act`; `just act-build` does the same by hand. A machine without cargo (`--no-cargo`) gets no `act` until Rust is installed.

Add an action: an entry in `actions.json`, an entry with the same id in `bindings/quickshell.json`, then `lib/check.sh --only registry,actions-rust`. The step fails a duplicate id, a missing or stray binding, and an IPC function or script that does not exist. Hyprland binds do not read the manifest yet.

Try it: `act zoom.toggle`.
