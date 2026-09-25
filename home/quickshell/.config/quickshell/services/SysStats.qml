// home/quickshell/.config/quickshell/services/SysStats.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property real cpu_percent: 0
    property real mem_percent: 0
    property real mem_used_gb: 0
    property real mem_total_gb: 0
    property real temp_c: 0

    property string temp_path: ""
    readonly property bool has_temp: temp_path !== ""

    // Recent samples for sparklines, oldest first; they grow only when a poll lands.
    readonly property int history_size: 60
    property var cpu_history: []
    property var mem_history: []
    property var temp_history: []
    function pushed(list, v) {
        const out = list.length >= root.history_size ? list.slice(list.length - root.history_size + 1) : list.slice();
        out.push(v);
        return out;
    }

    property real prev_total: -1
    property real prev_idle: -1

    // Prefers k10temp/coretemp (real CPU die sensor) over acpitz (chassis).
    Process {
        id: find_temp_proc
        command: ["sh", "-c", "for pref in k10temp coretemp acpitz; do for f in /sys/class/hwmon/*/name; do n=$(cat \"$f\" 2>/dev/null); if [ \"$n\" = \"$pref\" ]; then d=$(dirname \"$f\"); i=$(ls \"$d\"/temp*_input 2>/dev/null | head -1); if [ -n \"$i\" ]; then echo \"$i\"; exit 0; fi; fi; done; done"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.temp_path = text.trim()
        }
    }

    onTemp_pathChanged: if (root.has_temp) temp_file.reload();

    Timer {
        interval: 10000
        running: Power.on_ac
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }

    function poll() {
        stat_file.reload();
        meminfo_file.reload();
        if (root.has_temp) temp_file.reload();
    }

    FileView {
        id: stat_file
        path: "/proc/stat"
        onLoaded: {
            const line = text().split("\n")[0];
            const parts = line.trim().split(/\s+/).slice(1).map(Number);
            const idle = parts[3] + parts[4];
            const total = parts.reduce((a, b) => a + b, 0);
            if (root.prev_total >= 0) {
                const dt = total - root.prev_total;
                const di = idle - root.prev_idle;
                if (dt > 0) {
                    root.cpu_percent = Math.round((1 - di / dt) * 100);
                    root.cpu_history = root.pushed(root.cpu_history, root.cpu_percent);
                }
            }
            root.prev_total = total;
            root.prev_idle = idle;
        }
    }

    FileView {
        id: meminfo_file
        path: "/proc/meminfo"
        onLoaded: {
            const t = text();
            const total = Number(t.match(/MemTotal:\s+(\d+)/)[1]);
            const avail = Number(t.match(/MemAvailable:\s+(\d+)/)[1]);
            if (total > 0) {
                root.mem_percent = Math.round((1 - avail / total) * 100);
                root.mem_total_gb = total / 1048576;
                root.mem_used_gb = (total - avail) / 1048576;
                root.mem_history = root.pushed(root.mem_history, root.mem_percent);
            }
        }
    }

    FileView {
        id: temp_file
        path: root.has_temp ? root.temp_path : ""
        onLoaded: {
            root.temp_c = Math.round(Number(text()) / 1000);
            root.temp_history = root.pushed(root.temp_history, root.temp_c);
        }
    }
}
