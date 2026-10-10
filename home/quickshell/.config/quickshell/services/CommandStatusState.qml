// home/quickshell/.config/quickshell/services/CommandStatusState.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Machine-local status commands from custom/command-status.json, each polled into one pill of the cmdstatus module.
Singleton {
    id: root

    readonly property string config_path: Quickshell.shellDir + "/custom/command-status.json"
    readonly property var classes: ["idle", "active", "warn", "error"]
    readonly property int default_interval_s: 30
    readonly property int min_interval_ms: 1000
    readonly property string error_glyph: "\u{f0026}"

    property var entries: []
    // id -> { text, tooltip, class, hidden }; an entry without a result yet has no key.
    property var results: ({})
    // Mounted cmdstatus modules; commands only run while one is on a bar.
    property int mounted_modules: 0
    readonly property bool polling: root.mounted_modules > 0

    function result_of(id) {
        return root.results[id] || null;
    }

    function set_result(id, result) {
        const next = Object.assign({}, root.results);
        next[id] = result;
        root.results = next;
    }

    function runner_of(id) {
        for (let i = 0; i < runners.count; i++) {
            const r = runners.objectAt(i);
            if (r && r.entry.id === id) return r;
        }
        return null;
    }

    // "" refreshes every entry. Returns false for an unknown id.
    function refresh(id) {
        if (id === "") {
            for (let i = 0; i < runners.count; i++) runners.objectAt(i).run();
            return true;
        }
        const r = root.runner_of(id);
        if (r) r.run();
        return !!r;
    }

    function click(id, right) {
        const r = root.runner_of(id);
        if (r) r.click(right);
    }

    // A string runs through sh, so ~ and pipes work; an array is the argv itself.
    function argv(command) {
        return Array.isArray(command) ? command.map(String) : ["sh", "-c", String(command)];
    }

    function has_command(c) {
        return (typeof c === "string" && c.trim() !== "") || (Array.isArray(c) && c.length > 0);
    }

    function parse_entries(raw) {
        if (!Array.isArray(raw)) throw new Error("expected a JSON array of entries");
        const out = [];
        const seen = [];
        raw.forEach((e, i) => {
            const id = e && typeof e.id === "string" ? e.id.trim() : "";
            if (!id || seen.indexOf(id) >= 0 || !root.has_command(e.command)) {
                console.warn("cmdstatus: skipping entry " + i + " (needs a unique id and a command)");
                return;
            }
            seen.push(id);
            const interval = typeof e.interval === "number" && e.interval >= 0 ? e.interval : root.default_interval_s;
            out.push({
                id: id,
                command: root.argv(e.command),
                interval_ms: Math.round(interval * 1000),
                on_click: root.has_command(e.on_click) ? root.argv(e.on_click) : null,
                on_right_click: root.has_command(e.on_right_click) ? root.argv(e.on_right_click) : null
            });
        });
        return out;
    }

    // One line of {text, tooltip, class, hidden}; anything else is reported as the error state.
    function result_from_output(id, code, stdout, stderr) {
        const fail = why => ({ text: root.error_glyph, tooltip: id + ": " + why, class: "error", hidden: false });
        if (code !== 0) {
            const detail = stderr.trim().split("\n").slice(-3).join("\n");
            return fail("exited with code " + code + (detail ? "\n" + detail : ""));
        }
        const line = stdout.trim().split("\n").pop();
        let data;
        try {
            data = JSON.parse(line);
        } catch (e) {
            return fail("output is not JSON (" + e + ")");
        }
        if (typeof data !== "object" || data === null || Array.isArray(data)) return fail("output is not a JSON object");
        return {
            text: data.text === undefined ? "" : String(data.text),
            tooltip: data.tooltip === undefined ? "" : String(data.tooltip),
            class: root.classes.indexOf(data.class) >= 0 ? data.class : "idle",
            hidden: data.hidden === true
        };
    }

    FileView {
        id: config_file
        path: root.config_path
        printErrors: false
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.entries = root.parse_entries(JSON.parse(text()));
            } catch (e) {
                console.warn("cmdstatus: ignoring custom/command-status.json (" + e + ")");
                root.entries = [];
            }
        }
        onLoadFailed: error => root.entries = []
    }

    onEntriesChanged: {
        const ids = root.entries.map(e => e.id);
        const kept = {};
        for (const id of Object.keys(root.results)) {
            if (ids.indexOf(id) >= 0) kept[id] = root.results[id];
        }
        root.results = kept;
    }

    Instantiator {
        id: runners
        model: root.entries
        delegate: QtObject {
            id: runner
            required property var modelData
            readonly property var entry: runner.modelData

            // Exit and end of stdout arrive in either order; the result settles once both are in.
            property int exit_code: 0
            property bool exited: false
            property bool drained: false

            // A run still going skips this refresh, so a slow command never stacks up.
            function run() {
                if (!root.polling || runner.status_proc.running) return;
                runner.exited = false;
                runner.drained = false;
                runner.status_proc.running = true;
            }

            function settle() {
                if (!runner.exited || !runner.drained) return;
                root.set_result(runner.entry.id, root.result_from_output(runner.entry.id, runner.exit_code, status_out.text, status_err.text));
            }

            function click(right) {
                const command = right ? runner.entry.on_right_click : runner.entry.on_click;
                if (!command || runner.click_proc.running) return;
                runner.click_proc.command = command;
                runner.click_proc.running = true;
            }

            readonly property Process status_proc: Process {
                command: runner.entry.command
                stdout: StdioCollector {
                    id: status_out
                    onStreamFinished: {
                        runner.drained = true;
                        runner.settle();
                    }
                }
                stderr: StdioCollector {
                    id: status_err
                }
                onExited: code => {
                    runner.exit_code = code;
                    runner.exited = true;
                    runner.settle();
                }
            }

            // A click usually changes what the status command reports, so it reruns once the click's command ends.
            readonly property Process click_proc: Process {
                onExited: runner.run()
            }

            readonly property Timer poll: Timer {
                interval: Math.max(runner.entry.interval_ms, root.min_interval_ms)
                running: root.polling && runner.entry.interval_ms > 0
                repeat: true
                triggeredOnStart: true
                onTriggered: runner.run()
            }

            // An interval of 0 still runs once when the module appears, then only on a click or IPC refresh.
            readonly property Connections run_on_mount: Connections {
                target: root
                function onPollingChanged() {
                    if (root.polling && runner.entry.interval_ms === 0) runner.run();
                }
            }

            Component.onCompleted: if (root.polling && runner.entry.interval_ms === 0) runner.run()
        }
    }
}
