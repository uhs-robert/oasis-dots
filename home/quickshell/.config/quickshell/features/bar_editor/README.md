# Bar editor

A full-screen mode that edits the bar modules on the real bars. Open it with `qs ipc call bareditor open ""` (an empty string is the focused monitor; `open DP-1` picks one), `hypr-act bareditor.open` or `qs ipc call bareditor toggle`; `close` and `state` exist too. Settings > Bar modules > Edit bar opens it too (after Settings closes; Settings does not reopen). The keys, the shared versus own layout rules and what is not covered are in [`specs/core/baredit.md`](../../../../../../specs/core/baredit.md).

- `BarEditor.qml` (singleton) holds the state: which monitor and module are selected, the mode, the undo stacks, and the key dispatcher `press("h")`. Every edit is a pure function in [`../bar/BarLayout.js`](../bar/README.md) applied through `BarSettings.set_state`, so the bars change as keys are pressed.
- `BarEditorWindow.qml` is one overlay per screen (`quickshell-bareditor`). Every screen draws its own selection and swallows the pointer, leaving the system cursor as it is (skin cursors are for modes where the keyboard moves the pointer); only the picked monitor's window takes the keyboard (an exclusive grab, which is what lets it follow monitor select) and draws the mode, hints and boxes.
- [`../bar/BarItems.qml`](../bar/README.md) is where `Bar.qml` publishes each live module, so the overlay can place its mark on it (kept in `bar/` so the bar never imports the editor).
- `BarEditorIpc.qml` is the `bareditor` IPC target.

Tests: `home/quickshell/tests/bar_editor/` runs the real `BarSettings` and `BarEditor` in a headless `qs` (`lib/check.sh --only bar-editor`); the pure edits are in `tests/bar_layout.js`. No layer-shell window loads headless, so the windows are checked with the `shadow` skill.
