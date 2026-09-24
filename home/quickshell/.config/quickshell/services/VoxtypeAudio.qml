// home/quickshell/.config/quickshell/services/VoxtypeAudio.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Mic peaks from voxtype-audio-bridge, streamed only while recording.
Singleton {
    id: root

    readonly property bool active: VoxtypeState.recording
    // Seconds of audio kept; read from voxtype's osd.waveform_window_secs.
    property real window_secs: 3
    readonly property int frame_rate: 100
    readonly property real floor_dbfs: -60
    // Linear peak multiplier for the line wave; read from voxtype's osd.waveform_gain.
    property real gain: 10
    readonly property int capacity: Math.max(1, Math.round(root.window_secs * root.frame_rate))

    // Mutated in place so a frame never re-evaluates bindings; read through columns().
    property var ring: []
    property int head: 0
    property int count: 0

    function clear() {
        root.ring = new Array(root.capacity).fill(0);
        root.head = 0;
        root.count = 0;
    }

    // Peak mapped to 0..1 on a dBFS scale from floor_dbfs.
    function level(peak) {
        if (!(peak > 0)) return 0;
        const dbfs = 20 * Math.log10(peak);
        return Math.max(0, Math.min(1, (dbfs - root.floor_dbfs) / -root.floor_dbfs));
    }

    function push(value) {
        if (root.ring.length !== root.capacity) root.clear();
        root.ring[root.head] = value;
        root.head = (root.head + 1) % root.capacity;
        root.count = Math.min(root.count + 1, root.capacity);
    }

    // Linear peaks averaged into n buckets, right-aligned so a filling window reads as silence on the left.
    function averages(n) {
        const out = new Array(n).fill(0);
        const size = root.ring.length;
        if (size === 0 || root.count === 0) return out;
        const pad = size - root.count;
        for (let c = 0; c < n; c++) {
            const start = Math.max(pad, Math.floor(c * size / n));
            const end = Math.max(start + 1, Math.floor((c + 1) * size / n));
            let sum = 0;
            let k = 0;
            for (let j = start; j < Math.min(end, size); j++) {
                sum += root.ring[(root.head - size + j + size * 2) % size];
                k++;
            }
            out[c] = k > 0 ? sum / k : 0;
        }
        return out;
    }

    // The window split into n buckets, oldest first, each the loudest level in it.
    function columns(n) {
        const out = new Array(n).fill(0);
        const size = root.ring.length;
        if (size === 0 || root.count === 0) return out;
        for (let i = 0; i < root.count; i++) {
            const age = root.count - 1 - i;
            const value = root.ring[(root.head - 1 - age + size * 2) % size];
            const col = Math.min(n - 1, Math.floor((size - 1 - age) * n / size));
            const lvl = root.level(value);
            if (lvl > out[col]) out[col] = lvl;
        }
        return out;
    }

    function handle(line) {
        let data;
        try {
            data = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (typeof data.peak === "number") root.push(Math.max(0, Math.min(1, data.peak)));
    }

    // The last recording stays in the ring so the transcribing view can show it frozen.
    onActiveChanged: {
        if (root.active) root.clear();
        bridge.running = root.active;
        if (root.active) {
            settings.running = true;
            gain_setting.running = true;
        }
    }

    Component.onCompleted: root.clear()

    Process {
        id: bridge
        command: ["voxtype-audio-bridge"]
        stdout: SplitParser {
            onRead: line => root.handle(line)
        }
        onExited: if (root.active) restart_timer.start()
    }

    Timer {
        id: restart_timer
        interval: 1000
        onTriggered: bridge.running = root.active
    }

    Process {
        id: settings
        command: ["voxtype", "config", "get", "osd.waveform_window_secs"]
        stdout: StdioCollector {
            onStreamFinished: {
                const secs = parseFloat(text);
                if (secs > 0 && secs !== root.window_secs) {
                    root.window_secs = secs;
                    root.clear();
                }
            }
        }
    }

    Process {
        id: gain_setting
        command: ["voxtype", "config", "get", "osd.waveform_gain"]
        stdout: StdioCollector {
            onStreamFinished: {
                const g = parseFloat(text);
                if (g > 0) root.gain = g;
            }
        }
    }
}
