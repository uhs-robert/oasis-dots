pragma Singleton
import QtQuick
import Quickshell
import qs.core
import "../../core/Validated.js" as Validated

// Clock and calendar choices saved in clock.json under the Quickshell state dir.
Singleton {
    id: root

    readonly property string state_dir: Paths.state_dir

    readonly property var choices: ({ week_start: ["locale", "monday", "sunday"], time_format: ["locale", "12h", "24h"] })
    readonly property var defaults: ({ week_start: "locale", time_format: "locale" })

    readonly property var values: store.values
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
        return Validated.in_choices(root.choices, key, value);
    }

    function set(key, value) {
        if (!root.valid(key, value)) return;
        store.set_key(key, value);
    }

    JsonStore {
        id: store
        path: root.state_dir + "/clock.json"
        defaults: root.defaults
        debounce_ms: 300
        validate: raw => Validated.validated(root.defaults, raw, root.valid)
        onLoaded: root.has_time_format = root.valid("time_format", store.raw.time_format)
    }
}
