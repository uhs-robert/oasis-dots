.pragma library

// Which Hyprland windows a monitor shows now, from `hyprctl -j monitors` and `hyprctl -j clients` objects (or
// Quickshell's lastIpcObject copies of them): those on the monitor's active workspace, on its open special workspace,
// and pinned ones, each on the monitor it is on. Pure, so node can test it.

// A workspace as a key to compare by: its name, which Hyprland keeps unique. Hyprland 0.57 sends a special workspace
// with no `id`, and a closed one as an empty name, so ids alone would match a hidden scratchpad window to it.
function workspace_key(workspace) {
    if (!workspace) return "";
    if (workspace.name) return String(workspace.name);
    return typeof workspace.id === "number" && workspace.id !== 0 ? "#" + workspace.id : "";
}

// Each monitor's shown workspaces by monitor id: { name, ws, special }, as workspace keys; special "" while none is open.
function shown_by_monitor(monitors) {
    const shown = {};
    for (const m of monitors || []) {
        if (!m) continue;
        shown[m.id] = { name: m.name, ws: workspace_key(m.activeWorkspace), special: workspace_key(m.specialWorkspace) };
    }
    return shown;
}

// Whether a client is on screen on its monitor; `shown` is shown_by_monitor's result.
function is_shown(client, shown) {
    const m = client ? shown[client.monitor] : null;
    if (!m || !client.mapped || client.hidden || !client.workspace) return false;
    if (client.pinned === true) return true;
    const key = workspace_key(client.workspace);
    return key !== "" && (key === m.ws || key === m.special);
}

// Whether a shown client is a tiled one that a fullscreen or maximized client on its workspace covers; `clients` are
// the shown ones. Floating and pinned clients stay above it.
function is_covered(client, clients) {
    if (client.fullscreen > 0 || client.floating || client.pinned === true) return false;
    const key = workspace_key(client.workspace);
    return clients.some(c => c !== client && c.fullscreen > 0 && workspace_key(c.workspace) === key);
}
