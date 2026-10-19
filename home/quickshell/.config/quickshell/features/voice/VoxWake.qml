pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

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
    readonly property string state: wake.values.state
    readonly property string reason: wake.values.reason
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

    JsonStore {
        id: wake
        path: VoxSession.voxcmd_dir + "/wake.json"
        read_only: true
        defaults: ({ state: "", reason: "" })
        validate: raw => ({ state: String(raw.state || ""), reason: String(raw.reason || "") })
    }

    // VoxSession finds the folder once voxcmd has made it; a watch reports a file only in a folder that exists.
    Connections {
        target: VoxSession
        function onVoxcmd_dir_existsChanged() {
            wake.rearm();
        }
    }
}
