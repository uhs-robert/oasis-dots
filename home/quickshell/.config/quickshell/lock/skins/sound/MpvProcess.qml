// home/quickshell/.config/quickshell/lock/skins/sound/MpvProcess.qml
import QtQuick
import Quickshell
import Quickshell.Io

// One mpv child driven over its IPC socket, so FFmpeg never loads into qs itself.
Scope {
    id: root

    property bool wanted: false
    property var args: []
    // Linear 0-1 like QtMultimedia; mpv's volume is cubic.
    property real volume: 1
    readonly property int mpv_volume: Math.round(100 * Math.cbrt(Math.max(0, Math.min(1, root.volume))))
    readonly property string sock: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-mpv-" + Quickshell.processId + "-" + Math.floor(Math.random() * 1e9)

    function send(command) {
        if (!socket.connected) return false;
        socket.write(JSON.stringify({ command: command }) + "\n");
        socket.flush();
        return true;
    }

    function sync() {
        if (root.wanted && !proc.running) {
            proc.command = ["setpriv", "--pdeathsig", "TERM", "mpv", "--no-config", "--no-video", "--no-terminal", "--really-quiet", "--gapless-audio=yes", "--volume=" + root.mpv_volume, "--input-ipc-server=" + root.sock].concat(root.args);
            proc.running = true;
        } else if (!root.wanted && proc.running) {
            if (!root.send(["quit"])) proc.signal(15);
        }
    }

    onWantedChanged: root.sync()
    onMpv_volumeChanged: root.send(["set_property", "volume", root.mpv_volume])
    Component.onCompleted: root.sync()
    Component.onDestruction: {
        if (proc.running) proc.signal(15);
        Quickshell.execDetached(["rm", "-f", root.sock]);
    }

    Process {
        id: proc
        onRunningChanged: {
            if (proc.running) return;
            socket.connected = false;
            Quickshell.execDetached(["rm", "-f", root.sock]);
        }
        // A start with no audio sink exits at once; try again while still wanted.
        onExited: if (root.wanted) retry.restart()
    }

    Timer {
        id: retry
        interval: 1000
        onTriggered: root.sync()
    }

    Socket {
        id: socket
        path: root.sock
        onConnectedChanged: if (socket.connected) root.send(["set_property", "volume", root.mpv_volume])
    }

    // The socket appears a moment after mpv starts.
    Timer {
        interval: 50
        repeat: true
        running: proc.running && !socket.connected
        onTriggered: socket.connected = true
    }
}
