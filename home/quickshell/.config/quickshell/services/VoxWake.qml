// home/quickshell/.config/quickshell/services/VoxWake.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Whether voxcmd's wake word listener holds the microphone, read from the file the listener keeps while it runs:
// {"state": "armed" | "ready" | "paused"}. Paused (media playing, voxtype recording) has released the microphone, so it shows nothing.
// The service removes the file when it stops, including when it is killed.
Singleton {
    id: root

    readonly property bool armed: state === "armed"
    // The listener's trigger started a recording: speak now.
    readonly property bool ready: state === "ready"
    property string state: ""

    FileView {
        id: wake_file
        path: VoxSession.voxcmd_dir + "/wake.json"
        printErrors: false
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.state = String(JSON.parse(text()).state || "");
            } catch (e) {
                root.state = "";
            }
        }
        onLoadFailed: error => root.state = ""
    }

    // VoxSession finds the folder once voxcmd has made it; a watch reports a file only in a folder that exists.
    Connections {
        target: VoxSession
        function onVoxcmd_dir_existsChanged() {
            wake_file.reload();
        }
    }
}
