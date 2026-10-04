// home/quickshell/.config/quickshell/services/Zoom.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// State for zoom mode: a live loupe at the pointer, or the compositor's full-screen zoom.
Singleton {
    id: root

    property bool active: false
    property bool full: false
    // Holds the keyboard for the whole session, like the selector's focus_screen.
    property string focus_screen: ""
    property string cursor_screen: ""
    property point cursor_point: Qt.point(0, 0)
    // Mirrors Loupe's odd sample count; logical half-size of the area the lens shows.
    readonly property int sample_count: Math.floor(Screenshot.lens_size / Screenshot.zoom) % 2 === 0 ? Math.floor(Screenshot.lens_size / Screenshot.zoom) + 1 : Math.floor(Screenshot.lens_size / Screenshot.zoom)
    readonly property real sample_half: ((root.sample_count - 1) / 2 + 1) / root.sample_scale
    property int scan_step: -1
    property int scan_steps: 6
    readonly property bool scan_complete: root.scan_step >= root.scan_steps
    property bool lens_on: true
    property real warp_at: 0
    readonly property bool reticle_shown: root.active && !root.full
    readonly property bool loupe_shown: root.reticle_shown && root.lens_on

    // The loupe's buffer px per logical px, kept through full screen.
    property real sample_scale: 1
    readonly property real screen_height: Quickshell.screens.find(s => s.name === root.cursor_screen)?.height ?? 0
    // Full screen shows the lens's area: its height fills the monitor, centered on the cursor.
    readonly property real wanted_factor: root.full && root.screen_height > 0 ? Math.max(1, root.screen_height / (root.sample_half * 2)) : 1
    readonly property string wanted_cursor: "hl.config({ cursor = { zoom_factor = " + root.wanted_factor + ", zoom_detached_camera = " + !root.full + ", zoom_rigid = " + root.full + " } })"
    onActiveChanged: Screenshot.set_capture_opaque(root.active)
    onWanted_cursorChanged: if (!cursor_proc.running) root.apply_cursor()

    // One hyprctl at a time, so a stale state can never land after a newer one.
    function apply_cursor() {
        cursor_proc.applied = root.wanted_cursor;
        cursor_proc.command = ["hyprctl", "eval", root.wanted_cursor];
        cursor_proc.running = true;
    }

    Process {
        id: cursor_proc
        property string applied: ""
        onExited: if (cursor_proc.applied !== root.wanted_cursor) root.apply_cursor()
    }

    function start() {
        const mon = Hyprland.focusedMonitor;
        root.focus_screen = mon ? mon.name : (Quickshell.screens[0]?.name ?? "");
        root.full = false;
        root.active = true;
        locate_proc.running = true;
    }

    function stop() {
        root.active = false;
        root.full = false;
        root.cursor_screen = "";
    }

    function toggle() {
        if (root.active) root.stop();
        else root.start();
    }

    function toggle_full() {
        if (!root.active) return;
        root.full = !root.full;
    }

    function step(delta) {
        Screenshot.step_zoom(delta);
    }

    function size(delta) {
        Screenshot.step_lens(delta);
    }

    function screen_at(x, y) {
        let best = null;
        let best_d = Infinity;
        for (const s of Quickshell.screens) {
            const d = Math.hypot(Math.max(s.x - x, 0, x - (s.x + s.width - 1)), Math.max(s.y - y, 0, y - (s.y + s.height - 1)));
            if (d < best_d) {
                best_d = d;
                best = s;
            }
        }
        return best;
    }

    function place(x, y) {
        const s = root.screen_at(x, y);
        if (!s) return;
        root.cursor_screen = s.name;
        root.cursor_point = Qt.point(Math.max(0, Math.min(s.width - 1, x - s.x)), Math.max(0, Math.min(s.height - 1, y - s.y)));
    }

    // Moves the zoom cursor in global coordinates and warps the real pointer to match.
    function move(dx, dy) {
        const from = Quickshell.screens.find(s => s.name === root.cursor_screen);
        if (!from) return;
        const gx = from.x + root.cursor_point.x + dx;
        const gy = from.y + root.cursor_point.y + dy;
        root.place(gx, gy);
        const to = Quickshell.screens.find(s => s.name === root.cursor_screen);
        const wx = to.x + root.cursor_point.x;
        const wy = to.y + root.cursor_point.y;
        root.warp_at = Date.now();
        Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.cursor.move({ x = " + wx + ", y = " + wy + " }))"]);
    }

    Process {
        id: locate_proc
        command: ["hyprctl", "cursorpos"]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split(",");
                if (parts.length === 2 && root.cursor_screen === "") root.place(Number(parts[0]), Number(parts[1]));
            }
        }
    }
}
