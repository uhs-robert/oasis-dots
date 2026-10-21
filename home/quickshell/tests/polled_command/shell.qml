import QtQml
import QtQuick
import Quickshell
import Quickshell.Io

// Harness shell for run.py: runs the scenario named by $SCENARIO against core/PolledCommand.qml and writes every
// `finished`, `start_failed` and `busy` change, with its time in ms from start, to result.json under
// $XDG_STATE_HOME when the scenario's `end` is reached, then quits.
ShellRoot {
    id: root

    readonly property string scenario: Quickshell.env("SCENARIO")
    property real started: Date.now()
    property var events: []

    function note(kind, extra) {
        const event = Object.assign({ t: Date.now() - root.started, kind: kind }, extra || {});
        root.events = root.events.concat([event]);
    }

    // Each plan: the poller's settings, `runs` (ms from start -> command, or `null` for a bare run() of the current
    // command), the optional `rerun_on_finished` command and `end` (ms at which the result is saved).
    readonly property var plans: ({
        // A child keeps stdout open and writes to it at 1 s, after the parent exited: the result must arrive at the
        // exit without it, and the write must not reach the second run, which is going then.
        leaked: {
            settings: {},
            runs: [[0, ["sh", "-c", "(sleep 1; echo late) & echo hi"]], [800, ["sh", "-c", "sleep 0.6; echo second"]]],
            end: 2000
        },
        // The next run starts at once from the `finished` handler.
        rerun_from_handler: {
            settings: {},
            runs: [[0, ["sh", "-c", "echo hi"]]],
            rerun_on_finished: ["sh", "-c", "sleep 0.5; echo second"],
            end: 1500
        },
        // A normal command: finished right after exit, at once.
        normal: {
            settings: {},
            runs: [[0, ["sh", "-c", "echo hi; exit 3"]], [300, null]],
            end: 1200
        },
        // Slower than timeout_ms: killed as before, once.
        timeout_running: {
            settings: { timeout_ms: 300 },
            runs: [[0, ["sh", "-c", "sleep 5"]]],
            end: 1500
        },
        // A command that cannot start.
        start_fail: {
            settings: {},
            runs: [[0, ["/nonexistent/binary"]], [400, ["echo", "after"]]],
            end: 1000
        }
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

    PolledCommand {
        id: poller
        collect_stderr: false
        timeout_ms: root.plan.settings.timeout_ms || 0
        onFinished: (code, out, err) => {
            root.note("finished", { code: code, out: out, busy: poller.busy });
            if (root.plan.rerun_on_finished && !root.rerun_done) {
                root.rerun_done = true;
                poller.command = root.plan.rerun_on_finished;
                root.note("rerun", { accepted: poller.run() });
            }
        }
        onStart_failed: root.note("start_failed", { busy: poller.busy })
    }
    property bool rerun_done: false

    Instantiator {
        model: root.plan.runs
        delegate: Timer {
            required property var modelData
            interval: modelData[0]
            running: true
            onTriggered: {
                if (modelData[1] !== null) poller.command = modelData[1];
                root.note("run", { accepted: poller.run() });
            }
        }
    }

    Timer {
        interval: root.plan.end
        running: true
        onTriggered: {
            root.note("end", { busy: poller.busy });
            result_file.setText(JSON.stringify(root.events));
        }
    }
}
