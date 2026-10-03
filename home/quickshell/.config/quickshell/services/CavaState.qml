// home/quickshell/.config/quickshell/services/CavaState.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

// One shared cava process for every screen's border strip, running only while media is
// playing on AC power. Parses "n;n;...;" stdout lines into a 0..1 levels array.
Singleton {
    id: root

    readonly property int bar_count: 48
    property var levels: root.zeros()
    // Line-mode levels: fast rise, slow fall, blended with neighbours; updated once per frame for every bar.
    property var line_levels: root.zeros()
    property var smoothed: root.zeros()
    property double last_ms: 0
    // Lualine bars count the screens showing their strip; with none, cava does not run.
    property int lualine_viewers: 0
    readonly property bool wanted: MediaState.playing && Power.on_ac && (!Style.bar_lualine || root.lualine_viewers > 0)

    property int restart_delay_ms: 2000
    property double started_ms: 0
    property bool warned: false

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

    onLevelsChanged: if (Style.cava_line) root.smooth_levels()
    onWantedChanged: root.sync()
    Component.onCompleted: Qt.callLater(root.sync)

    function sync() {
        cava_proc.running = root.wanted;
        if (!root.wanted) root.levels = root.zeros();
    }

    Process {
        id: cava_proc
        command: ["cava", "-p", root.config_path]
        onStarted: root.started_ms = Date.now()

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.parse_line(data)
        }

        onExited: {
            root.levels = root.zeros();
            if (!root.wanted) return;
            if (Date.now() - root.started_ms < 30000) {
                if (!root.warned) console.warn("cava: exits quickly, backing off");
                root.warned = true;
                root.restart_delay_ms = Math.min(root.restart_delay_ms * 2, 60000);
            } else {
                root.restart_delay_ms = 2000;
                root.warned = false;
            }
            restart_timer.restart();
        }
    }

    // If cava exits unexpectedly while still wanted (e.g. pipewire hiccup), retry.
    Timer {
        id: restart_timer
        interval: root.restart_delay_ms
        onTriggered: if (root.wanted) cava_proc.running = true
    }

    function smooth_levels() {
        const now = Date.now();
        const dt = root.last_ms > 0 ? Math.min(0.05, Math.max(0.001, (now - root.last_ms) / 1000)) : 0.016;
        root.last_ms = now;
        const target = root.levels;
        const n = target.length;
        const prev = root.smoothed;
        const next = new Array(n);
        for (let i = 0; i < n; i++) {
            const cur = prev[i] || 0;
            const k = target[i] > cur ? 30 : 14;
            next[i] = cur + (target[i] - cur) * (1 - Math.exp(-k * dt));
        }
        const out = new Array(n);
        for (let i = 0; i < n; i++) out[i] = next[Math.max(0, i - 1)] * 0.25 + next[i] * 0.5 + next[Math.min(n - 1, i + 1)] * 0.25;
        root.smoothed = next;
        root.line_levels = out;
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
