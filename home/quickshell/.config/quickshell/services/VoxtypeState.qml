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

    Process {
        id: stream
        command: ["voxtype", "status", "--follow", "--format", "json"]
        running: true
        stdout: SplitParser {
            onRead: line => {
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
            restart_timer.start();
        }
    }

    // The service restarts on right-click, which ends the follow stream; reconnect after it.
    Timer {
        id: restart_timer
        interval: 3000
        onTriggered: stream.running = true
    }
}
