import QtQml
import QtQuick
import Quickshell
import Quickshell.Io

// Harness shell for run.py: runs the scenario named by $SCENARIO against core/RestartingStream.qml. The stream
// command writes its pid to $WORK/pid, prints "up" and sleeps; the probe command appends to $WORK/probes and
// succeeds while $WORK/present exists (run.py creates it, or not, before qs starts). Every `line`, `exited` and
// action is noted with its time in ms from start, and the events are saved to result.json under $XDG_STATE_HOME
// at the scenario's `end`, then qs quits.
ShellRoot {
    id: root

    readonly property string scenario: Quickshell.env("SCENARIO")
    readonly property string work: Quickshell.env("WORK")
    property real started: Date.now()
    property var events: []

    function note(kind, extra) {
        const event = Object.assign({ t: Date.now() - root.started, kind: kind }, extra || {});
        root.events = root.events.concat([event]);
    }

    function sh(script) {
        Quickshell.execDetached(["sh", "-c", script]);
    }

    readonly property string stream_script: "echo $$ > " + root.work + "/pid; echo up; exec sleep 30"
    readonly property string probe_script: "echo x >> " + root.work + "/probes; sleep " + root.cfg.probe_sleep + "; test -e " + root.work + "/present"
    readonly property string kill_script: "kill $(cat " + root.work + "/pid)"

    // Each plan: the stream's settings, `actions` as [ms from start, name, argument] (expect_exit, kill, wanted,
    // reprobe, absent, present) and `end` (ms at which the result is saved). Delays are scaled down from production.
    readonly property var plans: ({
        // A planned exit restarts after the initial delay, with no warning and no doubling.
        planned: { settings: { probe: false }, actions: [[300, "expect_exit"], [310, "kill"]], end: 2400 },
        // The control: the same kill without the mark is a quick failure.
        unplanned: { settings: { probe: false }, actions: [[300, "kill"]], end: 900 },
        // A mark whose exit never came lapses, so a later crash counts.
        stale_mark: { settings: { probe: false, ttl: 200 }, actions: [[100, "expect_exit"], [600, "kill"]], end: 1000 },
        // The mark is refused while the stream is down, so it cannot swallow the next crash.
        mark_after_exit: { settings: { probe: false }, actions: [[300, "kill"], [350, "expect_exit"], [1100, "kill"]], end: 1500 },
        // Repeated right-clicks make one planned exit; the next crash counts again.
        repeated_marks: { settings: { probe: false }, actions: [[300, "expect_exit"], [305, "expect_exit"], [310, "expect_exit"], [315, "kill"], [900, "kill"]], end: 1300 },
        // The tool is missing at start: one warning, no stream; installed later, the re-probe starts it.
        missing_then_installed: { settings: {}, actions: [[700, "present"]], end: 2800 },
        // The re-probe timer ticks faster than a probe takes: still one probe at a time.
        probe_in_flight: { settings: { probe_sleep: "0.5", reprobe: 100 }, actions: [], end: 1300 },
        // A restart re-probes; the tool is gone, so no stream comes back, until it is installed again.
        removed_then_back: { settings: {}, actions: [[300, "absent"], [310, "kill"], [1200, "present"]], end: 4000 },
        // A probe failing while the stream runs leaves that stream alone; it is not restarted once it ends.
        probe_flips_while_running: { settings: {}, actions: [[300, "absent"], [310, "reprobe"], [600, "kill"]], end: 2000 },
        // wanted dropping during backoff: the pending restart must not start it.
        wanted_off_in_backoff: { settings: { probe: false }, actions: [[300, "kill"], [350, "wanted_false"]], end: 1200 },
        // wanted flapping during backoff starts it once, at the flap, and the old timer adds no second start.
        wanted_flap_in_backoff: { settings: { probe: false }, actions: [[300, "kill"], [350, "wanted_false"], [450, "wanted_true"]], end: 2400 },
        // wanted false stops the stream and leaves no process behind.
        stop_leaves_nothing: { settings: { probe: false }, actions: [[300, "wanted_false"], [400, "check_alive"]], end: 800 }
    })
    readonly property var plan: root.plans[root.scenario]
    readonly property var cfg: Object.assign({ probe: true, ttl: 10000, reprobe: 400, probe_sleep: "0" }, root.plan.settings)

    FileView {
        id: result_file
        path: Quickshell.env("XDG_STATE_HOME") + "/result.json"
        atomicWrites: true
        printErrors: false
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    Process {
        id: alive_check
        command: ["sh", "-c", "kill -0 $(cat " + root.work + "/pid)"]
        onExited: code => root.note("alive", { alive: code === 0 })
    }

    RestartingStream {
        id: stream
        command: ["sh", "-c", root.stream_script]
        probe_command: root.cfg.probe ? ["sh", "-c", root.probe_script] : []
        initial_delay_ms: 200
        max_delay_ms: 5000
        quick_exit_ms: 100000
        reprobe_interval_ms: root.cfg.reprobe
        expect_exit_ttl_ms: root.cfg.ttl
        warn_text: "TEST-WARN-QUICK"
        missing_text: "TEST-WARN-MISSING"
        onLine: text => root.note("line", { text: text })
        // `exited` is emitted before the backoff is updated, so the delay is read once the handler is done.
        onExited: Qt.callLater(() => root.note("exited", { delay: stream.restart_delay_ms }))
    }

    Instantiator {
        model: root.plan.actions
        delegate: Timer {
            required property var modelData
            interval: modelData[0]
            running: true
            onTriggered: {
                const name = modelData[1];
                root.note("action", { name: name });
                if (name === "expect_exit") stream.expect_exit();
                else if (name === "kill") root.sh(root.kill_script);
                else if (name === "reprobe") stream.reprobe();
                else if (name === "absent") root.sh("rm -f " + root.work + "/present");
                else if (name === "present") root.sh("touch " + root.work + "/present");
                else if (name === "wanted_false") stream.wanted = false;
                else if (name === "wanted_true") stream.wanted = true;
                else if (name === "check_alive") alive_check.running = true;
            }
        }
    }

    Timer {
        interval: root.plan.end
        running: true
        onTriggered: {
            root.note("end", { running: stream.running, available: stream.available, delay: stream.restart_delay_ms });
            result_file.setText(JSON.stringify(root.events));
        }
    }
}
