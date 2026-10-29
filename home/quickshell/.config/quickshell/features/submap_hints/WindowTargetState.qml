pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.features.bar
import "../../core/WindowVisibility.js" as WindowVisibility
import "SelectionOrder.js" as SelectionOrder

// The window selection of the `targets` submaps (Windows, Resize, Move), which
// home/hypr/.config/hypr/lib/selection.lua keeps and sends over `submap_hints selection`, and where those
// windows are. Window places are reread from Hyprland only while such a submap is up.
Singleton {
    id: root

    readonly property bool active: !!SubmapState.hint && SubmapState.hint.targets === true
    // Selected addresses as Quickshell writes them (no 0x), in the order they were selected.
    property var selected: []
    // The (generation, serial) of the last selection applied, as SelectionOrder.js orders them.
    property real generation: 0
    property real serial: 0

    function apply(next) {
        if (!next)
            return;
        root.generation = next.generation;
        root.serial = next.serial;
        root.selected = next.selected;
    }

    // Stores a selection `{ "generation": g, "serial": n, "windows": ["0x..."] }` unless a newer one was applied;
    // returns "" or why it was refused.
    function set_selection(json) {
        let spec;
        try {
            spec = JSON.parse(json);
        } catch (e) {
            return "not JSON: " + e.message;
        }
        if (!spec || typeof spec.generation !== "number" || typeof spec.serial !== "number" || !Array.isArray(spec.windows))
            return "needs a generation, a serial and windows";
        root.apply(SelectionOrder.after_selection({ generation: root.generation, serial: root.serial }, spec));
        return "";
    }

    // A config load's generation starts with nothing selected.
    function clear(generation) {
        root.apply(SelectionOrder.after_clear({ generation: root.generation, serial: root.serial }, generation));
    }

    // The 1-based place of a window in the selection, 0 when it is not selected.
    function selection_number(address) {
        return root.selected.indexOf(address) + 1;
    }

    // Windows a screen shows now, each { address, x, y, w, h } in that screen's coordinates, by the rule the screenshot
    // window picker uses (core/WindowVisibility.js): its active workspace, its open special workspace and pinned
    // windows. Grouped tabs that are not shown are skipped, and so are the tiled windows a fullscreen or maximized one
    // covers.
    function windows_on(screen) {
        const monitor = screen ? Hyprland.monitorFor(screen) : null;
        if (!monitor)
            return [];
        const shown_workspaces = WindowVisibility.shown_by_monitor(Hyprland.monitors.values.map(m => m.lastIpcObject));
        const shown = Hyprland.toplevels.values.filter(t => {
            const ipc = t.lastIpcObject;
            return ipc && ipc.at && ipc.size && ipc.monitor === monitor.id && WindowVisibility.is_shown(ipc, shown_workspaces);
        });
        const shown_ipc = shown.map(t => t.lastIpcObject);
        const out = [];
        for (const toplevel of shown) {
            const ipc = toplevel.lastIpcObject;
            if (WindowVisibility.is_covered(ipc, shown_ipc))
                continue;
            out.push({
                address: toplevel.address,
                x: ipc.at[0] - screen.x,
                y: ipc.at[1] - screen.y,
                w: ipc.size[0],
                h: ipc.size[1]
            });
        }
        return out;
    }

    function refresh() {
        Hyprland.refreshToplevels();
        Hyprland.refreshMonitors();
    }

    onActiveChanged: if (root.active) root.refresh()

    // Window and workspace changes that move a frame; `custom>>window_targets` is the event the Lua actions raise after
    // a relative move or resize, which Hyprland reports with no event of its own.
    readonly property var geometry_events: ["activewindowv2", "workspacev2", "movewindowv2", "openwindow", "closewindow", "changefloatingmode", "fullscreen", "focusedmonv2", "activespecialv2", "moveworkspacev2", "pin"]

    Connections {
        target: Hyprland
        enabled: root.active

        function onRawEvent(event) {
            if (root.geometry_events.includes(event.name) || (event.name === "custom" && event.data === "window_targets")) {
                if (!soon.running) soon.start();
                settled.restart();
            }
        }
    }

    // Coalesces a held key's repeats into one reread per frame or so.
    Timer {
        id: soon
        interval: 16
        onTriggered: root.refresh()
    }

    // Once more after the layout's animation: a tiled window's neighbours can report their place before it settles.
    Timer {
        id: settled
        interval: 400
        onTriggered: root.refresh()
    }
}
