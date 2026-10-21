pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// One `voxtype status --follow` stream shared by every bar.
Singleton {
    id: root

    property string state: "stopped"
    property string tooltip: "Voxtype not running"
    readonly property bool recording: state === "recording"
    readonly property bool transcribing: state === "transcribing"

    readonly property bool installed: stream.available

    // Right-click on the bar module: the service restart ends the follow stream, which is planned, not a crash.
    function restart() {
        stream.expect_exit();
        Quickshell.execDetached(["systemctl", "--user", "restart", "voxtype"]);
    }

    RestartingStream {
        id: stream
        command: ["voxtype", "status", "--follow", "--format", "json"]
        probe_command: ["sh", "-c", "command -v voxtype"]
        initial_delay_ms: 3000
        max_delay_ms: 300000
        warn_text: "voxtype: status stream exits quickly, backing off"
        onLine: text => {
            if (!text.startsWith("{")) return;
            try {
                const data = JSON.parse(text);
                root.state = data.alt || data.class || "idle";
                root.tooltip = data.tooltip || "";
            } catch (e) {
                console.warn("voxtype: " + e);
            }
        }
        onExited: {
            root.state = "stopped";
            root.tooltip = "Voxtype not running";
        }
    }
}
