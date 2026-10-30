import QtQml
import QtQuick
import Quickshell
import Quickshell.Io

// Harness shell for run.py: runs the scenario named by $SCENARIO against core/PolledFile.qml, reading files from
// $DATA (a.txt and b.txt exist, missing.txt does not), and writes every `loaded` and `load_failed`, with its time in
// ms from start, to result.json under $XDG_STATE_HOME when the scenario's `end` is reached, then quits.
// The plan's clock starts when FileView's own first read arrives (that event is t = 0), not when the shell is built, so
// a slow boot cannot move that read into the plan's window.
ShellRoot {
    id: root

    readonly property string scenario: Quickshell.env("SCENARIO")
    readonly property string data: Quickshell.env("DATA")
    property real started: Date.now()
    property bool ready: false
    property var events: []

    function note(kind, extra) {
        if (!root.ready && (kind === "loaded" || kind === "load_failed")) {
            root.ready = true;
            root.started = Date.now();
        }
        const event = Object.assign({ t: Date.now() - root.started, kind: kind }, extra || {});
        root.events = root.events.concat([event]);
    }

    // Each plan: the poller's `settings` (path is a file name under $DATA), `steps` (ms from start -> action:
    // "poll", or a file name to switch the path to) and `end` (ms at which the result is saved).
    readonly property var plans: ({
        loaded: { settings: { path: "a.txt" }, steps: [[100, "poll"]], end: 500 },
        loaded_blocking: { settings: { path: "a.txt", block_loading: true }, steps: [[100, "poll"]], end: 500 },
        missing: { settings: { path: "missing.txt" }, steps: [[100, "poll"]], end: 500 },
        missing_blocking: { settings: { path: "missing.txt", block_loading: true }, steps: [[100, "poll"]], end: 500 },
        // Each read after a path change must give the new file, also while blocking.
        path_change: {
            settings: { path: "a.txt" },
            steps: [[100, "poll"], [300, "b.txt"], [500, "poll"], [700, "missing.txt"], [900, "poll"], [1100, "a.txt"], [1300, "poll"]],
            end: 1600
        },
        path_change_blocking: {
            settings: { path: "a.txt", block_loading: true },
            steps: [[100, "poll"], [300, "b.txt"], [500, "poll"], [700, "missing.txt"], [900, "poll"], [1100, "a.txt"], [1300, "poll"]],
            end: 1600
        },
        // Disabled gates the timer, not poll().
        disabled: { settings: { path: "a.txt", enabled: false, interval_ms: 100 }, steps: [[500, "poll"]], end: 900 },
        // Switched on at 400: the timer starts then.
        enabled_late: { settings: { path: "a.txt", enabled: false, interval_ms: 100 }, steps: [[400, "enable"], [650, "disable"]], end: 1200 },
        interval_start: { settings: { path: "a.txt", interval_ms: 200 }, steps: [], end: 700 },
        interval_no_start: { settings: { path: "a.txt", interval_ms: 200, run_on_start: false }, steps: [], end: 700 },
        no_interval: { settings: { path: "a.txt" }, steps: [], end: 500 }
    })
    readonly property var plan: root.plans[root.scenario]

    FileView {
        id: result_file
        path: Quickshell.env("XDG_STATE_HOME") + "/result.json"
        atomicWrites: true
        printErrors: false
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    PolledFile {
        id: poller
        path: root.data + "/" + root.plan.settings.path
        enabled: root.plan.settings.enabled !== false
        interval_ms: root.plan.settings.interval_ms || 0
        run_on_start: root.plan.settings.run_on_start !== false
        block_loading: root.plan.settings.block_loading === true
        onLoaded: text => root.note("loaded", { text: text, path: poller.path.split("/").pop() })
        onLoad_failed: error => root.note("load_failed", { not_found: error === FileViewError.FileNotFound, path: poller.path.split("/").pop() })
    }

    Instantiator {
        model: root.plan.steps
        delegate: Timer {
            required property var modelData
            interval: modelData[0]
            running: root.ready
            onTriggered: {
                const action = modelData[1];
                if (action === "poll") poller.poll();
                else if (action === "enable") poller.enabled = true;
                else if (action === "disable") poller.enabled = false;
                else poller.path = root.data + "/" + action;
            }
        }
    }

    Timer {
        interval: root.plan.end
        running: root.ready
        onTriggered: result_file.setText(JSON.stringify(root.events))
    }
}
