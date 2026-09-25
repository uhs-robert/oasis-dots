// home/quickshell/.config/quickshell/components/neovim/WindowSegment.qml
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../../theme"

// Lualine section c: the focused window's app on this monitor and, for terminals, its working directory.
Item {
    id: root

    property string screen_name: ""
    property int bar_height: 24
    // The room the path may take before it elides from the left.
    property real max_width: 400

    property string app_name: ""
    property string cwd: ""
    property var toplevel: null

    readonly property var terminal_classes: ["kitty", "foot", "alacritty", "wezterm", "org.wezfurlong.wezterm", "com.mitchellh.ghostty", "xterm"]
    readonly property string home: Quickshell.env("HOME")

    visible: root.app_name !== ""
    // Everything but the path, and the narrowest the segment gets: the app plus up to 120px of path.
    readonly property real lead: 24 + app_text.implicitWidth + (root.cwd !== "" ? 22 : 0)
    readonly property real min_width: root.visible ? root.lead + (root.cwd !== "" ? Math.min(path_text.implicitWidth, 120) : 0) : 0
    implicitWidth: root.lead + (root.cwd !== "" ? path_text.width : 0)
    implicitHeight: root.bar_height

    function class_of(t) {
        if (t.wayland && t.wayland.appId) return t.wayland.appId;
        return (t.lastIpcObject && t.lastIpcObject.class) || "";
    }

    // The focused window if it is on this monitor, else the one last focused on this monitor's workspace.
    function focused_here() {
        const active = Hyprland.activeToplevel;
        if (active && active.workspace && active.workspace.monitor && active.workspace.monitor.name === root.screen_name) return active;
        const mon = Hyprland.monitors.values.find(m => m.name === root.screen_name);
        const ws = mon ? mon.activeWorkspace : null;
        if (!ws) return null;
        const last = ((ws.lastIpcObject && ws.lastIpcObject.lastwindow) || "").replace(/^0x/, "");
        const list = ws.toplevels.values;
        return list.find(t => t.address === last) || (list.length > 0 ? list[list.length - 1] : null);
    }

    function refresh() {
        const t = root.focused_here();
        root.toplevel = t;
        if (!t) {
            root.app_name = "";
            root.cwd = "";
            return;
        }
        const cls = root.class_of(t);
        const entry = cls ? DesktopEntries.heuristicLookup(cls) : null;
        root.app_name = entry && entry.name ? entry.name : cls;
        const terminal = root.terminal_classes.indexOf(cls.toLowerCase()) >= 0 || (!!entry && Array.from(entry.categories || []).indexOf("TerminalEmulator") >= 0);
        const pid = t.lastIpcObject ? t.lastIpcObject.pid : 0;
        if (!terminal || !pid) {
            root.cwd = "";
            return;
        }
        cwd_proc.pending = [String(pid), t.title || ""];
        if (!cwd_proc.running) cwd_proc.start_pending();
    }

    // Lualine-style path: ~ for $HOME, the last dir and its two parents whole (plus the file name), higher dirs to one
    // letter except dot-folders, then 48 chars at most, cut from the left.
    function shorten(path, is_file) {
        if (path === "") return "";
        const p = root.home && (path === root.home || path.startsWith(root.home + "/")) ? "~" + path.slice(root.home.length) : path;
        const parts = p.split("/");
        const keep = parts.length - (is_file ? 4 : 3);
        const short = parts.map((d, i) => i >= keep || d === "" || d === "~" || d.startsWith(".") ? d : d.charAt(0)).join("/");
        if (short.length <= 48) return short;
        const tail = short.slice(short.length - 46);
        const cut = tail.indexOf("/");
        return "\u2026/" + (cut >= 0 ? tail.slice(cut + 1) : tail);
    }

    // Runs once per event; a change while it runs queues one more pass.
    Process {
        id: cwd_proc
        property var pending: null

        function start_pending() {
            if (!cwd_proc.pending) return;
            cwd_proc.command = [Quickshell.shellDir + "/scripts/window-cwd"].concat(cwd_proc.pending);
            cwd_proc.pending = null;
            cwd_proc.running = true;
        }

        stdout: StdioCollector {
            // window-cwd marks an open Neovim file with "file:".
            onStreamFinished: {
                const out = text.trim();
                root.cwd = out.startsWith("file:") ? root.shorten(out.slice(5), true) : root.shorten(out, false);
            }
        }
        onExited: cwd_proc.start_pending()
    }

    Connections {
        target: Hyprland

        function onActiveToplevelChanged() {
            Qt.callLater(root.refresh);
        }

        function onRawEvent(event) {
            if (["activewindow", "activewindowv2", "windowtitle", "windowtitlev2", "workspace", "workspacev2", "focusedmon", "closewindow", "openwindow", "movewindow"].includes(event.name)) Qt.callLater(root.refresh);
        }
    }

    Component.onCompleted: Qt.callLater(root.refresh)

    Row {
        id: row
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Text {
            id: app_text
            anchors.verticalCenter: parent.verticalCenter
            text: root.app_name
            color: Style.bar_fg
            font.family: Style.bar_font_family
            font.pixelSize: Style.bar_font_size
        }

        Shape {
            visible: root.cwd !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 16
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 1.2
                strokeColor: Style.text_muted
                fillColor: "transparent"
                startX: 1
                startY: 1
                PathLine { x: 5; y: 8 }
                PathLine { x: 1; y: 15 }
            }
        }

        Text {
            id: path_text
            visible: root.cwd !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, Math.min(implicitWidth, root.max_width - root.lead))
            elide: Text.ElideLeft
            text: root.cwd
            color: Style.text_dim
            font.family: Style.bar_font_family
            font.pixelSize: Style.bar_font_size
        }
    }
}
