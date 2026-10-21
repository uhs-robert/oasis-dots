import QtQuick
import Quickshell
import Quickshell.Io

// A long-running command whose stdout lines are streamed out, restarted with doubling backoff
// when it exits. Starts itself once loaded: with `wanted` true and no `probe_command` that is
// at load, so a caller that must not run yet sets `wanted` false.
//
// The probe is re-run before every restart and, while the tool is missing, every
// `reprobe_interval_ms`, so installing or removing the tool needs no shell restart.
Scope {
    id: root

    property list<string> command: []
    // Empty means no probe. Otherwise exit 0 makes the stream `available`.
    property list<string> probe_command: []
    property bool wanted: true
    property int initial_delay_ms: 1000
    property int max_delay_ms: 60000
    // A run shorter than this doubles the delay; a longer one resets it.
    property int quick_exit_ms: 30000
    // Logged once per streak of quick exits.
    property string warn_text: ""
    // Logged once per streak of failed probes; empty for tools that are fine to lack.
    property string missing_text: ""
    property int reprobe_interval_ms: 60000
    // How long `expect_exit()` stays armed.
    property int expect_exit_ttl_ms: 10000

    readonly property bool available: root.probe_command.length === 0 || root.probed
    readonly property bool running: stream.running
    readonly property int restart_delay_ms: root.delay_ms

    signal line(string text)
    // Emitted first on every exit, before the `wanted` check and the backoff, so the caller
    // resets its state even when the stream is not coming back.
    signal exited()

    property bool probed: false
    property int delay_ms: root.initial_delay_ms
    property double started_ms: 0
    property bool warned: false
    property bool warned_missing: false
    property bool exit_expected: false

    function sync() {
        if (!root.wanted) {
            stream.running = false;
            restart_timer.stop();
        } else if (root.available) {
            restart_timer.stop();
            stream.running = true;
        }
    }

    // Marks the next exit as planned (the caller is about to restart the command's service):
    // it restarts after `initial_delay_ms` without counting as a failure. Armed only while the
    // stream runs, so a mark cannot outlive an exit it was not meant for, and it lapses after
    // `expect_exit_ttl_ms` so a restart that never happens cannot hide a later crash.
    function expect_exit() {
        if (!stream.running) return;
        root.exit_expected = true;
        expect_exit_timer.restart();
    }

    // Setting `running` on a probe already in flight is a no-op, so the timer and a restart cannot overlap probes.
    function reprobe() {
        if (root.probe_command.length > 0) probe.running = true;
    }

    onWantedChanged: root.sync()
    // Deferred so the caller's own bindings (`wanted`, `command`) are settled before the first start.
    Component.onCompleted: Qt.callLater(() => {
        root.reprobe();
        root.sync();
    })

    Process {
        id: probe
        command: root.probe_command
        onExited: code => {
            root.probed = code === 0;
            if (root.probed) {
                root.warned_missing = false;
            } else if (root.missing_text !== "" && !root.warned_missing) {
                console.warn(root.missing_text);
                root.warned_missing = true;
            }
            root.sync();
        }
    }

    Timer {
        interval: root.reprobe_interval_ms
        repeat: true
        running: root.probe_command.length > 0 && !root.available
        onTriggered: root.reprobe()
    }

    Timer {
        id: expect_exit_timer
        interval: root.expect_exit_ttl_ms
        onTriggered: root.exit_expected = false
    }

    Process {
        id: stream
        command: root.command
        onStarted: root.started_ms = Date.now()
        stdout: SplitParser {
            onRead: text => root.line(text)
        }
        onExited: {
            root.exited();
            const planned = root.exit_expected;
            root.exit_expected = false;
            expect_exit_timer.stop();
            if (!root.wanted) return;
            if (planned) {
                root.delay_ms = root.initial_delay_ms;
            } else if (Date.now() - root.started_ms < root.quick_exit_ms) {
                if (!root.warned) console.warn(root.warn_text);
                root.warned = true;
                root.delay_ms = Math.min(root.delay_ms * 2, root.max_delay_ms);
            } else {
                root.delay_ms = root.initial_delay_ms;
                root.warned = false;
            }
            restart_timer.restart();
        }
    }

    Timer {
        id: restart_timer
        interval: root.delay_ms
        onTriggered: {
            if (!root.wanted) return;
            // The tool may have been removed since; an unavailable result is picked up by the re-probe timer.
            if (root.probe_command.length > 0) root.reprobe();
            else stream.running = true;
        }
    }
}
