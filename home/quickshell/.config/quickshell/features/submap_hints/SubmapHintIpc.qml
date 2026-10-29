import Quickshell.Io
import qs.features.bar

IpcHandler {
    target: "submap_hints"

    // Stores the hint bar of one submap, shown while Hyprland is in it:
    // `{ "name": ..., "groups": [{ "name": ..., "keys": [[cap, label]...] }...], "footer": [[cap, label]...], "targets": true }`,
    // `targets` only for a submap whose keys act on windows, where WindowTargetOverlay numbers the selected ones.
    // Called by Submap.define on every entry (lib/key/submap_hint.lua). "ok", or why the JSON was refused.
    function set(json: string): string {
        const problem = SubmapState.set_hint(json);
        return problem === "" ? "ok" : problem;
    }

    // Stores the window selection `{ "generation": g, "serial": n, "windows": ["0x..."] }`, sent by
    // lib/selection.lua on every change. "ok", or why the JSON was refused.
    function selection(json: string): string {
        const problem = WindowTargetState.set_selection(json);
        return problem === "" ? "ok" : problem;
    }

    // Drops every stored hint and the selection. Sent on each Hyprland config load with that load's selection
    // generation, so a hint the reload removed stops showing and a selection the old config sent is ignored.
    function clear(generation: string): void {
        SubmapState.hints = ({});
        WindowTargetState.clear(Number(generation) || 0);
    }
}
