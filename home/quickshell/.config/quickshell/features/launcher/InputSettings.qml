pragma Singleton
import QtQuick
import Quickshell
import qs.core

// Input choices saved in input.json under the Quickshell state dir.
Singleton {
    id: root

    readonly property string state_dir: Paths.state_dir

    readonly property var choices: ({ start_mode: ["insert", "normal"], remember_query: [false, true] })
    readonly property var defaults: ({ start_mode: "insert", remember_query: false })

    readonly property var values: store.values
    // Island pickers, settings lists and type-to-search popups open in INSERT when true; bottom-docked pickers and the HyprVim prompt always do.
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
        store.set_key(key, value);
    }

    JsonStore {
        id: store
        path: root.state_dir + "/input.json"
        defaults: root.defaults
        debounce_ms: 300
        validate: raw => {
            const next = Object.assign({}, root.defaults);
            for (const key in next) {
                if (root.valid(key, raw[key])) next[key] = raw[key];
            }
            return next;
        }
    }
}
