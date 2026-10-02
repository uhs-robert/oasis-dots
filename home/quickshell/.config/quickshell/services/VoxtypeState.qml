// home/quickshell/.config/quickshell/services/VoxtypeState.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// One `voxtype status --follow` stream shared by every bar.
Singleton {
    id: root

    property string state: "stopped"
    property string tooltip: "Voxtype not running"
    readonly property bool recording: state === "recording"
    readonly property bool transcribing: state === "transcribing"

    property bool installed: false
    property int restart_delay_ms: 3000
    property double started_ms: 0
    property bool warned: false

    Process {
        id: probe
        command: ["sh", "-c", "command -v voxtype"]
        running: true
        onExited: code => {
            root.installed = code === 0;
            stream.running = root.installed;
        }
    }

    Process {
        id: stream
        command: ["voxtype", "status", "--follow", "--format", "json"]
        onStarted: root.started_ms = Date.now()
        stdout: SplitParser {
            onRead: line => {
                if (!line.startsWith("{")) return;
                try {
                    const data = JSON.parse(line);
                    root.state = data.alt || data.class || "idle";
                    root.tooltip = data.tooltip || "";
                } catch (e) {
                    console.warn("voxtype: " + e);
                }
            }
        }
        onExited: {
            root.state = "stopped";
            root.tooltip = "Voxtype not running";
            if (Date.now() - root.started_ms < 30000) {
                if (!root.warned) console.warn("voxtype: status stream exits quickly, backing off");
                root.warned = true;
                root.restart_delay_ms = Math.min(root.restart_delay_ms * 2, 300000);
            } else {
                root.restart_delay_ms = 3000;
                root.warned = false;
            }
            restart_timer.restart();
        }
    }

    // The service restarts on right-click, which ends the follow stream; reconnect after it.
    Timer {
        id: restart_timer
        interval: root.restart_delay_ms
        onTriggered: stream.running = true
    }
}
