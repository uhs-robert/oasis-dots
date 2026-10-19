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

    // From `run()` until `finished` or `start_failed` has been delivered.
    readonly property bool busy: root.in_flight

    // Every timer tick, before the auto run.
    signal due()
    // Once per run, after both the exit and the end of stdout; `err` is "" unless `collect_stderr`.
    signal finished(int code, string out, string err)
    // The process stopped without ever exiting: its executable could not start.
    signal start_failed()

    property bool in_flight: false
    property bool exited: false
    property bool drained: false
    property int exit_code: 0

    // Returns false, doing nothing, while a run is going.
    function run(): bool {
        if (root.in_flight) return false;
        root.in_flight = true;
        root.exited = false;
        root.drained = false;
        proc.running = true;
        if (root.timeout_ms > 0) timeout.restart();
        return true;
    }

    // Exit and end of stdout arrive in either order; the result is delivered once both are in.
    function settle() {
        if (!root.exited || !root.drained) return;
        timeout.stop();
        // Deferred so a handler that calls `run()` again finds `busy` false.
        Qt.callLater(() => {
            root.in_flight = false;
            root.finished(root.exit_code, out.text, err.text);
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
            root.settle();
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
        onTriggered: if (proc.running) proc.running = false
    }
}
