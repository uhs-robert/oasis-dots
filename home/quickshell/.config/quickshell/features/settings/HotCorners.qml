pragma Singleton
import QtQuick
import Quickshell
import qs.core

// Whether the screen corners act as hot corners, saved in hot_corners.json.
Singleton {
    id: root

    readonly property bool enabled: store.values.enabled

    function set_enabled(on) {
        store.set_key("enabled", on);
    }

    JsonStore {
        id: store
        path: Paths.state_dir + "/hot_corners.json"
        defaults: ({ enabled: true })
        validate: raw => ({ enabled: raw.enabled !== false })
    }
}
