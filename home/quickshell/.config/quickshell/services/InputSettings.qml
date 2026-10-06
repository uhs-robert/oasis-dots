// home/quickshell/.config/quickshell/services/InputSettings.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

// Input choices saved in input.json under the Quickshell state dir.
Singleton {
    id: root

    readonly property string state_dir: Paths.state_dir

    readonly property var choices: ({ start_mode: ["insert", "normal"], remember_query: [false, true] })
    readonly property var defaults: ({ start_mode: "insert", remember_query: false })

    property var values: root.defaults
    // Pickers, settings lists and type-to-search popups open in INSERT when true; the HyprVim prompt always does.
    readonly property bool starts_insert: root.values.start_mode === "insert"
    // Last query per picker or settings list, for this session only; recall gives "" unless remember_query is on.
    property var last_queries: ({})

    function remember(key, text) {
        root.last_queries[key] = text;
    }

    function recall(key) {
        return root.values.remember_query ? root.last_queries[key] || "" : "";
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
            save_proc.command = ["sh", "-c", "mkdir -p \"$1\" && printf %s \"$2\" > \"$1/input.json.tmp\" && mv \"$1/input.json.tmp\" \"$1/input.json\"",
                "sh", root.state_dir, JSON.stringify(root.values)];
            save_proc.running = true;
        }
    }

    Process {
        id: save_proc
    }

    FileView {
        path: root.state_dir + "/input.json"
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
            } catch (e) {
                console.warn("InputSettings: invalid input.json (" + e + ")");
            }
        }
        onLoadFailed: error => root.values = root.defaults
    }
}
