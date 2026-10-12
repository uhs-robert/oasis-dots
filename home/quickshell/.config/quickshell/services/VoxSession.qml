// home/quickshell/.config/quickshell/services/VoxSession.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The voice session voxcmd keeps open (click mode), read from the file it writes while one is open and removes when
// it ends. While `active`, the microphone re-opens after every turn, so the bar says so.
Singleton {
    id: root

    readonly property bool active: session_open && owner_alive
    property string label: ""

    readonly property string voxcmd_dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/voxcmd"
    property bool session_open: false
    property int owner: 0
    property bool owner_alive: false
    property bool voxcmd_dir_exists: false

    FileView {
        id: session_file
        path: root.voxcmd_dir + "/session.json"
        printErrors: false
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.label = String(data.label || "Voice session");
                root.owner = Number(data.owner) || 0;
                root.session_open = true;
                owner_probe.reload();
            } catch (e) {
                root.session_open = false;
            }
        }
        onLoadFailed: error => root.session_open = false
    }

    // A watch only reports a file appearing in a folder that exists, and voxcmd makes its folder on first use, which
    // can come after the bar starts. Until the folder is there it is looked for; reading a folder fails with an error
    // other than FileNotFound.
    FileView {
        id: voxcmd_dir_probe
        path: root.voxcmd_dir
        printErrors: false
        blockLoading: true
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                return;
            root.voxcmd_dir_exists = true;
            session_file.reload();
        }
    }

    Timer {
        running: !root.voxcmd_dir_exists
        repeat: true
        triggeredOnStart: true
        interval: 1000
        onTriggered: voxcmd_dir_probe.reload()
    }

    // voxcmd removes the file however its owner ends, except when the owner is killed outright (SIGKILL), so while a
    // session shows, its owner is checked.
    FileView {
        id: owner_probe
        path: root.owner > 0 ? "/proc/" + root.owner + "/stat" : ""
        printErrors: false
        blockLoading: true
        onLoaded: root.owner_alive = true
        onLoadFailed: error => root.owner_alive = false
    }

    Timer {
        running: root.session_open
        repeat: true
        interval: 3000
        onTriggered: owner_probe.reload()
    }
}
