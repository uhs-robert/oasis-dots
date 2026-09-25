// home/quickshell/.config/quickshell/services/Screenshot.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The screenshot menu, the region selector's shared state, and the recording indicator.
Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/screenshot.sh"

    // "select" while dragging, "toolbar" once a region is chosen, "capture" while grim runs.
    property string phase: ""
    readonly property bool selecting: root.phase !== ""
    property bool frozen: false
    // Runs on confirm instead of showing the toolbar: "" for the toolbar, else a toolbar action.
    property string preset: ""
    property string focus_screen: ""
    property string sel_screen: ""
    property rect sel_rect: Qt.rect(0, 0, 0, 0)
    readonly property bool has_selection: root.sel_screen !== "" && root.sel_rect.width >= 2 && root.sel_rect.height >= 2
    readonly property var actions: [
        { id: "copy", key: "c", label: "Copy" },
        { id: "save", key: "s", label: "Save" },
        { id: "annotate", key: "a", label: "Annotate" },
        { id: "ocr", key: "o", label: "OCR" },
        { id: "record", key: "r", label: "Record" }
    ]
    property int tool_index: 0
    // The loupe: on/off, zoom (displayed px per buffer px) and where it looks.
    property bool lens_on: true
    readonly property var zoom_levels: [2, 4, 8, 16]
    property int zoom_index: 1
    readonly property int zoom: root.zoom_levels[root.zoom_index]
    property string lens_screen: ""
    property point lens_point: Qt.point(0, 0)
    property string pending_action: ""
    property string capture_file: ""

    property bool recording: false
    property double record_start_ms: 0
    property int elapsed_s: 0
    readonly property string elapsed_text: {
        const s = root.elapsed_s;
        const pad = n => String(n).padStart(2, "0");
        return (s >= 3600 ? Math.floor(s / 3600) + ":" : "") + pad(Math.floor(s / 60) % 60) + ":" + pad(s % 60);
    }

    // Drops from the center island, like the clock.
    function open_menu() {
        const found = Popups.find_default("clock");
        if (found) {
            Popups.open("screenshot", found.item, Popups.anchor_color(found), found.screen_name);
        } else {
            const mon = Hyprland.focusedMonitor;
            Popups.open("screenshot", null, undefined, mon ? mon.name : "");
        }
    }

    // Waits for an open popup's close animation so it never lands in the capture.
    function run_after_close(fn) {
        if (Popups.open_name === "") return fn();
        Popups.close();
        after_close.fn = fn;
        after_close.restart();
    }

    function run_flag(flag) {
        root.run_after_close(() => Quickshell.execDetached([root.script, "--" + flag]));
    }

    function select(frozen, preset) {
        root.run_after_close(() => root.start_select(frozen, preset));
    }

    function start_select(frozen, preset) {
        if (root.phase === "capture") return;
        const mon = Hyprland.focusedMonitor;
        const screen = (mon && root.screen_of(mon.name)) || Quickshell.screens[0];
        root.focus_screen = screen ? screen.name : "";
        root.frozen = frozen;
        root.preset = preset || "";
        root.sel_screen = "";
        root.sel_rect = Qt.rect(0, 0, 0, 0);
        root.tool_index = 0;
        root.phase = "select";
    }

    function cancel() {
        capture_delay.stop();
        capture_watchdog.stop();
        root.phase = "";
        root.sel_screen = "";
    }

    function fail(message) {
        root.cancel();
        Quickshell.execDetached(["notify-send", "Screenshot Failed", message]);
    }

    function confirm() {
        if (!root.has_selection) return;
        if (root.preset !== "") root.act(root.preset);
        else root.phase = "toolbar";
    }

    function screen_of(name) {
        return Quickshell.screens.find(s => s.name === name) || null;
    }

    function set_selection(screen_name, x, y, w, h) {
        root.sel_screen = screen_name;
        root.sel_rect = Qt.rect(x, y, w, h);
    }

    function select_screen(screen_name) {
        const s = root.screen_of(screen_name);
        if (s) root.set_selection(screen_name, 0, 0, s.width, s.height);
    }

    function set_lens(screen_name, x, y) {
        root.lens_screen = screen_name;
        root.lens_point = Qt.point(x, y);
    }

    function step_zoom(delta) {
        root.zoom_index = Math.max(0, Math.min(root.zoom_levels.length - 1, root.zoom_index + delta));
    }

    // Moves by dx/dy and grows by dw/dh, kept inside the selection's screen; the loupe follows the corner that moved.
    function nudge(dx, dy, dw, dh) {
        const s = root.screen_of(root.sel_screen);
        if (!s || !root.has_selection) return;
        const r = root.sel_rect;
        const w = Math.max(2, Math.min(s.width, r.width + dw));
        const h = Math.max(2, Math.min(s.height, r.height + dh));
        const x = Math.max(0, Math.min(s.width - w, r.x + dx));
        const y = Math.max(0, Math.min(s.height - h, r.y + dy));
        root.sel_rect = Qt.rect(x, y, w, h);
        const resized = dw !== 0 || dh !== 0;
        root.set_lens(root.sel_screen, resized ? x + w - 1 : x, resized ? y + h - 1 : y);
    }

    // Global logical geometry in slurp's "x,y wxh" form.
    function geometry() {
        const s = root.screen_of(root.sel_screen);
        if (!s) return "";
        const r = root.sel_rect;
        return Math.round(s.x + r.x) + "," + Math.round(s.y + r.y) + " " + Math.round(r.width) + "x" + Math.round(r.height);
    }

    function act(action) {
        const geometry = root.geometry();
        if (geometry === "") return root.cancel();
        if (action === "record") {
            root.cancel();
            after_close.fn = () => Quickshell.execDetached([root.script, "--record-geometry", geometry]);
            after_close.restart();
            return;
        }
        root.pending_action = action;
        root.capture_file = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-screenshot-" + Date.now() + ".png";
        const s = root.screen_of(root.sel_screen);
        grab.command = ["grim", "-s", String(s.devicePixelRatio), "-g", geometry, root.capture_file];
        root.phase = "capture";
        capture_delay.restart();
    }

    // The overlay drops its chrome first; a frozen one keeps showing the still frame for grim to read.
    Timer {
        id: capture_delay
        interval: 120
        onTriggered: {
            grab.running = true;
            capture_watchdog.restart();
        }
    }

    // A grim that never starts (missing) must not leave the invisible overlay holding the keyboard.
    Timer {
        id: capture_watchdog
        interval: 5000
        onTriggered: if (root.phase === "capture") root.cancel()
    }

    Process {
        id: grab
        onExited: code => {
            if (root.phase !== "capture") {
                Quickshell.execDetached(["rm", "-f", "--", root.capture_file]);
                return;
            }
            root.cancel();
            if (code === 0) Quickshell.execDetached([root.script, "--image", root.capture_file, "--" + root.pending_action]);
            else Quickshell.execDetached(["notify-send", "Screenshot Failed", "grim exited with " + code]);
        }
    }

    Timer {
        id: after_close
        property var fn: null
        interval: 350
        onTriggered: {
            const fn = after_close.fn;
            after_close.fn = null;
            if (fn) fn();
        }
    }

    // Called by screenshot.sh with wf-recorder's pid; the watcher ends with it.
    function recording_started(pid, elapsed_s) {
        root.record_start_ms = Date.now() - (elapsed_s || 0) * 1000;
        root.elapsed_s = elapsed_s || 0;
        root.recording = true;
        if (!watcher.running && /^[0-9]+$/.test(pid)) {
            watcher.command = ["tail", "--pid=" + pid, "-f", "/dev/null"];
            watcher.running = true;
        }
    }

    function recording_stopped() {
        root.recording = false;
        watcher.running = false;
    }

    function stop_recording() {
        Quickshell.execDetached(["pkill", "-INT", "-x", "wf-recorder"]);
    }

    Process {
        id: watcher
        onExited: root.recording = false
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.elapsed_s = Math.floor((Date.now() - root.record_start_ms) / 1000)
    }

    // One check at start, for a recording that outlived a shell restart.
    Process {
        running: true
        command: ["sh", "-c", "pid=$(pidof -s wf-recorder) && echo \"$pid $(ps -o etimes= -p \"$pid\")\""]
        stdout: StdioCollector {
            id: running_pid
            onStreamFinished: {
                const parts = running_pid.text.trim().split(/\s+/);
                if (parts[0] !== "") root.recording_started(parts[0], parseInt(parts[1]) || 0);
            }
        }
    }
}
