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
    // command), the optional `rerun_on_finished` command and `end` (ms at which the result is saved). `sim_` plans
    // are run by run.py against a PolledCommand whose end of stdout is held back (see run.py).
    readonly property var plans: ({
        // A child keeps stdout open for 3 s after the parent exits. Quickshell 0.3.2 ends the stream at the exit
        // anyway, so this is the real-command case: prompt, once, and the next run works.
        leaked: {
            settings: { drain_grace_ms: 300 },
            runs: [[0, ["sh", "-c", "sleep 3 & echo hi"]], [800, ["echo", "second"]]],
            end: 1500
        },
        // The next run starts at once from the `finished` handler.
        rerun_from_handler: {
            settings: { drain_grace_ms: 300 },
            runs: [[0, ["sh", "-c", "echo hi"]]],
            rerun_on_finished: ["sh", "-c", "sleep 0.5; echo second"],
            end: 1500
        },
        // A normal command: finished right after exit, long before the grace.
        normal: {
            settings: { drain_grace_ms: 600 },
            runs: [[0, ["sh", "-c", "echo hi; exit 3"]], [300, null]],
            end: 1200
        },
        // Slower than timeout_ms: killed as before, once.
        timeout_running: {
            settings: { timeout_ms: 300, drain_grace_ms: 600 },
            runs: [[0, ["sh", "-c", "sleep 5"]]],
            end: 1500
        },
        // A command that cannot start.
        start_fail: {
            settings: { drain_grace_ms: 300 },
            runs: [[0, ["/nonexistent/binary"]], [400, ["echo", "after"]]],
            end: 1000
        },
        // The end of stdout never comes within the test (3 s): the grace delivers the run, and the late end of stdout
        // changes nothing.
        sim_grace: {
            settings: { drain_grace_ms: 300 },
            runs: [[0, ["sh", "-c", "echo hi"]]],
            end: 3600
        },
        // The end of stdout comes after the grace and before the next run: no second `finished`, next run intact.
        sim_late_drain: {
            settings: { drain_grace_ms: 200 },
            runs: [[0, ["sh", "-c", "echo hi"]], [1500, ["sh", "-c", "echo second"]]],
            end: 3600
        },
        // The next run starts from the `finished` handler of the forced one; the first run's late end of stdout (1 s)
        // arrives after that run ended too.
        sim_rerun_from_handler: {
            settings: { drain_grace_ms: 200 },
            runs: [[0, ["sh", "-c", "echo hi"]]],
            rerun_on_finished: ["sh", "-c", "echo second"],
            end: 3600
        },
        // The parent is killed by timeout_ms while the end of stdout is held back: the grace bounds the wait.
        sim_timeout_then_grace: {
            settings: { timeout_ms: 300, drain_grace_ms: 300 },
            runs: [[0, ["sh", "-c", "echo hi; sleep 5"]]],
            end: 3600
        },
        // timeout_ms shorter than the grace: the timeout settles the run after the exit, before the grace.
        sim_timeout_before_grace: {
            settings: { timeout_ms: 400, drain_grace_ms: 1500 },
            runs: [[0, ["sh", "-c", "echo hi"]]],
            end: 3600
        },
        // No grace (0): the wait lasts until the end of stdout, as before.
        sim_grace_off: {
            settings: { drain_grace_ms: 0 },
            runs: [[0, ["sh", "-c", "echo hi"]]],
            end: 3600
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
        drain_grace_ms: root.plan.settings.drain_grace_ms === undefined ? 500 : root.plan.settings.drain_grace_ms
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
