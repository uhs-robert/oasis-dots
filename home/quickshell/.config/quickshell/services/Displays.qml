// home/quickshell/.config/quickshell/services/Displays.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "DisplayLayout.js" as DisplayLayout
import "../theme"

// Monitor state, live apply through hyprctl, and the keep-or-revert countdown; it outlives the settings panel.
Singleton {
    id: root

    readonly property int window: 15
    readonly property string state_path: Paths.hypr_state_dir + "/monitors.json"

    property var monitors: []
    property bool pending: false
    property int seconds_left: 0
    property string notice: ""

    property var saved: ({})
    property var snapshot: ({})
    property var proposed: ({})
    property var queued: ({})
    property string after: ""
    property var written: ({})

    readonly property int enabled_count: root.monitors.filter(m => !m.disabled).length

    function refresh() {
        if (!list_proc.running) list_proc.running = true;
    }

    function say(text) {
        root.notice = text;
        notice_timer.restart();
    }

    function monitor_named(name) {
        return root.monitors.find(m => m.name === name) || null;
    }

    // Applies rules (connector name to spec) now and starts or extends the countdown; keep() persists them.
    function stage(changes) {
        if (root.after !== "") return;
        if (!root.pending) {
            root.snapshot = {};
            root.proposed = {};
            root.pending = true;
        }
        const snapshot = Object.assign({}, root.snapshot);
        const proposed = Object.assign({}, root.proposed);
        const queued = Object.assign({}, root.queued);
        let next = root.monitors;
        for (const name of Object.keys(changes)) {
            const m = root.monitor_named(name);
            if (!m) continue;
            if (!(name in snapshot)) snapshot[name] = DisplayLayout.spec_of(m);
            proposed[m.key] = DisplayLayout.state_entry(m, changes[name]);
            queued[name] = changes[name];
            next = next.map(x => x.name === name ? DisplayLayout.apply_spec(x, changes[name]) : x);
        }
        root.snapshot = snapshot;
        root.proposed = proposed;
        root.queued = queued;
        root.monitors = next;
        root.notice = "";
        root.seconds_left = root.window;
        tick.restart();
        flush_timer.restart();
    }

    function flush() {
        if (apply_proc.running) {
            if (root.after === "") flush_timer.restart();
            return;
        }
        const chunk = DisplayLayout.lua_chunk(root.monitors, root.queued);
        root.queued = {};
        if (chunk === "") return;
        apply_proc.command = ["hyprctl", "eval", chunk];
        apply_proc.running = true;
    }

    // Waits for the in-flight apply and any queued edits before persisting.
    function keep() {
        if (!root.pending || root.after !== "") return;
        tick.stop();
        flush_timer.stop();
        root.after = "keep";
        if (apply_proc.running) return;
        if (Object.keys(root.queued).length > 0) root.flush();
        else root.settle();
    }

    // Drops queued edits and restores the snapshot once the in-flight apply has finished.
    function revert() {
        if (!root.pending || root.after === "revert") return;
        tick.stop();
        flush_timer.stop();
        root.queued = {};
        root.after = "revert";
        if (!apply_proc.running) root.settle();
    }

    function settle() {
        const mode = root.after;
        root.after = "";
        if (mode === "keep") {
            root.written = Object.assign({}, root.saved, root.proposed);
            write_proc.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1.tmp" && mv "$1.tmp" "$1"', "sh", root.state_path, JSON.stringify({ monitors: root.written })];
            write_proc.running = true;
        } else if (mode === "revert") {
            const chunk = DisplayLayout.lua_chunk(root.monitors, root.snapshot);
            if (chunk !== "") {
                revert_proc.command = ["hyprctl", "eval", chunk];
                revert_proc.running = true;
            }
        }
        root.finish();
    }

    function applied(code, text, err) {
        if (code !== 0 || err.trim() !== "" || text.trim().indexOf("error") === 0) {
            root.say("Hyprland rejected the change");
            root.queued = {};
            root.after = "revert";
        }
        if (root.after === "keep" && Object.keys(root.queued).length > 0) root.flush();
        else if (root.after !== "") root.settle();
        else refresh_timer.restart();
    }

    function finish() {
        tick.stop();
        flush_timer.stop();
        root.pending = false;
        root.seconds_left = 0;
        root.snapshot = {};
        root.proposed = {};
        root.queued = {};
        refresh_timer.restart();
    }

    Component.onCompleted: root.refresh()

    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.seconds_left -= 1;
            if (root.seconds_left <= 0) root.revert();
        }
    }

    Timer {
        id: flush_timer
        interval: 200
        onTriggered: root.flush()
    }

    Timer {
        id: refresh_timer
        interval: 600
        onTriggered: root.refresh()
    }

    Timer {
        id: notice_timer
        interval: 4000
        onTriggered: root.notice = ""
    }

    Process {
        id: list_proc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = DisplayLayout.parse_monitors(JSON.parse(text));
                } catch (e) {}
            }
        }
    }

    Process {
        id: apply_proc
        stdout: StdioCollector {
            id: apply_out
        }
        stderr: StdioCollector {
            id: apply_err
        }
        onExited: code => root.applied(code, apply_out.text, apply_err.text)
    }

    Process {
        id: revert_proc
    }

    Process {
        id: write_proc
        onExited: code => {
            if (code === 0) root.saved = root.written;
            else root.say("Applied but not saved; it will not survive a restart");
        }
    }

    FileView {
        path: root.state_path
        printErrors: false
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.saved = data && typeof data.monitors === "object" && data.monitors !== null && !Array.isArray(data.monitors) ? data.monitors : {};
            } catch (e) {
                root.saved = {};
            }
        }
        onLoadFailed: error => root.saved = {}
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name.indexOf("monitor") === 0 || event.name === "configreloaded") refresh_timer.restart();
        }
    }
}
