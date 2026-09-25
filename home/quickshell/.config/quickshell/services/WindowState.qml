// home/quickshell/.config/quickshell/services/WindowState.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Hyprland windows in most-recently-focused order, with focus and move helpers.
Singleton {
    id: root

    // Addresses, newest first; windows missing from it fall back to Hyprland's focusHistoryID.
    property var mru: []
    readonly property var windows: root.ordered(Hyprland.toplevels.values, root.mru)
    // Before the first focus event after startup, focus history stands in for activeToplevel.
    property bool seen_active: false
    readonly property string active_address: Hyprland.activeToplevel ? Hyprland.activeToplevel.address : root.seen_active ? "" : (root.windows.find(t => root.history_of(t) === 0) || { address: "" }).address

    function history_of(toplevel) {
        const ipc = toplevel.lastIpcObject;
        return ipc && typeof ipc.focusHistoryID === "number" && ipc.focusHistoryID >= 0 ? ipc.focusHistoryID : 1000;
    }

    function ordered(list, mru) {
        const rank = t => {
            const i = mru.indexOf(t.address);
            return i >= 0 ? i : mru.length + root.history_of(t);
        };
        return list.slice().sort((a, b) => rank(a) - rank(b));
    }

    function touch(address) {
        if (!address) return;
        const alive = Hyprland.toplevels.values.map(t => t.address);
        root.mru = [address].concat(root.mru.filter(a => a !== address && alive.indexOf(a) >= 0));
    }

    // Re-reads classes, titles and focus history; the lists update when Hyprland answers.
    function refresh() {
        Hyprland.refreshToplevels();
        Hyprland.refreshWorkspaces();
    }

    function find(address) {
        return Hyprland.toplevels.values.find(t => t.address === address) || null;
    }

    function class_of(toplevel) {
        if (!toplevel) return "";
        const ipc = toplevel.lastIpcObject;
        if (ipc && ipc.class) return ipc.class;
        if (ipc && ipc.initialClass) return ipc.initialClass;
        return toplevel.wayland && toplevel.wayland.appId ? toplevel.wayland.appId : "";
    }

    // Reverse-DNS prefix dropped: org.qutebrowser.qutebrowser -> qutebrowser.
    function short_class(toplevel) {
        const cls = root.class_of(toplevel);
        return cls.indexOf(".") >= 0 ? cls.split(".").pop() : cls;
    }

    function icon_for(toplevel) {
        const cls = root.class_of(toplevel);
        if (!cls) return Quickshell.iconPath("application-x-executable", true);
        const entry = DesktopEntries.heuristicLookup(cls);
        return Quickshell.iconPath(entry && entry.icon ? entry.icon : root.short_class(toplevel).toLowerCase(), "application-x-executable");
    }

    function selector(address) {
        return "'address:0x" + address + "'";
    }

    function valid(address) {
        return /^[0-9a-fA-F]+$/.test(address || "");
    }

    function focus(address) {
        if (!root.valid(address)) return;
        Hyprland.dispatch("hl.dsp.focus({ window = " + root.selector(address) + " })");
        Hyprland.dispatch("hl.dsp.window.alter_zorder({ mode = 'top', window = " + root.selector(address) + " })");
    }

    // Negative ids would read as relative, so those workspaces go by name.
    function workspace_selector(workspace_id) {
        if (workspace_id > 0) return String(workspace_id);
        const ws = Hyprland.workspaces.values.find(w => w.id === workspace_id);
        if (!ws || !ws.name) return "";
        const name = ws.name.startsWith("special:") ? ws.name : "name:" + ws.name;
        return "'" + name.replace(/\\/g, "\\\\").replace(/'/g, "\\'") + "'";
    }

    function move_to_workspace(source_address, workspace_id, follow) {
        const target = root.workspace_selector(workspace_id);
        if (!root.valid(source_address) || target === "") return;
        Hyprland.dispatch("hl.dsp.window.move({ window = " + root.selector(source_address) + ", workspace = " + target + ", follow = " + (follow ? "true" : "false") + " })");
        if (follow) root.focus(source_address);
    }

    Connections {
        target: Hyprland

        function onActiveToplevelChanged() {
            if (!Hyprland.activeToplevel) return;
            root.seen_active = true;
            root.touch(Hyprland.activeToplevel.address);
        }
    }

    Component.onCompleted: {
        root.refresh();
        if (!Hyprland.activeToplevel) return;
        root.seen_active = true;
        root.touch(Hyprland.activeToplevel.address);
    }
}
