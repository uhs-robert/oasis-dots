import QtQuick
import Quickshell
import Quickshell.Io

// A long-running command whose stdout lines are streamed out, restarted with doubling backoff
// when it exits. Starts itself once loaded: with `wanted` true and no `probe_command` that is
// at load, so a caller that must not run yet sets `wanted` false.
Scope {
    id: root

    property list<string> command: []
    // Empty means no probe. Otherwise run once at startup; exit 0 makes the stream `available`.
    property list<string> probe_command: []
    property bool wanted: true
    property int initial_delay_ms: 1000
    property int max_delay_ms: 60000
    // A run shorter than this doubles the delay; a longer one resets it.
    property int quick_exit_ms: 30000
    // Logged once per streak of quick exits.
    property string warn_text: ""

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

    function sync() {
        stream.running = root.wanted && root.available;
    }

    onWantedChanged: root.sync()
    // Deferred so the caller's own bindings (`wanted`, `command`) are settled before the first start.
    Component.onCompleted: Qt.callLater(root.sync)

    Process {
        id: probe
        command: root.probe_command
        running: root.probe_command.length > 0
        onExited: code => {
            root.probed = code === 0;
            root.sync();
        }
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
            if (!root.wanted) return;
            if (Date.now() - root.started_ms < root.quick_exit_ms) {
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
        onTriggered: if (root.wanted) stream.running = true
    }
}
