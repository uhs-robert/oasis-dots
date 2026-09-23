// home/quickshell/.config/quickshell/services/CavaState.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// One shared cava process for every screen's border strip, running only while media is
// playing on AC power. Parses "n;n;...;" stdout lines into a 0..1 levels array.
Singleton {
    id: root

    readonly property int bar_count: 48
    property var levels: root.zeros()
    readonly property bool wanted: MediaState.playing && Power.on_ac

    function zeros() {
        const a = [];
        for (let i = 0; i < root.bar_count; i++) a.push(0);
        return a;
    }

    readonly property string config_path: Quickshell.cacheDir + "/cava_border.conf"
    readonly property string config_text:
        "[general]\n" +
        "bars = " + root.bar_count + "\n" +
        "framerate = 30\n" +
        "[input]\n" +
        "method = pipewire\n" +
        "[output]\n" +
        "method = raw\n" +
        "raw_target = /dev/stdout\n" +
        "data_format = ascii\n" +
        "ascii_max_range = 100\n" +
        "bar_delimiter = 59\n" +
        "[smoothing]\n" +
        "noise_reduction = 77\n"

    FileView {
        id: config_file
        path: root.config_path
        printErrors: false
        Component.onCompleted: config_file.setText(root.config_text)
    }

    onWantedChanged: root.sync()
    Component.onCompleted: Qt.callLater(root.sync)

    function sync() {
        cava_proc.running = root.wanted;
        if (!root.wanted) root.levels = root.zeros();
    }

    Process {
        id: cava_proc
        command: ["cava", "-p", root.config_path]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.parse_line(data)
        }

        onExited: {
            root.levels = root.zeros();
            if (root.wanted) restart_timer.start();
        }
    }

    // If cava exits unexpectedly while still wanted (e.g. pipewire hiccup), retry.
    Timer {
        id: restart_timer
        interval: 2000
        onTriggered: if (root.wanted) cava_proc.running = true
    }

    function parse_line(line) {
        const trimmed = line.trim();
        if (!trimmed) return;
        const parts = trimmed.split(";").filter(p => p !== "");
        if (parts.length === 0) return;
        const out = [];
        for (let i = 0; i < root.bar_count; i++) {
            const v = parseInt(parts[i], 10);
            out.push(isNaN(v) ? 0 : Math.max(0, Math.min(100, v)) / 100);
        }
        root.levels = out;
    }
}
