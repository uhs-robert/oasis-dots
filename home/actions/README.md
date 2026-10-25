# actions

One list of what the desktop can do, independent of the tool that does it, and `act` to run any of it.

- `.config/actions/actions.json`: each action's `id` (`area.verb`), `label`, `intent`, positional `params` (`int`, `float`, `string`, `bool`, `enum` with `values`; a `default` makes one optional), its default `key` and `extra_keys`. A key is `{key, leader, universal}`: `leader` puts it behind the leader key, `universal` keeps it live inside submaps. Schema: `specs/schema/actions.yaml`.
- `.config/actions/bindings/quickshell.json`: how the bar performs each id, either `ipc` (`target`, `function`, `args`) or `command` (`argv`, for what has no IPC function). A word may hold `{param}`; `~/` starts a home path. Schema: `specs/schema/bindings.yaml`.
- `.local/bin/act`: `act <id> [param...]`. Exit 0 done, 1 the performer failed, 2 an unknown id, bad param or unreadable manifest (nothing runs). It needs the logged-in session: it calls the bar through `~/.config/hypr/scripts/qs-ipc`.
- `.local/share/actions/manifest.py`: the reader `act` and the `registry` check step share.

Add an action: an entry in `actions.json`, an entry with the same id in `bindings/quickshell.json`, then `lib/check.sh --only registry`. The step fails a duplicate id, a missing or stray binding, and an IPC function or script that does not exist. Hyprland binds do not read the manifest yet.

Try it: `act zoom.toggle`.
