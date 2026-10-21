import QtQuick
import Quickshell
import Quickshell.Io

// A command run on a timer and on demand, with one `finished` per run carrying its exit code
// and output. The caller parses; a run that is still going makes the next `run()` a no-op, so
// a slow command never stacks up.
Scope {
    id: root

    property list<string> command: []
    // Gates the timer only; `run()` ignores it.
    property bool enabled: true
    // 0 means no timer, only `run()`.
    property int interval_ms: 0
    // Fire the timer when `enabled` turns true, not only one interval later.
    property bool run_on_start: true
    // False makes a tick only emit `due()`, for a caller that decides whether to run.
    property bool auto_run: true
    // False leaves stderr going to the qs log.
    property bool collect_stderr: false
    // 0 means none; otherwise a run still going after this long is stopped.
    property int timeout_ms: 0
    // How long to wait for the end of stdout once the process has exited. A child that outlives
    // it holding stdout open keeps the end away, so the run is then delivered with the output
    // collected so far (a StdioCollector's `text` is "" until its stream ends, so that is often
    // nothing). Quickshell 0.3.2 ends the stream at the exit even when a child holds the pipe, so
    // this is a guard against a version that waits for EOF. 0 means wait as long as it takes.
    property int drain_grace_ms: 500

    // From `run()` until `finished` or `start_failed` has been delivered.
    readonly property bool busy: root.in_flight

    // Every timer tick, before the auto run.
    signal due()
    // Once per run, after the exit and the end of stdout, or `drain_grace_ms` after the exit, or
    // at `timeout_ms`, whichever is first; `err` is "" unless `collect_stderr`.
    signal finished(int code, string out, string err)
    // The process stopped without ever exiting: its executable could not start.
    signal start_failed()

    property bool in_flight: false
    property bool exited: false
    property bool drained: false
    // Set when the run's result is on its way, so no later event of that run delivers it again.
    property bool settled: false
    property int exit_code: 0

    // Returns false, doing nothing, while a run is going.
    function run(): bool {
        if (root.in_flight) return false;
        root.in_flight = true;
        root.exited = false;
        root.drained = false;
        root.settled = false;
        proc.running = true;
        if (root.timeout_ms > 0) timeout.restart();
        return true;
    }

    // Exit and end of stdout arrive in either order; the result is delivered when both are in.
    function settle() {
        if (!root.exited || !root.drained) return;
        root.deliver();
    }

    // Delivers the run's result, once, with whatever output has been collected.
    function deliver() {
        if (root.settled) return;
        root.settled = true;
        timeout.stop();
        grace.stop();
        const code = root.exit_code;
        const out_text = out.text;
        const err_text = err.text;
        // Deferred so a handler that calls `run()` again finds `busy` false.
        Qt.callLater(() => {
            root.in_flight = false;
            root.finished(code, out_text, err_text);
        });
    }

    Timer {
        interval: root.interval_ms
        running: root.enabled && root.interval_ms > 0
        repeat: true
        triggeredOnStart: root.run_on_start
        onTriggered: {
            root.due();
            if (root.auto_run) root.run();
        }
    }

    Process {
        id: proc
        command: root.command
        stdout: StdioCollector {
            id: out
            onStreamFinished: {
                root.drained = true;
                root.settle();
            }
        }
        stderr: root.collect_stderr ? err : null
        onExited: code => {
            root.exit_code = code;
            root.exited = true;
            if (root.drained) root.settle();
            else if (root.drain_grace_ms > 0 && !root.settled) grace.restart();
        }
        // A command that cannot start stops running without exited or the end of stdout, so it
        // would never settle.
        onRunningChanged: {
            if (proc.running || root.exited || !root.in_flight) return;
            timeout.stop();
            root.in_flight = false;
            root.start_failed();
        }
    }

    StdioCollector {
        id: err
    }

    Timer {
        id: timeout
        interval: root.timeout_ms
        onTriggered: {
            if (proc.running) proc.running = false;
            else if (root.exited) root.deliver();
        }
    }

    Timer {
        id: grace
        interval: root.drain_grace_ms
        onTriggered: root.deliver()
    }
}
