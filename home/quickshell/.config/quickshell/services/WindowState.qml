// home/quickshell/.config/quickshell/services/WindowState.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

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

    // A workspace's own toplevels list can keep a window that moved away; the window's workspace stays current.
    function windows_on(workspace) {
        return Hyprland.toplevels.values.filter(t => t.workspace === workspace);
    }

    // Every workspace with its monitor, read with hyprctl; Quickshell can miss persistent ones at login.
    property var hypr_workspaces: []

    // One resync for all bars: the workspace/toplevel models can lag behind these events.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (["openwindow", "closewindow", "movewindow", "workspace", "focusedmon"].includes(event.name)) {
                refresh_soon.restart();
            } else if (["createworkspacev2", "destroyworkspacev2", "moveworkspacev2", "configreloaded", "monitoraddedv2"].includes(event.name)) {
                ids_refresh.restart();
            }
        }
    }

    Timer {
        id: refresh_soon
        interval: 40
        onTriggered: root.refresh()
    }

    Timer {
        id: ids_refresh
        interval: 200
        onTriggered: {
            Hyprland.refreshWorkspaces();
            ids_proc.running = true;
        }
    }

    Process {
        id: ids_proc
        running: true
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.hypr_workspaces = JSON.parse(text).filter(w => w.id > 0).map(w => ({ id: w.id, monitor: w.monitor }));
                } catch (e) {}
            }
        }
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
        const ws = (root.find(address) || {}).workspace;
        const hidden = ws && !(ws.name || "").startsWith("special:") && (!ws.monitor || ws.monitor.activeWorkspace !== ws);
        const target = hidden ? root.workspace_selector(ws.id) : "";
        const steps = [
            "hl.dsp.focus({ window = " + root.selector(address) + " })",
            "hl.dsp.window.alter_zorder({ mode = 'top', window = " + root.selector(address) + " })"
        ];
        if (target === "") {
            steps.forEach(s => Hyprland.dispatch(s));
            return;
        }
        // Separate dispatches can land out of order, and the workspace switch would then refocus its last window.
        steps.unshift("hl.dsp.focus({ workspace = " + target + " })");
        Quickshell.execDetached(["hyprctl", "eval", steps.map(s => "hl.dispatch(" + s + ")").join("; ")]);
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

    function close(address) {
        if (!root.valid(address)) return;
        Hyprland.dispatch("hl.dsp.window.close({ window = " + root.selector(address) + " })");
    }

    // Swaps two windows' places; `window` names the source, as it does for window.move.
    function swap(address, other_address) {
        if (!root.valid(address) || !root.valid(other_address) || address === other_address) return;
        Hyprland.dispatch("hl.dsp.window.swap({ window = " + root.selector(address) + ", target = " + root.selector(other_address) + " })");
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
