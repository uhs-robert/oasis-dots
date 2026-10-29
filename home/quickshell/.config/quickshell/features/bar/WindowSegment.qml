import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.theme
import qs.features.windows
import "DirectoryFormat.js" as DirectoryFormat

// The focused window's app on this monitor and, for terminals, its working directory (or open Neovim file).
// Drawn by the Directory module, and by lualine in section c.
Item {
    id: root

    property string screen_name: ""
    property int bar_height: 24
    // The room the path may take before it elides from the left.
    property real max_width: 400
    // Side padding; 0 inside an island, whose layout spaces its items.
    property real padding: 12

    // window-cwd's raw output; `cwd` is what it shows under the current switches. A program running in a terminal
    // (yazi, nvim, claude) is named by its command in place of the terminal.
    property string app_name: ""
    property string cwd_output: ""
    readonly property var cwd_parts: DirectoryFormat.parse(root.cwd_output)
    readonly property string window_app: root.cwd_parts.app || root.app_name
    readonly property string cwd: DirectoryFormat.path_text(root.cwd_parts.path, BarSettings.directory_switches, root.home)
    readonly property string shown_app: DirectoryFormat.app_text(root.window_app, BarSettings.directory_switches)
    readonly property string tooltip_text: DirectoryFormat.tooltip_text(root.window_app, root.cwd_parts.path, root.home)
    property var toplevel: null

    readonly property var terminal_classes: ["kitty", "foot", "alacritty", "wezterm", "org.wezfurlong.wezterm", "com.mitchellh.ghostty", "xterm"]
    readonly property string home: Quickshell.env("HOME")

    // Not `visible`, which also follows the parent: a hidden Directory module would otherwise never reappear.
    readonly property bool has_content: root.shown_app !== "" || root.cwd !== ""
    visible: root.has_content
    // Everything but the path, and the narrowest the segment gets: the app plus up to 120px of path.
    readonly property bool has_chevron: root.shown_app !== "" && root.cwd !== ""
    readonly property real lead: root.padding * 2 + (root.shown_app !== "" ? app_text.implicitWidth : 0) + (root.has_chevron ? 22 : 0)
    readonly property real min_width: root.has_content ? root.lead + (root.cwd !== "" ? Math.min(path_text.implicitWidth, 120) : 0) : 0
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
        const list = WindowState.windows_on(ws);
        return list.find(t => t.address === last) || (list.length > 0 ? list[list.length - 1] : null);
    }

    function refresh() {
        const t = root.focused_here();
        root.toplevel = t;
        if (!t) {
            root.retry_settle();
            root.app_name = "";
            root.cwd_output = "";
            return;
        }
        const cls = root.class_of(t);
        if (!cls) root.retry_settle();
        const entry = cls ? DesktopEntries.heuristicLookup(cls) : null;
        root.app_name = entry && entry.name ? entry.name : cls;
        const terminal = root.terminal_classes.indexOf(cls.toLowerCase()) >= 0 || (!!entry && Array.from(entry.categories || []).indexOf("TerminalEmulator") >= 0);
        const pid = t.lastIpcObject ? t.lastIpcObject.pid : 0;
        if (terminal && !pid) root.retry_settle();
        if (!terminal || !pid) {
            root.cwd_output = "";
            return;
        }
        cwd_proc.pending = [String(pid), t.title || "", t === Hyprland.activeToplevel ? "1" : "0"];
        if (!cwd_proc.running) cwd_proc.start_pending();
    }

    // A window that has just opened can lack its workspace or pid for a moment, and Hyprland sends no event when they
    // arrive, so an event that finds nothing looks again a few times.
    Timer {
        id: settle_timer
        property int left: 0
        interval: 300
        onTriggered: root.refresh()
    }

    function retry_settle() {
        if (settle_timer.left <= 0) return;
        settle_timer.left--;
        settle_timer.restart();
    }

    function refresh_on_event() {
        settle_timer.left = 3;
        Qt.callLater(root.refresh);
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
            onStreamFinished: root.cwd_output = text
        }
        onExited: cwd_proc.start_pending()
    }

    Connections {
        target: Hyprland

        function onActiveToplevelChanged() {
            root.refresh_on_event();
        }

        function onRawEvent(event) {
            if (["activewindow", "activewindowv2", "windowtitle", "windowtitlev2", "workspace", "workspacev2", "focusedmon", "closewindow", "openwindow", "movewindow"].includes(event.name)) root.refresh_on_event();
        }
    }

    Component.onCompleted: root.refresh_on_event()

    Row {
        id: row
        x: root.padding
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Text {
            id: app_text
            visible: root.shown_app !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.shown_app
            color: Style.bar_fg
            font.family: Style.bar_font_family
            font.pixelSize: Style.bar_font_size
        }

        Shape {
            visible: root.has_chevron
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
