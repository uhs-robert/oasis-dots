// home/quickshell/.config/quickshell/services/ClockSettings.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Clock and calendar choices saved in clock.json under the Quickshell state dir.
Singleton {
    id: root

    readonly property string state_dir: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        return (xdg && xdg !== "" ? xdg : Quickshell.env("HOME") + "/.local/state") + "/quickshell";
    }

    readonly property var choices: ({ week_start: ["locale", "monday", "sunday"], time_format: ["locale", "12h", "24h"] })
    readonly property var defaults: ({ week_start: "locale", time_format: "locale" })

    property var values: root.defaults
    property bool has_time_format: false
    readonly property string week_start: root.values.week_start
    readonly property string time_format: root.values.time_format

    // One-time carry-over of the old weather time_format; a saved choice wins.
    function migrate_time_format(value) {
        if (root.has_time_format || !root.valid("time_format", value)) return;
        root.has_time_format = true;
        root.set("time_format", value);
    }

    function valid(key, value) {
        return !!root.choices[key] && root.choices[key].indexOf(value) >= 0;
    }

    function set(key, value) {
        if (!root.valid(key, value)) return;
        root.values = Object.assign({}, root.values, { [key]: value });
        save_timer.restart();
    }

    Timer {
        id: save_timer
        interval: 300
        onTriggered: {
            if (save_proc.running) {
                save_timer.restart();
                return;
            }
            save_proc.command = ["sh", "-c", "mkdir -p \"$1\" && printf %s \"$2\" > \"$1/clock.json.tmp\" && mv \"$1/clock.json.tmp\" \"$1/clock.json\"",
                "sh", root.state_dir, JSON.stringify(root.values)];
            save_proc.running = true;
        }
    }

    Process {
        id: save_proc
    }

    FileView {
        path: root.state_dir + "/clock.json"
        printErrors: false
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                const next = Object.assign({}, root.defaults);
                for (const key in next) {
                    if (root.valid(key, data[key])) next[key] = data[key];
                }
                root.values = next;
                root.has_time_format = root.valid("time_format", data.time_format);
            } catch (e) {
                console.warn("ClockSettings: invalid clock.json (" + e + ")");
            }
        }
        onLoadFailed: error => {
            root.values = root.defaults;
            root.has_time_format = false;
        }
    }
}
