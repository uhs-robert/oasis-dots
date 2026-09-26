// home/quickshell/.config/quickshell/lock/LockCapture.qml
import QtQuick
import Quickshell
import Quickshell.Io

// Screenshots outputs into the runtime dir for a lock backdrop; done when grim is, or at the cap.
Scope {
    id: root

    // The file prefix, which lock-backdrop only accepts as qs-lock or qs-lockpreview.
    property string prefix: "qs-lock"
    property int cap_ms: 400
    property bool running: false
    property var captured: []
    readonly property string script: Quickshell.shellDir + "/scripts/lock-backdrop"
    readonly property string dir: Quickshell.env("XDG_RUNTIME_DIR") || ""

    // Output name to file URL, for each output whose screenshot finished in time.
    signal finished(var files)

    function start(names) {
        if (root.running) return;
        root.captured = [];
        if (root.dir === "" || names.length === 0 || proc.running) {
            root.finished({});
            return;
        }
        root.running = true;
        proc.command = [root.script, "capture", root.prefix].concat(names);
        proc.running = true;
        cap.restart();
    }

    function finish() {
        if (!root.running) return;
        root.running = false;
        cap.stop();
        if (proc.running) proc.signal(15);
        const files = {};
        for (const name of root.captured) files[name] = "file://" + root.dir + "/" + root.prefix + "-" + name + ".png";
        root.finished(files);
    }

    function clear() {
        if (root.running) {
            root.running = false;
            cap.stop();
            proc.signal(15);
        }
        Quickshell.execDetached([root.script, "clear", root.prefix]);
    }

    Process {
        id: proc
        stdout: SplitParser {
            onRead: data => {
                if (root.running && data !== "") root.captured = root.captured.concat([data]);
            }
        }
        onRunningChanged: {
            if (!proc.running) root.finish();
        }
    }

    Timer {
        id: cap
        interval: root.cap_ms
        onTriggered: root.finish()
    }
}
