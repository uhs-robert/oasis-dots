import Quickshell.Io
import qs.features.bar

IpcHandler {
    target: "submap_hints"

    // Stores the hint bar of one submap, shown while Hyprland is in it:
    // `{ "name": ..., "groups": [{ "name": ..., "keys": [[cap, label]...] }...], "footer": [[cap, label]...] }`.
    // Called by Submap.define on every entry (lib/key/submap_hint.lua). "ok", or why the JSON was refused.
    function set(json: string): string {
        const problem = SubmapState.set_hint(json);
        return problem === "" ? "ok" : problem;
    }

    // Drops every stored hint. Sent on each Hyprland config load, so a hint the reload removed stops showing.
    function clear(): void {
        SubmapState.hints = ({});
    }
}
