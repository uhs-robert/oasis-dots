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

    property real wanted_factor: 1

    // One hyprctl at a time, so a stale factor can never land after a newer one.
    function set_factor(factor) {
        root.wanted_factor = factor;
        if (!factor_proc.running) root.apply_factor();
    }

    function apply_factor() {
        factor_proc.factor = root.wanted_factor;
        factor_proc.command = ["hyprctl", "eval", "hl.config({ cursor = { zoom_factor = " + root.wanted_factor + " } })"];
        factor_proc.running = true;
    }

    Process {
        id: factor_proc
        property real factor: 1
        onExited: if (factor_proc.factor !== root.wanted_factor) root.apply_factor()
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

    Process {
        running: root.loupe_shown
        command: ["sh", "-c", "while :; do hyprctl cursorpos || exit; sleep 0.016; done"]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split(",");
                if (parts.length === 2) root.place(Number(parts[0]), Number(parts[1]));
            }
        }
    }
}
