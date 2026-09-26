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
    // "region" drags a rect, "pixel" picks a colour from the still frame, "window" and "screen" pick a window's or monitor's rect.
    property string mode: "region"
    // Pickable rects for window and screen mode: { screen, rect (screen-local), label }, most recently focused first.
    property var targets: []
    property int target_index: -1
    // The centre pixel under the loupe in pixel mode, sampled from the still frame; "" until known.
    property string pixel_hex: ""
    // Where pixel_hex was sampled; a pick trusts it only at that exact cursor spot.
    property string pixel_hex_screen: ""
    property point pixel_hex_point: Qt.point(-1, -1)
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
    // The loupe: on/off and zoom (displayed px per buffer px); it looks at the cursor.
    property bool lens_on: true
    readonly property var zoom_levels: [2, 4, 8, 16]
    property int zoom_index: 1
    readonly property int zoom: root.zoom_levels[root.zoom_index]
    // The selector's cursor, moved by the mouse and by hjkl; keys_moved draws it while the pointer rests.
    property string cursor_screen: ""
    property point cursor_point: Qt.point(0, 0)
    property bool keys_moved: false
    // vim visual: v sets the anchor, the selection spans anchor to cursor.
    property bool anchored: false
    property point anchor_point: Qt.point(0, 0)
    property string pending_action: ""
    // Set when the selector is cancelled mid-grab, so a late grim result is thrown away.
    property bool grab_cancelled: false
    // Capture delay, kept for the session: the selector closes and the bar counts down before the action runs.
    readonly property var delays: [0, 3, 5, 10]
    property int delay_index: 0
    readonly property int delay_s: root.delays[root.delay_index]
    property int countdown: 0
    property var countdown_run: null
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

    function select(frozen, preset, mode) {
        root.run_after_close(() => root.start_select(frozen, preset, mode));
    }

    function start_select(frozen, preset, mode) {
        if (root.phase === "capture") return;
        root.cancel_countdown();
        root.mode = mode || "region";
        root.lens_on = root.mode === "region" || root.mode === "pixel";
        root.pixel_hex = "";
        root.pixel_hex_screen = "";
        if (root.mode === "pixel") frozen = true;
        root.targets = [];
        root.target_index = -1;
        const mon = Hyprland.focusedMonitor;
        const screen = (mon && root.screen_of(mon.name)) || Quickshell.screens[0];
        root.focus_screen = screen ? screen.name : "";
        root.frozen = frozen;
        root.preset = preset || "";
        root.sel_screen = "";
        root.sel_rect = Qt.rect(0, 0, 0, 0);
        root.tool_index = 0;
        root.anchored = false;
        root.keys_moved = false;
        if (screen) root.set_cursor(screen.name, screen.width / 2, screen.height / 2, false);
        pointer_query.running = true;
        if (root.mode === "window") window_query.running = true;
        if (root.mode === "screen") {
            const list = Quickshell.screens.map(s => ({ screen: s.name, rect: Qt.rect(0, 0, s.width, s.height), label: s.name }));
            root.set_targets(list, list.findIndex(t => t.screen === root.focus_screen));
        }
        root.phase = "select";
    }

    // Visible windows on each monitor's shown workspace (and its open special one), clipped to that monitor.
    Process {
        id: window_query
        command: ["sh", "-c", "printf '[%s,%s]' \"$(hyprctl -j monitors)\" \"$(hyprctl -j clients)\""]
        stdout: StdioCollector {
            id: window_text
            onStreamFinished: {
                if (root.mode !== "window" || root.phase === "") return;
                try {
                    const data = JSON.parse(window_text.text);
                    root.set_targets(root.window_targets(data[0], data[1]), 0);
                } catch (e) {
                    console.warn("Screenshot: window list: " + e);
                }
            }
        }
    }

    function window_targets(monitors, clients) {
        const shown = {};
        for (const m of monitors) shown[m.id] = { name: m.name, ws: m.activeWorkspace ? m.activeWorkspace.id : 0, special: m.specialWorkspace ? m.specialWorkspace.id : 0 };
        const visible = c => {
            const m = shown[c.monitor];
            return m && c.mapped && !c.hidden && c.workspace && (c.workspace.id === m.ws || (m.special !== 0 && c.workspace.id === m.special) || c.pinned);
        };
        const list = [];
        for (const c of clients.filter(visible).sort((a, b) => a.focusHistoryID - b.focusHistoryID)) {
            const s = root.screen_of(shown[c.monitor].name);
            if (!s) continue;
            const x0 = Math.max(c.at[0], s.x);
            const y0 = Math.max(c.at[1], s.y);
            const x1 = Math.min(c.at[0] + c.size[0], s.x + s.width);
            const y1 = Math.min(c.at[1] + c.size[1], s.y + s.height);
            if (x1 - x0 >= 2 && y1 - y0 >= 2) list.push({ screen: s.name, rect: Qt.rect(x0 - s.x, y0 - s.y, x1 - x0, y1 - y0), label: c.class || c.title || "" });
        }
        return list;
    }

    function set_targets(list, first) {
        root.targets = list;
        root.highlight(list.length > 0 ? Math.max(0, first) : -1);
    }

    function highlight(index) {
        root.target_index = index;
        const t = root.targets[index];
        if (t) root.set_selection(t.screen, t.rect.x, t.rect.y, t.rect.width, t.rect.height);
    }

    function center_of(t) {
        const s = root.screen_of(t.screen);
        return Qt.point((s ? s.x : 0) + t.rect.x + t.rect.width / 2, (s ? s.y : 0) + t.rect.y + t.rect.height / 2);
    }

    // Nearest target in a direction, like Hyprland movefocus: along the axis first, sideways offset weighs double.
    function step_target(dx, dy) {
        const from = root.targets[root.target_index];
        if (!from) return root.highlight(root.targets.length > 0 ? 0 : -1);
        const c = root.center_of(from);
        let best = -1;
        let best_score = Infinity;
        for (let i = 0; i < root.targets.length; i++) {
            if (i === root.target_index) continue;
            const p = root.center_of(root.targets[i]);
            const along = (p.x - c.x) * dx + (p.y - c.y) * dy;
            if (along <= 0) continue;
            const side = Math.abs(dx !== 0 ? p.y - c.y : p.x - c.x);
            const score = along + side * 2;
            if (score < best_score) {
                best_score = score;
                best = i;
            }
        }
        if (best >= 0) root.highlight(best);
    }

    function cycle_target(delta) {
        const n = root.targets.length;
        if (n > 0) root.highlight(((root.target_index + delta) % n + n) % n);
    }

    // The most recently focused target under a screen-local point, so floating windows win over tiled ones below.
    function target_at(screen_name, x, y) {
        return root.targets.findIndex(t => t.screen === screen_name && x >= t.rect.x && y >= t.rect.y && x < t.rect.x + t.rect.width && y < t.rect.y + t.rect.height);
    }

    // Starts the cursor at the real pointer when it is on the focused screen.
    Process {
        id: pointer_query
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            id: pointer_text
            onStreamFinished: {
                const m = pointer_text.text.match(/(-?\d+(?:\.\d+)?)\D+(-?\d+(?:\.\d+)?)/);
                const s = root.screen_of(root.focus_screen);
                if (!m || !s || root.keys_moved) return;
                const x = parseFloat(m[1]) - s.x;
                const y = parseFloat(m[2]) - s.y;
                if (x >= 0 && y >= 0 && x < s.width && y < s.height) root.set_cursor(s.name, x, y, false);
            }
        }
    }

    function cancel() {
        if (root.phase === "capture") root.grab_cancelled = true;
        capture_delay.stop();
        capture_watchdog.stop();
        root.phase = "";
        root.sel_screen = "";
        root.anchored = false;
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

    // Anchored, the cursor stays on the anchor's screen and drags the selection with it.
    function set_cursor(screen_name, x, y, by_keys) {
        if (root.anchored && screen_name !== root.cursor_screen) return;
        const s = root.screen_of(screen_name);
        if (!s) return;
        root.cursor_screen = screen_name;
        root.cursor_point = Qt.point(Math.max(0, Math.min(s.width - 1, x)), Math.max(0, Math.min(s.height - 1, y)));
        root.keys_moved = by_keys;
        if (root.anchored) root.span_selection();
    }

    // Unanchored, the cursor crosses onto the monitor past the edge it runs into (the nearest one that way
    // when monitors are offset or gapped); anchored, it stays on the anchor's monitor.
    function move_cursor(dx, dy) {
        const from = root.screen_of(root.cursor_screen);
        if (!from) return;
        const gx = from.x + root.cursor_point.x + dx;
        const gy = from.y + root.cursor_point.y + dy;
        const inside = s => gx >= s.x && gy >= s.y && gx < s.x + s.width && gy < s.y + s.height;
        let to = root.anchored || inside(from) ? from : Quickshell.screens.find(inside) || null;
        if (!to) {
            let best = Infinity;
            for (const s of Quickshell.screens) {
                if (s === from) continue;
                const ahead = (dx > 0 && s.x >= from.x + from.width) || (dx < 0 && s.x + s.width <= from.x) || (dy > 0 && s.y >= from.y + from.height) || (dy < 0 && s.y + s.height <= from.y);
                if (!ahead) continue;
                const d = Math.hypot(Math.max(s.x - gx, 0, gx - (s.x + s.width - 1)), Math.max(s.y - gy, 0, gy - (s.y + s.height - 1)));
                if (d < best) {
                    best = d;
                    to = s;
                }
            }
        }
        if (!to) to = from;
        root.set_cursor(to.name, gx - to.x, gy - to.y, true);
    }

    function span_selection() {
        const a = root.anchor_point;
        const c = root.cursor_point;
        root.set_selection(root.cursor_screen, Math.min(a.x, c.x), Math.min(a.y, c.y), Math.abs(c.x - a.x), Math.abs(c.y - a.y));
    }

    function toggle_anchor() {
        if (root.anchored) return root.clear_anchor();
        if (root.cursor_screen === "") return;
        root.anchor_point = root.cursor_point;
        root.anchored = true;
        root.span_selection();
    }

    function clear_anchor() {
        root.anchored = false;
        root.sel_screen = "";
    }

    function swap_anchor() {
        if (!root.anchored) return;
        const a = root.anchor_point;
        root.anchor_point = root.cursor_point;
        root.cursor_point = a;
        root.keys_moved = true;
    }

    function step_zoom(delta) {
        root.zoom_index = Math.max(0, Math.min(root.zoom_levels.length - 1, root.zoom_index + delta));
    }

    // Global logical geometry in slurp's "x,y wxh" form.
    function geometry() {
        const s = root.screen_of(root.sel_screen);
        if (!s) return "";
        const r = root.sel_rect;
        return Math.round(s.x + r.x) + "," + Math.round(s.y + r.y) + " " + Math.round(r.width) + "x" + Math.round(r.height);
    }

    // Copies the sampled hex like hyprpicker -a; without a sample, screenshot.sh reads the pixel from the frozen overlay.
    function pick_pixel() {
        const s = root.screen_of(root.cursor_screen);
        if (!s) return root.cancel();
        const sampled = root.pixel_hex !== "" && root.lens_on && root.pixel_hex_screen === root.cursor_screen && root.pixel_hex_point.x === root.cursor_point.x && root.pixel_hex_point.y === root.cursor_point.y;
        if (sampled) {
            const hex = root.pixel_hex;
            root.cancel();
            Quickshell.execDetached(["wl-copy", hex]);
            Quickshell.execDetached(["notify-send", "Picked Color", hex]);
            return;
        }
        root.pending_action = "pixel";
        grab.command = [root.script, "--pixel-at", Math.floor(s.x + root.cursor_point.x) + "," + Math.floor(s.y + root.cursor_point.y) + " 1x1"];
        root.phase = "capture";
        capture_delay.restart();
    }

    function cycle_delay() {
        root.delay_index = (root.delay_index + 1) % root.delays.length;
    }

    function start_countdown(fn) {
        root.countdown_run = fn;
        root.countdown = root.delay_s;
    }

    function cancel_countdown() {
        root.countdown = 0;
        root.countdown_run = null;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.countdown > 0
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown > 0) return;
            const fn = root.countdown_run;
            root.countdown_run = null;
            // A selector opened meanwhile owns the screen; the old capture is dropped.
            if (fn && root.phase === "") fn();
        }
    }

    function act(action) {
        const geometry = root.geometry();
        if (geometry === "") return root.cancel();
        if (root.delay_s > 0 && !root.frozen) {
            const scale = String(root.screen_of(root.sel_screen).devicePixelRatio);
            root.cancel();
            root.start_countdown(() => action === "record" ? Quickshell.execDetached([root.script, "--record-geometry", geometry]) : root.run_grab(action, scale, geometry));
            return;
        }
        if (action === "record") {
            root.cancel();
            after_close.fn = () => Quickshell.execDetached([root.script, "--record-geometry", geometry]);
            after_close.restart();
            return;
        }
        root.phase = "capture";
        root.run_grab(action, String(root.screen_of(root.sel_screen).devicePixelRatio), geometry);
    }

    // With the selector up this waits for its chrome to hide; after a countdown there is no overlay and grim runs at once.
    function run_grab(action, scale, geometry) {
        root.pending_action = action;
        root.grab_cancelled = false;
        root.capture_file = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-screenshot-" + Date.now() + ".png";
        grab.command = ["grim", "-s", scale, "-g", geometry, root.capture_file];
        if (root.phase === "capture") return capture_delay.restart();
        if (root.phase !== "") return;
        grab.running = true;
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
            if (root.pending_action === "pixel") {
                root.cancel();
                return;
            }
            if (root.grab_cancelled) {
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

    // Also cancels a pending capture countdown.
    function stop_recording() {
        if (root.countdown > 0) return root.cancel_countdown();
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
