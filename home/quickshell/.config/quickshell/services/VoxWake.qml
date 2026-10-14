// home/quickshell/.config/quickshell/services/VoxWake.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Whether voxcmd's wake word listener holds the microphone, read from the file the listener keeps while it runs:
// {"state": "armed" | "ready" | "paused", "reason": <name of the check that paused>}. Paused has released the microphone;
// the reason (media_playing, mic_in_use, voxtype_recording, session_open) is only in the file while paused.
// The service removes the file when it stops, including when it is killed.
Singleton {
    id: root

    readonly property bool armed: state === "armed"
    // The listener's trigger started a recording: speak now.
    readonly property bool ready: state === "ready"
    readonly property bool paused: state === "paused"
    property string state: ""
    property string reason: ""
    // Why the listener is paused, in words for a tooltip.
    readonly property string paused_text: {
        const why = {
            mic_in_use: "another app is using the mic",
            media_playing: "media is playing",
            voxtype_recording: "a voice command is running",
            session_open: "a voice command is running"
        }[reason];
        return why ? "Wake word paused: " + why : "Wake word paused";
    }

    FileView {
        id: wake_file
        path: VoxSession.voxcmd_dir + "/wake.json"
        printErrors: false
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const wake = JSON.parse(text());
                root.state = String(wake.state || "");
                root.reason = String(wake.reason || "");
            } catch (e) {
                root.state = "";
                root.reason = "";
            }
        }
        onLoadFailed: error => {
            root.state = "";
            root.reason = "";
        }
    }

    // VoxSession finds the folder once voxcmd has made it; a watch reports a file only in a folder that exists.
    Connections {
        target: VoxSession
        function onVoxcmd_dir_existsChanged() {
            wake_file.reload();
        }
    }
}
