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

    readonly property bool linked: link.item !== null && link.item.connected

    function send(command) {
        if (!root.linked) return false;
        link.item.write(JSON.stringify({ command: command }) + "\n");
        link.item.flush();
        return true;
    }

    // Commands from before the socket connects, sent once it does.
    property var pending: []

    function queue(command) {
        if (root.send(command)) return;
        root.pending = root.pending.concat([command]).slice(-8);
    }

    // Null until the one-time probe for mpv and setpriv answers.
    property var available: null
    property int retry_ms: 1000
    property int quick_fails: 0
    property double started_ms: 0
    readonly property int max_quick_fails: 6

    function sync() {
        if (root.wanted && root.available === true && root.quick_fails < root.max_quick_fails && !proc.running) {
            proc.command = ["setpriv", "--pdeathsig", "TERM", "mpv", "--no-config", "--no-video", "--no-terminal", "--really-quiet", "--gapless-audio=yes", "--volume=" + root.mpv_volume, "--input-ipc-server=" + root.sock].concat(root.args);
            proc.running = true;
        } else if (!root.wanted && proc.running) {
            if (!root.send(["quit"])) proc.signal(15);
        }
    }

    onWantedChanged: {
        if (!root.wanted) {
            root.quick_fails = 0;
            root.retry_ms = 1000;
        }
        root.sync();
    }
    onMpv_volumeChanged: root.send(["set_property", "volume", root.mpv_volume])
    Component.onCompleted: root.sync()
    Component.onDestruction: {
        if (proc.running) proc.signal(15);
        Quickshell.execDetached(["rm", "-f", root.sock]);
    }

    Process {
        id: probe
        command: ["sh", "-c", "command -v mpv setpriv >/dev/null"]
        running: true
        onExited: code => {
            root.available = code === 0;
            if (code !== 0) console.warn("mpv audio: mpv or setpriv missing, staying silent");
            root.sync();
        }
    }

    Process {
        id: proc
        onStarted: root.started_ms = Date.now()
        onRunningChanged: {
            if (proc.running) return;
            link.active = false;
            root.pending = [];
            Quickshell.execDetached(["rm", "-f", root.sock]);
        }
        onExited: {
            if (!root.wanted) return;
            if (Date.now() - root.started_ms < 10000) {
                root.quick_fails++;
                if (root.quick_fails >= root.max_quick_fails) {
                    console.warn("mpv audio: exits quickly, giving up");
                    return;
                }
                root.retry_ms = Math.min(root.retry_ms * 2, 60000);
            } else {
                root.quick_fails = 0;
                root.retry_ms = 1000;
            }
            retry.restart();
        }
    }

    Timer {
        id: retry
        interval: root.retry_ms
        onTriggered: root.sync()
    }

    // A Socket never retries after a failed connect, so each attempt builds a fresh one.
    Loader {
        id: link
        active: false
        sourceComponent: Socket {
            path: root.sock
            connected: true
        }
    }

    onLinkedChanged: {
        if (!root.linked) return;
        root.send(["set_property", "volume", root.mpv_volume]);
        for (const command of root.pending) root.send(command);
        root.pending = [];
    }

    // The socket appears a moment after mpv starts.
    Timer {
        interval: 50
        repeat: true
        running: proc.running && !root.linked
        onTriggered: {
            link.active = false;
            link.active = true;
        }
    }
}
