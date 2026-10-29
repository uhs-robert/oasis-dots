import Quickshell.Io
import qs.features.bar

IpcHandler {
    target: "submap_hints"

    // Stores the hint bar of one submap, shown while Hyprland is in it:
    // `{ "name": ..., "groups": [{ "name": ..., "keys": [[cap, label]...] }...], "footer": [[cap, label]...], "targets": true }`,
    // `targets` only for a submap whose keys act on windows, which WindowTargetOverlay then frames.
    // Called by Submap.define on every entry (lib/key/submap_hint.lua). "ok", or why the JSON was refused.
    function set(json: string): string {
        const problem = SubmapState.set_hint(json);
        return problem === "" ? "ok" : problem;
    }

    // Stores the window selection `{ "serial": n, "windows": ["0x..."] }`, sent by lib/actions/selection.lua on every
    // change. "ok", or why the JSON was refused.
    function selection(json: string): string {
        const problem = WindowTargetState.set_selection(json);
        return problem === "" ? "ok" : problem;
    }

    // Drops every stored hint and the selection. Sent on each Hyprland config load, so a hint the reload removed stops
    // showing.
    function clear(): void {
        SubmapState.hints = ({});
        WindowTargetState.clear();
    }
}
