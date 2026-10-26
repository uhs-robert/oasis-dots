pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.theme
import "CavaViewers.js" as Viewers

// One shared cava process for every screen, running only while media is playing on AC power
// and something is drawing it (a registered viewer). Parses "n;n;...;" stdout lines into a 0..1 levels array.
Singleton {
    id: root

    readonly property int bar_count: 48
    property var levels: root.zeros()
    // Line-mode levels: fast rise, slow fall, blended with neighbours; updated once per frame for every bar.
    property var line_levels: root.zeros()
    property var smoothed: root.zeros()
    property double last_ms: 0
    // Whatever is drawing cava registers itself here while it is shown and unregisters when it hides or is destroyed.
    property var viewers: []
    readonly property bool wanted: MediaState.playing && PowerSource.on_ac && Viewers.any(root.viewers)

    function register(viewer) { root.viewers = Viewers.register(root.viewers, viewer); }
    function unregister(viewer) { root.viewers = Viewers.unregister(root.viewers, viewer); }

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

    onLevelsChanged: if (MediaSettings.cava_line) root.smooth_levels()
    onWantedChanged: root.sync()
    Component.onCompleted: Qt.callLater(root.sync)

    function sync() {
        if (!root.wanted) root.levels = root.zeros();
    }

    RestartingStream {
        id: cava_proc
        wanted: root.wanted
        command: ["cava", "-p", root.config_path]
        probe_command: ["sh", "-c", "command -v cava"]
        missing_text: "cava: not installed, border strip stays flat"
        initial_delay_ms: 2000
        max_delay_ms: 60000
        warn_text: "cava: exits quickly, backing off"
        onLine: text => root.parse_line(text)
        onExited: root.levels = root.zeros()
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
