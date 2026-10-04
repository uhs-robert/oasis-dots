// home/quickshell/.config/quickshell/services/Zoom.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// State for the Hyprland zoom submap: a live loupe at the pointer, or the compositor's full-screen zoom.
Singleton {
    id: root

    property bool active: false
    property bool full: false
    property string cursor_screen: ""
    property point cursor_point: Qt.point(0, 0)
    readonly property bool loupe_shown: root.active && !root.full
    readonly property string socket_path: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + "/.socket.sock"

    function set_factor(factor) {
        Quickshell.execDetached(["hyprctl", "eval", "hl.config({ cursor = { zoom_factor = " + factor + " } })"]);
    }

    function start() {
        root.full = false;
        root.active = true;
    }

    function stop() {
        root.active = false;
        root.full = false;
        root.cursor_screen = "";
        root.set_factor(1);
    }

    function toggle_full() {
        if (!root.active) return;
        root.full = !root.full;
        root.set_factor(root.full ? Screenshot.zoom : 1);
    }

    function step(delta) {
        Screenshot.step_zoom(delta);
    }

    function size(delta) {
        Screenshot.step_lens(delta);
    }

    Connections {
        target: Screenshot
        function onZoomChanged() {
            if (root.active && root.full) root.set_factor(Screenshot.zoom);
        }
    }

    function place(x, y) {
        for (const s of Quickshell.screens) {
            if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) {
                root.cursor_screen = s.name;
                root.cursor_point = Qt.point(x - s.x, y - s.y);
                return;
            }
        }
    }

    // Hyprland answers one request per connection, then closes it.
    Socket {
        id: sock
        path: root.socket_path
        onConnectedChanged: {
            if (!sock.connected) return;
            sock.write("j/cursorpos");
            sock.flush();
        }
        parser: StdioCollector {
            onStreamFinished: {
                sock.connected = false;
                try {
                    const pos = JSON.parse(this.text);
                    root.place(pos.x, pos.y);
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 16
        repeat: true
        running: root.loupe_shown
        triggeredOnStart: true
        onTriggered: if (!sock.connected) sock.connected = true
    }
}
