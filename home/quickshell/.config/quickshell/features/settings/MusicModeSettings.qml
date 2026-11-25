pragma Singleton
import QtQuick
import Quickshell
import qs.core

// Whether the screen frame shows the music bars, saved in music_mode.json. One setting for every style.
Singleton {
    id: root

    readonly property bool on: store.values.on

    function set_on(value) {
        store.set_key("on", value);
    }

    JsonStore {
        id: store
        path: Paths.state_dir + "/music_mode.json"
        defaults: ({ on: false })
        validate: raw => ({ on: raw.on === true })
    }
}
